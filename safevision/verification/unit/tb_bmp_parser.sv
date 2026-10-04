// ============================================================================
// tb_bmp_parser.sv — 阶段 7：BMP 头严格校验
// ----------------------------------------------------------------------------
// 被测：rtl/media/bmp_parser.v
// 本 TB 不挂 SPI：bmp_parser 是纯字节流模块，用一个合成字节源驱动即可，
// 这样每条负向分支都能在几百个周期内跑完，比挂真实卡快得多。
//
// ★ file_size 的口径：模块校验用的是【声明长度】（来自目录项 / 索引表），
//   不是"到目前收到了多少字节"。一张 640x480x24 的 BMP 像素数据有
//   921600 Byte，真在仿真里灌完太浪费，所以本 TB 只灌头部 + 少量像素，
//   但把 file_size 传成 offbits + 921600 —— 和真实链路上的行为一致。
//
// 验证内容：
//   T41 合法 BMP：字段全对 + 像素数据从 bfOffBits 开始透传
//   T42 签名不是 'BM'        -> DET_BMP_SIG，且一个字节都不透传
//   T43 biSize = 39          -> DET_BMP_DIB
//   T44 宽度 800             -> DET_BMP_SIZE
//   T45 biBitCount = 32      -> DET_BMP_FMT
//   T46 biCompression = 1    -> DET_BMP_FMT
//   T47 声明长度差 1 Byte    -> DET_BMP_TRUNC
//   T48 bfOffBits = 70（中间有 16 Byte 调色板/填充）：透传从第 70 个字节起
//   T49 高 = -480（top-down）：top_down = 1
//   T50 下游反压：不丢字节、内容不变
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_bmp_parser;

    localparam [31:0] PIX_BYTES = 32'd921_600;   // 640*480*3

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer wait_cnt;
    integer i;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // 合成字节源
    // ------------------------------------------------------------------------
    reg [7:0]  src_mem [0:8191];
    integer    src_len;
    reg        src_go;         // 单拍：武装（由激励驱动）
    reg        src_armed;      // 已武装、正在发（只由源自己驱动）
    reg        src_valid;
    reg [7:0]  src_data;
    reg        src_eof;
    integer    src_idx;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------
    reg  [31:0] bp_file_size;
    reg         bp_out_ready;

    wire        bp_ready;
    wire        bp_check_done, bp_check_error;
    wire [7:0]  bp_err_code, bp_err_detail;
    wire [15:0] bp_width, bp_height;
    wire        bp_top_down;
    wire [7:0]  bp_bpp;
    wire [31:0] bp_compression, bp_pixel_off, bp_file_size_o;
    wire [7:0]  bp_out_data;
    wire        bp_out_valid, bp_out_sof, bp_out_eof;

    bmp_parser u_bp (
        .clk(clk), .rst_n(rst_n),
        .data(src_data), .valid(src_valid), .ready(bp_ready),
        .eof(src_eof), .file_size(bp_file_size),
        .check_done(bp_check_done), .check_error(bp_check_error),
        .err_code(bp_err_code), .err_detail(bp_err_detail),
        .width(bp_width), .height(bp_height), .top_down(bp_top_down),
        .bpp(bp_bpp), .compression(bp_compression), .pixel_off(bp_pixel_off),
        .file_size_o(bp_file_size_o), .dbg_state(),
        .out_data(bp_out_data), .out_valid(bp_out_valid), .out_ready(bp_out_ready),
        .out_sof(bp_out_sof), .out_eof(bp_out_eof)
    );

    // ---- 源：只要 valid && ready 同拍就换下一个字节（单驱动源）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_valid <= 1'b0;
            src_data  <= 8'h00;
            src_eof   <= 1'b0;
            src_idx   <= 0;
            src_armed <= 1'b0;
        end else if (src_go) begin
            src_armed <= 1'b1;
            src_idx   <= 0;
            src_data  <= src_mem[0];
            src_eof   <= (src_len == 1);
            src_valid <= 1'b1;
        end else if (src_valid && bp_ready) begin
            if (src_idx + 1 < src_len) begin
                src_idx   <= src_idx + 1;
                src_data  <= src_mem[src_idx + 1];
                src_eof   <= (src_idx + 1 == src_len - 1);
                src_valid <= 1'b1;
            end else begin
                src_valid <= 1'b0;
                src_eof   <= 1'b0;
                src_armed <= 1'b0;      // 本文件发完，等下一次 src_go
            end
        end
    end

    // ---- 监视器：捕获结果 + 收集透传字节 ----
    reg [7:0]  sink_mem [0:8191];
    integer    out_n;
    integer    out_sof_n, out_eof_n;
    reg [7:0]  sink_first;
    integer    chk_cnt;
    reg        chk_err;
    reg [7:0]  chk_ec, chk_ed;
    reg [15:0] chk_w, chk_h;
    reg [7:0]  chk_bpp;
    reg [31:0] chk_comp, chk_off;
    reg        chk_td;

    always @(posedge clk) begin
        if (bp_check_done === 1'b1) begin
            chk_cnt = chk_cnt + 1;
            chk_err = bp_check_error;
            chk_ec  = bp_err_code;
            chk_ed  = bp_err_detail;
            chk_w   = bp_width;
            chk_h   = bp_height;
            chk_bpp = bp_bpp;
            chk_comp= bp_compression;
            chk_off = bp_pixel_off;
            chk_td  = bp_top_down;
        end
        if (bp_out_valid === 1'b1 && bp_out_ready === 1'b1) begin
            if (out_n == 0) begin
                sink_first = bp_out_data;
                out_sof_n  = out_sof_n + bp_out_sof;
            end
            if (out_n < 8192) sink_mem[out_n] = bp_out_data;
            out_n     = out_n + 1;
            out_eof_n = out_eof_n + bp_out_eof;
        end
    end

    task clear_mon;
        begin
            out_n = 0;
            out_sof_n = 0;
            out_eof_n = 0;
            sink_first = 8'h00;
            chk_cnt = 0;
            chk_err = 1'b0;
            chk_ec  = 8'h00;
            chk_ed  = 8'h00;
            chk_w   = 16'd0;
            chk_h   = 16'd0;
            chk_bpp = 8'd0;
            chk_comp= 32'd0;
            chk_off = 32'd0;
            chk_td  = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------------
    // 造一张 BMP（头 + 一点像素数据）
    //   offbits : 像素数据起点（>= 54；> 54 时中间那截当调色板/填充）
    //   npix    : 真正灌进流的像素字节数
    // ------------------------------------------------------------------------
    task build_bmp;
        input [7:0]  sig0, sig1;
        input [31:0] bfsize;
        input [31:0] offbits;
        input [31:0] dibsize;
        input [31:0] w;
        input [31:0] h;
        input [15:0] planes;
        input [15:0] bpp;
        input [31:0] comp;
        input integer npix;
        begin
            for (i = 0; i < 8192; i = i + 1) src_mem[i] = 8'h00;
            src_mem[0] = sig0;
            src_mem[1] = sig1;
            // bfSize @ 0x02
            src_mem[2]  = bfsize[7:0];   src_mem[3]  = bfsize[15:8];
            src_mem[4]  = bfsize[23:16]; src_mem[5]  = bfsize[31:24];
            // bfOffBits @ 0x0A
            src_mem[10] = offbits[7:0];   src_mem[11] = offbits[15:8];
            src_mem[12] = offbits[23:16]; src_mem[13] = offbits[31:24];
            // biSize @ 0x0E
            src_mem[14] = dibsize[7:0];   src_mem[15] = dibsize[15:8];
            src_mem[16] = dibsize[23:16]; src_mem[17] = dibsize[31:24];
            // biWidth @ 0x12
            src_mem[18] = w[7:0];   src_mem[19] = w[15:8];
            src_mem[20] = w[23:16]; src_mem[21] = w[31:24];
            // biHeight @ 0x16
            src_mem[22] = h[7:0];   src_mem[23] = h[15:8];
            src_mem[24] = h[23:16]; src_mem[25] = h[31:24];
            // biPlanes @ 0x1A
            src_mem[26] = planes[7:0]; src_mem[27] = planes[15:8];
            // biBitCount @ 0x1C
            src_mem[28] = bpp[7:0]; src_mem[29] = bpp[15:8];
            // biCompression @ 0x1E
            src_mem[30] = comp[7:0];   src_mem[31] = comp[15:8];
            src_mem[32] = comp[23:16]; src_mem[33] = comp[31:24];
            // 头之后到像素之前：填可辨认的 0xEE（调色板/填充）
            for (i = 54; i < offbits; i = i + 1) src_mem[i] = 8'hEE;
            // 像素数据：0xA0, 0xA1, 0xA2 ...
            for (i = 0; i < npix; i = i + 1)
                src_mem[offbits + i] = (8'hA0 + i) & 8'hFF;
            src_len = offbits + npix;
        end
    endtask

    task run_bmp;
        input [31:0] fsz;
        begin
            clear_mon;
            bp_file_size = fsz;
            @(posedge clk); src_go = 1'b1;
            @(posedge clk); src_go = 1'b0;
            // 等头解析完
            wait_cnt = 0;
            while (!(chk_cnt != 0) && wait_cnt < 200_000) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            // 等整条流走完
            wait_cnt = 0;
            while ((src_valid === 1'b1 || bp_out_valid === 1'b1) && wait_cnt < 200_000) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // 激励
    // ------------------------------------------------------------------------
    initial begin
        errors = 0;
        src_go = 1'b0;
        src_len = 0;
        bp_file_size = 32'd0;
        bp_out_ready = 1'b1;
        clear_mon;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ====================================================================
        // T41 合法 BMP
        // ====================================================================
        $display("\n==== T41: 合法 BMP ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_cnt == 1,             "T41.1 check_done 只出现 1 次");
        check(chk_err === 1'b0,         "T41.2 没报错");
        check(chk_ec  === `ERR_NONE,    "T41.3 主码 = 0");
        check(chk_w === 16'd640,        "T41.4 宽 = 640");
        check(chk_h === 16'd480,        "T41.5 高 = 480（正 = bottom-up）");
        check(chk_td === 1'b0,          "T41.6 不是 top-down");
        check(chk_bpp === 8'd24,        "T41.7 bpp = 24");
        check(chk_comp === 32'd0,       "T41.8 compression = 0 (BI_RGB)");
        check(chk_off === 32'd54,       "T41.9 pixel_off = 54");
        check(out_n == 200,             "T41.10 像素数据透传 200 字节");
        check(out_n > 0 && sink_first === 8'hA0, "T41.11 第一个透传字节 = 0xA0");
        check(out_sof_n == 1,           "T41.12 out_sof 只出现 1 次");
        check(out_eof_n == 1,           "T41.13 out_eof 只出现 1 次");
        check(sink_mem[199] === 8'h67,  "T41.14 最后一个透传字节内容正确(0xA0+199)");

        // ====================================================================
        // T42 签名错
        // ====================================================================
        $display("\n==== T42: 签名不是 BM ====");
        build_bmp(8'h42, 8'h58, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b1,                "T42.1 报错");
        check(chk_ed  === `DET_BMP_SIG,        "T42.2 细分码 = 0x37(签名非 BM)");
        check(chk_ec  === `ERR_MEDIA_INVALID,  "T42.3 主码 = 0x03");
        check(out_n == 0,                      "T42.4 一个字节都不透传");

        // ====================================================================
        // T43 DIB 头长度不足
        // ====================================================================
        $display("\n==== T43: biSize = 39 ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd39,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b1,           "T43.1 报错");
        check(chk_ed  === `DET_BMP_DIB,   "T43.2 细分码 = 0x38(DIB 头不足 40)");
        check(out_n == 0,                 "T43.3 不透传");

        // ====================================================================
        // T44 尺寸不对
        // ====================================================================
        $display("\n==== T44: 宽度 800 ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd800, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b1,            "T44.1 报错");
        check(chk_ed  === `DET_BMP_SIZE,   "T44.2 细分码 = 0x39(尺寸非 640x480)");

        // ====================================================================
        // T45 bpp 不对
        // ====================================================================
        $display("\n==== T45: biBitCount = 32 ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd32, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b1,          "T45.1 报错");
        check(chk_ed  === `DET_BMP_FMT,  "T45.2 细分码 = 0x3A(bpp 不合法)");

        // ====================================================================
        // T46 压缩方式不对
        // ====================================================================
        $display("\n==== T46: biCompression = 1 ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd1, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b1,          "T46.1 报错");
        check(chk_ed  === `DET_BMP_FMT,  "T46.2 细分码 = 0x3A(压缩方式不合法)");

        // ====================================================================
        // T47 声明长度差 1 Byte
        // ====================================================================
        $display("\n==== T47: 声明长度差 1 Byte ====");
        build_bmp(8'h42, 8'h4D, (32'd53 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd53 + PIX_BYTES);          // 比需要的少 1
        check(chk_err === 1'b1,             "T47.1 报错");
        check(chk_ed  === `DET_BMP_TRUNC,   "T47.2 细分码 = 0x3B(长度越界)");

        // ====================================================================
        // T48 中间有调色板 / 填充（bfOffBits = 70）
        // ====================================================================
        $display("\n==== T48: bfOffBits = 70 ====");
        build_bmp(8'h42, 8'h4D, (32'd70 + PIX_BYTES), 32'd70, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd70 + PIX_BYTES);
        check(chk_err === 1'b0,          "T48.1 校验通过");
        check(chk_off === 32'd70,        "T48.2 pixel_off = 70");
        check(out_n == 200,              "T48.3 只透传像素那 200 字节");
        check(sink_first === 8'hA0,      "T48.4 中间那 16 字节被丢掉了");

        // ====================================================================
        // T49 top-down（高为负）
        // ====================================================================
        $display("\n==== T49: 高 = -480 ====");
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, -32'sd480, 16'd1, 16'd24, 32'd0, 200);
        run_bmp(32'd54 + PIX_BYTES);
        check(chk_err === 1'b0,          "T49.1 负高也算合法");
        check(chk_td  === 1'b1,          "T49.2 top_down 拉高");
        check(chk_h   === 16'hFE20,      "T49.3 height 保留符号位(-480)");

        // ====================================================================
        // T50 下游反压
        // ====================================================================
        $display("\n==== T50: 下游反压 ====");
        bp_out_ready = 1'b0;
        build_bmp(8'h42, 8'h4D, (32'd54 + PIX_BYTES), 32'd54, 32'd40,
                  32'd640, 32'd480, 16'd1, 16'd24, 32'd0, 200);
        clear_mon;
        bp_file_size = 32'd54 + PIX_BYTES;
        @(posedge clk); src_go = 1'b1;
        @(posedge clk); src_go = 1'b0;
        wait_cnt = 0;
        while ((out_n == 0) && wait_cnt < 200_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (300) @(posedge clk);
        check(bp_out_valid === 1'b1,     "T50.1 反压期间 out_valid 保持");
        check(out_n == 0,                "T50.2 下游没收就不算送达");
        @(negedge clk); // Change ready away from DUT/monitor sampling edge.
        bp_out_ready = 1'b1;
        wait_cnt = 0;
        while ((src_valid === 1'b1 || bp_out_valid === 1'b1) && wait_cnt < 200_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (10) @(posedge clk);
        check(out_n == 200,              "T50.3 放开后 200 字节一个不少");
        check(sink_first === 8'hA0,      "T50.4 第一个字节没乱");
        check(sink_mem[199] === 8'h67,   "T50.5 最后一个字节没乱");

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
