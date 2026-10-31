`timescale 1ns/1ps
module compositor_case #(parameter N=1,O=4,E=0)(output reg done);
 initial begin done = 0; end

 localparam M=(N>O ? (N>E ? N:E):(O>E ? O:E));
 reg clk=0,rst=0;always #3 clk=~clk;
 reg [34:0] raw=0,hist[0:31];integer i,seq=0,checks=0;
 wire [34:0] ns=N==0 ? raw:hist[N-1],os=O==0 ? raw:hist[O-1],es=E==0 ? raw:hist[E-1];
 wire [23:0] rgb;wire [11:0] x,y;wire hs,vs,de,ls,fs,afs,hb,vb,pv;wire [1:0] layer;
 video_compositor #(.NORMAL_LATENCY(N),.OSD_LATENCY(O),.EMERGENCY_LATENCY(E),.SAFE_COLOR(24'haabbcc)) dut(
 .clk(clk),.rst_n(rst),.normal_rgb({ns[34:11]}^24'h112233),.osd_rgb({os[34:11]}^24'h445566),.emergency_rgb({es[34:11]}^24'h778899),
 .normal_valid(ns[2]),.osd_valid(os[1]),.emergency_valid(es[0]),
 .x_in(raw[34:23]),.y_in(raw[22:11]),.hsync_in(raw[10]),.vsync_in(raw[9]),.de_in(raw[8]),.line_start_in(raw[7]),.frame_start_in(raw[6]),.active_frame_start_in(raw[5]),.hblank_in(raw[4]),.vblank_in(raw[3]),
 .rgb_out(rgb),.x_out(x),.y_out(y),.hsync_out(hs),.vsync_out(vs),.de_out(de),.pixel_valid_out(pv),.line_start_out(ls),.frame_start_out(fs),.active_frame_start_out(afs),.hblank_out(hb),.vblank_out(vb),.selected_layer(layer));
 reg [34:0] want;reg [23:0] wrgb;reg [1:0] wl;reg wv;
 always @(posedge clk)begin
  if(!rst)begin for(i=0;i<32;i=i+1)hist[i]<=35'h618;end
  else begin
   want=M==0 ? raw:hist[M-1];
   for(i=31;i>0;i=i-1)hist[i]<=hist[i-1];hist[0]<=raw;
   wl=want[0] ? 3:want[1] ? 2:want[2] ? 1:0;
   wrgb=wl==3 ? (want[34:11]^24'h778899):wl==2 ? (want[34:11]^24'h445566):wl==1 ? (want[34:11]^24'h112233):24'haabbcc;
   wv=want[8]&&(|want[2:0]);if(!want[8])begin wrgb=0;wl=0;end
   #0.1;
   if({x,y,hs,vs,de,ls,fs,afs,hb,vb}!==want[34:3]||rgb!==wrgb||pv!==wv||layer!==wl)
      begin $display("[FAIL] compositor N/O/E=%0d/%0d/%0d seq=%0d tags=%h/%h rgb=%h/%h layer=%0d/%0d",N,O,E,seq,{x,y,hs,vs,de,ls,fs,afs,hb,vb},want[34:3],rgb,wrgb,layer,wl); $finish; end
   checks=checks+1;
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(seq=0;seq<2000;seq=seq+1)begin @(negedge clk);raw={v_cast_s12(seq),v_cast_s12(seq*7),v_cast_s8(seq),v_cast_s3(seq)};end
  rst=0;repeat(5)@(negedge clk);raw=0;rst=1;
  for(seq=0;seq<1000;seq=seq+1)begin @(negedge clk);raw={v_cast_s12(seq+2048),v_cast_s12(seq*13),v_cast_s8(seq*3),v_cast_s3(seq)};end
  done=1;$display("compositor N/O/E=%0d/%0d/%0d checks=%0d",N,O,E,checks);
 end

function signed [2:0] v_cast_s3; input signed [2:0] value; begin  v_cast_s3=value;   end endfunction
function signed [7:0] v_cast_s8; input signed [7:0] value; begin  v_cast_s8=value;   end endfunction
function signed [11:0] v_cast_s12; input signed [11:0] value; begin  v_cast_s12=value;   end endfunction
endmodule
module tb_video_compositor;
 wire a,b,c;
 compositor_case c0(a);compositor_case #(.N(0),.O(0),.E(0)) c1(b);compositor_case #(.N(4),.O(1),.E(2)) c2(c);
 initial begin wait(a&&b&&c);$display("PASS tb_video_compositor: three latency configurations, all layer priorities, tag alignment, reset");$finish;end
 initial begin #50000;begin $display("[FAIL] compositor timeout"); $finish; end end
endmodule
