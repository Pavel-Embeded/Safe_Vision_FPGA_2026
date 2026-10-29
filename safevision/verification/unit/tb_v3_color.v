`timescale 1ns/1ps
module tb_v3_color;
 reg clk=0;always #5 clk=~clk;reg rst=0,v=0;reg[15:0] p=0;reg[7:0] c=128;reg signed[8:0] b=0;
 wire[15:0] out;wire vo;color_adjust dut(clk,rst,v,p,b,c,out,vo);
 integer errors=0,comparisons=0,i,seed=321,j;
 reg[15:0] reference,delayed;reg delayed_valid=0;
 function[7:0] channel;input integer value,contrast,brightness;integer z;
 begin begin z=((value-128)*contrast+128*128+brightness*128);if(z<0)z=0;else z=z/128;
 if(z>255)z=255;channel=z;end  end endfunction
 function[15:0] model;input[15:0] pix;input integer con,bright;reg[7:0] r,g,bb;
 begin begin r=channel((pix[15:11]<<3)|(pix[15:11]>>2),con,bright);
 g=channel((pix[10:5]<<2)|(pix[10:5]>>4),con,bright);
 bb=channel((pix[4:0]<<3)|(pix[4:0]>>2),con,bright);model={r[7:3],g[7:2],bb[7:3]};end  end endfunction
 always @(posedge clk)begin
  reference=model(p,c,$signed(b));
  #1;if(vo)begin comparisons=comparisons+1;if(out!==delayed || !delayed_valid)begin
   errors=errors+1;if(errors<6)$display("[FAIL] color actual=%h reference=%h",out,delayed);end end
  if(rst)begin delayed=reference;delayed_valid=v;end
 end
 initial begin repeat(4)@(negedge clk);rst=1;v=1;
 for(i=0;i<65536;i=i+1)begin p=i;c=128;b=0;@(negedge clk);end
 for(i=0;i<32768;i=i+1)begin p=$random(seed);c=$random(seed);j=$random(seed);b=j[7:0]-128;@(negedge clk);end
 v=0;repeat(3)@(negedge clk);
 if(errors==0 && comparisons==98304)$display("[PASS] exhaustive identity, signed contrast and saturation");
 else if(comparisons!=98304)begin errors=errors+1;$display("[FAIL] missing comparisons %0d",comparisons);end
 $display("PASS tb_v3_color errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #1100000;$display("[FAIL] global timeout");$finish;end
endmodule
