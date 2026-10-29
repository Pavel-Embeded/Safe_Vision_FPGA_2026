


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_file_index;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer i;
    integer done_cnt;

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


    reg  [87:0] ent_name;
    reg  [7:0]  ent_attr;
    reg  [31:0] ent_first_clus;
    reg  [31:0] ent_size;
    reg  [15:0] ent_index;
    reg         ent_valid;
    wire        ent_ready;

    reg         idx_clear, idx_commit;
    wire        idx_done, insufficient;
    wire [3:0]  file_cnt, file_valid;
    wire [7:0]  ec, ed;

    reg  [1:0]  sel_slot;
    wire [31:0] sel_first_clus, sel_size, sel_wav_first_clus, sel_wav_size;
    wire        sel_valid, sel_wav_valid;
    wire [15:0] bmp_seen, wav_seen;

    file_index u_idx (
        .clk(clk), .rst_n(rst_n),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index),
        .ent_valid(ent_valid), .ent_ready(ent_ready),
        .idx_clear(idx_clear), .idx_commit(idx_commit), .idx_done(idx_done),
        .file_cnt(file_cnt), .file_valid(file_valid), .insufficient(insufficient),
        .err_code(ec), .err_detail(ed),
        .sel_slot(sel_slot), .sel_first_clus(sel_first_clus), .sel_size(sel_size),
        .sel_valid(sel_valid),
        .sel_wav_first_clus(sel_wav_first_clus), .sel_wav_size(sel_wav_size),
        .sel_wav_valid(sel_wav_valid),
        .bmp_seen(bmp_seen), .wav_seen(wav_seen)
    );


    always @(posedge clk) begin
        if (idx_done === 1'b1) done_cnt = done_cnt + 1;
    end


    task do_clear;
        begin
            @(posedge clk); idx_clear = 1'b1;
            @(posedge clk); idx_clear = 1'b0;
            repeat (3) @(posedge clk);
            done_cnt = 0;
        end
    endtask

    task push_ent;
        input [87:0] nm;
        input [31:0] clus;
        input [31:0] size;
        begin
            @(posedge clk);
            ent_name       = nm;
            ent_attr       = 8'h20;
            ent_first_clus = clus;
            ent_size       = size;
            ent_valid      = 1'b1;
            @(posedge clk);
            ent_valid      = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task do_commit;
        begin
            @(posedge clk); idx_commit = 1'b1;
            @(posedge clk); idx_commit = 1'b0;
            repeat (5) @(posedge clk);
        end
    endtask


    task chk_slot;
        input [1:0]  s;
        input [31:0] exp_clus;
        input [31:0] exp_size;
        input        exp_valid;
        input [255:0] name;
        begin
            sel_slot = s;
            #1;
            check(sel_first_clus === exp_clus, name);
            check(sel_size === exp_size,       name);
            check(sel_valid === exp_valid,     name);
        end
    endtask


    initial begin
        errors = 0;
        ent_valid = 1'b0;
        ent_name = 88'h0;
        ent_attr = 8'h20;
        ent_first_clus = 32'd0;
        ent_size = 32'd0;
        ent_index = 16'd0;
        idx_clear = 1'b0;
        idx_commit = 1'b0;
        sel_slot = 2'd0;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        check(ent_ready === 1'b1, "T60.1 ent_ready 恒 1（本模块不反压）");


        $display("\n==== T61: 乱序 -> 升序 ====");
        do_clear;
        push_ent("SV0003  BMP", 32'd300, 32'd921600);
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        push_ent("SV0002  BMP", 32'd200, 32'd921600);
        push_ent("SV0004  BMP", 32'd400, 32'd921600);
        do_commit;
        check(done_cnt == 1,           "T61.1 idx_done 恰好脉冲 1 次");
        check(file_cnt === 4'd4,       "T61.2 file_cnt = 4");
        check(file_valid === 4'b1111,  "T61.3 file_valid 全 1");
        check(insufficient === 1'b0,   "T61.4 不算不足");
        check(ec === `ERR_NONE,        "T61.5 无错误码");
        chk_slot(2'd0, 32'd100, 32'd921600, 1'b1, "T61.6 槽0 = SV0001");
        chk_slot(2'd1, 32'd200, 32'd921600, 1'b1, "T61.7 槽1 = SV0002");
        chk_slot(2'd2, 32'd300, 32'd921600, 1'b1, "T61.8 槽2 = SV0003");
        chk_slot(2'd3, 32'd400, 32'd921600, 1'b1, "T61.9 槽3 = SV0004");
        check(bmp_seen === 16'd4,      "T61.10 bmp_seen = 4");


        $display("\n==== T62: 6 幅只留最小的 4 幅 ====");
        do_clear;
        push_ent("SV0006  BMP", 32'd600, 32'd921600);
        push_ent("SV0005  BMP", 32'd500, 32'd921600);
        push_ent("SV0004  BMP", 32'd400, 32'd921600);
        push_ent("SV0003  BMP", 32'd300, 32'd921600);
        push_ent("SV0002  BMP", 32'd200, 32'd921600);
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        do_commit;
        check(file_cnt === 4'd4,       "T62.1 file_cnt = 4");
        chk_slot(2'd0, 32'd100, 32'd921600, 1'b1, "T62.2 槽0 = SV0001");
        chk_slot(2'd3, 32'd400, 32'd921600, 1'b1, "T62.3 槽3 = SV0004（0005/0006 落榜）");
        check(bmp_seen === 16'd6,      "T62.4 bmp_seen = 6（看得到但榜上只有 4）");


        $display("\n==== T63: 只有 2 幅 ====");
        do_clear;
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        push_ent("SV0002  BMP", 32'd200, 32'd921600);
        do_commit;
        check(file_cnt === 4'd2,                "T63.1 file_cnt = 2");
        check(file_valid === 4'b0011,           "T63.2 file_valid = 0011");
        check(insufficient === 1'b1,            "T63.3 insufficient 拉高");
        check(ec === `ERR_MEDIA_INVALID,        "T63.4 主码 = 0x03");
        check(ed === `DET_BMP_COUNT,            "T63.5 细分码 = 0x3C(合法图片少于 4 幅)");
        chk_slot(2'd2, 32'd0, 32'd0, 1'b0,      "T63.6 槽2 无效");


        $display("\n==== T64: 非法名跳过 ====");
        do_clear;
        push_ent("sv0001  BMP", 32'd999, 32'd921600);
        push_ent("SV0000  BMP", 32'd998, 32'd921600);
        push_ent("SV0001  JPG", 32'd997, 32'd921600);
        push_ent("SV00001 BMP", 32'd996, 32'd921600);
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        do_commit;
        check(file_cnt === 4'd1,       "T64.1 只有 1 幅合法");
        check(bmp_seen === 16'd1,      "T64.2 bmp_seen = 1");
        chk_slot(2'd0, 32'd100, 32'd921600, 1'b1, "T64.3 只认 SV0001.BMP");


        $display("\n==== T65: WAV 配对 ====");
        do_clear;
        push_ent("SV0001  WAV", 32'd1100, 32'd96000);
        push_ent("SV0002  BMP", 32'd200,  32'd921600);
        push_ent("SV0001  BMP", 32'd100,  32'd921600);
        push_ent("SV0003  WAV", 32'd1300, 32'd96000);
        do_commit;
        sel_slot = 2'd0; #1;
        check(sel_wav_valid === 1'b1,            "T65.1 槽0 有同编号 WAV");
        check(sel_wav_first_clus === 32'd1100,   "T65.2 WAV 首簇 = 1100");
        check(sel_wav_size === 32'd96000,        "T65.3 WAV 大小 = 96000");
        sel_slot = 2'd1; #1;
        check(sel_wav_valid === 1'b0,            "T65.4 槽1 无 WAV（缺失不算失败）");
        check(insufficient === 1'b1,             "T65.5 只有 1 幅图 -> 仍报不足");
        check(wav_seen === 16'd2,                "T65.6 wav_seen = 2");


        $display("\n==== T66: WAV 串号 ====");
        do_clear;
        push_ent("SV0001  BMP", 32'd100,  32'd921600);
        push_ent("SV0003  WAV", 32'd1300, 32'd96000);
        do_commit;
        sel_slot = 2'd0; #1;
        check(sel_wav_valid === 1'b0, "T66.1 SV0001.BMP 不能配 SV0003.WAV");


        $display("\n==== T67: 清表后重扫 ====");
        do_clear;
        check(file_cnt === 4'd0,     "T67.1 清表后 file_cnt = 0");
        check(file_valid === 4'b0,   "T67.2 清表后 file_valid = 0");
        check(bmp_seen === 16'd0,    "T67.3 清表后 bmp_seen = 0");
        check(insufficient === 1'b0, "T67.4 清表后不足标志也清掉");
        push_ent("SV0009  BMP", 32'd900, 32'd921600);
        do_commit;
        check(file_cnt === 4'd1,     "T67.5 重扫后 file_cnt = 1");
        chk_slot(2'd0, 32'd900, 32'd921600, 1'b1, "T67.6 新增的 SV0009 在槽0");


        $display("\n==== T68: 重复编号 ====");
        do_clear;
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        push_ent("SV0001  BMP", 32'd999, 32'd921600);
        do_commit;
        check(file_cnt === 4'd1,          "T68.1 重复编号只占 1 槽");
        chk_slot(2'd0, 32'd100, 32'd921600, 1'b1, "T68.2 保留先出现的那一条");
        check(bmp_seen === 16'd2,         "T68.3 bmp_seen 仍计 2（看到就算看到）");


        $display("\n==== T69: 编号位数边界（缺陷 25）====");
        do_clear;
        push_ent("SV0100  BMP", 32'd700, 32'd921600);
        push_ent("SV0001  BMP", 32'd100, 32'd921600);
        push_ent("SV0101  BMP", 32'd900, 32'd921600);
        do_commit;
        check(file_cnt === 4'd3, "T69.1 三幅全部合法（SV0100 不能因键=0 被忽略）");

        chk_slot(2'd0, 32'd100, 32'd921600, 1'b1, "T69.2 槽0 = SV0001（键 0x0001）");
        chk_slot(2'd1, 32'd700, 32'd921600, 1'b1, "T69.3 槽1 = SV0100（键 0x0100）");
        chk_slot(2'd2, 32'd900, 32'd921600, 1'b1, "T69.4 槽2 = SV0101（键 0x0101，≠0x0001）");
        check(bmp_seen === 16'd3, "T69.5 bmp_seen 计 3");


        push_ent("SV0002  BMP", 32'd333, 32'd921600);
        push_ent("SV0100  WAV", 32'd444, 32'd96000);
        repeat(5)@(posedge clk);
        check(file_cnt===4'd3 && bmp_seen===16'd3 && wav_seen===16'd0,
              "T70.1 committed index and counters remain frozen");
        chk_slot(2'd1,32'd700,32'd921600,1'b1,"T70.2 late smaller ID cannot reorder published slots");

        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
