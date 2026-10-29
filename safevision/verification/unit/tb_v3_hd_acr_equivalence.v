`timescale 1ns/1ps
module tb_v3_hd_acr_equivalence;
 reg clk=0,rst=0,sv=0;always #5 clk=~clk;
 wire a,b;wire[19:0]ac,bc,an,bn;integer errors=0,comparisons=0,valids=0,k;reg[31:0]rng=32'h129a0bb7;
 hdmi_acr dut(clk,rst,sv,a,ac,an);hd_acr_reference reference(clk,rst,sv,b,bc,bn);
 always@(posedge clk or negedge rst)begin #1;comparisons = comparisons + 1;
  if({a,ac,an}!=={b,bc,bn})begin errors = errors + 1;if(errors<6)$display("[FAIL] ACR cycle-exact mismatch a=%h b=%h",{a,ac,an},{b,bc,bn});end
  if(a)valids = valids + 1;
 end
 task reset;begin begin @(negedge clk);rst=0;sv=0;repeat(3)@(negedge clk);rst=1;end  end endtask
 initial begin
  reset;
  for(k=0;k<150000;k = k + 1)begin @(negedge clk);rng=rng*1664525+1013904223;sv=rng[0]||rng[5:1]==0;end
  reset;sv=1;@(negedge clk);sv=0;repeat(1048580)@(negedge clk);
  if(dut.clocks!==20'hfffff)begin errors = errors + 1;$display("[FAIL] interval must saturate");end
  repeat(48)begin sv=1;@(negedge clk);end sv=0;
  if(!a||ac!=0)begin errors = errors + 1;$display("[FAIL] saturated plus-one CTS modulo20 retained");end
  reset;
  for(k=0;k<1000;k = k + 1)begin sv=1;@(negedge clk);sv=0;repeat((k%19)+1)@(negedge clk);end
  reset;sv=1;repeat(1000)@(negedge clk);sv=0;
  if(errors==0)$display("[PASS] independent original ACR, all carry boundaries, real saturation interval, resets and random sample spacing");
  $display("[TB] tb_v3_hd_acr_equivalence done errors=%0d comparisons=%0d valids=%0d",errors,comparisons,valids);$finish;
 end
 initial begin #20000000;$display("[FAIL] ACR watchdog");$display("[TB] tb_v3_hd_acr_equivalence done errors=1");$finish;end
endmodule
