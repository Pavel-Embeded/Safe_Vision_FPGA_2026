// ============================================================================
// fat32_boot_parser.v — FAT32 挂载与 BPB 解析（SafeVision B 链 · 学习阶段 6）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「FAT32 要回答的是：一个文件占用了哪些簇、按什么顺序串起来」
//       「第一版刻意做简单：单分区、FAT32、根目录、8.3 文件名」
//
// 只做一件事：读 0 号扇区（DBR），校验 BPB，算出后续所有模块需要的基准地址。
//   data_start_lba = RsvdSecCnt + NumFATs * FATSz32
//   root_dir_lba   = data_start_lba + (RootClus - 2) * SecPerClus
//   total_clus     = (TotSec32 - data_start_lba) / SecPerClus
//
// ★ FAT32 的判定依据（三个字段必须同时成立，这是 FAT16/12 与 FAT32 的分水岭）：
//     RootEntCnt == 0 且 FATSz16 == 0 且 TotSec16 == 0
//   只要有一个不为 0，就不是 FAT32，必须明确报错而不是硬着头皮解析。
//
// ★ 不做的：中文名 / LFN / 子目录 / exFAT / NTFS（手册 7.6 明确首版不做）
// ============================================================================
`include "safevision_defs.vh"

module fat32_boot_parser255_reference (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,           // 单拍脉冲，触发一次挂载
    output reg         mount_done,
    output reg         mount_error,
    output reg  [7:0]  err_code,        // 对外主码
    output reg  [7:0]  err_detail,      // 内部细分码（见 interface_spec §6.2）
    output reg  [3:0]  dbg_state,

    // ---- 解析结果 ----
    output reg  [15:0] bytes_per_sec,   // 必须 512
    output reg  [7:0]  sec_per_clus,    // 每簇扇区数
    output reg  [7:0]  num_fats,        // 1 或 2
    output reg  [31:0] fat_start_lba,   // FAT1 起始扇区
    output reg  [31:0] root_clus,       // 根目录起始簇
    output reg  [31:0] root_dir_lba,    // 根目录起始扇区
    output reg  [31:0] data_start_lba,  // 数据区起始扇区
    output reg  [31:0] total_sec,       // 总扇区数
    output reg  [31:0] total_clus,      // 总簇数（供簇链判越界与判环）

    // ---- 到 sd_sector_reader 的读请求 ----
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
    // 状态
    // ------------------------------------------------------------------------
    localparam [3:0] M_IDLE = 4'd0,
                     M_REQ  = 4'd1,   // 发起读 0 号扇区
                     M_RECV = 4'd2,   // 收 512 字节，按偏移抽取 BPB 字段
                     M_EVAL = 4'd3,   // 校验 + 计算派生地址
                     M_DONE = 4'd4,
                     M_ERR  = 4'd5;

    reg  [3:0]  mstate;
    reg  [9:0]  bcnt;               // 扇区内字节偏移 0..511
    // Every counting state exits or clears at SD_TO_DATA. The last
    // scheduled increment can reach SD_TO_DATA+1, which this width retains.
    localparam integer TO_W=$clog2(`SD_TO_DATA+32'd2);
    reg [TO_W-1:0] to_cnt;             // 整次挂载的兜底超时

    // ---- BPB 原始字段（按偏移抽取）----
    reg  [7:0]  bps_l,  bps_h;      // 0x0B BytsPerSec      (2)
    reg  [7:0]  spc;                // 0x0D SecPerClus      (1)
    reg  [7:0]  rsvd_l, rsvd_h;     // 0x0E RsvdSecCnt      (2)
    reg  [7:0]  nfat;               // 0x10 NumFATs         (1)
    reg  [7:0]  roote_l, roote_h;   // 0x11 RootEntCnt      (2)
    reg  [7:0]  ts16_l, ts16_h;     // 0x13 TotSec16        (2)
    reg  [7:0]  media;              // 0x15 Media           (1)
    reg  [7:0]  fs16_l, fs16_h;     // 0x16 FATSz16         (2)
    reg  [7:0]  ts32_0, ts32_1, ts32_2, ts32_3;   // 0x20 TotSec32 (4)
    reg  [7:0]  fs32_0, fs32_1, fs32_2, fs32_3;   // 0x24 FATSz32  (4)
    reg  [7:0]  rc_0,   rc_1,   rc_2,   rc_3;     // 0x2C RootClus (4)
    reg  [7:0]  sig_l,  sig_h;      // 0x1FE 签名 0x55 0xAA

    // ---- 拼装后的值 ----
    wire [15:0] w_bps   = {bps_h,  bps_l};
    wire [15:0] w_rsvd  = {rsvd_h, rsvd_l};
    wire [15:0] w_roote = {roote_h, roote_l};
    wire [15:0] w_ts16  = {ts16_h, ts16_l};
    wire [15:0] w_fs16  = {fs16_h, fs16_l};
    wire [31:0] w_ts32  = {ts32_3, ts32_2, ts32_1, ts32_0};
    wire [31:0] w_fs32  = {fs32_3, fs32_2, fs32_1, fs32_0};
    wire [31:0] w_rc    = {rc_3,   rc_2,   rc_1,   rc_0};
    wire        w_sig_ok = (sig_l == 8'h55) && (sig_h == 8'hAA);

    // ---- FAT32 判别位（手册 7.6：挂载检查 BPB 字段、每簇扇区数、FAT 数量、根目录起始簇）----
    wire is_fat32_fields = (w_roote == 16'h0000) &&
                           (w_fs16  == 16'h0000) &&
                           (w_ts16  == 16'h0000) &&
                           (w_fs32  != 32'h0000_0000);
    wire spc_ok = (spc != 8'd0) && (spc <= 8'd128) && ((spc & (spc - 8'd1)) == 8'd0);  // 2 的幂
    // ★ log2(spc)：供 total_clus 的移位使用（见 M_EVAL 里的注释）。
    //   只有走到"全部合法"那一支时才会用到它，而那一支已经被 spc_ok 保证
    //   spc 是 2 的幂（1..128），所以一个优先编码器就够了，不需要通用除法。
    wire [2:0] w_log2_spc = (spc[7]) ? 3'd7 :
                            (spc[6]) ? 3'd6 :
                            (spc[5]) ? 3'd5 :
                            (spc[4]) ? 3'd4 :
                            (spc[3]) ? 3'd3 :
                            (spc[2]) ? 3'd2 :
                            (spc[1]) ? 3'd1 : 3'd0;
    wire nfat_ok = (nfat == 8'd1) || (nfat == 8'd2);

    // BPB fields stop changing after byte47; only these five predicates
    // need staging before evaluation following byte511. Keep address math
    // directly from the settled fields, without192 unnecessary data registers.
    reg [4:0] bpb_checks_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)bpb_checks_q<=0;
        else bpb_checks_q<={w_rc>=32'd2,nfat_ok,spc_ok,is_fat32_fields,w_bps==16'd512};
    end

    // 只收不含 dout 的字节，永远 ready（本模块不反压）
    assign sd_data_ready = (mstate == M_RECV);

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate        <= M_IDLE;
            bcnt          <= 10'd0;
            to_cnt        <= 32'd0;
            mount_done    <= 1'b0;
            mount_error   <= 1'b0;
            err_code      <= `ERR_NONE;
            err_detail    <= `DET_NONE;
            bytes_per_sec <= 16'd0;
            sec_per_clus  <= 8'd0;
            num_fats      <= 8'd0;
            fat_start_lba <= 32'd0;
            root_clus     <= 32'd0;
            root_dir_lba  <= 32'd0;
            data_start_lba<= 32'd0;
            total_sec     <= 32'd0;
            total_clus    <= 32'd0;
            sd_rd_addr    <= 32'd0;
            sd_rd_len     <= 16'd1;
            sd_rd_en      <= 1'b0;
            dbg_state     <= M_IDLE;
            bps_l <= 8'h0; bps_h <= 8'h0; spc <= 8'h0;
            rsvd_l <= 8'h0; rsvd_h <= 8'h0; nfat <= 8'h0;
            roote_l <= 8'h0; roote_h <= 8'h0; ts16_l <= 8'h0; ts16_h <= 8'h0;
            media <= 8'h0; fs16_l <= 8'h0; fs16_h <= 8'h0;
            ts32_0 <= 8'h0; ts32_1 <= 8'h0; ts32_2 <= 8'h0; ts32_3 <= 8'h0;
            fs32_0 <= 8'h0; fs32_1 <= 8'h0; fs32_2 <= 8'h0; fs32_3 <= 8'h0;
            rc_0 <= 8'h0; rc_1 <= 8'h0; rc_2 <= 8'h0; rc_3 <= 8'h0;
            sig_l <= 8'h0; sig_h <= 8'h0;
        end else begin
            dbg_state <= mstate;
            sd_rd_en  <= 1'b0;              // 单拍脉冲

            case (mstate)
            // ------------------------------------------------------------------
            M_IDLE: begin
                mount_done <= 1'b0;
                if (start) begin
                    mount_error <= 1'b0;
                    err_code    <= `ERR_NONE;
                    err_detail  <= `DET_NONE;
                    bcnt        <= 10'd0;
                    to_cnt      <= 32'd0;
                    sd_rd_addr  <= 32'd0;   // DBR 固定在 0 号扇区
                    sd_rd_len   <= 16'd1;
                    mstate      <= M_REQ;
                end
            end
            // ---- 发起读请求 --------------------------------------------------
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
            // ---- 收 512 字节，按偏移抽取 BPB 字段 -----------------------------
            M_RECV: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= M_ERR;
                end else if (sd_data_valid) begin
                    // 小端：先收到的字节是低位
                    case (bcnt)
                        10'd11 : bps_l   <= sd_data;
                        10'd12 : bps_h   <= sd_data;
                        10'd13 : spc     <= sd_data;
                        10'd14 : rsvd_l  <= sd_data;
                        10'd15 : rsvd_h  <= sd_data;
                        10'd16 : nfat    <= sd_data;
                        10'd17 : roote_l <= sd_data;
                        10'd18 : roote_h <= sd_data;
                        10'd19 : ts16_l  <= sd_data;
                        10'd20 : ts16_h  <= sd_data;
                        10'd21 : media   <= sd_data;
                        10'd22 : fs16_l  <= sd_data;
                        10'd23 : fs16_h  <= sd_data;
                        10'd32 : ts32_0  <= sd_data;
                        10'd33 : ts32_1  <= sd_data;
                        10'd34 : ts32_2  <= sd_data;
                        10'd35 : ts32_3  <= sd_data;
                        10'd36 : fs32_0  <= sd_data;
                        10'd37 : fs32_1  <= sd_data;
                        10'd38 : fs32_2  <= sd_data;
                        10'd39 : fs32_3  <= sd_data;
                        10'd44 : rc_0    <= sd_data;
                        10'd45 : rc_1    <= sd_data;
                        10'd46 : rc_2    <= sd_data;
                        10'd47 : rc_3    <= sd_data;
                        10'd510: sig_l   <= sd_data;
                        10'd511: sig_h   <= sd_data;
                        default: ;
                    endcase
                    bcnt <= bcnt + 10'd1;
                    // 收满 512 字节即评估（不依赖 rd_done，rd_data_last 可作为交叉检查）
                    if (bcnt == 10'd511) mstate <= M_EVAL;
                end
            end
            // ---- 校验 + 计算派生地址 -----------------------------------------
            M_EVAL: begin
                if (sd_timeout_err || sd_crc16_err) begin
                    // 介质层已经报错，直接透传它的细分码
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= M_ERR;
                end else if (!w_sig_ok) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;          // 签名不是 0x55AA
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[0]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;          // 每扇区不是 512 字节
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[1]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_NOT32;        // 不是 FAT32
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[2] || !bpb_checks_q[3]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;          // 每簇扇区数 / FAT 数量非法
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[4]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;          // 根目录簇号非法
                    mstate     <= M_ERR;
                end else begin
                    // ---- 全部合法：算出后续模块需要的全部基准地址 ----
                    bytes_per_sec  <= w_bps;
                    sec_per_clus   <= spc;
                    num_fats       <= nfat;
                    fat_start_lba  <= {16'd0, w_rsvd};
                    root_clus      <= w_rc;
                    data_start_lba <= {16'd0, w_rsvd} + (nfat == 8'd2 ? (w_fs32<<1) : w_fs32);
                    root_dir_lba   <= {16'd0, w_rsvd} + (nfat == 8'd2 ? (w_fs32<<1) : w_fs32)
                                      + ((w_rc - 32'd2) << w_log2_spc);
                    total_sec      <= w_ts32;
                    // ★ 这里绝对不能用 `/ spc`。
                    //   Verilog 的除法运算符会被综合器实现成【组合除法阵列】：
                    //   TD 2026-10-02 的综合报告（evidence/reports/ 条目 TC-Q-STA-2）
                    //   显示这条路径 Logic Level = 100、其中 ADDER = 68、长 105 ns，
                    //   直接把 50 MHz 的建立时间顶穿（SWNS = -85.399 ns，28 个端点违例），
                    //   而 ModelSim 里除法是零延迟、530 项断言全绿也看不出来。
                    //   改用移位：本分支已由 spc_ok 保证 spc 是 2 的幂（1..128），
                    //   所以 `X / spc` 与 `X >> log2(spc)` 对无符号数是【逐值等价】的。
                    //   ⇒ 行为与原来完全一致（既有 TB 断言逐字不变），只是不再有除法器。
                    total_clus     <= (w_ts32 - ({16'd0, w_rsvd} + (nfat == 8'd2 ? (w_fs32<<1) : w_fs32))) >> w_log2_spc;
                    mstate         <= M_DONE;
                end
            end
            // ------------------------------------------------------------------
            M_DONE: begin
                mount_done <= 1'b1;
                if (start) begin
                    // 重新挂载：必须把偏移与兜底超时一起清零，否则会读错字段/立刻超时
                    mount_done <= 1'b0;
                    bcnt       <= 10'd0;
                    to_cnt     <= 32'd0;
                    sd_rd_addr <= 32'd0;
                    mstate     <= M_REQ;
                end
            end
            M_ERR: begin
                mount_error <= 1'b1;
                if (start) begin
                    mount_error <= 1'b0;
                    err_code    <= `ERR_NONE;
                    err_detail  <= `DET_NONE;
                    bcnt        <= 10'd0;
                    to_cnt      <= 32'd0;
                    mstate      <= M_REQ;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end

endmodule