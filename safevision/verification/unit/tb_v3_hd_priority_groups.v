`timescale 1ns/1ps
module tb_v3_hd_priority_groups;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[10:0] stimulus=0,expected;integer i,k,errors=0,comparisons=0;
 v3_supervisor a(.clk(clk),.rst_n(rst));
 task check(input  ok,input [4095:0] message);begin begin
  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<8)$display("[FAIL] %s pending=%h expected=%h",message,stimulus,expected);end
 end  end endtask
 initial begin


  force a.pending=stimulus;force a.selection=11'd0;force a.new_events=11'd0;
  #12;rst=1;
  for(i=0;i<2048;i = i + 1)begin
   @(negedge clk);stimulus=i;expected=0;
   for(k=10;k>=0;k = k - 1)if(stimulus[k])expected=11'd1<<k;
   #1;check(a.priority_next===expected,"lowest occupied event has unique same-cycle grant");
   @(posedge clk);#1;
   check(a.priority_q===expected,"grant register updates on current edge");
   check(a.priority_ts==={4{expected}},"all four timestamp byte selectors use same edge");
  end
  if(errors==0)$display("[PASS] all2048 masks have exact mathematical priority and6144 same-edge grant/timestamp checks");
  $display("[TB] tb_v3_hd_priority_groups done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #100000;errors = errors + 1;$display("[FAIL] bounded priority sweep timeout");$display("[TB] tb_v3_hd_priority_groups done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
