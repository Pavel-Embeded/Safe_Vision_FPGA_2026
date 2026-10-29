`timescale 1ns/1ps
module dma_frame_case #(parameter integer BURST=16,STREAMING=0)(input wire clk,rst_n,start,output reg finished);
 initial begin finished = 0; end

    localparam [31:0] BASE=32'h100000;
    reg [31:0] cycle=0;
    reg [15:0] level=0;
    wire consume=level!=0 && cycle[1:0]==0;
    wire req,ack,busy,active,done,fifo_en,rd_valid;
    wire [31:0] addr,rd_data,bytes;
    wire [15:0] len,pixel;
    wire mem_req,mem_wr,mem_ready;
    wire [31:0] mem_addr,mem_wdata;
    wire [3:0] mem_wstrb;
    reg [2:0] valid_pipe=0;
    reg [31:0] data_pipe[0:2];
    reg wr_req=0;
    wire wr_ack;
    integer pixel_count=0,word_count=0,write_count=0,i;
    assign mem_ready=(cycle%7!=1 && cycle%7!=2);
    function automatic [31:0] packed_pixels(input [31:0] a);
        reg [31:0] index;
        begin begin index=(a-BASE)>>1;packed_pixels={(index[15:0]+16'd1),index[15:0]};end
     end endfunction
    video_read_dma #(.BURST_WORDS(BURST),.PIX_DEPTH(256),.LOW_WATER(192),.STREAMING(STREAMING)) dma(
        .clk(clk),.rst_n(rst_n),.start(start),.frame_base(BASE),.pix_fifo_level(level),
        .rd_req(req),.rd_addr(addr),.rd_len(len),.rd_ack(ack),.rd_busy(busy),
        .rd_data(rd_data),.rd_data_valid(rd_valid),.fifo_wr_data(pixel),.fifo_wr_en(fifo_en),
        .rd_bytes_cnt(bytes),.active(active),.done(done));
    memory_arbiter arb(
        .clk(clk),.rst_n(rst_n),.video_fifo_level(level),
        .rd_req(req),.rd_addr(addr),.rd_len(len),.rd_ack(ack),.rd_busy(busy),.rd_data(rd_data),.rd_data_valid(rd_valid),
        .wr_req(wr_req),.wr_addr(32'h700000),.wr_data(32'hcafecafe),.wr_len(16'd3),.wr_ack(wr_ack),.wr_busy(),
        .sd_req(1'b0),.sd_wr(1'b0),.sd_addr(32'd0),.sd_wdata(32'd0),.sd_len(16'd0),
        .sd_ack(),.sd_busy(),.sd_rdata(),.sd_rdata_valid(),
        .mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready),.mem_rdata(data_pipe[2]),.mem_rdata_valid(valid_pipe[2]),
        .wr_starve_cnt(),.rd_starve_cnt());
    always @(posedge clk) begin
        if(!rst_n) begin
            cycle<=0;level<=0;valid_pipe<=0;wr_req<=0;finished<=0;
            pixel_count=0;word_count=0;write_count=0;
            for(i=0;i<3;i=i+1)data_pipe[i]<=0;
        end else begin
            cycle<=cycle+1;
            valid_pipe<={valid_pipe[1:0],mem_req&&mem_ready&&!mem_wr};
            data_pipe[0]<=packed_pixels(mem_addr);
            for(i=1;i<3;i=i+1)data_pipe[i]<=data_pipe[i-1];
            if(wr_ack)wr_req<=0;
            else if(!wr_req && active && cycle%113==0)wr_req<=1;
            if(mem_req&&mem_ready) begin
                if(mem_wr)write_count=write_count+1;
                else begin
                    if(mem_addr!==BASE+word_count*4 || word_count>=153600)
                        begin $display("[FAIL] DMA BURST=%0d frame read address/count mismatch",BURST); $finish; end 
                    word_count=word_count+1;
                end
            end
            if(fifo_en) begin
                if(pixel!==pixel_count[15:0] || pixel_count>=307200)
                    begin $display("[FAIL] DMA BURST=%0d pixel=%0d got=%04h",BURST,pixel_count,pixel); $finish; end 
                if(level>=256 && !consume)begin $display("[FAIL] DMA FIFO overflow BURST=%0d",BURST); $finish; end 
                pixel_count=pixel_count+1;
            end
            case({fifo_en,consume})
                2'b10:level<=level+1;
                2'b01:level<=level-1;
                default:;
            endcase
            if(done)begin
                if(bytes!==614400 || pixel_count!=307200 || word_count!=153600 || write_count==0 || active)
                    begin $display("[FAIL] DMA BURST=%0d frame completion/count/competing writer mismatch",BURST); $finish; end 
                finished<=1;
                $display("FRAME PASS BURST=%0d pixels=%0d reads=%0d competing-write-words=%0d",BURST,pixel_count,word_count,write_count);
            end
        end
    end
endmodule
module tb_video_read_dma_integration #(parameter integer STREAMING=0);
    reg clk=0,rst_n=0,start=0;
    always #4 clk=~clk;
    wire [3:0] finished;
    dma_frame_case #(.BURST(1),.STREAMING(STREAMING)) c1(clk,rst_n,start,finished[0]);
    dma_frame_case #(.BURST(7),.STREAMING(STREAMING)) c7(clk,rst_n,start,finished[1]);
    dma_frame_case #(.BURST(16),.STREAMING(STREAMING)) c16(clk,rst_n,start,finished[2]);
    dma_frame_case #(.BURST(64),.STREAMING(STREAMING)) c64(clk,rst_n,start,finished[3]);
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;

        repeat(20)@(negedge clk);rst_n=0;
        repeat(5)@(negedge clk);rst_n=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        wait(&finished);
        repeat(10)@(negedge clk);
        $display("PASS tb_video_read_dma_integration: four full RGB565 frames, 1228800 pixels; bursts 1/7/16/64, shortened frame tail, FIFO capacity, memory stalls, delayed responses, competing writer, reset restart");
        $finish;
    end
    initial begin #100000000; begin $display("[FAIL] DMA integration timeout"); $finish; end end
endmodule
