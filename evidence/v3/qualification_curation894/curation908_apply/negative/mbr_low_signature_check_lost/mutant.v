// ============================================================================
// mbr_parser.v — 主引导记录（MBR）分区表解析（SafeVision B 链 · 学习阶段 6）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「FAT32 与图片装载」；本仓库 docs/interface_spec.md §3.2。
//
// ★ 为什么需要这个模块（2026-10-02 板级实测发现的问题）：
//   FAT32 层（`fat32_boot_parser` / `fat32_directory_scanner` / `fat32_cluster_walker`
//   / `file_streamer`）内部一律按 **【卷内相对 LBA】** 工作 —— 卷的第一个扇区记作
//   0 号扇区。这是"超级软盘 / 无分区表"格式的假设，也是它们 TB 一直验证的口径。
//
//   但**真实 TF 卡是分区的**：卡的第 0 号扇区是 MBR，真正的 FAT32 卷从**分区的
//   起始 LBA** 开始。实测这张 HX4S20C 卡的分区起始 = **物理扇区 8192**
//   （`Get-Partition` 可查）。所以把 FAT32 层直接接到卡上，它会去读卡的 0 号扇区
//   = MBR，然后因为找不到 "MSDOS5.0" 与 FAT32 判别位而报 `mount_error`。
//
//   本模块只做一件事：把**卷基址**（分区 0 的起始物理 LBA）解析出来。
//   ★ 约定（全链唯一口径）：**卷基址只在板级顶层加一次**，即
//       送给 sd_sector_reader 的地址 = FAT32 层的相对 LBA + vol_base_lba
//     FAT32 层内部永远不碰这个偏移，避免"加两次"这类难查的错。
//
// 容错取舍（故意不报错的两条）：
//   - 扇区 510/511 不是 0x55AA（没有分区表），或
//   - 分区 0 的表项为空（类型 = 0，或起始 LBA = 0）
//   这两种情况按"**无分区表**"处理：`has_mbr = 0`、`vol_base_lba = 0`，
//   让下游直接按卷 0 = 卡 0 去试。真是坏卡的话，`fat32_boot_parser` 读卷 0 号
//   扇区时会以 `DET_FAT_BPB` 报错，错误码不会丢。
//   只有 SD 层错误（数据令牌超时 / CRC16）才在这里透传成失败。
//
// 字节序：分区表字段是**小端**（手册 7.6 的硬约定；对比 SD 命令参数是大端）。
//   offset 446 + 0  分区引导标志（0x80 = 活动）
//   offset 446 + 4  分区类型（0x0B/0x0C = FAT32）
//   offset 446 + 8  分区起始 LBA（4 字节小端）  <- 本模块要的就是它
//   offset 446 + 12 分区扇区数（4 字节小端）
//   offset 510/511  0x55 0xAA
// ============================================================================
`include "safevision_defs.vh"
module mbr_parser (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 控制 ----
    input  wire        start,           // 单拍脉冲，触发一次解析
    output reg         parse_done,      // 电平：解析结束（成败都置位，下次 start 清零）
    output reg  [7:0]  err_code,        // 对外主码（只透传 SD 层错误）
    output reg  [7:0]  err_detail,      // B 链内部细分码
    output reg  [3:0]  dbg_state,       // 供 ChipWatcher / LED
    // ---- 解析结果 ----
    output reg         has_mbr,         // 1 = 有有效分区表且分区 0 可用
    output reg  [31:0] vol_base_lba,    // 卷起始【物理】LBA（无分区表时为 0）
    output reg  [31:0] part_secs,       // 分区 0 的扇区数（无分区表时为 0）
    // ---- 到 sd_sector_reader 的读请求（与 fat32_boot_parser 同一种接法）----
    output reg  [31:0] sd_rd_addr,
    output reg  [15:0] sd_rd_len,
    output reg         sd_rd_en,
    input  wire        sd_rd_ready,
    input  wire [7:0]  sd_data,
    input  wire        sd_data_valid,
    output wire        sd_data_ready,
    input  wire        sd_data_last,
    input  wire        sd_rd_done,
    input  wire        sd_timeout_err,
    input  wire        sd_crc16_err,
    input  wire [7:0]  sd_err_code,
    input  wire [7:0]  sd_err_detail
);
    // ------------------------------------------------------------------------
    // 主状态
    // ------------------------------------------------------------------------
    localparam [2:0] M_IDLE = 3'd0,
                     M_REQ  = 3'd1,   // 请求读卡的 0 号扇区（MBR）
                     M_RECV = 3'd2,   // 收 512 字节，按偏移抽字段
                     M_EVAL = 3'd3,   // 判签名 / 判表项，给出卷基址
                     M_DONE = 3'd4,
                     M_ERR  = 3'd5;
    reg  [2:0]  mstate;
    reg  [9:0]  bcnt;           // 字节计数 0..511
    // Every counting state exits or clears at SD_TO_DATA. The last
    // scheduled increment can reach SD_TO_DATA+1, which this width retains.
    localparam integer TO_W=$clog2(`SD_TO_DATA+32'd2);
    reg [TO_W-1:0] to_cnt;         // 【独立超时】本模块自己的等待计数器
    // MBR 字段（收到就锁存）
    // Private header assembly has no reset dependency. Each contiguous
    // field is completely overwritten before M_EVAL; partial/timeout reads
    // never publish it. Shift whole fields under one enable to reduce physical
    // control-set fragmentation. Public results and all error edges retain reset.
    reg [31:0] hdr_base;
    wire [7:0] pb0=hdr_base[0+:8];
    wire [7:0] pb1=hdr_base[8+:8];
    wire [7:0] pb2=hdr_base[16+:8];
    wire [7:0] pb3=hdr_base[24+:8];
    reg [31:0] hdr_size;
    wire [7:0] ps0=hdr_size[0+:8];
    wire [7:0] ps1=hdr_size[8+:8];
    wire [7:0] ps2=hdr_size[16+:8];
    wire [7:0] ps3=hdr_size[24+:8];
    reg hdr_sig_matches;
    reg part_nonzero;
    always @(posedge clk)begin
      if(rst_n && mstate==M_RECV && to_cnt!=`SD_TO_DATA && sd_data_valid)begin
        if(bcnt>=454 && bcnt<=457)hdr_base <= {sd_data,hdr_base[31:8]};
        if(bcnt>=458 && bcnt<=461)hdr_size <= {sd_data,hdr_size[31:8]};
        if(bcnt==510)hdr_sig_matches<=sd_data==8'h55;
        if(bcnt==511)hdr_sig_matches<=(sd_data==8'haa);
        if(bcnt==450)part_nonzero<=|sd_data;
      end
    end

    // ------------------------------------------------------------------------
    // 组合判断（在 M_EVAL 里字段已经锁存，稳定）
    // ------------------------------------------------------------------------
    wire [31:0] w_start_lba = {pb3, pb2, pb1, pb0};
    wire [31:0] w_secs      = {ps3, ps2, ps1, ps0};
    wire        w_sig_ok    = hdr_sig_matches;
    // 有效分区：签名对 + 类型非 0 + 起始 LBA 非 0
    // （起始 LBA 必须非 0：否则"卷"就等于 MBR 自己，那是无分区表的情形）
    wire        w_ok        = w_sig_ok && part_nonzero && (w_start_lba != 32'd0);
    assign sd_data_ready = (mstate == M_RECV);
    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= M_IDLE;
            bcnt         <= 10'd0;
            to_cnt       <= 32'd0;
            sd_rd_addr   <= 32'd0;
            sd_rd_len    <= 16'd1;
            sd_rd_en     <= 1'b0;
            parse_done   <= 1'b0;
            has_mbr      <= 1'b0;
            vol_base_lba <= 32'd0;
            part_secs    <= 32'd0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            dbg_state    <= M_IDLE;
        end else begin
            sd_rd_en  <= 1'b0;          // 单拍脉冲（唯一驱动源：本块）
            dbg_state <= mstate;
            case (mstate)
            // ------------------------------------------------------------------
            M_IDLE: begin
                if (start) begin
                    parse_done   <= 1'b0;
                    has_mbr      <= 1'b0;
                    vol_base_lba <= 32'd0;
                    part_secs    <= 32'd0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    bcnt         <= 10'd0;
                    to_cnt       <= 32'd0;
                    sd_rd_addr   <= 32'd0;    // 卡的 0 号扇区 = MBR
                    sd_rd_len    <= 16'd1;
                    mstate       <= M_REQ;
                end
            end
            // ---- 发起读请求（自己的超时，不与下游共用计数器）------------------
            M_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= M_ERR;
                end else if (sd_rd_ready) begin
                    sd_rd_en <= 1'b1;
                    mstate   <= M_RECV;
                end
            end
            // ---- 收 512 字节，按偏移抽分区表字段 ------------------------------
            M_RECV: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= M_ERR;
                end else if (sd_data_valid) begin

                    bcnt <= bcnt + 10'd1;
                    if (bcnt == 10'd511) mstate <= M_EVAL;
                end
            end
            // ---- 判定：给出卷基址 --------------------------------------------
            M_EVAL: begin
                if (sd_timeout_err || sd_crc16_err) begin
                    // 介质层已报错，直接透传它的细分码
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= M_ERR;
                end else begin
                    has_mbr      <= w_ok;
                    vol_base_lba <= w_ok ? w_start_lba : 32'd0;
                    part_secs    <= w_ok ? w_secs      : 32'd0;
                    mstate       <= M_DONE;
                end
            end
            // ------------------------------------------------------------------
            M_DONE: begin
                parse_done <= 1'b1;
                if (start) begin          // 允许直接重跑，不必先回 IDLE
                    parse_done   <= 1'b0;
                    has_mbr      <= 1'b0;
                    vol_base_lba <= 32'd0;
                    part_secs    <= 32'd0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    bcnt         <= 10'd0;
                    to_cnt       <= 32'd0;
                    sd_rd_addr   <= 32'd0;
                    sd_rd_len    <= 16'd1;
                    mstate       <= M_REQ;
                end
            end
            M_ERR: begin
                parse_done <= 1'b1;
                if (start) begin
                    parse_done <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    bcnt       <= 10'd0;
                    to_cnt     <= 32'd0;
                    sd_rd_addr <= 32'd0;
                    sd_rd_len  <= 16'd1;
                    mstate     <= M_REQ;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end
endmodule
