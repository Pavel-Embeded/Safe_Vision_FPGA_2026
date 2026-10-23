// ============================================================================
// fat32_cluster_walker.v — FAT32 簇链跟踪（SafeVision 阶段 7 · rtl/storage）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「FAT32 要回答的是：一个文件占用了哪些簇、按什么顺序串起来」
//       本模块职责：
//         fat32_cluster_walker.v — FAT 簇链、EOF、环/坏簇/越界检测
//
// 只做一件事：给一个簇号，去 FAT 表查出它的下一个簇号，并判定三种收尾：
//     eoc    : 下一个簇号 >= 0x0FFFFFF8，链到头（正常收尾）
//     error  : 簇号越界 / 首簇非法 -> DET_DIR_OOB
//              跳簇次数 > total_clus -> DET_FS_LOOP（成环）
//     normal : next_clus 合法，可以继续走
//
// ★ 为什么单独抽一个模块？
//   `fat32_directory_scanner`（遍历根目录）和 `file_streamer`（读文件内容）
//   都要跳簇。各写一份会导致"两处判环逻辑不一致"这种最难查的 bug，
//   所以把它独立成一个模块，两边共用同一份。
//
// ★ FAT 入口寻址（FAT32 规范）：
//     入口字节偏移 = clus * 4
//     扇区号      = fat_start_lba + (clus*4) / 512
//     扇区内偏移  = (clus*4) % 512
//   入口是【小端】：地址最低的字节是 32bit 值的 bit[7:0]。
//   高 4 bit 是保留位，必须掩掉，只取 [27:0] 再判 EOC。
//
// ★ 用法：
//     - 开始走一条新链前，先拉一拍 rst_walk 清跳簇计数；
//     - 之后每要"下一簇"就拉一拍 start（cur_clus = 当前簇号）；
//     - done 拉高那一拍读 eoc / error / next_clus。
//
// ★ 依赖：sd_sector_reader 目前只支持单扇区读（O-11），所以这里读一整个
//   FAT 扇区（512 Byte）只为抽出 4 Byte。等 CMD18 落地后可优化。
// ============================================================================
`include "safevision_defs.vh"

module fat32_cluster_walker (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        rst_walk,      // 单拍：清跳簇计数（开始走一条新链）
    input  wire        start,         // 单拍：请求查 cur_clus 的下一个簇
    input  wire [31:0] cur_clus,      // 当前簇号
    output reg         busy,          // 查表中
    output reg         done,          // 单拍：本次查表结束
    output reg  [31:0] next_clus,     // 有效 = done && !eoc && !error
    output reg         eoc,           // 单拍有效（与 done 同拍）：链到头
    output reg         error,         // 单拍有效（与 done 同拍）：簇链异常
    output reg  [7:0]  err_code,      // 对外主码
    output reg  [7:0]  err_detail,    // 内部细分码
    output reg  [31:0] hop_cnt,       // 已跳簇次数（判环用，供观测）
    output reg  [3:0]  dbg_state,

    // ---- 来自 fat32_boot_parser 的基准 ----
    input  wire [31:0] fat_start_lba, // FAT1 起始扇区
    input  wire [31:0] total_clus,    // 总簇数（判越界 / 判环）

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

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [2:0] W_IDLE = 3'd0,
                     W_REQ  = 3'd1,   // 发起读 FAT 扇区
                     W_RECV = 3'd2,   // 收 512 Byte，抽出 4 Byte 入口
                     W_DONE = 3'd3,
                     W_ERR  = 3'd4;

    reg  [2:0]  mstate;
    reg  [8:0]  bcnt;          // 扇区内字节偏移
    reg  [8:0]  fat_off;       // 目标入口在扇区内的偏移
    reg  [31:0] fat_val;       // 4 Byte 入口，byte0 落在 [7:0]
    reg  [31:0] to_cnt;        // 兜底超时

    // 入口地址
    wire [31:0] fat_byte_off = {cur_clus[29:0], 2'b00};   // clus*4
    wire [31:0] fat_lba      = fat_start_lba + (fat_byte_off >> 9);

    // fat_off always has low2bits00 (reset or cur_clus*4). Prefix equality
    // selects precisely its four-byte window; no range add/compare is needed.
    wire        fat_in_win = (bcnt[8:2] == fat_off[8:2]);
    // nxt_* is consumed only on accepted sector byte511. The current
    // byte belongs to the entry exactly when its aligned offset is508.
    // Keep byte-counter/window decoding OUT of the32-bit classifier mux.
    wire [31:0] fat_now    = (fat_off[8:2]==7'd126) ? {sd_data, fat_val[31:8]} : fat_val;
    wire [27:0] nxt_clus   = fat_now[27:0];               // 高 4 位保留位掩掉
    wire        nxt_eoc    = (nxt_clus >= 28'h0FFF_FFF8);
    wire        nxt_oob    = (nxt_clus < 28'd2) ||
                             ({4'b0, nxt_clus} > (total_clus + 32'd1));
    function unsigned_ge32;
        input [31:0] a,b;
        reg [3:0] gt,eq;integer q;
        begin
            for(q=0;q<4;q=q+1)begin
                gt[q]=(a[q*8+:8]>b[q*8+:8]);
                eq[q]=(a[q*8+:8]==b[q*8+:8]);
            end
            unsigned_ge32=gt[3]||(eq[3]&&(gt[2]||(eq[2]&&(gt[1]||(eq[1]&&(gt[0]||eq[0]))))));
        end
    endfunction
    // Exact 32-bit modulo identity: (H+1)>T iff H!=0xffffffff && H>=T.
    // Keep the overflow guard; dropping it changes a legal context boundary.
    wire        nxt_loop   = (!(&hop_cnt)) && unsigned_ge32(hop_cnt,total_clus);

    assign sd_data_ready = (mstate == W_RECV);
    assign sd_rd_len     = 16'd1;

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate     <= W_IDLE;
            bcnt       <= 9'd0;
            fat_off    <= 9'd0;
            fat_val    <= 32'h0;
            to_cnt     <= 32'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
            next_clus  <= 32'd0;
            eoc        <= 1'b0;
            error      <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            hop_cnt    <= 32'd0;
            dbg_state  <= W_IDLE;
            sd_rd_addr <= 32'd0;
            sd_rd_en   <= 1'b0;
        end else begin
            dbg_state <= mstate;
            done      <= 1'b0;              // 单拍脉冲
            sd_rd_en  <= 1'b0;              // 单拍脉冲
            busy      <= (mstate != W_IDLE);

            // 清跳簇计数：走一条新链前拉一拍
            if (rst_walk) hop_cnt <= 32'd0;

            case (mstate)
            // ------------------------------------------------------------------
            W_IDLE: begin
                if (start) begin
                    eoc        <= 1'b0;
                    error      <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    next_clus  <= 32'd0;
                    fat_off    <= {cur_clus[6:0], 2'b00};   // (clus*4) % 512
                    fat_val    <= 32'h0;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= W_REQ;
                end
            end
            // ---- 请求读 FAT 扇区 ---------------------------------------------
            W_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= W_ERR;
                end else if (sd_rd_ready) begin
                    sd_rd_addr <= fat_lba;
                    sd_rd_en   <= 1'b1;
                    to_cnt     <= 32'd0;
                    mstate     <= W_RECV;
                end
            end
            // ---- 收 FAT 扇区，抽出 4 Byte 入口 -------------------------------
            W_RECV: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= W_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= W_ERR;
                end else if (sd_data_valid && sd_data_ready) begin
                    if (fat_in_win) fat_val <= {sd_data, fat_val[31:8]};

                    bcnt <= bcnt + 9'd1;
                    if (bcnt == 9'd511) begin
                        if (nxt_eoc) begin
                            eoc      <= 1'b1;
                            next_clus<= {4'b0, nxt_clus};
                            mstate   <= W_DONE;
                        end else if (nxt_oob) begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_DIR_OOB;
                            mstate     <= W_ERR;
                        end else if (nxt_loop) begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_FS_LOOP;
                            mstate     <= W_ERR;
                        end else begin
                            next_clus <= {4'b0, nxt_clus};
                            hop_cnt   <= hop_cnt + 32'd1;
                            mstate    <= W_DONE;
                        end
                    end
                end
            end
            // ------------------------------------------------------------------
            W_DONE: begin
                done   <= 1'b1;
                mstate <= W_IDLE;
            end
            W_ERR: begin
                error  <= 1'b1;
                done   <= 1'b1;
                mstate <= W_IDLE;
            end
            default: mstate <= W_IDLE;
            endcase
        end
    end

endmodule