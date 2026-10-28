`timescale 1ns/1ps
module tb_v3_geometry_stages;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,sof=0,td=0;reg[15:0] width=1,height=1;
 v3_bmp_normalizer #(.FLEX_PIXELS(1)) dut(.clk(clk),.rst_n(rst),.din(8'h5a),.din_valid(valid),.din_sof(sof),.din_eof(1'b0),.width(width),.height(height),.top_down(td),.pixel_ready(1'b1),.bpp(8'd24));
 integer errors=0,comparisons=0,w,h,sgn,boundary,vectors=0;
 task ck(input bit okay,input string message);begin comparisons++;if(!okay)begin errors++;if(errors<12)$display("[FAIL] %s w=%0d h=%0d s=%0d",message,w,h,sgn);end end endtask
 task size(input integer iw,ih,input bit orientation);reg wide;integer numerator,divisor;begin
  if(ih>=1&&ih<=16384)begin
   vectors++;wide=iw*480>=ih*640;numerator=wide?ih*640:iw*480;divisor=wide?iw:ih;
   @(negedge clk);rst=0;valid=0;sof=0;width=iw;height=orientation?-ih:ih;td=orientation;
   @(negedge clk);rst=1;valid=1;sof=1;
   @(posedge clk);#0.001;
   ck(dut.state==dut.GEOM&&dut.initial_y,"SOF arms the geometry setup phase");
   ck(dut.w==iw&&dut.h==ih&&dut.orientation==orientation,"both sizes and orientation are captured atomically");
   @(negedge clk);valid=0;sof=0;width=16'h7fff;height=16'h8000;td=~orientation;
   @(posedge clk);#0.001;
   ck(dut.state==dut.GEOM_DECIDE&&dut.wide===wide,"decision uses captured sizes after live inputs change");
   @(posedge clk);#0.001;
   ck(dut.state==dut.GEOM&&!dut.initial_y,"the second added edge enters the original divider");
   ck(dut.geometry_scratch==numerator&&dut.geometry_divisor==divisor,"full original numerator and divisor survive the split");
   ck(dut.store_x==0&&!dut.pixel_valid&&!dut.error,"setup emits no pixels and starts the quotient at zero");
  end
 end endtask
 initial begin
  repeat(3)@(negedge clk);
  for(sgn=0;sgn<2;sgn++)begin
   for(w=1;w<=16384;w++)begin
    boundary=w*3/4;size(w,1,sgn);size(w,16384,sgn);size(w,boundary,sgn);size(w,boundary+1,sgn);
   end
   for(h=1;h<=16384;h++)begin size(1,h,sgn);size(16384,h,sgn);end
  end
  ck(vectors>190000,"all valid dimensions and exact-aspect boundaries receive both orientations");
  $display("[PASS] captured metadata, deliberate live-input changes, two-edge latency and exact DDA initialization");
  $display("PASS tb_v3_geometry_stages errors=%0d comparisons=%0d vectors=%0d",errors,comparisons,vectors);$finish;
 end
endmodule
