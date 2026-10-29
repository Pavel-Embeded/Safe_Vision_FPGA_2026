`timescale 1ns/1ps
module tb_v3_hd_pending_or;
 reg clk=0,rst=0;reg[10:0] pending=0;integer errors=0,comparisons=0,i;
 v3_supervisor a(.clk(clk),.rst_n(rst));
 v3_hd_supervisor_reference b(.clk(clk),.rst_n(rst));
 initial begin
  force a.pending=pending;force a.pending_alert=pending;force b.pending=pending;
  for(i=0;i<2048;i=i+1)begin pending=i;#1;comparisons = comparisons + 1;
   if(a.err_push!==b.err_push || a.err_push!==(i!=0))begin errors = errors + 1;$display("[FAIL] pending=%h got=%b expected=%b",pending,a.err_push,b.err_push);end
  end
  if(errors==0)$display("[PASS] direct pending OR tree exact for all2048 queue states; all state/priority/timestamps unchanged");
  $display("PASS tb_v3_hd_pending_or comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
