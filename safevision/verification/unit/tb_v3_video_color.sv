`timescale 1ns/1ps
module tb_v3_video_color;
 reg clk=0,rst=0,valid=0;always #5 clk=~clk;
 reg[15:0] input_pixel=0;reg signed[8:0] brightness=0;reg[7:0] contrast=0;
 wire[15:0] pixel;wire output_valid;
 color_adjust dut(clk,rst,valid,input_pixel,brightness,contrast,pixel,output_valid);
 function integer channel(input integer expanded,bright,gain);
  integer numerator;begin
   numerator=(expanded-128)*gain+(bright+128)*128;
   // Clamp the signed numerator before division; this is independent of the
   // DUT's arithmetic-shift width and signed-expression context.
   channel=numerator<0?0:numerator>=255*128?255:numerator/128;
  end
 endfunction
 function[15:0] reference(input[15:0] p,input integer bright,gain);
  integer r,g,b;begin
   r=channel((p[15:11]*8)+(p[15:11]/4),bright,gain);
   g=channel((p[10:5]*4)+(p[10:5]/16),bright,gain);
   b=channel((p[4:0]*8)+(p[4:0]/4),bright,gain);
   reference={5'(r/8),6'(g/4),5'(b/8)};
  end
 endfunction
 reg[15:0] expected0=0,expected1=0;reg[1:0] expected_valid=0;
 integer errors=0,comparisons=0,bright,gain,value;
 always @(posedge clk)begin
  if(!rst)begin expected0=0;expected1=0;expected_valid=0;end
  else begin
   expected1=expected0;expected0=reference(input_pixel,$signed(brightness),contrast);
   expected_valid={expected_valid[0],valid};#1;
   if(pixel!==expected1||output_valid!==expected_valid[1])begin
    if(errors<5)$display("[FAIL] color bright=%0d contrast=%0d input=%h expected=%h output=%h",$signed(brightness),contrast,input_pixel,expected1,pixel);
    errors=errors+1;
   end
   comparisons=comparisons+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  // Every legal channel value at every contrast and signed brightness value.
  // The arithmetic is separable, so red/blue enumerate all32 values twice
  // while green enumerates all64; cross-channel coupling is not assumed.
  for(bright=-256;bright<256;bright=bright+1)
   for(gain=0;gain<256;gain=gain+1)for(value=0;value<64;value=value+1)begin
    brightness=bright;contrast=gain;valid=value%5!=1;
    input_pixel={5'(value+bright),6'(value),5'(value*17+gain)};
    @(negedge clk);
   end
  repeat(3)@(negedge clk);
  if(!errors)$display("[PASS] complete signed brightness/contrast/channel Cartesian domain, clipping, RGB565 expansion, valid bubbles and two-clock latency");
  $display("[TB] tb_v3_video_color done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #200000000;$display("[FAIL] color test timeout errors=1");$finish;end
endmodule
