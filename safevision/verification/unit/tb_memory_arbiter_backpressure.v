`timescale 1ns/1ps
module tb_memory_arbiter_backpressure;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, rd_req=0, mem_ready=0;
    wire mem_req, mem_wr, rd_ack, rd_busy, rd_data_valid;
    wire [31:0] mem_addr, mem_wdata, rd_data;
    wire [3:0] mem_wstrb;
    wire [15:0] wr_starve_cnt, rd_starve_cnt;
    memory_arbiter dut(
        .clk(clk), .rst_n(rst_n), .video_fifo_level(16'd0),
        .rd_req(rd_req), .rd_addr(32'h1000), .rd_len(16'd1),
        .rd_ack(rd_ack), .rd_busy(rd_busy), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .wr_req(1'b0), .wr_addr(32'd0), .wr_data(32'd0), .wr_len(16'd0),
        .wr_ack(), .wr_busy(), .sd_req(1'b0), .sd_wr(1'b0),
        .sd_addr(32'd0), .sd_wdata(32'd0), .sd_len(16'd0),
        .sd_ack(), .sd_busy(), .sd_rdata(), .sd_rdata_valid(),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(32'h12345678), .mem_rdata_valid(mem_req && mem_ready && !mem_wr),
        .wr_starve_cnt(wr_starve_cnt), .rd_starve_cnt(rd_starve_cnt));
    integer accepted=0;
    always @(posedge clk) if (rst_n && mem_req && mem_ready) begin
        accepted=accepted+1;
        $display("ACCEPT word=%0d addr=%08h busy=%b",accepted,mem_addr,rd_busy);
    end
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk); rd_req=1;
        wait(rd_ack);
        @(negedge clk); rd_req=0;

        repeat(3) @(negedge clk);
        mem_ready=1;
        repeat(5) @(negedge clk);
        if(accepted!=1) begin $display("[FAIL] ARB_ONE_WORD_BACKPRESSURE: expected 1 accepted word, got %0d",accepted); $finish; end 
        $display("PASS tb_memory_arbiter_backpressure: one-word memory ready/req handshake");
        $finish;
    end
    initial begin #2000; begin $display("[FAIL] AUDIT_TIMEOUT"); $finish; end  end
endmodule
