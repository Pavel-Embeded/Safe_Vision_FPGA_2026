


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_framebuffer_loopback_core;

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


    wire        c_req, c_wr;
    wire [31:0] c_addr, c_wdata;
    wire [3:0]  c_wstrb;
    wire [31:0] c_rdata;
    wire        c_rvalid, c_ready, c_initdone;


    wire        rep_valid;
    wire        rep_ready;
    wire [7:0]  rep_data;
    wire        fb_ok, crc_ok, slot_valid;
    wire [7:0]  err_code;
    wire [18:0] wr_px, rd_px, bad_px;

    assign rep_ready = 1'b1;

    framebuffer_loopback_core u_core (
        .clk               (clk),
        .rst_n             (rst_n),
        .sdram_req         (c_req),
        .sdram_wr          (c_wr),
        .sdram_addr        (c_addr),
        .sdram_wdata       (c_wdata),
        .sdram_wstrb       (c_wstrb),
        .sdram_rdata       (c_rdata),
        .sdram_rdata_valid (c_rvalid),
        .sdram_ready       (c_ready),
        .sdram_init_done   (c_initdone),
        .rep_valid         (rep_valid),
        .rep_data          (rep_data),
        .rep_ready         (rep_ready),
        .ok                (fb_ok),
        .err_code          (err_code),
        .wr_px             (wr_px),
        .rd_px             (rd_px),
        .bad_px            (bad_px),
        .crc_ok            (crc_ok),
        .slot_valid        (slot_valid)
    );

    frame_memory_model u_mem (
        .clk        (clk),
        .rst_n      (rst_n),
        .req        (c_req),
        .wr         (c_wr),
        .addr       (c_addr),
        .wdata      (c_wdata),
        .wstrb      (c_wstrb),
        .rdata      (c_rdata),
        .rdata_valid(c_rvalid),
        .ready      (c_ready),
        .init_done  (c_initdone)
    );


    localparam integer RPT_LEN = 208;
    reg [8*RPT_LEN-1:0] got_vec;
    integer rep_n = 0;

    always @(posedge clk) begin
        if (rst_n && rep_valid) begin
            got_vec <= { got_vec[8*RPT_LEN-8-1:0], rep_data };
            rep_n   <= rep_n + 1;
        end
    end

    wire [8*RPT_LEN-1:0] exp_vec = {
        "SV-FB-LOOP", 8'h0D, 8'h0A,
        "INIT=01",    8'h0D, 8'h0A,
        "WR=04B000 CRC=01 SV=01", 8'h0D, 8'h0A,
        "RD=04B000 BAD=000000",   8'h0D, 8'h0A,
        "W0=59C3ACE1 W1=670FB387", 8'h0D, 8'h0A,
        "AM=FFFFFFFF", 8'h0D, 8'h0A,
        "AF=FF",       8'h0D, 8'h0A,
        "AV=00000000", 8'h0D, 8'h0A,
        "C0=1004 C1=1005 C2=1006 C3=1007", 8'h0D, 8'h0A,
        "B0=1035 B1=1036 B2=1037 B3=1038", 8'h0D, 8'h0A,
        "BF=000000", 8'h0D, 8'h0A,
        "DONE",       8'h0D, 8'h0A
    };


    integer wacc = 0;
    reg     prb_val_bad  = 1'b0;
    reg     prb_a_bad    = 1'b0;
    reg     prb_b_bad    = 1'b0;
    reg [31:0] prb_a_first = 32'd0;
    reg [31:0] prb_b_first = 32'd0;

    always @(posedge clk) begin
        if (rst_n && c_req && c_ready && c_wr) begin
            if (wacc < 36) begin
                if (c_wdata !== c_addr) prb_val_bad <= 1'b1;
                if (wacc == 0)  prb_a_first <= c_addr;
                if (wacc == 32) prb_b_first <= c_addr;
                if ((wacc > 0) && (wacc < 32)) begin
                    if (c_addr !== (prb_a_first + wacc)) prb_a_bad <= 1'b1;
                end else if (wacc > 32) begin
                    if (c_addr !== (prb_b_first + (wacc - 32))) prb_b_bad <= 1'b1;
                end
            end
            wacc <= wacc + 1;
        end
    end

    integer guard;

    initial begin
        got_vec = {8*RPT_LEN{1'b0}};
        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        guard = 0;
        while (!fb_ok && (err_code == 8'h00) && (guard < 20_000_000)) begin
            @(negedge clk);
            guard = guard + 1;
        end

        guard = 0;
        while ((rep_n < RPT_LEN) && (guard < 200_000)) begin
            @(negedge clk);
            guard = guard + 1;
        end
        repeat (2) @(negedge clk);

        $display("---- 帧缓存回环结果 ----");
        $display("  wr_px=%0d rd_px=%0d bad=%0d err=%02h rep_n=%0d",
                 wr_px, rd_px, bad_px, err_code, rep_n);
        $display("  探针写访问数=%0d A首址=%08h B首址=%08h 值错=%0b A段地址错=%0b B段地址错=%0b",
                 wacc, prb_a_first, prb_b_first, prb_val_bad, prb_a_bad, prb_b_bad);

        check(fb_ok      === 1'b1,        "T1 回环通过 ok=1");
        check(err_code   === 8'h00,       "T2 无错误码");
        check(wr_px      === 19'd307200,  "T3 写入像素数 = 307200");
        check(rd_px      === 19'd307200,  "T4 读回像素数 = 307200");
        check(bad_px     === 19'd0,       "T5 逐像素比对零错");
        check(crc_ok     === 1'b1,        "T6 frame_writer 抽样 CRC 通过");
        check(slot_valid === 1'b1,        "T7 slot_valid 置位");
        check(rep_n      === RPT_LEN,     "T8 报告 = 208 Byte");
        check(got_vec    === exp_vec,     "T9 报告字节逐字节正确");
        check((wacc >= 36) && (prb_val_bad === 1'b0),
                                          "T10 探针写值 = 字地址（36 word）");
        check((wacc >= 36) && (prb_a_bad === 1'b0) && (prb_b_bad === 1'b0) &&
              (prb_a_first === 32'h1000) && (prb_b_first === 32'h1035),
                                          "T11 探针写地址连续且基址正确（32+4 word）");

        $display("========================================");
        $display("  断言总数 %0d，失败 %0d", total, errors);
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("========================================");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
