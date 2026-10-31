`timescale 1ns/1ps
module tb_v3_response_timer;
 reg clk=0,rst=0,start=0,finish=0,cancel=0;always #5 clk=~clk;wire[15:0] latency;
 v3_response_timer #(.CLK_HZ(10000)) dut(clk,rst,start,finish,cancel,latency);
 integer errors=0,comparisons=0,k,n;
 task ck(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s",msg);end   end endtask
 task launch;begin  @(negedge clk);start=1;@(negedge clk);start=0;  end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;
  for(k=0;k<40;k = k + 1)begin launch();repeat(k)@(negedge clk);finish=1;@(negedge clk);finish=0;ck(latency==(k+1)/10,"millisecond boundary rounding");end
  launch();repeat(700000)@(negedge clk);finish=1;@(negedge clk);finish=0;ck(latency==65535,"16-bit saturation without wrap");
  launch();repeat(100)@(negedge clk);cancel=1;finish=1;@(negedge clk);cancel=0;finish=0;ck(latency==65535,"cancel never publishes success");
  launch();repeat(11)@(negedge clk);finish=1;@(negedge clk);finish=0;ck(latency==1,"new start after cancelled generation");
  if(errors==0)$display("[PASS] measured response timer, boundary rounding, saturation and cancellation");
  $display("[TB] tb_v3_response_timer done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
