`timescale 1ns/1ps
module tb_v3_handbook_energy;
 reg clk=0,rst=0,sv=0;always #5 clk=~clk;reg signed[15:0] l=0,r=0;
 wire[6:0]energy;wire update;audio_energy #(.HANDBOOK_PROFILE(1)) d(clk,rst,sv,l,r,energy,update);
 integer errors=0,comparisons=0,count=0,golden=0,raw,level,delta,k,i,amplitude,blocks=0;reg [63:0]  sum=0;
 reg[31:0]rng=32'h10242618;reg expect_update;
 task ck(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s",msg);end   end endtask
 always@(posedge clk)begin
  expect_update=0;
  if(!rst)begin count=0;sum=0;golden=0;end
  else if(sv)begin
   amplitude=$signed(l);if(amplitude<0)amplitude=-amplitude;sum=sum+amplitude;count = count + 1;
   if(count==1024)begin
    raw=(sum*100)/33554432;level=raw+raw/2;if(level>100)level=100;
    if(level>=golden)golden=level;else begin delta=(golden-level)/8;if(delta<1)delta=1;golden=golden-delta;end
    count=0;sum=0;expect_update=1;blocks = blocks + 1;
   end
  end
  #0.001;if(rst)begin ck(update===expect_update,"exact1024 accepted sample window");ck(energy===golden,"independent integer left-channel/gain/attack/release reference");end
 end
 task block(input integer magnitude);
  begin  for(i=0;i<1024;i = i + 1)begin
   @(negedge clk);rng=rng*1664525+1013904223;
   sv=0;r=rng[31:16];repeat(rng[1:0])@(negedge clk);
   sv=1;l=(i%2==0) ? -magnitude:magnitude;
  end @(negedge clk);sv=0;
  end endtask
 initial begin repeat(4)@(negedge clk);rst=1;
  block(0);ck(energy==0,"manual silence=0");
  block(8192);ck(energy==37,"manual quarter-scale=37");
  block(16384);ck(energy==75,"manual half-scale=75");
  block(32768);ck(energy==100,"manual negative full-scale=100");
  block(0);ck(energy==88,"manual first release100->88");
  repeat(60)block(0);ck(energy==0,"finite release to true zero");
  for(k=0;k<40;k = k + 1)block((k*7919)%32768);
  if(errors==0)$display("[PASS] manual amplitude cases,1024 valid samples, random stalls/right channel, floor release and finite silence");
  $display("[TB] tb_v3_handbook_energy done errors=%0d comparisons=%0d windows=%0d",errors,comparisons,blocks);$finish;
 end
endmodule
