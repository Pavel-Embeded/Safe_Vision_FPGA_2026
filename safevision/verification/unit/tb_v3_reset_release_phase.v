`timescale 1ns/1ps
module tb_v3_reset_release_phase;
 reg clk=0;always #10 clk=~clk;
 reg ar=0;wire rising,falling,falling3;
 integer errors=0,comparisons=0,i,k;
 reset_sync r0(clk,ar,rising);
 reset_sync #(.RELEASE_FALLING(1)) r1(clk,ar,falling);
 reset_sync #(.STAGES(3),.RELEASE_FALLING(1)) r2(clk,ar,falling3);
 task check(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons=comparisons+1;
  if(!ok)begin errors=errors+1;$display("[FAIL] %s trial=%0d",msg,i);end   end endtask
 initial begin
  for(i=0;i<100;i=i+1)begin
   ar=0;#0.001;check({rising,falling,falling3}===3'b000,"asynchronous assertion at arbitrary phase");
   #((i%19)+1);ar=1;
   @(posedge clk);#0.001;check({rising,falling,falling3}===3'b000,"first local sample cannot release");
   @(negedge clk);#0.001;check({rising,falling,falling3}===3'b000,"first falling edge cannot release");
   @(posedge clk);#0.001;check({rising,falling,falling3}===3'b100,"default exact second-edge contract");
   @(negedge clk);#0.001;check({rising,falling,falling3}===3'b110,"two samples plus falling phase");
   @(posedge clk);#0.001;check({rising,falling,falling3}===3'b110,"three-sample phase retains reset until falling");
   @(negedge clk);#0.001;check({rising,falling,falling3}===3'b111,"three samples plus falling phase");
   #((i%7)+0.25);
  end
  if(errors==0)$display("[PASS] default reset contract and phase-safe optional release,100 asynchronous epochs");
  $display("[TB] tb_v3_reset_release_phase done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #100000;$display("[FAIL] reset release watchdog errors=1");$finish;end
endmodule
