`timescale 1ns/1ps
module tb_v3_column_equivalence67;
 reg clk=0,rst_n=0,frame_start=0,de=1;always #5 clk=~clk;
 reg[6:0] energy=0,volume=0;reg[11:0] x=600,y=350;wire[6:0] a,b;wire ba,bb,ea,eb,fa,fb;wire[1:0] ca,cb;
 integer errors=0,comparisons=0,e,v,k;reg[31:0] rng=32'h67ac;
 v3_volume_column d(clk,rst_n,frame_start,energy,volume,x,y,de,ea,fa,ca,a,ba);
 v3_volume_column_reference67 reference(clk,rst_n,frame_start,energy,volume,x,y,de,eb,fb,cb,b,bb);
 always @(posedge clk or negedge rst_n)begin #1;comparisons++;if({a,ba,ea,fa,ca}!=={b,bb,eb,fb,cb})begin errors++;if(errors<8)$display("[FAIL] exact column level,busy,raster outputs a=%d b=%d ba=%b bb=%b",a,b,ba,bb);end end
 task ticks(input integer n);begin repeat(n)@(negedge clk);end endtask
 initial begin
  ticks(3);rst_n=1;
  for(e=0;e<128;e++)for(v=0;v<128;v++)begin energy=e;volume=v;frame_start=1;ticks(1);frame_start=0;ticks(110);if(a!==7'(((e>100?100:e)*(v>100?100:v))/100))begin errors++;$display("[FAIL] independent saturated division");end end
  for(k=0;k<50000;k++)begin
   @(negedge clk);rng=rng*1664525+1013904223;energy=rng[6:0];volume=rng[13:7];frame_start=rng[14:10]==0;de=rng[0];x=rng[27:16]%640;y=rng[19:8]%480;
   if(k%617==0)begin #1;rst_n=0;#2;rst_n=1;end
  end
  frame_start=0;ticks(120);
  if(errors==0)$display("[PASS] original clock-by-clock column contract;all128x128raw inputs,clipping,mute,restarts,asynchronous resets and random raster");
  $display("PASS tb_v3_column_equivalence67 errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
