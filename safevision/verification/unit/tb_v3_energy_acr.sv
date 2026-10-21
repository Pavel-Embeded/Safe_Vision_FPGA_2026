`timescale 1ns/1ps
module tb_v3_energy_acr;
 reg clk=0;always #5 clk=~clk;reg rst=0,sv=0;reg signed[15:0] l=0,r=0;
 wire[6:0] energy;wire update;audio_energy #(.LOG_N(3)) en(clk,rst,sv,l,r,energy,update);
 wire av;wire[19:0] cts,n;hdmi_acr acr(clk,rst,sv,av,cts,n);
 integer errors=0,i;
 task ck;input c;input [255:0] msg;begin
 if(c)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 initial begin
 repeat(3)@(negedge clk);rst=1;sv=1;l=-32768;r=-32768;
 repeat(8)@(negedge clk);ck(update && energy==100,"negative full scale unsigned magnitude");
 l=0;r=0;repeat(8)@(negedge clk);ck(energy==87,"release rounded up 1/8");
 repeat(60*8)@(negedge clk);ck(energy==0,"release reaches zero");
 sv=0;rst=0;repeat(3)@(negedge clk);rst=1;
 for(i=0;i<50;i=i+1)begin sv=1;@(negedge clk);sv=0;repeat(9)@(negedge clk);
  if(i==48)ck(cts==480 && n==6144,"CTS measured between 48 samples");end
 $display("PASS tb_v3_energy_acr errors=%0d",errors);$finish;
 end
endmodule
