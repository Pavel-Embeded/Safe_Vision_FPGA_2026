// Experimental eight-entry queue: this vendor mapping uses three RAM9K tiles.
// It is not included in the production source list. Synchronous RAM
// reads prefetch the next head on the consuming edge. The first write and a
// one-entry pop/push use an explicit bypass, so no read-during-write behavior
// is required from the RAM primitive. FWFT latency and full policy match the
// legacy sync_fifo exactly, including rejecting writes when initially full.
module v3_event_fifo #(parameter integer W=44)(
 input wire clk,rst_n,wr_en,input wire[W-1:0] din,
 output wire full,almost_full,input wire rd_en,output wire[W-1:0] dout,
 output wire empty,almost_empty,output wire[3:0] data_count);
 reg[2:0] wr_ptr,rd_ptr;reg[3:0] count;reg bypass;reg[W-1:0] bypass_data;
 wire write_fire=wr_en&&!full,read_fire=rd_en&&!empty;
 wire[2:0] next_head=rd_ptr+read_fire;
 wire[W-1:0] ram_head;
 assign full=count==8;assign empty=count==0;
 assign almost_full=count>=6;assign almost_empty=count<=1;assign data_count=count;
 assign dout=bypass?bypass_data:ram_head;
 a_pixel_fifo_eram #(.MODE("SDP"),.DATAWIDTH_A(W),.DATAWIDTH_B(W),
 .ADDRWIDTH_A(8),.ADDRWIDTH_B(8),.REGMODE_B("NOREG")) storage(
 .clka(clk),.rsta(!rst_n),.cea(write_fire),.ocea(1'b1),.wea(write_fire),
 .dia(din),.addra({5'd0,wr_ptr}),.doa(),
 .clkb(clk),.rstb(!rst_n),.ceb(rst_n),.oceb(1'b1),.web(1'b0),.dib({W{1'b0}}),
 .addrb({5'd0,next_head}),.dob(ram_head));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wr_ptr<=0;rd_ptr<=0;count<=0;bypass<=0;bypass_data<=0;end
  else begin
   bypass<=write_fire&&(empty||(count==1&&read_fire));
   if(write_fire&&(empty||(count==1&&read_fire)))bypass_data<=din;
   if(write_fire)wr_ptr<=wr_ptr+1'b1;
   if(read_fire)rd_ptr<=rd_ptr+1'b1;
   case({write_fire,read_fire})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
  end
 end
endmodule
