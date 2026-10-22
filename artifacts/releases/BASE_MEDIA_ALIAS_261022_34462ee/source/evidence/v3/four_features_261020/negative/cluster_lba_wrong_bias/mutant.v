// One physical kernel; sector-boundary contexts are stored by v3_wav_source.
// ============================================================================
// file_streamer.v — 文件字节流（SafeVision 阶段 7 · rtl/storage）
// ----------------------------------------------------------------------------
// 依据：手册 7.6 / 7.7「把 (首簇, 文件大小) 变成连续字节流」
//       本模块职责与接口：
//         file_streamer.v — 输出统一 byte valid/ready/sof/eof/error
//       「File Stream」接口：data[7:0], valid, ready, sof, eof, error
//       「可反压流」统一规则
//
// 输入：(first_clus, file_size) —— 来自 fat32_directory_scanner / 索引表
// 输出：一串字节，带 sof / eof / error
//
// ★ 三层节奏：
//     扇区层：一次 CMD17 读 512 Byte（sd_sector_reader 只支持单扇区，O-11）
//     簇  层：一个簇读完，用 fat32_cluster_walker 去 FAT 查下一个簇
//     字节层：向上游要一个字节 -> 先记账 -> 再交给下游，下游 ready 低就端着
//
// ★ 两条最容易写错的规则（都是实测踩出来的，见 interface_spec §一）：
//   1) 从 sd_sector_reader 收字节必须用 `sd_data_valid && sd_data_ready` 门控。
//      上游会把 data_valid 挂在同一个字节上不放，只判 valid 会把同一字节
//      吃掉很多次。
//   2) 字节数够到 file_size 之后【不能中途停读】。sd_sector_reader 的
//      rd_ready 只在 S_IDLE 有效，中途把 data_ready 拉低不放，它会永远停在
//      S_DATA，之后每一次读都拿不到 rd_ready。正确做法是记下 stop_pending，
//      把本扇区剩下的字节收干净（丢掉），再收工。
//
// ★ 反压：下游 ready 低时，valid/data/sof/eof 全部保持不动，并且【不再向上游
//   要新字节】。字节记账发生在"从上游取到字节"的那一拍，和下游取走无关，
//   所以下游慢不会导致 bytes_rd 与实际不符。
//
// ★ file_size = 0：直接收工，一个字节都不发，也不会发 sof/eof。
// ============================================================================
`include "safevision_defs.vh"

// V3 derivative: freeze ONLY idle_between_sectors during intentional cache pause.
// Native clk remains running; timeout protection stays enabled for every live transaction.
module v3_file_streamer_compact_ctx (
    input wire context_load,
    input wire [135:0] context_in,
    output wire [135:0] context_out,
    input wire context_enable,
    input wire stream_enable,
    output wire idle_between_sectors,
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,          // 单拍：开始读一个文件
    input  wire [31:0] first_clus,
    input  wire [31:0] file_size,      // 文件字节数
    output reg         busy,
    output reg         done,           // 电平：本次读结束（成功或出错都置 1）
    output reg         error,          // 电平：出错
    output reg  [7:0]  err_code,       // 对外主码
    output reg  [7:0]  err_detail,     // 内部细分码
    output wire [31:0] bytes_rd,       // 已发出的字节数（与电脑端比对用）
    output reg  [3:0]  dbg_state,

    // ---- 字节流输出（可反压流）----
    output reg  [7:0]  data,
    output reg         valid,
    input  wire        ready,
    output reg         sof,            // 与第一个字节同拍
    output reg         eof,            // 与最后一个字节同拍

    // ---- 来自 fat32_boot_parser 的基准 ----
    input  wire [7:0]  sec_per_clus,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] total_clus,

    // ---- 到 fat32_cluster_walker ----
    output reg  [31:0] wk_cur_clus,
    output reg         wk_start,
    output reg         wk_rst_walk,
    input  wire        wk_busy,
    input  wire        wk_done,
    input  wire [31:0] wk_next_clus,
    input  wire        wk_eoc,
    input  wire        wk_error,
    input  wire [7:0]  wk_err_code,
    input  wire [7:0]  wk_err_detail,

    // ---- 到 sd_sector_reader 的读请求 ----
    output reg  [31:0] sd_rd_addr,
    output wire [15:0] sd_rd_len,
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

    // Mounted FAT32 contract: sectors/cluster is a power of two in 1..128.
    function [31:0] cluster_sectors;
      input [31:0] delta;input [7:0] spc;
      reg[31:0] shifted1,shifted2,shifted4;
      reg legal;
      begin
       legal=(spc!=0)&&((spc&(spc-8'd1))==0);
       shifted1=(spc[1]|spc[3]|spc[5]|spc[7]) ? (delta<<1) : delta;
       shifted2=(spc[2]|spc[3]|spc[6]|spc[7]) ? (shifted1<<2) : shifted1;
       shifted4=(|spc[7:4]) ? (shifted2<<4) : shifted2;
       cluster_sectors=legal ? shifted4 : 32'd0;
      end
    endfunction

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [2:0] F_IDLE     = 3'd0,
                     F_SEC_REQ  = 3'd1,
                     F_SEC_RECV = 3'd2,
                     F_WALK     = 3'd3,
                     F_DONE     = 3'd4,
                     F_ERR      = 3'd5;

    reg  [2:0]  mstate;

    reg  [31:0] cur_lba;
    reg  [7:0]  sec_in_clus;    // 本簇已读扇区数
    reg  [8:0]  bcnt;           // 扇区内字节偏移
    reg  [31:0] cnt;            // 已发出字节数
    reg  [31:0] fsize;          // 本文件目标字节数
    reg         stop_pending;   // 字节数够了：本扇区收完就收工
    // Every counting state exits or clears at SD_TO_DATA. The last
    // scheduled increment can reach SD_TO_DATA+1, which this width retains.
    localparam integer TO_W=$clog2(`SD_TO_DATA+32'd2);
    reg [TO_W-1:0] to_cnt;

    assign idle_between_sectors = (mstate == F_SEC_REQ) && !valid;
    assign sd_data_ready = (mstate == F_SEC_RECV) && !valid;   // 手里端着字节就不再向上游要
    assign sd_rd_len     = 16'd1;

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    // Only F_SEC_REQ && !valid is a legal context save point. All transient
    // command/data/error state is rebuilt on LOAD; it never occupies the
    // rotating persistent state. The caller must gate SD during SAVE/LOAD.
    assign context_out={wk_cur_clus,cur_lba,sec_in_clus,cnt,fsize};
    assign bytes_rd=cnt;
    // Exact modular FAT32 LBA: (cluster-2)*SPC+base = cluster*SPC+
    // (base-2*SPC). Move the subtract away from the selected cluster path.
    // Invalid SPC still maps to base because cluster_sectors returns zero.
    wire [31:0] cluster_argument=(mstate==F_IDLE)?first_clus:wk_next_clus;
    wire cluster_spc_legal=(sec_per_clus!=0)&&((sec_per_clus&(sec_per_clus-8'd1))==0);
    (* use_ripple=1 *) wire [31:0] cluster_lba_bias=data_start_lba-(cluster_spc_legal?{24'd0,sec_per_clus}:32'd0);
    wire[31:0] cluster_offset=cluster_sectors(cluster_argument,sec_per_clus);
    (* use_ripple=1 *) wire[31:0] next_cluster_lba=cluster_lba_bias+cluster_offset;
    wire [31:0] next_count=cnt+32'd1;
    wire last_file_byte=next_count==fsize;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= F_IDLE;

            cur_lba      <= 32'd0;
            sec_in_clus  <= 8'd0;
            bcnt         <= 9'd0;
            cnt          <= 32'd0;
            fsize        <= 32'd0;
            stop_pending <= 1'b0;
            to_cnt       <= 32'd0;
            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;

            dbg_state    <= F_IDLE;
            data         <= 8'h00;
            valid        <= 1'b0;
            sof          <= 1'b0;
            eof          <= 1'b0;
            wk_cur_clus  <= 32'd0;
            wk_start     <= 1'b0;
            wk_rst_walk  <= 1'b0;
            sd_rd_addr   <= 32'd0;
            sd_rd_en     <= 1'b0;
        end else if(context_load)begin
            {wk_cur_clus,cur_lba,sec_in_clus,cnt,fsize} <= context_in;
            mstate<=F_SEC_REQ;bcnt<=0;to_cnt<=0;stop_pending<=0;
            busy<=1;done<=0;error<=0;err_code<=0;err_detail<=0;
            data<=0;valid<=0;sof<=0;eof<=0;dbg_state<=F_SEC_REQ;
            sd_rd_addr<=0;sd_rd_en<=0;wk_start<=0;wk_rst_walk<=0;
        end else if (stream_enable && context_enable) begin
            dbg_state   <= mstate;
            sd_rd_en    <= 1'b0;        // 单拍脉冲
            wk_start    <= 1'b0;        // 单拍脉冲
            wk_rst_walk <= 1'b0;        // 单拍脉冲
            busy        <= (mstate != F_IDLE);

            // ---- 下游把手里这个字节收走了 ----------------------------------
            // ★ 必须放在 case 之外、对所有状态生效。原因：一个扇区的最后一个
            //   字节被锁存时（valid=1）正好也是扇区结束那一拍，state 立刻跳到
            //   F_SEC_REQ；如果清零逻辑只写在 F_SEC_RECV 里，valid 就再也没人清，
            //   而 F_SEC_REQ 又在等 !valid —— 直接死等到兜底超时。
            //   这是实测中真实踩过的坑。
            if (valid && ready) begin
                valid <= 1'b0;
                sof   <= 1'b0;
                eof   <= 1'b0;
            end

            case (mstate)
            // ------------------------------------------------------------------
            F_IDLE: begin
                if (start) begin
                    done         <= 1'b0;
                    error        <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    valid        <= 1'b0;
                    sof          <= 1'b0;
                    eof          <= 1'b0;
                    cnt          <= 32'd0;

                    fsize        <= file_size;

                    cur_lba      <= next_cluster_lba;
                    sec_in_clus  <= 8'd0;
                    bcnt         <= 9'd0;
                    stop_pending <= 1'b0;
                    to_cnt       <= 32'd0;
                    wk_cur_clus  <= first_clus;
                    wk_rst_walk  <= 1'b1;      // 走新链前清跳簇计数
                    if (file_size == 32'd0) begin
                        // 空文件：一个字节都不发，直接收工
                        mstate <= F_DONE;
                    end else begin
                        mstate <= F_SEC_REQ;
                    end
                end
            end
            // ---- 请求读当前扇区 ----------------------------------------------
            F_SEC_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= F_ERR;
                end else if (!valid && sd_rd_ready) begin
                    sd_rd_addr <= cur_lba;
                    sd_rd_en   <= 1'b1;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= F_SEC_RECV;
                end
            end
            // ---- 收一个扇区，边收边往下游送 ---------------------------------
            F_SEC_RECV: begin
                // 下游慢不算上游超时
                if (!valid) to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= F_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= F_ERR;
                end else begin
                    // (a) 下游取走字节由 case 之外的公共逻辑处理（见上文★）
                    // (b) 手里空了，就向上游要一个（必须 valid && ready 双判）
                    if (!valid && sd_data_valid && sd_data_ready) begin
                        bcnt <= bcnt + 9'd1;

                        if (!stop_pending) begin
                            data  <= sd_data;
                            valid <= 1'b1;
                            sof   <= (cnt == 32'd0);
                            eof   <= (last_file_byte);
                            cnt   <= next_count;

                            // 本字节就是文件的最后一个：之后只排空，不再外送
                            if (last_file_byte) stop_pending <= 1'b1;
                        end

                        // (c) 扇区收完：决定下一个扇区从哪来
                        if (bcnt == 9'd511) begin
                            // ★ stop_pending 是"上一拍"的值；当文件的最后一个字节
                            //   正好落在扇区最后一个字节时，它要到下一拍才生效。
                            //   所以这里必须把"本拍锁存的就是最后一字节"也算进去，
                            //   否则会白跳一次簇、撞上 EOC 误报 DET_FS_SHORT。
                            if (stop_pending || (last_file_byte)) begin
                                mstate <= F_DONE;
                            end else if ((sec_in_clus + 8'd1) >= sec_per_clus) begin
                                wk_start <= 1'b1;      // 一个簇读完，去查下一个簇
                                mstate   <= F_WALK;
                            end else begin
                                cur_lba     <= cur_lba + 32'd1;
                                sec_in_clus <= sec_in_clus + 8'd1;
                                to_cnt      <= 32'd0;
                                mstate      <= F_SEC_REQ;
                            end
                        end
                    end
                end
            end
            // ---- 查下一个簇 --------------------------------------------------
            F_WALK: begin
                if (wk_done) begin
                    if (wk_eoc) begin
                        // 链到头了还没凑够 file_size 个字节
                        err_code   <= `ERR_MEDIA_INVALID;
                        err_detail <= `DET_FS_SHORT;
                        mstate     <= F_ERR;
                    end else if (wk_error) begin
                        err_code   <= wk_err_code;
                        err_detail <= wk_err_detail;
                        mstate     <= F_ERR;
                    end else begin

                        wk_cur_clus <= wk_next_clus;
                        cur_lba     <= next_cluster_lba;
                        sec_in_clus <= 8'd0;
                        to_cnt      <= 32'd0;
                        mstate      <= F_SEC_REQ;
                    end
                end
            end
            // ------------------------------------------------------------------
            F_DONE: begin
                // 等最后一个字节被下游取走再宣告结束
                if (!valid) begin
                    done   <= 1'b1;
                    mstate <= F_IDLE;
                end
            end
            F_ERR: begin
                error  <= 1'b1;
                done   <= 1'b1;
                mstate <= F_IDLE;
            end
            default: mstate <= F_IDLE;
            endcase
        end
    end

endmodule