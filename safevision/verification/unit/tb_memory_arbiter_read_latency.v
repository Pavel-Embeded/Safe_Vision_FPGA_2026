`timescale 1ns/1ps
module tb_memory_arbiter_read_latency;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, rd_req=0, wr_req=0;
    reg [3:0] response_pipe=0;
    wire mem_req, mem_wr, rd_ack, wr_ack, rd_busy, rd_data_valid;
    wire [31:0] mem_addr, mem_wdata, rd_data;
    wire [3:0] mem_wstrb;
    memory_arbiter dut(
        .clk(clk), .rst_n(rst_n), .video_fifo_level(16'd0),
        .rd_req(rd_req), .rd_addr(32'h1000), .rd_len(16'd1),
        .rd_ack(rd_ack), .rd_busy(rd_busy), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .wr_req(wr_req), .wr_addr(32'h2000), .wr_data(32'h87654321), .wr_len(16'd1),
        .wr_ack(wr_ack), .wr_busy(), .sd_req(1'b0), .sd_wr(1'b0),
        .sd_addr(32'd0), .sd_wdata(32'd0), .sd_len(16'd0),
        .sd_ack(), .sd_busy(), .sd_rdata(), .sd_rdata_valid(),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(1'b1), .mem_rdata(32'h12345678), .mem_rdata_valid(response_pipe[3]),
        .wr_starve_cnt(), .rd_starve_cnt());
    integer accepted_reads=0, returned_reads=0;
    always @(posedge clk) begin
        if(!rst_n) response_pipe<=0;
        else begin
            response_pipe<={response_pipe[2:0],mem_req&&!mem_wr};
            if(mem_req&&!mem_wr) begin
                accepted_reads=accepted_reads+1;
                $display("READ_ACCEPT addr=%08h",mem_addr);
            end
            if(response_pipe[3]) $display("MEMORY_RESPONSE rd_valid=%b current_channel=%0d",rd_data_valid,dut.cur_ch);
            if(rd_data_valid) returned_reads=returned_reads+1;
        end
    end
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); rd_req=1;
        wait(rd_ack);
        @(negedge clk); rd_req=0; wr_req=1;
        wait(wr_ack);
        @(negedge clk); wr_req=0;
        repeat(10) @(negedge clk);
        if(accepted_reads!=1 || returned_reads!=1)
            begin $display("[FAIL] ARB_DELAYED_RESPONSE_LOST: accepted=%0d returned_to_reader=%0d",accepted_reads,returned_reads); $finish; end 
        $display("PASS tb_memory_arbiter_read_latency: delayed read response retains original channel");
        $finish;
    end
    initial begin #2000; begin $display("[FAIL] AUDIT_TIMEOUT"); $finish; end  end
endmodule
