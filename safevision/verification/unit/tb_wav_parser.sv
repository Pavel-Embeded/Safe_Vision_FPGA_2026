


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_wav_parser;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer checks;
    integer wc;
    integer i;

    task check;
        input         cond;
        input [255:0] name;
        begin
            checks=checks+1;
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask


    reg [7:0] w_mem [0:1023];
    integer   w_len;
    reg       w_go;
    reg       w_flush;
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

    wav_parser u_wav (
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


    task build_wav;
        input [15:0] code, ch, bits;
        input [31:0] rate;
        input integer unk_size;
        input         bad_riff;
        integer p;
        begin
            for (i = 0; i < 1024; i = i + 1) w_mem[i] = 8'h00;

            w_mem[0] = bad_riff ? 8'h58 : 8'h52;
            w_mem[1] = 8'h49;
            w_mem[2] = 8'h46;
            w_mem[3] = 8'h46;
            w_mem[8]  = 8'h57; w_mem[9]  = 8'h41;
            w_mem[10] = 8'h56; w_mem[11] = 8'h45;


            w_mem[12] = 8'h66; w_mem[13] = 8'h6D;
            w_mem[14] = 8'h74; w_mem[15] = 8'h20;
            wr_le32(16, 32'd16);
            wr_le16(20, code);
            wr_le16(22, ch);
            wr_le32(24, rate);
            wr_le32(28, rate * ch * bits / 8);
            wr_le16(32, ch * bits / 8);
            wr_le16(34, bits);

            p = 36;
            if (unk_size > 0) begin
                w_mem[p]   = 8'h4C; w_mem[p+1] = 8'h49;
                w_mem[p+2] = 8'h53; w_mem[p+3] = 8'h54;
                wr_le32(p+4, unk_size);
                for (i = 0; i < unk_size; i = i + 1) w_mem[p+8+i] = 8'hA5;
                p = p + 8 + unk_size;
                if (unk_size % 2 != 0) begin
                    w_mem[p] = 8'h00;
                    p = p + 1;
                end
            end


            w_mem[p]   = 8'h64; w_mem[p+1] = 8'h61;
            w_mem[p+2] = 8'h74; w_mem[p+3] = 8'h61;
            wr_le32(p+4, 32'd16);
            w_mem[p+8]  = 8'h00; w_mem[p+9]  = 8'h01;
            w_mem[p+10] = 8'h00; w_mem[p+11] = 8'h02;
            w_mem[p+12] = 8'hF0; w_mem[p+13] = 8'hFF;
            w_mem[p+14] = 8'hFF; w_mem[p+15] = 8'h7F;
            w_mem[p+16] = 8'h01; w_mem[p+17] = 8'h00;
            w_mem[p+18] = 8'h00; w_mem[p+19] = 8'h80;
            w_mem[p+20] = 8'hCD; w_mem[p+21] = 8'hAB;
            w_mem[p+22] = 8'h34; w_mem[p+23] = 8'h12;

            w_len = p + 24;
            wr_le32(4, w_len - 8);
        end
    endtask

    task wav_run;
        input integer maxc;
        begin
            wav_clear_mon;
            wav_file_size = w_len;


            @(negedge clk);w_flush=1;w_go=0;wav_start=0;
            @(negedge clk);w_flush=0;wav_start=1;
            @(negedge clk);wav_start=0;w_go=1;
            @(negedge clk);w_go=0;
            wc = 0;
            while ((w_error === 1'b0) && (w_n < 4) && (wc < maxc)) begin
                @(posedge clk);
                wc = wc + 1;
            end
            repeat (40) @(posedge clk);
        end
    endtask


    initial begin
        errors       = 0;
        checks       = 0;
        w_go         = 1'b0;
        w_flush      = 1'b0;
        w_len        = 0;
        wav_start    = 1'b0;
        wav_first_clus = 32'd0;
        wav_file_size  = 32'd0;
        wav_track_id   = 8'h01;
        wav_pcm_ready  = 1'b1;
        wav_clear_mon;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);


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


        $display("\n==== T11: 左右声道打包顺序 ====");
        check(wl[0] === 16'h0100 && wr[0] === 16'h0200, "T11.1 样本0 l=0100 r=0200");
        check(ws[0] === 32'h0200_0100,       "T11.2 sample = {r,l} = 0x02000100");
        check(wl[1] === 16'hFFF0 && wr[1] === 16'h7FFF, "T11.3 样本1 l=FFF0 r=7FFF");
        check(ws[3] === 32'h1234_ABCD,       "T11.4 样本3 sample = {r,l}（左低右高）");


        $display("\n==== T12: 非 PCM ====");
        build_wav(16'd3, 16'd2, 16'd16, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T12.1 报错");
        check(w_ed === 8'h72,                "T12.2 细分码 = 0x72（非 PCM）");
        check(w_ec === `ERR_WAV,               "T12.3 主码 = 0x07(WAV 不支持)");
        check(w_n == 0,                      "T12.4 一个样本都不出");
        check(w_fallback === 1'b1,           "T12.5 请求回退提示音");


        $display("\n==== T13: 单声道 ====");
        build_wav(16'd1, 16'd1, 16'd16, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T13.1 报错");
        check(w_ed === 8'h74,                "T13.2 细分码 = 0x74（非立体声）");
        check(w_n == 0,                      "T13.3 无样本输出");


        $display("\n==== T14: 采样率 44100 ====");
        build_wav(16'd1, 16'd2, 16'd16, 32'd44100, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T14.1 报错");
        check(w_ed === 8'h73,                "T14.2 细分码 = 0x73（采样率非 48k）");
        check(w_rate === 32'd44100,          "T14.3 回读采样率供日志");


        $display("\n==== T15: 8 bit ====");
        build_wav(16'd1, 16'd2, 16'd8, 32'd48000, 0, 1'b0);
        wav_run(20000);
        check(w_error === 1'b1,              "T15.1 报错");
        check(w_ed === 8'h74,                "T15.2 细分码 = 0x74（非 16 bit）");


        $display("\n==== T16: 非 RIFF ====");
        build_wav(16'd1, 16'd2, 16'd16, 32'd48000, 0, 1'b1);
        wav_run(20000);
        check(w_error === 1'b1,              "T16.1 报错");
        check(w_ed === 8'h71,                "T16.2 细分码 = 0x71（非 RIFF/WAVE）");


        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $display("PASS tb_wav_parser errors=%0d comparisons=%0d",errors,checks);
        $finish;
    end

    initial begin
        #600_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
