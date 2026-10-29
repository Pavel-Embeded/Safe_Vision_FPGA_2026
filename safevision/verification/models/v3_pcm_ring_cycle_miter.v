


module v3_pcm_ring_cycle_miter #(parameter integer PTR_W=14,PREFETCH=800)(
 input wire clk,rst_n,input wire [127:0] in_data,input wire [3:0] in_valid,output wire [3:0] in_ready,
 input wire commit_valid,input wire [1:0] commit_slot,input wire [7:0] commit_generation,
 output wire commit_ready,input wire [3:0] fallback,
 output wire [3:0] prefetched,output wire [63:0] levels,
 output wire [39:0] out_data,output wire out_valid,input wire out_ready,
 input wire [9:0] output_level,
 output wire req,output wire wr,output wire [31:0] addr,wdata,output wire [15:0] len,
 input wire ack,busy,input wire [31:0] rdata,input wire rvalid,
 output wire [31:0] overflow_count);

 wire[3:0]new_in_ready;
 wire[0:0]new_commit_ready;
 wire[3:0]new_prefetched;
 wire[63:0]new_levels;
 wire[39:0]new_out_data;
 wire[0:0]new_out_valid;
 wire[0:0]new_req;
 wire[0:0]new_wr;
 wire[31:0]new_addr;
 wire[31:0]new_wdata;
 wire[15:0]new_len;
 wire[31:0]new_overflow_count;
v3_pcm_ring_reference #(.PTR_W(PTR_W),.PREFETCH(PREFETCH)) reference(.clk(clk),.rst_n(rst_n),.in_data(in_data),.in_valid(in_valid),.commit_valid(commit_valid),.commit_slot(commit_slot),.commit_generation(commit_generation),.fallback(fallback),.out_ready(out_ready),.output_level(output_level),.ack(ack),.busy(busy),.rdata(rdata),.rvalid(rvalid),.in_ready(in_ready),.commit_ready(commit_ready),.prefetched(prefetched),.levels(levels),.out_data(out_data),.out_valid(out_valid),.req(req),.wr(wr),.addr(addr),.wdata(wdata),.len(len),.overflow_count(overflow_count));
v3_pcm_ring #(.PTR_W(PTR_W),.PREFETCH(PREFETCH)) candidate(.clk(clk),.rst_n(rst_n),.in_data(in_data),.in_valid(in_valid),.commit_valid(commit_valid),.commit_slot(commit_slot),.commit_generation(commit_generation),.fallback(fallback),.out_ready(out_ready),.output_level(output_level),.ack(ack),.busy(busy),.rdata(rdata),.rvalid(rvalid),.in_ready(new_in_ready),.commit_ready(new_commit_ready),.prefetched(new_prefetched),.levels(new_levels),.out_data(new_out_data),.out_valid(new_out_valid),.req(new_req),.wr(new_wr),.addr(new_addr),.wdata(new_wdata),.len(new_len),.overflow_count(new_overflow_count));
 integer comparisons=0,errors=0;
 always @(posedge clk)begin #1;if(rst_n)begin comparisons = comparisons + 1;
 if({in_ready,commit_ready,prefetched,levels,out_data,out_valid,req,wr,addr,wdata,len,overflow_count}!=={new_in_ready,new_commit_ready,new_prefetched,new_levels,new_out_data,new_out_valid,new_req,new_wr,new_addr,new_wdata,new_len,new_overflow_count})begin errors = errors + 1;if(errors<9)$display("[FAIL] parallel ring cycle contract");end
 end end
 task report; begin $display("[PASS] ring exact original exposed-port miter comparisons=%0d errors=%0d",comparisons,errors);end endtask
endmodule
