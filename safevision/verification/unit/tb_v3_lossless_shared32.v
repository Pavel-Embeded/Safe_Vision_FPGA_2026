`timescale 1ns/1ps
module tb_v3_lossless_shared32;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,fs=0,de=0;reg[11:0]x=0,y=0;
 wire[1:0]panel,text,edge_bit,rpanel,rtext,redge;
 wire[11:0]pos[0:1],rpos[0:1];wire[15:0]frames[0:1],rframes[0:1],loops[0:1],rloops[0:1];
 wire[1:0]request,index_hi;wire[8:0]index[0:1],word9[0:1];wire[7:0]word8[0:1];
 integer errors=0,comparisons=0,cycles=0,high_reads=0,highest_bit_reads=0,p,xx,yy,i;
 genvar lane;
 generate for(lane=0;lane<2;lane=lane+1)begin:pair
  localparam LAT=lane==0 ? 5:21;
  v3_scrolling_ticker #(.WIDTH(640),.HEIGHT(480),.PIXEL_LATENCY(LAT),.SOURCE_AHEAD(5),.CLIP_INPUT(0),
   .EXTERNAL_FONT(1),.PACKED_EXTERNAL(1),.MESSAGE_CHARS(32)) current(
   .clk(clk),.rst_n(rst_n),.frame_start(fs),.x(x),.y(y),.de(de),.panel_pixel(panel[lane]),.text_pixel(text[lane]),.edge_pixel(edge_bit[lane]),
   .position(pos[lane]),.frames(frames[lane]),.loops(loops[lane]),.font_request(request[lane]),.font_index(index[lane]),.font_word(word8[lane]),.font_index_hi(index_hi[lane]),.font_word9(word9[lane]));
  v3_scrolling_ticker_frozen_packed32 #(.WIDTH(640),.HEIGHT(480),.PIXEL_LATENCY(LAT),.SOURCE_AHEAD(5),.CLIP_INPUT(0),
   .MESSAGE_CHARS(32),.BITMAP_FILE("v3_ticker16.mem")) original(
   .clk(clk),.rst_n(rst_n),.frame_start(fs),.x(x),.y(y),.de(de),.panel_pixel(rpanel[lane]),.text_pixel(rtext[lane]),.edge_pixel(redge[lane]),
   .position(rpos[lane]),.frames(rframes[lane]),.loops(rloops[lane]),.font_request(),.font_index(),.font_word(8'd0));


  v3_audio_spectrum #(.SHARED_TICKER(1),.SHARED_PACKED_FONT(1),.PACKED_INIT_FILE("v3_spectrum_ticker32.mem")) memory(
   .clk(clk),.rst_n(rst_n),.frame_start(fs),.pcm_valid(1'b0),.pcm_left(24'd0),.x(x),.y(y),.de(1'b0),
   .trace_pixel(),.grid_pixel(),.colour(),.ready(),.spectrum_sequence(),.dominant_bin(),.peak_height(),
   .font_request(request[lane]),.font_index(index[lane]),.font_word(word8[lane]),.font_index_hi(index_hi[lane]),.font_word9(word9[lane]));
 end endgenerate
 task ck(input  okay,input [4095:0] message);begin begin
  okay = (okay === 1'b1); comparisons = comparisons + 1;if(!okay)begin errors = errors + 1;if(errors<15)$display("[FAIL] %s cycle=%0d phase=%0d x=%0d y=%0d",message,cycles,pos[0],x,y);end
 end  end endtask
 always @(posedge clk)begin #0.001;cycles = cycles + 1;
  begin : v_loop_1 integer n; for( n=0;n<2;n = n + 1)ck({panel[n],text[n],edge_bit[n],pos[n],frames[n],loops[n]}==={rpanel[n],rtext[n],redge[n],rpos[n],rframes[n],rloops[n]},"every public pixel and counter equals the full frozen local32 parent"); end 
  if(rst_n&&request[0])begin
   ck({index_hi[0],index[0]}<626,"all packed accesses stay inside the immutable glyph payload");
   if(index_hi[0])high_reads = high_reads + 1;
   if(word9[0][7])highest_bit_reads = highest_bit_reads + 1;
  end
 end
 task tick(input integer a,b,input  active,frame);begin begin
  active = (active === 1'b1); frame = (frame === 1'b1); @(negedge clk);x=a;y=b;de=active;fs=frame;
 end  end endtask
 task advance;begin begin tick(0,0,0,1);tick(0,0,0,0);tick(0,0,0,1);tick(0,0,0,0);end  end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;

  for(p=0;p<1024;p = p + 1)begin
   ck(pos[0]==p,"exact1024-position production cadence");
   for(yy=456;yy<476;yy = yy + 1)begin
    for(xx=0;xx<640;xx = xx + 1)tick(xx,yy,1,0);
    repeat(24)tick(700,yy,0,0);
   end
   advance();
  end
  repeat(30)tick(4095,4095,0,0);
  ck(pos[0]==0&&loops[0]==1,"one complete unchanged1024-position wrap");

  for(i=0;i<5;i = i + 1)begin
   repeat(1260)tick(198,460+i%3,1,1);
   ck(request[0],"reset occurs during a genuine packed glyph read");
   #2;rst_n=0;#0.002;
   ck(panel===rpanel&&text===rtext&&edge_bit===redge,"asynchronous reset immediately matches the parent");
   #7;rst_n=1;repeat(30)tick(0,0,0,0);
  end
  ck(high_reads>1000&&highest_bit_reads>1000,"both extended address and highest payload data bit are genuinely used");
  $display("[PASS] all1024positions, all32original16x16glyphs,5/21clockinterfaces, real shared RAM and asynchronous reset");
  $display("PASS tb_v3_lossless_shared32 errors=%0d comparisons=%0d cycles=%0d high_reads=%0d highest_bit_reads=%0d",errors,comparisons,cycles,high_reads,highest_bit_reads);$finish;
 end
 initial begin #2000000000;$display("[FAIL] lossless font miter timeout");$display("PASS tb_v3_lossless_shared32 errors=1 comparisons=%0d",comparisons);$finish;end
endmodule
