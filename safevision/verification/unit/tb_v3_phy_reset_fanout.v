`timescale 1ns/1ps
module tb_v3_phy_reset_fanout;
 reg clk=0,enabled=1,ar=0;always #1.348 if(enabled)clk=~clk;
 wire reference;wire[3:0] actual;integer i,errors=0,comparisons=0;
 reset_sync old(.clk(clk),.async_rst_n(ar),.rst_n(reference));
 v3_phy_reset_fanout dut(.clk(clk),.async_rst_n(ar),.lane_rst_n(actual));
 task check(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons=comparisons+1;if(!ok)begin errors=errors+1;if(errors<10)$display("[FAIL] %s trial=%0d",msg,i);end   end endtask
 initial begin
  for(i=0;i<100;i=i+1)begin
   ar=0;#0.001;check(actual===4'd0 && reference===0,"all lanes asynchronously assert");
   #((i%7)+0.123);ar=1;
   @(posedge clk);#0.001;check(actual==={4{reference}} && actual===0,"first common sample cannot release");
   @(posedge clk);#0.001;check(actual==={4{reference}} && actual===4'hf,"all copies release on original second edge");
   @(negedge clk);#0.001;check(actual==={4{reference}},"four copies remain aligned");
  end
  enabled=0;ar=0;#0.001;check(actual===0,"stopped clock still asserts reset");ar=1;#10;check(actual===0,"no clock cannot release");enabled=1;
  repeat(3)@(posedge clk);#0.001;check(actual===4'hf && reference===1,"clock restart releases normally");
  if(errors==0)$display("[PASS] common first stage and four same-cycle reset releases");
  $display("[TB] tb_v3_phy_reset_fanout done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #100000;$display("[FAIL] reset fanout watchdog errors=1");$finish;end
endmodule
