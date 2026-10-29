`timescale 1ns/1ps
module tb_video_read_dma_burst64;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,start=0,rd_ack=0,rd_data_valid=0;
    reg [31:0] rd_data=0;
    wire rd_req,active,done,fifo_wr_en;
    wire [31:0] rd_addr,rd_bytes_cnt;
    wire [15:0] rd_len,fifo_wr_data;
    video_read_dma #(.BURST_WORDS(64)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.frame_base(32'h1000),.pix_fifo_level(16'd0),
        .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(1'b0),
        .rd_data(rd_data),.rd_data_valid(rd_data_valid),.fifo_wr_data(fifo_wr_data),
        .fifo_wr_en(fifo_wr_en),.rd_bytes_cnt(rd_bytes_cnt),.active(active),.done(done));
    integer pixels=0,i;
    always @(posedge clk) if(rst_n&&fifo_wr_en) pixels=pixels+1;
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        wait(rd_req);
        @(negedge clk); rd_ack=1;
        @(negedge clk); rd_ack=0;
        if(rd_len!=64) begin $display("[FAIL] AUDIT_BAD_REQUEST_LENGTH"); $finish; end 
        for(i=0;i<64;i=i+1) begin rd_data_valid=1; rd_data=i; @(negedge clk); end
        rd_data_valid=0;
        repeat(135) @(negedge clk);
        if(pixels!=128 || rd_bytes_cnt!=256)
            begin $display("[FAIL] DMA_BURST64_HANG: sent=64 words, pixels=%0d bytes=%0d collect_cnt=%0d",pixels,rd_bytes_cnt,dut.collect_cnt); $finish; end 
        $display("PASS tb_video_read_dma_burst64: first 64-word burst drains 128 pixels"); $finish;
    end
    initial begin #4000; begin $display("[FAIL] AUDIT_TIMEOUT"); $finish; end  end
endmodule
