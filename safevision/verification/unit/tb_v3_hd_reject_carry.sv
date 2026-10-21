`timescale 1ns/1ps
module tb_v3_hd_reject_carry;
 reg[15:0]a=0,b=0;reg[31:0]rng=32'h918356;integer k,j,errors=0,comparisons=0;
 v3_supervisor dut(.clk(1'b0),.rst_n(1'b0),.rejected_files(a));
 task check;begin #1;comparisons++;if(dut.rejected_rise!==(a>b))begin errors++;if(errors<7)$display("[FAIL] unsigned reject A=%h B=%h",a,b);end end endtask
 initial begin
  force dut.rejected_old=b;
  for(k=0;k<65536;k++)begin
   a=k;b=0;check;b=16'hffff;check;b=a;check;b=a-1'b1;check;b=a+1'b1;check;b=a^16'h8000;check;b=a^16'h0100;check;b=a^16'h0001;check;
  end
  for(k=0;k<262144;k++)begin rng=rng*1664525+1013904223;a=rng[31:16];rng=rng*1664525+1013904223;b=rng[15:0];check;end
  if(errors==0)$display("[PASS] all65536 counts across8 independent boundary pairs plus262144 random pairs;unsigned full-width relation exact");
  $display("[TB] tb_v3_hd_reject_carry done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
