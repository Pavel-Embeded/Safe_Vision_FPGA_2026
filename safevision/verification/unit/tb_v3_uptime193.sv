`timescale 1ns/1ps
module tb_v3_uptime193;
 reg clk=0;always #5 clk=~clk;wire[31:0] seconds,bcd;integer errors=0,comparisons=0,n,k,want,t;
 v3_boot_uptime #(.CLK_HZ(7)) dut(clk,seconds,bcd);
 initial begin
  #1;if(seconds!==0||bcd!==0)errors++;
  for(n=1;n<=71000;n++)begin @(posedge clk);#1;want=n/7;t=want;comparisons++;
   if(seconds!==want)begin errors++;if(errors<5)$display("[FAIL] tick %0d sec=%0d/%0d",n,seconds,want);end
   for(k=0;k<8;k++)begin comparisons++;if(bcd[k*4+:4]!==4'(t%10))errors++;t=t/10;end
  end
  // Configuration saturation; not reachable through any warm/media reset.
  @(negedge clk);dut.seconds=99999998;dut.bcd=32'h99999998;dut.ticks=0;
  repeat(21)@(posedge clk);#1;comparisons++;if(seconds!==99999999||bcd!==32'h99999999)errors++;
  if(!errors)$display("[PASS] exact seven-clock seconds,all decimal carries through10142s,no reset input,saturation");
  $display("[TB] tb_v3_uptime193 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] uptime watchdog errors=1");$finish;end
endmodule
