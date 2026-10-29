


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_memory_arbiter;


    reg clk_b = 1'b0;
    always #5  clk_b = ~clk_b;

    reg rst_arb_n = 1'b0;

    integer passes = 0;
    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                passes = passes + 1;
                $display("[PASS] %0s", name);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    localparam integer N_BURST = 4;


    wire        mem_req, mem_wr, mem_ready, mem_rdata_valid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;
    wire        rd_ack, rd_busy, rd_data_valid;
    wire [31:0] rd_data;
    wire        wr_ack, wr_busy;
    wire        sd_ack, sd_busy, sd_rdata_valid;
    wire [31:0] sd_rdata;
    wire [15:0] wr_starve_cnt, rd_starve_cnt;

    reg  arb_run = 1'b0;


    wire        rd_req  = arb_run;
    wire [31:0] rd_addr = 32'h0000_2000;
    wire [15:0] rd_len  = 16'd16;


    wire        wr_req  = arb_run;
    wire [31:0] wr_addr = 32'h0008_0000;
    reg  [31:0] wr_data = 32'hAAAA_5555;
    wire [15:0] wr_len  = 16'd16;


    reg         sd_req = 1'b0;
    reg         sd_wr  = 1'b0;
    wire [31:0] sd_addr = 32'h002C_0000;
    wire [31:0] sd_wdata= 32'h1234_5678;
    wire [15:0] sd_len = 16'd8;
    reg  [15:0] sd_timer = 16'd0;

    always @(posedge clk_b or negedge rst_arb_n) begin
        if (!rst_arb_n) begin
            sd_req <= 1'b0; sd_timer <= 16'd0;
        end else if (!arb_run) begin
            sd_req <= 1'b0;
        end else begin
            if (sd_ack) sd_req <= 1'b0;
            else if (!sd_req) begin
                if (sd_timer == 16'd200) begin sd_req <= 1'b1; sd_timer <= 16'd0; end
                else sd_timer <= sd_timer + 16'd1;
            end
        end
    end

    memory_arbiter #(.MAX_BURSTS(N_BURST), .STARVE_LIMIT(64)) u_arb (
        .clk(clk_b), .rst_n(rst_arb_n), .video_fifo_level(16'd0),
        .rd_req(rd_req), .rd_addr(rd_addr), .rd_len(rd_len),
        .rd_ack(rd_ack), .rd_busy(rd_busy), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ack(wr_ack), .wr_busy(wr_busy),
        .sd_req(sd_req), .sd_wr(sd_wr), .sd_addr(sd_addr), .sd_wdata(sd_wdata), .sd_len(sd_len),
        .sd_ack(sd_ack), .sd_busy(sd_busy), .sd_rdata(sd_rdata), .sd_rdata_valid(sd_rdata_valid),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_rdata_valid(mem_rdata_valid),
        .wr_starve_cnt(wr_starve_cnt), .rd_starve_cnt(rd_starve_cnt)
    );


    reg [31:0] mem [0:65535];
    assign mem_ready       = 1'b1;
    assign mem_rdata       = mem[mem_addr[18:2]];
    assign mem_rdata_valid = mem_req && mem_ready && !mem_wr;
    always @(posedge clk_b) begin
        if (mem_req && mem_wr && mem_ready) mem[mem_addr[18:2]] <= mem_wdata;
    end


    integer rd_words = 0, wr_bursts = 0, sd_bursts = 0;
    integer rd_consec = 0, rd_consec_max = 0;
    integer wr_consec = 0, wr_consec_max = 0;
    integer sd_consec = 0, sd_consec_max = 0;

    always @(posedge clk_b or negedge rst_arb_n) begin
        if (!rst_arb_n) begin
            rd_words <= 0; wr_bursts <= 0; sd_bursts <= 0;
            rd_consec <= 0; rd_consec_max <= 0; wr_consec <= 0; wr_consec_max <= 0;
            sd_consec <= 0; sd_consec_max <= 0;
        end else begin
            if (rd_data_valid) rd_words <= rd_words + 1;
            if (rd_ack) begin
                rd_consec <= rd_consec + 1;
                if (rd_consec + 1 > rd_consec_max) rd_consec_max <= rd_consec + 1;
                wr_consec <= 0; sd_consec <= 0;
            end else if (wr_ack) begin
                wr_bursts <= wr_bursts + 1;
                wr_consec <= wr_consec + 1;
                if (wr_consec + 1 > wr_consec_max) wr_consec_max <= wr_consec + 1;
                rd_consec <= 0; sd_consec <= 0;
            end else if (sd_ack) begin
                sd_bursts <= sd_bursts + 1;
                sd_consec <= sd_consec + 1;
                if (sd_consec + 1 > sd_consec_max) sd_consec_max <= sd_consec + 1;
                rd_consec <= 0; wr_consec <= 0;
            end
        end
    end


    integer i;

    initial begin
        for (i = 0; i < 65536; i = i + 1) mem[i] = i[31:0];


        $display("==== 阶段 A：仲裁器 ====");
        rst_arb_n = 1'b0; arb_run = 1'b0;
        repeat (10) @(posedge clk_b);
        rst_arb_n = 1'b1;
        arb_run   = 1'b1;
        repeat (3000) @(posedge clk_b);
        arb_run   = 1'b0;
        repeat (4) @(posedge clk_b);

        $display("  rd_words=%0d  wr_bursts=%0d  sd_bursts=%0d  consec max: rd=%0d wr=%0d sd=%0d",
                 rd_words, wr_bursts, sd_bursts, rd_consec_max, wr_consec_max, sd_consec_max);
        check(wr_bursts >= 10,        "ARB: 帧写持续完成（>=10 个突发）");
        check(rd_words  >= 1000,      "ARB: 显示读持续供数（>=1000 word）");
        check(rd_consec_max <= N_BURST, "ARB: 读 grant 连续突发数不超过 N");
        check(wr_consec_max <= N_BURST, "ARB: 写 grant 连续突发数不超过 N");
        check(sd_consec_max <= N_BURST, "ARB: SD grant 连续突发数不超过 N");
        check(rd_starve_cnt == 16'd0, "ARB: rd_starve_cnt == 0");
        check(wr_starve_cnt == 16'd0, "ARB: wr_starve_cnt == 0（帧写未饿死）");


        $display("========================================");
        $display("  PASS = %0d   FAIL = %0d", passes, errors);
        $display("========================================");
        if (errors == 0) $display("[RESULT] ALL PASS");
        else             $display("[RESULT] %0d FAILED", errors);
        $finish;
    end


    initial begin
        #500000;
        $display("[FAIL] watchdog timeout");
        $finish;
    end

endmodule
