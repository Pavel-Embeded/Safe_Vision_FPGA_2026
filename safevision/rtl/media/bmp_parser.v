// ============================================================================
// bmp_parser.v — BMP 头严格校验（SafeVision 阶段 7 · rtl/media）
// ----------------------------------------------------------------------------
// 依据：手册 7.6.1 的 BMP 校验清单
//       本模块职责与接口：
//         bmp_parser.v — Header、BGR、bottom-up、行 padding 转换
//       「Image Stream」接口
//
// 只做"头"这一半：把 DIB 头读完、逐条核对，合格才让像素数据继续往下走。
// BGR 换序 / bottom-up 翻行 / 行 padding 属于 bmp_unpack（阶段 8），不在本模块。
//
// ★ 校验清单（手册 7.6.1，第一条不通过就停，细分码指出是哪一条）
//     1) 0x00 两个字节必须是 'B','M'          -> DET_BMP_SIG
//     2) biSize >= 40（BITMAPINFOHEADER）      -> DET_BMP_DIB
//     3) 宽 = 640，高 = ±480                   -> DET_BMP_SIZE
//        高为负表示 top-down（行从上往下存），正表示 bottom-up（手册要求处理）
//     4) biPlanes = 1，biBitCount = 24，
//        biCompression = 0（BI_RGB，不压缩）   -> DET_BMP_FMT
//     5) bfOffBits >= 54，bfSize <= 文件长度，
//        且 bfOffBits + 640*480*3 <= 文件长度   -> DET_BMP_TRUNC
//        640*3 = 1920 能被 4 整除，所以 24bpp 每行天然无 padding
//
// ★ 字节序：BMP 所有多字节字段都是【小端】。装配用"新字节从高端进、
//   老字节往低端退"（{new, old[31:8]}），装反了会把 640 读成
//   0x80020000 这种数，直接落进尺寸校验失败，症状很误导。
//
// ★ 校验通过后本模块变成"透传"：把 bfOffBits 之后的像素字节原样转给下游
//   bmp_unpack。校验不通过则只把本文件的字节排空、不外送，避免上游
//   file_streamer 卡死（它的 rd_ready 只在空闲态有效）。
// ============================================================================
`include "safevision_defs.vh"

module bmp_parser (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 输入：file_streamer 的字节流（本模块是它的下游）----
    input  wire [7:0]  data,
    input  wire        valid,
    output wire        ready,
    input  wire        eof,          // 与最后一个字节同拍
    input  wire [31:0] file_size,    // 本文件声明长度（来自 file_streamer / 索引表）

    // ---- 校验结果 ----
    output reg         check_done,   // 单拍：头解析结束
    output reg         check_error,  // 电平：头不合法（与 check_done 同拍起有效）
    output reg  [7:0]  err_code,     // 对外主码
    output reg  [7:0]  err_detail,   // 内部细分码
    output reg  [15:0] width,
    output reg  [15:0] height,       // bit15 = 1 表示 top-down（手册：负高）
    output reg         top_down,
    output reg  [7:0]  bpp,
    output reg  [31:0] compression,
    output reg  [31:0] pixel_off,    // = bfOffBits
    output reg  [31:0] file_size_o,  // 回读，供日志
    output reg  [3:0]  dbg_state,

    // ---- 透传：像素字节交给 bmp_unpack（阶段 8）----
    output reg  [7:0]  out_data,
    output reg         out_valid,
    input  wire        out_ready,
    output reg         out_sof,      // 与像素数据第一个字节同拍
    output reg         out_eof       // 与像素数据最后一个字节同拍
);

    // 640 x 480 x 3 Byte —— 24bpp 无 padding
    localparam [31:0] BMP_PIX_BYTES = 32'd921_600;
    localparam [31:0] BMP_HDR_BYTES = 32'd54;      // 14 + 40

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    localparam [1:0] H_HEAD = 2'd0,   // 读前 54 Byte 头
                     H_XFER = 2'd1,   // 排空 / 透传
                     H_DONE = 2'd2;

    reg  [1:0]  mstate;
    reg  [31:0] hcnt;          // 已消费字节数
    reg  [31:0] skip_cnt;      // 头之后、像素之前还要丢掉的字节数
    reg         hdr_ok;

    // ---- 头字段装配（小端）----
    reg  [31:0] bfsize_r;
    reg  [31:0] offbits_r;
    reg  [31:0] dibsize_r;
    reg  [31:0] width_r;
    reg  [31:0] height_r;
    reg  [15:0] planes_r;
    reg  [15:0] bpp_r;
    reg  [31:0] comp_r;
    reg  [7:0]  sig0;
    reg  [7:0]  sig1;

    // ---- 校验用组合判定 ----
    wire sig_ok    = (sig0 == 8'h42) && (sig1 == 8'h4D);            // 'B','M'
    wire dib_ok    = (dibsize_r >= 32'd40);
    wire size_ok   = (width_r == 32'd640) &&
                     ((height_r == 32'd480) || (height_r == -32'sd480));
    wire fmt_ok    = (planes_r == 16'd1) && (bpp_r == 16'd24) && (comp_r == 32'd0);
    wire trunc_ok  = (offbits_r >= BMP_HDR_BYTES) &&
                     (bfsize_r <= file_size) &&
                     ((offbits_r + BMP_PIX_BYTES) <= file_size);

    wire        check_ok = sig_ok && dib_ok && size_ok && fmt_ok && trunc_ok;

    assign ready = (mstate == H_HEAD) ||
                   (mstate == H_XFER && (!hdr_ok || !out_valid));

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= H_HEAD;
            hcnt        <= 32'd0;
            skip_cnt    <= 32'd0;
            hdr_ok      <= 1'b0;
            bfsize_r    <= 32'h0;
            offbits_r   <= 32'h0;
            dibsize_r   <= 32'h0;
            width_r     <= 32'h0;
            height_r    <= 32'h0;
            planes_r    <= 16'h0;
            bpp_r       <= 16'h0;
            comp_r      <= 32'h0;
            sig0        <= 8'h0;
            sig1        <= 8'h0;
            check_done  <= 1'b0;
            check_error <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            width       <= 16'd0;
            height      <= 16'd0;
            top_down    <= 1'b0;
            bpp         <= 8'd0;
            compression <= 32'd0;
            pixel_off   <= 32'd0;
            file_size_o <= 32'd0;
            dbg_state   <= H_HEAD;
            out_data    <= 8'h00;
            out_valid   <= 1'b0;
            out_sof     <= 1'b0;
            out_eof     <= 1'b0;
        end else begin
            dbg_state  <= mstate;
            check_done <= 1'b0;             // 单拍脉冲

            case (mstate)
            // ---- 读前 54 Byte 头 -------------------------------------------
            H_HEAD: begin
                if (valid && ready) begin
                    // 小端装配：新字节进高端，老字节往低端退
                    case (hcnt)
                        32'd0 : sig0 <= data;
                        32'd1 : sig1 <= data;
                        32'd2, 32'd3, 32'd4, 32'd5  : bfsize_r  <= {data, bfsize_r[31:8]};
                        32'd10, 32'd11, 32'd12, 32'd13: offbits_r <= {data, offbits_r[31:8]};
                        32'd14, 32'd15, 32'd16, 32'd17: dibsize_r <= {data, dibsize_r[31:8]};
                        32'd18, 32'd19, 32'd20, 32'd21: width_r   <= {data, width_r[31:8]};
                        32'd22, 32'd23, 32'd24, 32'd25: height_r  <= {data, height_r[31:8]};
                        32'd26, 32'd27                : planes_r  <= {data, planes_r[15:8]};
                        32'd28, 32'd29                : bpp_r     <= {data, bpp_r[15:8]};
                        32'd30, 32'd31, 32'd32, 32'd33: comp_r    <= {data, comp_r[31:8]};
                        default: ;
                    endcase

                    hcnt <= hcnt + 32'd1;

                    if (eof && (hcnt != (BMP_HDR_BYTES - 32'd1))) begin
                        // 头还没读完文件就结束了
                        check_error <= 1'b1;
                        err_code    <= `ERR_MEDIA_INVALID;
                        err_detail  <= `DET_BMP_TRUNC;
                        check_done  <= 1'b1;
                        file_size_o <= file_size;
                        out_eof     <= 1'b1;
                        mstate      <= H_DONE;
                    end else if (hcnt == (BMP_HDR_BYTES - 32'd1)) begin
                        // 第 54 个字节到手：全部字段已装配完（组合判定用的是
                        // 本拍就绪的寄存器值，最后一个字段在 hcnt=33 就齐了）
                        check_done  <= 1'b1;
                        file_size_o <= file_size;
                        pixel_off   <= offbits_r;
                        width       <= width_r[15:0];
                        height      <= height_r[15:0];
                        top_down    <= height_r[31];
                        bpp         <= bpp_r[7:0];
                        compression <= comp_r;
                        hdr_ok      <= check_ok;
                        check_error <= !check_ok;
                        if (!check_ok) begin
                            err_code <= `ERR_MEDIA_INVALID;
                            if      (!sig_ok)   err_detail <= `DET_BMP_SIG;
                            else if (!dib_ok)   err_detail <= `DET_BMP_DIB;
                            else if (!size_ok)  err_detail <= `DET_BMP_SIZE;
                            else if (!fmt_ok)   err_detail <= `DET_BMP_FMT;
                            else                err_detail <= `DET_BMP_TRUNC;
                        end
                        // 头之后到像素开头之间可能还有调色板/填充，要丢掉
                        skip_cnt <= (offbits_r > BMP_HDR_BYTES)
                                    ? (offbits_r - BMP_HDR_BYTES) : 32'd0;
                        out_eof  <= eof;
                        // 文件只有头、没有像素数据时直接收尾
                        mstate   <= eof ? H_DONE : H_XFER;
                    end
                end
            end
            // ---- 排空剩余头字节 / 透传像素数据 ------------------------------
            H_XFER: begin
                // 下游把手里这个字节收走了
                if (out_valid && out_ready) begin
                    out_valid <= 1'b0;
                    out_sof   <= 1'b0;
                    out_eof   <= 1'b0;
                end

                if (valid && ready) begin
                    hcnt <= hcnt + 32'd1;
                    if (skip_cnt != 32'd0) begin
                        skip_cnt <= skip_cnt - 32'd1;      // 调色板 / 填充，丢掉
                    end else if (hdr_ok) begin
                        out_data  <= data;
                        out_valid <= 1'b1;
                        out_sof   <= 1'b1;                 // 像素数据第一个字节
                        out_eof   <= eof;
                    end
                    if (eof) begin
                        out_eof <= 1'b1;
                        mstate  <= H_DONE;
                    end
                end
            end
            // ------------------------------------------------------------------
            // 本文件收尾：等最后一个透传字节被取走，然后复位"装配寄存器"，
            // 直接准备解析下一个文件。★ 注意只清装配寄存器，
            // check_done / check_error / err_* / width / height / pixel_off
            // 这些"结果寄存器"要保持到下一次 check_done，否则控制器会读不到。
            H_DONE: begin
                if (out_valid && out_ready) begin
                    out_valid <= 1'b0;
                    out_sof   <= 1'b0;
                    out_eof   <= 1'b0;
                end
                if (!out_valid) begin
                    hcnt      <= 32'd0;
                    skip_cnt  <= 32'd0;
                    hdr_ok    <= 1'b0;
                    sig0      <= 8'h0;
                    sig1      <= 8'h0;
                    bfsize_r  <= 32'h0;
                    offbits_r <= 32'h0;
                    dibsize_r <= 32'h0;
                    width_r   <= 32'h0;
                    height_r  <= 32'h0;
                    planes_r  <= 16'h0;
                    bpp_r     <= 16'h0;
                    comp_r    <= 32'h0;
                    mstate    <= H_HEAD;
                end
            end
            default: mstate <= H_HEAD;
            endcase
        end
    end

endmodule