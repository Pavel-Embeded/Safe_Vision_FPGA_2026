// ============================================================================
// tb_media.sv — 阶段 8 媒体格式层：bmp_unpack + wav_reader
// ----------------------------------------------------------------------------
// 被测：rtl/media/bmp_unpack.v、rtl/media/wav_reader.v
// 本 TB 不挂 SPI / SD：两个模块都是纯字节流消费者，用合成字节源驱动即可，
// 每一条负向分支都能在几千个周期内跑完，比挂真实卡快得多。
//
// 注意：本机 ModelSim 代码页问题会让中文 $display 显示成乱码（全项目都一样），
//       不影响 [PASS]/[FAIL] 统计；断言名统一加 ASCII 前缀（T1..T16）便于阅读。
//
// ---- bmp_unpack ----
//   T1  纯色 BGR->RGB565（红/绿/蓝），同时验证 3 Byte 行填充被丢弃
//   T2  多行 + 行填充：x/y 计数跨行正确（宽 5 -> 行步长 16）
//   T3  top_down=1：y 随行递增 0,1,2
//   T4  top_down=0（正高）：y 从 height-1 递减 2,1,0
//   T5  输出反压：不丢像素、顺序不变
//   T6  像素数不足（提前 eof）-> error + DET_BMP_TRUNC
//   T7  像素数超限（多给一个像素）-> error + DET_BMP_SIZE
//   T8  全尺寸 640x480：像素总数严格 = 307200，img_sof/img_eof 各一次
//   T9  O-1 对比：同一字节流下 截断(0x0821) vs 舍入(0x1042)
//   （同一条流同时喂给 ROUNDING=0 与 ROUNDING=1 两个例化，逐项对照）
//
// ---- wav_reader ----
//   T10 合法 WAV：fmt 与 data 之间故意插一个【奇数 size 的未知块】验证跳过+偶对齐
//   T11 样本打包顺序：左声道先到（低 16 位）、右声道后到（高 16 位）
//   T12 非 PCM（format code = 3）-> 0x72
//   T13 单声道（ch = 1）        -> 0x74
//   T14 采样率 44100            -> 0x73
//   T15 8 bit                   -> 0x74
//   T16 非 RIFF/WAVE            -> 0x71
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_media;

    localparam [7:0]  PAD_BYTE = 8'hEE;    // 行填充字节（值无所谓，必须被丢弃）
    localparam [15:0] PX_RED   = 16'hF800;
    localparam [15:0] PX_GREEN = 16'h07E0;
    localparam [15:0] PX_BLUE  = 16'h001F;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer wc;
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

    // ========================================================================
    // bmp_unpack：合成字节源 + 两个例化（截断 / 舍入）
    // ========================================================================
    reg [7:0] src_mem [0:4095];
    integer   src_len;
    reg       src_gen;          // 1 = 不查数组，发全 0 流（大图只数个数）
    reg       src_go;
    reg       src_valid, src_sof, src_eof;
    reg [7:0] src_data;
    integer   src_idx;

    reg [15:0] bmp_width, bmp_height;
    reg        bmp_topdown;
    reg [31:0] bmp_pixoff;
    reg        dout_ready;
    reg        bp_en;           // 1 = 让 dout_ready 每拍翻转，制造反压

    wire        d1_rdy, d2_rdy;
    wire [15:0] d1_pixel, d2_pixel;
    wire        d1_pv, d1_sof, d1_eof, d1_done, d1_err;
    wire [7:0]  d1_ec, d1_ed;
    wire [9:0]  d1_x, d1_y;
    wire [15:0] d2_pixel_v;
    wire        d2_pv, d2_sof, d2_eof, d2_done, d2_err;
    wire [7:0]  d2_ec, d2_ed;
    wire [9:0]  d2_x, d2_y;

    bmp_unpack #(.ROUNDING(1'b0)) u_unpack (
        .clk(clk), .rst_n(rst_n),
        .din(src_data), .din_valid(src_valid), .din_ready(d1_rdy),
        .din_sof(src_sof), .din_eof(src_eof),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_topdown),
        .pixel_off(bmp_pixoff),
        .pixel(d1_pixel), .pixel_valid(d1_pv), .pixel_ready(dout_ready),
        .x(d1_x), .y(d1_y), .img_sof(d1_sof), .img_eof(d1_eof),
        .done(d1_done), .error(d1_err), .err_code(d1_ec), .err_detail(d1_ed),
        .dbg_state()
    );

    bmp_unpack #(.ROUNDING(1'b1)) u_unpack_r (
        .clk(clk), .rst_n(rst_n),
        .din(src_data), .din_valid(src_valid), .din_ready(d2_rdy),
        .din_sof(src_sof), .din_eof(src_eof),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_topdown),
        .pixel_off(bmp_pixoff),
        .pixel(d2_pixel_v), .pixel_valid(d2_pv), .pixel_ready(dout_ready),
        .x(d2_x), .y(d2_y), .img_sof(d2_sof), .img_eof(d2_eof),
        .done(d2_done), .error(d2_err), .err_code(d2_ec), .err_detail(d2_ed),
        .dbg_state()
    );

    // 两个例化逻辑完全一致（只差 ROUNDING），ready 永远同步，可以共用同一个源
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_valid <= 1'b0;
            src_data  <= 8'h00;
            src_sof   <= 1'b0;
            src_eof   <= 1'b0;
            src_idx   <= 0;
        end else if (src_go) begin
            src_idx   <= 0;
            src_data  <= src_gen ? 8'h00 : src_mem[0];
            src_sof   <= 1'b1;                       // 像素段有效
            src_eof   <= (src_len == 1);
            src_valid <= 1'b1;
        end else if (src_valid && d1_rdy && d2_rdy) begin
            if ((src_idx + 1) < src_len) begin
                src_idx   <= src_idx + 1;
                src_data  <= src_gen ? 8'h00 : src_mem[src_idx + 1];
                src_eof   <= ((src_idx + 1) == (src_len - 1));
                src_valid <= 1'b1;
            end else begin
                src_valid <= 1'b0;
                src_sof   <= 1'b0;
                src_eof   <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dout_ready <= 1'b1;
        else if (bp_en) dout_ready <= ~dout_ready;
        else            dout_ready <= 1'b1;
    end

    // ---- 监视器 ----
    integer    c1_n, c2_n;
    reg [15:0] m1_pix [0:4095];
    reg [9:0]  m1_x [0:4095];
    reg [9:0]  m1_y [0:4095];
    integer    m1_sof, m1_eof, m1_done;
    integer    m2_sof, m2_eof, m2_done;
    reg [15:0] m1_last_pix, m2_last_pix;
    reg [9:0]  m1_last_x, m1_last_y, m2_last_x, m2_last_y;

    always @(posedge clk) begin
        if (d1_pv === 1'b1 && dout_ready === 1'b1) begin
            if (c1_n < 4096) begin
                m1_pix[c1_n] = d1_pixel;
                m1_x[c1_n]   = d1_x;
                m1_y[c1_n]   = d1_y;
            end
            m1_last_pix = d1_pixel;
            m1_last_x   = d1_x;
            m1_last_y   = d1_y;
            c1_n        = c1_n + 1;
            m1_sof      = m1_sof + d1_sof;
            m1_eof      = m1_eof + d1_eof;
        end
        if (d1_done === 1'b1) m1_done = m1_done + 1;

        if (d2_pv === 1'b1 && dout_ready === 1'b1) begin
            m2_last_pix = d2_pixel_v;
            m2_last_x   = d2_x;
            m2_last_y   = d2_y;
            c2_n        = c2_n + 1;
            m2_sof      = m2_sof + d2_sof;
            m2_eof      = m2_eof + d2_eof;
        end
        if (d2_done === 1'b1) m2_done = m2_done + 1;
    end

    task clear_mon;
        begin
            c1_n = 0; c2_n = 0;
            m1_sof = 0; m1_eof = 0; m1_done = 0;
            m2_sof = 0; m2_eof = 0; m2_done = 0;
            m1_last_pix = 16'h0000; m2_last_pix = 16'h0000;
            m1_last_x = 10'd0; m1_last_y = 10'd0;
            m2_last_x = 10'd0; m2_last_y = 10'd0;
        end
    endtask

    task src_clear;
        begin
            for (i = 0; i < 4096; i = i + 1) src_mem[i] = 8'h00;
        end
    endtask

    task bmp_run;
        input integer maxc;
        begin
            @(posedge clk); src_go = 1'b1;
            @(posedge clk); src_go = 1'b0;
            wc = 0;
            while ((m1_done == 0) && (wc < maxc)) begin
                @(posedge clk);
                wc = wc + 1;
            end
            repeat (40) @(posedge clk);
        end
    endtask

    // 在 src_mem[p] 起放一个 BGR 像素
    task put_pix;
        input integer p;
        input [7:0]   b, g, r;
        begin
            src_mem[p]     = b;
            src_mem[p + 1] = g;
            src_mem[p + 2] = r;
        end
    endtask

    // ========================================================================
    // wav_reader：第二个合成字节源 + DUT
    // ========================================================================
    reg [7:0] w_mem [0:1023];
    integer   w_len;
    reg       w_go;
    reg       w_flush;          // 冲掉上一次残留（出错后 reader 不再收字节，源会卡在 valid=1）
    reg       w_valid, w_eof;
    reg [7:0] w_data;
    integer   w_idx;

    reg        wav_start;
    reg [31:0] wav_first_clus, wav_file_size;
    reg [7:0]  wav_track_id;
    reg        wav_pcm_ready;

    wire        w_rdy;
    wire [15:0] w_fmt_code, w_ch, w_bits;
    wire [31:0] w_rate, w_data_off, w_data_size;
    wire        w_hdr_done;
    wire [15:0] w_pcm_l, w_pcm_r;
    wire [31:0] w_sample;
    wire        w_pcm_valid, w_pcm_end;
    wire        w_error, w_fallback;
    wire [7:0]  w_ec, w_ed;
    wire [31:0] w_samples_rd;
    wire [7:0]  w_track_o;

    wav_reader u_wav (
        .clk(clk), .rst_n(rst_n),
        .start(wav_start), .first_clus(wav_first_clus), .file_size(wav_file_size),
        .track_id(wav_track_id),
        .din(w_data), .din_valid(w_valid), .din_ready(w_rdy), .din_eof(w_eof),
        .fmt_code(w_fmt_code), .num_channels(w_ch), .sample_rate(w_rate),
        .bits_per_sample(w_bits), .data_offset(w_data_off), .data_size(w_data_size),
        .header_done(w_hdr_done),
        .pcm_l(w_pcm_l), .pcm_r(w_pcm_r), .sample(w_sample),
        .pcm_valid(w_pcm_valid), .pcm_ready(wav_pcm_ready), .pcm_end(w_pcm_end),
        .track_id_o(w_track_o), .wav_error(w_error), .err_code(w_ec),
        .err_detail(w_ed), .fallback_req(w_fallback), .samples_rd(w_samples_rd),
        .dbg_state()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_valid <= 1'b0;
            w_data  <= 8'h00;
            w_eof   <= 1'b0;
            w_idx   <= 0;
        end else if (w_go) begin
            w_idx   <= 0;
            w_data  <= w_mem[0];
            w_eof   <= (w_len == 1);
            w_valid <= 1'b1;
        end else if (w_flush) begin
            w_valid <= 1'b0;
            w_eof   <= 1'b0;
        end else if (w_valid && w_rdy) begin
            if ((w_idx + 1) < w_len) begin
                w_idx   <= w_idx + 1;
                w_data  <= w_mem[w_idx + 1];
                w_eof   <= ((w_idx + 1) == (w_len - 1));
                w_valid <= 1'b1;
            end else begin
                w_valid <= 1'b0;
                w_eof   <= 1'b0;
            end
        end
    end

    integer    w_n, w_hd_n, w_end_n;
    reg [15:0] wl [0:63];
    reg [15:0] wr [0:63];
    reg [31:0] ws [0:63];

    always @(posedge clk) begin
        if (w_pcm_valid === 1'b1 && wav_pcm_ready === 1'b1) begin
            if (w_n < 64) begin
                wl[w_n] = w_pcm_l;
                wr[w_n] = w_pcm_r;
                ws[w_n] = w_sample;
            end
            w_n     = w_n + 1;
            w_end_n = w_end_n + w_pcm_end;
        end
        if (w_hdr_done === 1'b1) w_hd_n = w_hd_n + 1;
    end

    task wav_clear_mon;
        begin
            w_n = 0; w_hd_n = 0; w_end_n = 0;
        end
    endtask

    task wr_le16;
        input integer pos;
        input [15:0]  v;
        begin
            w_mem[pos]   = v[7:0];
            w_mem[pos+1] = v[15:8];
        end
    endtask

    task wr_le32;
        input integer pos;
        input [31:0]  v;
        begin
            w_mem[pos]   = v[7:0];
            w_mem[pos+1] = v[15:8];
            w_mem[pos+2] = v[23:16];
            w_mem[pos+3] = v[31:24];
        end
    endtask

    // 造一个 WAV：
    //   unk_size > 0 时在 fmt 与 data 之间插一个 "LIST" 未知块（可为奇数 size）
    //   PCM 固定 4 对样本：左低 16 位、右高 16 位
    task build_wav;
        input [15:0] code, ch, bits;
        input [31:0] rate;
        input integer unk_size;
        input         bad_riff;
        integer p;
        begin
            for (i = 0; i < 1024; i = i + 1) w_mem[i] = 8'h00;

            w_mem[0] = bad_riff ? 8'h58 : 8'h52;   // 'R' / 故意错成 'X'
            w_mem[1] = 8'h49;                      // 'I'
            w_mem[2] = 8'h46;                      // 'F'
            w_mem[3] = 8'h46;                      // 'F'
            w_mem[8]  = 8'h57; w_mem[9]  = 8'h41;  // 'W','A'
            w_mem[10] = 8'h56; w_mem[11] = 8'h45;  // 'V','E'

            // fmt 块
            w_mem[12] = 8'h66; w_mem[13] = 8'h6D;  // 'f','m'
            w_mem[14] = 8'h74; w_mem[15] = 8'h20;  // 't',' '
            wr_le32(16, 32'd16);                   // fmt 块大小
            wr_le16(20, code);
            wr_le16(22, ch);
            wr_le32(24, rate);
            wr_le32(28, rate * ch * bits / 8);     // byte_rate
            wr_le16(32, ch * bits / 8);            // block_align
            wr_le16(34, bits);

            p = 36;
            if (unk_size > 0) begin
                w_mem[p]   = 8'h4C; w_mem[p+1] = 8'h49;  // 'L','I'
                w_mem[p+2] = 8'h53; w_mem[p+3] = 8'h54;  // 'S','T'
                wr_le32(p+4, unk_size);
                for (i = 0; i < unk_size; i = i + 1) w_mem[p+8+i] = 8'hA5;
                p = p + 8 + unk_size;
                if (unk_size % 2 != 0) begin      // RIFF 块按偶数对齐
                    w_mem[p] = 8'h00;
                    p = p + 1;
                end
            end

            // data 块
            w_mem[p]   = 8'h64; w_mem[p+1] = 8'h61;  // 'd','a'
            w_mem[p+2] = 8'h74; w_mem[p+3] = 8'h61;  // 't','a'
            wr_le32(p+4, 32'd16);
            w_mem[p+8]  = 8'h00; w_mem[p+9]  = 8'h01;
            w_mem[p+10] = 8'h00; w_mem[p+11] = 8'h02;   // l=0x0100 r=0x0200
            w_mem[p+12] = 8'hF0; w_mem[p+13] = 8'hFF;
            w_mem[p+14] = 8'hFF; w_mem[p+15] = 8'h7F;   // l=0xFFF0 r=0x7FFF
            w_mem[p+16] = 8'h01; w_mem[p+17] = 8'h00;
            w_mem[p+18] = 8'h00; w_mem[p+19] = 8'h80;   // l=0x0001 r=0x8000
            w_mem[p+20] = 8'hCD; w_mem[p+21] = 8'hAB;
            w_mem[p+22] = 8'h34; w_mem[p+23] = 8'h12;   // l=0xABCD r=0x1234

            w_len = p + 24;
            wr_le32(4, w_len - 8);                 // RIFF 声明的文件大小
        end
    endtask

    task wav_run;
        input integer maxc;
        begin
            wav_clear_mon;
            wav_file_size = w_len;
            // (1) 冲掉上一次残留字节
            w_flush = 1'b1;
            @(posedge clk);
            w_flush = 1'b0;
            // (2) 先武装源（此时 DUT 尚未 start，不会消费），保证从流第一个字节开始
            w_go = 1'b1;
            @(posedge clk);
            w_go = 1'b0;
            // (3) 再拉 start（start 是全局的，W_END / W_ERR 都能重启）
            wav_start = 1'b1;
            @(posedge clk);
            wav_start = 1'b0;
            wc = 0;
            while ((w_error === 1'b0) && (w_n < 4) && (wc < maxc)) begin
                @(posedge clk);
                wc = wc + 1;
            end
            repeat (40) @(posedge clk);
        end
    endtask

    // ========================================================================
    // 激励
    // ========================================================================
    initial begin
        errors       = 0;
        src_go       = 1'b0;
        src_gen      = 1'b0;
        src_len      = 0;
        bmp_width    = 16'd640;
        bmp_height   = 16'd480;
        bmp_topdown  = 1'b1;
        bmp_pixoff   = 32'd54;
        bp_en        = 1'b0;
        w_go         = 1'b0;
        w_flush      = 1'b0;
        w_len        = 0;
        wav_start    = 1'b0;
        wav_first_clus = 32'd0;
        wav_file_size  = 32'd0;
        wav_track_id   = 8'h01;
        wav_pcm_ready  = 1'b1;
        clear_mon;
        wav_clear_mon;
        src_clear;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ====================================================================
        // T1 纯色 BGR -> RGB565（同时验证 3 Byte 行填充被丢弃）
        //    宽 3 -> 行步长 ((3*3+3)/4)*4 = 12，即 3 个像素 + 3 个填充字节
        // ====================================================================
        $display("\n==== T1: BGR->RGB565 纯色 ====");
        src_clear; clear_mon;
        put_pix(0, 8'h00, 8'h00, 8'hFF);   // B,G,R = 0,0,FF -> 纯红
        put_pix(3, 8'h00, 8'hFF, 8'h00);   // 纯绿
        put_pix(6, 8'hFF, 8'h00, 8'h00);   // 纯蓝
        src_mem[9] = PAD_BYTE; src_mem[10] = PAD_BYTE; src_mem[11] = PAD_BYTE;
        src_len = 12; src_gen = 1'b0;
        bmp_width = 16'd3; bmp_height = 16'hFFFF; bmp_topdown = 1'b1;   // -1（top-down）
        bmp_run(20000);
        check(c1_n == 3,                     "T1.1 px_cnt=3（填充字节未当像素）");
        check(m1_pix[0] === PX_RED,          "T1.2 红: 00 00 FF -> F800（未红蓝颠倒）");
        check(m1_pix[1] === PX_GREEN,        "T1.3 绿: 00 FF 00 -> 07E0");
        check(m1_pix[2] === PX_BLUE,         "T1.4 蓝: FF 00 00 -> 001F");
        check(m1_x[0] == 0 && m1_x[1] == 1 && m1_x[2] == 2, "T1.5 x = 0,1,2");
        check(m1_y[0] == 0 && m1_y[1] == 0 && m1_y[2] == 0, "T1.6 y 全 0");
        check(m1_sof == 1 && m1_eof == 1,    "T1.7 img_sof/img_eof 各 1 次");
        check(m1_done == 1,                  "T1.8 done 1 次");
        check(d1_err === 1'b0,               "T1.9 没报错");
        check(c2_n == 3 && m2_last_pix === PX_BLUE, "T1.10 ROUNDING=1 纯色结果一致");

        // ====================================================================
        // T2 多行 + 行填充：宽 5 -> 行步长 ((15+3)/4)*4 = 16（15 像素 + 1 填充）
        //    像素值 = B>>3，故意让每行错位就会立刻看出来
        // ====================================================================
        $display("\n==== T2: 行填充 + 跨行 x/y ====");
        src_clear; clear_mon;
        for (i = 0; i < 5; i = i + 1) put_pix(i * 3, i * 8, 8'h00, 8'h00);
        src_mem[15] = PAD_BYTE;
        for (i = 0; i < 5; i = i + 1) put_pix(16 + i * 3, (i + 5) * 8, 8'h00, 8'h00);
        src_mem[31] = PAD_BYTE;
        src_len = 32; src_gen = 1'b0;
        bmp_width = 16'd5; bmp_height = 16'hFFFE; bmp_topdown = 1'b1;   // -2（top-down）
        bmp_run(20000);
        check(c1_n == 10,                    "T2.1 px_cnt=10（10 个真像素）");
        check(m1_pix[0] == 0 && m1_pix[4] == 4,   "T2.2 第 0 行像素值 0..4");
        check(m1_pix[5] == 5 && m1_pix[9] == 9,   "T2.3 第 1 行像素值 5..9（填充已跳过）");
        check(m1_x[0] == 0 && m1_x[4] == 4 && m1_x[5] == 0 && m1_x[9] == 4, "T2.4 x 每行 0..4");
        check(m1_y[0] == 0 && m1_y[4] == 0 && m1_y[5] == 1 && m1_y[9] == 1, "T2.5 y 0,0,..,1");
        check(d1_err === 1'b0,               "T2.6 没报错");

        // ====================================================================
        // T3 top_down=1（负高）：y 随行递增 0,1,2
        //    宽 2 -> 行步长 ((6+3)/4)*4 = 8（2 像素 + 2 填充）
        // ====================================================================
        $display("\n==== T3: top_down=1 y 递增 ====");
        src_clear; clear_mon;
        for (i = 0; i < 3; i = i + 1) begin
            put_pix(0 + i * 8, (i * 2) * 8,     8'h00, 8'h00);
            put_pix(3 + i * 8, (i * 2 + 1) * 8, 8'h00, 8'h00);
        end
        src_len = 24; src_gen = 1'b0;
        bmp_width = 16'd2; bmp_height = 16'hFFFD; bmp_topdown = 1'b1;   // -3（top-down）
        bmp_run(20000);
        check(c1_n == 6,                     "T3.1 px_cnt=6");
        check(m1_y[0] == 0 && m1_y[1] == 0 && m1_y[2] == 1 &&
              m1_y[3] == 1 && m1_y[4] == 2 && m1_y[5] == 2, "T3.2 y = 0,0,1,1,2,2");
        check(m1_x[0] == 0 && m1_x[1] == 1 && m1_x[4] == 0 && m1_x[5] == 1, "T3.3 x 每行 0,1");

        // ====================================================================
        // T4 top_down=0（正高）：同一条流，y 从 height-1 递减 2,1,0
        // ====================================================================
        $display("\n==== T4: top_down=0 y 递减 ====");
        src_clear; clear_mon;
        for (i = 0; i < 3; i = i + 1) begin
            put_pix(0 + i * 8, (i * 2) * 8,     8'h00, 8'h00);
            put_pix(3 + i * 8, (i * 2 + 1) * 8, 8'h00, 8'h00);
        end
        src_len = 24; src_gen = 1'b0;
        bmp_width = 16'd2; bmp_height = 16'd3; bmp_topdown = 1'b0;
        bmp_run(20000);
        check(c1_n == 6,                     "T4.1 px_cnt=6");
        check(m1_y[0] == 2 && m1_y[1] == 2 && m1_y[2] == 1 &&
              m1_y[3] == 1 && m1_y[4] == 0 && m1_y[5] == 0, "T4.2 y = 2,2,1,1,0,0（左上原点）");
        check(m1_x[0] == 0 && m1_x[1] == 1,  "T4.3 x 仍左到右");

        // ====================================================================
        // T5 输出反压：不丢像素、顺序不变
        // ====================================================================
        $display("\n==== T5: 输出反压 ====");
        src_clear; clear_mon;
        put_pix(0,  8'h08, 8'h00, 8'h00);   // -> 1
        put_pix(3,  8'h10, 8'h00, 8'h00);   // -> 2
        put_pix(6,  8'h18, 8'h00, 8'h00);   // -> 3
        put_pix(9,  8'h20, 8'h00, 8'h00);   // -> 4
        src_len = 12; src_gen = 1'b0;       // 宽 4 -> 行步长 12，无填充
        bmp_width = 16'd4; bmp_height = 16'hFFFF; bmp_topdown = 1'b1;   // -1（top-down）
        bp_en = 1'b1;
        bmp_run(20000);
        bp_en = 1'b0;
        check(c1_n == 4,                     "T5.1 反压后 4 个像素一个不少");
        check(m1_pix[0] == 1 && m1_pix[1] == 2 && m1_pix[2] == 3 && m1_pix[3] == 4,
              "T5.2 像素顺序未乱");
        check(d1_err === 1'b0,               "T5.3 反压没导致误报错");

        // ====================================================================
        // T6 像素数不足（提前 eof）
        //    宽 2、高 2 -> 应有 4 个像素；只给 3 个就 eof
        // ====================================================================
        $display("\n==== T6: 像素数不足 ====");
        src_clear; clear_mon;
        // 宽 2 -> 行步长 8：行0 = 像素0(0..2) + 像素1(3..5) + 填充(6,7)
        put_pix(0, 8'h08, 8'h00, 8'h00);
        put_pix(3, 8'h10, 8'h00, 8'h00);
        src_mem[6] = PAD_BYTE; src_mem[7] = PAD_BYTE;
        put_pix(8, 8'h18, 8'h00, 8'h00);      // 第 3 个像素，然后直接 eof
        src_len = 11; src_gen = 1'b0;
        bmp_width = 16'd2; bmp_height = 16'hFFFE; bmp_topdown = 1'b1;   // -2 -> 应有 4 个
        bmp_run(20000);
        check(c1_n == 3,                     "T6.1 只出了 3 个像素");
        check(d1_err === 1'b1,               "T6.2 报错");
        check(d1_ed === `DET_BMP_TRUNC,      "T6.3 细分码 = 0x3B（像素数不足）");
        check(d1_ec === `ERR_MEDIA_INVALID,  "T6.4 主码 = 0x03");
        check(m1_done == 1,                  "T6.5 done 仍给出");

        // ====================================================================
        // T7 像素数超限（多给一个像素）
        //    宽 2、高 2 -> 2 行共 16 Byte（含填充）；再多给 3 Byte 就是第 5 个像素
        // ====================================================================
        $display("\n==== T7: 像素数超限 ====");
        src_clear; clear_mon;
        // 行0 (0..7)  : 像素0(0..2) 像素1(3..5) 填充(6,7)
        // 行1 (8..15) : 像素2(8..10) 像素3(11..13) 填充(14,15)
        // 行2 (16..18): 像素4 —— 第 5 个像素，超限
        put_pix(0,  8'h08, 8'h00, 8'h00);
        put_pix(3,  8'h10, 8'h00, 8'h00);
        src_mem[6] = PAD_BYTE;  src_mem[7]  = PAD_BYTE;
        put_pix(8,  8'h18, 8'h00, 8'h00);
        put_pix(11, 8'h20, 8'h00, 8'h00);
        src_mem[14] = PAD_BYTE; src_mem[15] = PAD_BYTE;
        put_pix(16, 8'h28, 8'h00, 8'h00);
        src_len = 19; src_gen = 1'b0;
        bmp_width = 16'd2; bmp_height = 16'hFFFE; bmp_topdown = 1'b1;   // -2 -> 只应有 4 个
        bmp_run(20000);
        check(d1_err === 1'b1,               "T7.1 报错");
        check(d1_ed === `DET_BMP_SIZE,       "T7.2 细分码 = 0x39（像素数超限）");
        check(c1_n == 4,                     "T7.3 只输出前 4 个像素");

        // ====================================================================
        // T8 全尺寸 640x480：像素总数严格 = 307200
        //    源发全 0 流（B=G=R=0 -> 像素 0），只验证个数与边界
        // ====================================================================
        $display("\n==== T8: 640x480 全尺寸计数 ====");
        clear_mon;
        src_gen = 1'b1; src_len = 640 * 480 * 3;   // 行步长 1920 恰好整除
        bmp_width = 16'd640; bmp_height = 16'hFE20; bmp_topdown = 1'b1;  // -480
        bmp_run(5_000_000);
        check(c1_n == 307200,                "T8.1 像素总数 = 307200");
        check(m1_sof == 1,                   "T8.2 img_sof 只 1 次");
        check(m1_eof == 1,                   "T8.3 img_eof 只 1 次");
        check(m1_done == 1,                  "T8.4 done 1 次");
        check(d1_err === 1'b0,               "T8.5 无错");
        check(m1_last_x == 10'd639 && m1_last_y == 10'd479, "T8.6 最后一个像素 (639,479)");
        check(m1_pix[0] === 16'h0000,        "T8.7 首像素 = 0（全 0 流）");
        src_gen = 1'b0;
        check(c2_n == 307200,                "T8.8 ROUNDING=1 计数一致");

        // ====================================================================
        // T9 O-1：截断 vs 舍入（B=0x0C, G=0x06, R=0x0C）
        //    截断 {1,1,1}=0x0821；舍入 {2,2,2}=0x1042
        // ====================================================================
        $display("\n==== T9: ROUNDING 截断 vs 舍入 ====");
        src_clear; clear_mon;
        put_pix(0, 8'h0C, 8'h06, 8'h0C);
        src_mem[3] = PAD_BYTE;                     // 宽 1 -> 行步长 4
        src_len = 4; src_gen = 1'b0;
        bmp_width = 16'd1; bmp_height = 16'hFFFF; bmp_topdown = 1'b1;   // -1（top-down）
        bmp_run(20000);
        check(c1_n == 1 && c2_n == 1,        "T9.1 两个例化各出 1 像素");
        check(m1_last_pix === 16'h0821,      "T9.2 ROUNDING=0 截断 -> 0x0821");
        check(m2_last_pix === 16'h1042,      "T9.3 ROUNDING=1 舍入 -> 0x1042");

        // ====================================================================
        // T10 合法 WAV + fmt/data 之间插一个【奇数 size 的未知块】
        // ====================================================================
        $display("\n==== T10: 合法 WAV（含未知块跳过）====");
        build_wav(16'd1, 16'd2, 16'd16, 32'd48000, 5, 1'b0);
        wav_run(20000);
        check(w_hd_n == 1,                   "T10.1 header_done 1 次");
        check(w_error === 1'b0,              "T10.2 没报错");
        check(w_fmt_code === 16'd1,          "T10.3 fmt_code = 1 (PCM)");
        check(w_ch === 16'd2,                "T10.4 声道数 = 2");
        check(w_rate === 32'd48000,          "T10.5 采样率 = 48000");
        check(w_bits === 16'd16,             "T10.6 位深 = 16");
        check(w_data_size === 32'd16,        "T10.7 data_size = 16");
        check(w_data_off === 32'd58,         "T10.7b data_offset = 58（未知块 8+5+1 已跳过）");
        check(w_samples_rd === 32'd4,        "T10.8 samples_rd = 4");
        check(w_n == 4,                      "T10.9 输出 4 对样本");
        check(w_end_n == 1,                  "T10.10 pcm_end 1 次");
        check(w_track_o === 8'h01,           "T10.11 track_id 透传");

        // ====================================================================
        // T11 样本打包顺序：左声道先到 = 低 16 位
        // ====================================================================
        $display("\n==== T11: 左右声道打包顺序 ====");
        check(wl[0] === 16'h0100 && wr[0] === 16'h0200, "T11.1 样本0 l=0100 r=0200");
        check(ws[0] === 32'h0200_0100,       "T11.2 sample = {r,l} = 0x02000100");
        check(wl[1] === 16'hFFF0 && wr[1] === 16'h7FFF, "T11.3 样本1 l=FFF0 r=7FFF");
        check(ws[3] === 32'h1234_ABCD,       "T11.4 样本3 sample = {r,l}（左低右高）");

        // ====================================================================
        // T12 非 PCM（format code = 3，浮点）
        // ====================================================================
        $display("\n==== T12: 非 PCM ====");
        build_wav(16'd3, 16'd2, 16'd16, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T12.1 报错");
        check(w_ed === 8'h72,                "T12.2 细分码 = 0x72（非 PCM）");
        check(w_ec === `ERR_WAV,               "T12.3 主码 = 0x07(WAV 不支持)");
        check(w_n == 0,                      "T12.4 一个样本都不出");
        check(w_fallback === 1'b1,           "T12.5 请求回退提示音");

        // ====================================================================
        // T13 单声道
        // ====================================================================
        $display("\n==== T13: 单声道 ====");
        build_wav(16'd1, 16'd1, 16'd16, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T13.1 报错");
        check(w_ed === 8'h74,                "T13.2 细分码 = 0x74（非立体声）");
        check(w_n == 0,                      "T13.3 无样本输出");

        // ====================================================================
        // T14 采样率 44100
        // ====================================================================
        $display("\n==== T14: 采样率 44100 ====");
        build_wav(16'd1, 16'd2, 16'd16, 32'd44100, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T14.1 报错");
        check(w_ed === 8'h73,                "T14.2 细分码 = 0x73（采样率非 48k）");
        check(w_rate === 32'd44100,          "T14.3 回读采样率供日志");

        // ====================================================================
        // T15 8 bit
        // ====================================================================
        $display("\n==== T15: 8 bit ====");
        build_wav(16'd1, 16'd2, 16'd8, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T15.1 报错");
        check(w_ed === 8'h74,                "T15.2 细分码 = 0x74（非 16 bit）");

        // ====================================================================
        // T16 非 RIFF / WAVE
        // ====================================================================
        $display("\n==== T16: 非 RIFF ====");
        build_wav(16'd1, 16'd2, 16'd16, 32'd48000, 0, 1'b1);
        wav_run(20000);
        check(w_error === 1'b1,              "T16.1 报错");
        check(w_ed === 8'h71,                "T16.2 细分码 = 0x71（非 RIFF/WAVE）");

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #600_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule