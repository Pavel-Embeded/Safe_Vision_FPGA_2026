`timescale 1ns/1ps
module tb_v3_shape_factor;
 reg[15:0] width=1,height=1;reg top_down=0;
 v3_bmp_normalizer #(.FLEX_PIXELS(1)) flex(.clk(1'b0),.rst_n(1'b0),.din(8'd0),.din_valid(1'b0),.din_sof(1'b0),.din_eof(1'b0),.width(width),.height(height),.top_down(top_down),.pixel_ready(1'b1),.bpp(8'd24));
 v3_bmp_normalizer #(.FLEX_PIXELS(0)) legacy(.clk(1'b0),.rst_n(1'b0),.din(8'd0),.din_valid(1'b0),.din_sof(1'b0),.din_eof(1'b0),.width(width),.height(height),.top_down(top_down),.pixel_ready(1'b1),.bpp(8'd24));
 integer errors=0,comparisons=0,w,h,k,sgn,boundary;integer equal_cases=0,wide_cases=0,tall_cases=0;
 task check_size(input integer iw,ih);reg expected;begin
  if(ih>=1&&ih<=16384)begin
   width=iw;height=top_down?-ih:ih;#1;
   expected=iw*480>=ih*640;
   comparisons++;
   if(flex.shape_wide!==expected||flex.abs_height!==ih||flex.shape_width3!==iw*3)begin errors++;if(errors<10)$display("[FAIL] factor/bits/orientation w=%0d h=%0d td=%0d",iw,ih,top_down);end
   if(iw<=1920&&ih<=1080)begin comparisons++;if(legacy.shape_wide!==expected)begin errors++;if(errors<10)$display("[FAIL] legacy13-bit factor w=%0d h=%0d",iw,ih);end end
   if(iw*480==ih*640)equal_cases++;else if(expected)wide_cases++;else tall_cases++;
  end
 end endtask
 initial begin
  for(sgn=0;sgn<2;sgn++)begin
   top_down=sgn;
   for(w=1;w<=16384;w++)begin
    boundary=w*3/4;
    check_size(w,1);check_size(w,16384);
    check_size(w,boundary-1);check_size(w,boundary);check_size(w,boundary+1);check_size(w,boundary+2);
    for(k=0;k<=14;k++)begin check_size(w,(1<<k)-1);check_size(w,1<<k);check_size(w,(1<<k)+1);end
   end
   for(h=1;h<=16384;h++)begin check_size(1,h);check_size(16384,h);end
  end
  if(equal_cases<8000||wide_cases<100000||tall_cases<100000)begin errors++;$display("[FAIL] insufficient comparison-boundary coverage");end
  $display("[PASS] every accepted dimension, both BMP orientations, exact4:3 boundaries, binary carries and upper limit16384");
  $display("PASS tb_v3_shape_factor errors=%0d comparisons=%0d equal=%0d wide=%0d tall=%0d",errors,comparisons,equal_cases,wide_cases,tall_cases);$finish;
 end
endmodule
