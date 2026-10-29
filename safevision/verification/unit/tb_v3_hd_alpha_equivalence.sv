`timescale 1ns/1ps
module tb_v3_hd_alpha_equivalence;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0;reg[15:0] front=0,back=0;reg[7:0] alpha=0;
 wire[15:0] pixel,gold;wire vo,gv;
 alpha_blend dut(.clk(clk),.rst_n(rst),.valid_in(valid),.front(front),.back(back),.alpha(alpha),.pixel(pixel),.valid_out(vo));
 v3_hd_alpha_reference reference(.clk(clk),.rst_n(rst),.valid_in(valid),.front(front),.back(back),.alpha(alpha),.pixel(gold),.valid_out(gv));
 integer errors=0,comparisons=0,math_checks=0,f,b,a,i,j;
 reg[15:0] e0=0,e1=0,e2=0;reg v0=0,v1=0,v2=0;reg[31:0] lfsr=32'h61a973e5;
 function[15:0] independent_pixel;input[15:0] fg,bg;input[7:0] al;integer r,g,bl;begin
  r=(((fg>>11)&31)*al+((bg>>11)&31)*(255-al)+127)/255;
  g=(((fg>>5)&63)*al+((bg>>5)&63)*(255-al)+127)/255;
  bl=((fg&31)*al+(bg&31)*(255-al)+127)/255;
  independent_pixel={r[4:0],g[5:0],bl[4:0]};
 end endfunction
 always@(posedge clk or negedge rst)begin
  if(!rst)begin e0=0;e1=0;e2=0;v0=0;v1=0;v2=0;end
  else begin
   e2=e1;e1=e0;e0=independent_pixel(front,back,alpha);v2=v1;v1=v0;v0=valid;
   #1;comparisons=comparisons+1;
   if({pixel,vo}!=={gold,gv})begin errors=errors+1;if(errors<9)$display("[FAIL] public blend mismatch cycle=%0d",comparisons);end
   if(vo!==v2)begin errors=errors+1;if(errors<9)$display("[FAIL] three-cycle valid latency");end
   if(v2)begin math_checks=math_checks+1;if(pixel!==e2)begin errors=errors+1;if(errors<9)$display("[FAIL] independent full precision math");end end
  end
 end
 task random_cycle;begin
  lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
  front=lfsr[15:0];back=lfsr[31:16];alpha=lfsr[11:4];valid=lfsr[2];@(negedge clk);
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;


  for(f=0;f<64;f=f+1)for(b=0;b<64;b=b+1)for(a=0;a<256;a=a+1)begin
   front={f[4:0],f[5:0],(f[4:0]^5'h15)};
   back={b[4:0],b[5:0],(b[4:0]^5'h0a)};alpha=a;valid=1;@(negedge clk);
  end
  valid=0;repeat(5)@(negedge clk);
  for(i=0;i<24;i=i+1)begin
   for(j=0;j<512;j=j+1)random_cycle;
   #2;rst=0;#1;if(pixel!==0||vo!==0)begin errors=errors+1;$display("[FAIL] asynchronous reset");end
   @(negedge clk);#1;rst=1;@(negedge clk);
  end
  valid=0;repeat(6)@(negedge clk);
  if(errors==0)$display("[PASS] exhaustive RGB565 endpoints/intermediates, exact integer rounding, invalid cycles,24 asynchronous resets and latency3");
  $display("PASS tb_v3_hd_alpha_equivalence errors=%0d comparisons=%0d math_checks=%0d",errors,comparisons,math_checks);$finish;
 end
 initial begin #30000000;$display("[FAIL] global timeout");$finish;end
endmodule
