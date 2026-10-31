


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_frame_writer;


    localparam [31:0] IMG0_BASE = `SV_IMG0_BASE;
    localparam [31:0] IMG2_BASE = `SV_IMG2_BASE;
    localparam [31:0] IMG3_BASE = `SV_IMG3_BASE;
    localparam [31:0] BAD_BASE  = 32'h003F_0000;

    localparam integer FRAME_W = 640;
    localparam integer FRAME_H = 480;
    localparam integer FRAME_PIX = FRAME_W * FRAME_H;


    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #4 clk = ~clk;

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end

     end endtask


    function [15:0] pix_of;
        input integer n;
        begin
            pix_of = 16'h1000 + (n & 12'hFFF);

     end endfunction


    reg         fw_start;
    reg  [1:0]  fw_slot;
    reg  [31:0] fw_base;
    reg  [15:0] fw_din;
    reg         fw_din_valid;

    wire        fw_din_ready;
    wire        fw_wr_req;
    wire [31:0] fw_wr_addr;
    wire [31:0] fw_wr_data;
    wire [15:0] fw_wr_len;
    wire        fw_wr_done;
    wire [3:0]  fw_slot_valid;
    wire        fw_crc_ok;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire        fw_wr_error;
    wire [7:0]  fw_err_code;
    wire [7:0]  fw_err_detail;

    wire        mem_init_done;
    wire [31:0] mem_rdata;
    wire        mem_rdata_valid;
    wire        mem_ready;
    wire        mem_error;

    wire        sd_req, sd_wr;
    wire [31:0] sd_addr, sd_wdata;
    wire [3:0]  sd_wstrb;
    wire [31:0] sd_rdata;
    wire        sd_rvalid, sd_ready, sd_initdone;

    frame_writer #(
        .GAP_TIMEOUT (16'd512)
    ) u_fw (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (fw_slot),
        .slot_base  (fw_base),
        .din        (fw_din),
        .din_valid  (fw_din_valid),
        .din_ready  (fw_din_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (mem_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid),
        .crc_ok     (fw_crc_ok),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );

    mem_ctrl u_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .init_done         (mem_init_done),
        .req               (fw_wr_req),
        .wr                (fw_wr_req),
        .addr              (fw_wr_addr),
        .wdata             (fw_wr_data),
        .wstrb             (4'hF),
        .rdata             (mem_rdata),
        .rdata_valid       (mem_rdata_valid),
        .ready             (mem_ready),
        .mem_error         (mem_error),
        .sdram_req         (sd_req),
        .sdram_wr          (sd_wr),
        .sdram_addr        (sd_addr),
        .sdram_wdata       (sd_wdata),
        .sdram_wstrb       (sd_wstrb),
        .sdram_rdata       (sd_rdata),
        .sdram_rdata_valid (sd_rvalid),
        .sdram_ready       (sd_ready),
        .sdram_init_done   (sd_initdone)
    );

    frame_memory_model u_sdram (
        .clk        (clk),
        .rst_n      (rst_n),
        .req        (sd_req),
        .wr         (sd_wr),
        .addr       (sd_addr),
        .wdata      (sd_wdata),
        .wstrb      (sd_wstrb),
        .rdata      (sd_rdata),
        .rdata_valid(sd_rvalid),
        .ready      (sd_ready),
        .init_done  (sd_initdone)
    );


    reg     mon_en = 1'b0;
    integer early_viol = 0;
    integer wr_done_seen = 0;

    always @(posedge clk) begin
        if (fw_wr_done) wr_done_seen = wr_done_seen + 1;
        if (rst_n && mon_en) begin
            if (fw_slot_valid[0] && (fw_px_cnt !== `SV_FRAME_PIXELS)) early_viol = early_viol + 1;
            if (fw_slot_valid[0] && !fw_crc_ok)                  early_viol = early_viol + 1;
        end
    end


    task do_start;
        input [1:0]  sel;
        input [31:0] base;
        begin
            @(negedge clk);
            fw_slot  = sel;
            fw_base  = base;
            fw_start = 1'b1;
            @(negedge clk);
            fw_start = 1'b0;

     end endtask


    task drive_pixels;
        input integer n;
        input integer base_idx;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(negedge clk);
                fw_din       = pix_of(base_idx + k);
                fw_din_valid = 1'b1;
                while (!fw_din_ready) @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            fw_din_valid = 1'b0;

     end endtask


    task wait_result;
        input integer maxc;
        integer c;
        begin
            c = 0;
            while (!fw_wr_done && !fw_wr_error && (c < maxc)) begin
                @(negedge clk);
                c = c + 1;
            end

     end endtask


    task chk_px;
        input integer x;
        input integer y;
        input [31:0]  base;
        input [255:0] name;
        integer      idx, k;
        reg   [31:0] widx, got, exp;
        reg   [15:0] lo, hi;
        begin
            idx  = y * FRAME_W + x;
            k    = idx / 2;
            widx = (base >> 2) + k;
            u_sdram.peek_word(widx, got);
            lo   = pix_of(k * 2);
            hi   = pix_of(k * 2 + 1);
            exp  = {hi, lo};
            check(got === exp, name);

     end endtask


    initial begin
        fw_start = 1'b0; fw_slot = 2'd0; fw_base = 32'd0;
        fw_din = 16'd0;  fw_din_valid = 1'b0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;


        while (!sd_initdone) @(negedge clk);
        repeat (2) @(negedge clk);
        check(mem_init_done === 1'b1, "T0 SDRAM init_done");
        check(mem_error === 1'b0,     "T0 无 mem_error");


        $display("---- T1 正常一帧写入 ----");
        mon_en = 1'b1;
        do_start(2'd0, IMG0_BASE);

        repeat (5) @(negedge clk);
        check(fw_slot_valid[0] === 1'b0, "T1 写入前 slot_valid[0]=0");
        drive_pixels(FRAME_PIX, 0);
        wait_result(20000);
        mon_en = 1'b0;
        repeat (2) @(negedge clk);

        check(fw_wr_done === 1'b1 || wr_done_seen > 0, "T1 wr_done 产生");
        check(fw_slot_valid[0] === 1'b1, "T1 slot_valid[0] 置位");
        check(fw_crc_ok === 1'b1,        "T1 crc_ok 通过");
        check(fw_px_cnt === `SV_FRAME_PIXELS,  "T1 px_cnt=307200");
        check(fw_wr_error === 1'b0,      "T1 无写错误");
        check(fw_slot_valid[3:1] === 3'b000, "T1 其他槽未置位");


        chk_px(0,   0,   IMG0_BASE, "T1 抽查(0,0)");
        chk_px(639, 0,   IMG0_BASE, "T1 抽查(639,0)");
        chk_px(0,   479, IMG0_BASE, "T1 抽查(0,479)");
        chk_px(639, 479, IMG0_BASE, "T1 抽查(639,479)");
        chk_px(320, 240, IMG0_BASE, "T1 抽查(320,240)");
        chk_px(100, 50,  IMG0_BASE, "T1 抽查(100,50)");


        $display("---- T2 像素数少一个 ----");
        do_start(2'd2, IMG2_BASE);
        drive_pixels(FRAME_PIX - 1, 0);
        wait_result(20000);
        repeat (2) @(negedge clk);
        check(fw_wr_error === 1'b1,          "T2 报写错误");
        check(fw_err_detail === `DET_FS_SHORT, "T2 细分码 DET_FS_SHORT");
        check(fw_err_code === `ERR_MEDIA_INVALID, "T2 主码 ERR_MEDIA_INVALID");
        check(fw_slot_valid[2] === 1'b0,     "T2 slot_valid[2] 未置位");
        check(fw_px_cnt === 19'd307199,      "T2 px_cnt=307199");


        $display("---- T3 像素数多一个 ----");
        do_start(2'd3, IMG3_BASE);
        drive_pixels(FRAME_PIX, 0);

        @(negedge clk);
        fw_din       = pix_of(FRAME_PIX);
        fw_din_valid = 1'b1;
        repeat (16) @(negedge clk);
        fw_din_valid = 1'b0;
        wait_result(20000);
        repeat (2) @(negedge clk);
        check(fw_wr_error === 1'b1,           "T3 报写错误");
        check(fw_err_detail === `DET_BMP_SIZE, "T3 细分码 DET_BMP_SIZE");
        check(fw_slot_valid[3] === 1'b0,      "T3 slot_valid[3] 未置位");


        $display("---- T4 slot_valid 时序 ----");
        check(early_viol === 0, "T4 slot_valid 未在整帧+CRC前提前置位");


        $display("---- T5 越界写被拒绝 ----");
        do_start(2'd1, BAD_BASE);
        repeat (8) @(negedge clk);
        check(fw_wr_error === 1'b1,            "T5 越界槽基地址被拒绝");
        check(fw_err_detail === `DET_BMP_TRUNC, "T5 细分码 DET_BMP_TRUNC");
        check(fw_slot_valid[1] === 1'b0,       "T5 slot_valid[1] 未置位");
        check(fw_slot_valid[0] === 1'b1,       "T5 合法槽的 slot_valid 未被误清");


        $display("========================================");
        $display("  断言总数 %0d，失败 %0d", total, errors);
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("========================================");
        $finish;
    end


    initial begin
        #500_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
