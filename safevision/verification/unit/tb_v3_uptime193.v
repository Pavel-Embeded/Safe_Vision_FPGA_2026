`timescale 1ns/1ps
module tb_v3_uptime193;
 reg clk=0;always #5 clk=~clk;wire[31:0] seconds,bcd;integer errors=0,comparisons=0,n,k,want,t;
 v3_boot_uptime #(.CLK_HZ(7)) dut(clk,seconds,bcd);
 initial begin
  #1;if(seconds!==0||bcd!==0)errors = errors + 1;
  for(n=1;n<=71000;n = n + 1)begin @(posedge clk);#1;want=n/7;t=want;comparisons = comparisons + 1;
   if(seconds!==want)begin errors = errors + 1;if(errors<5)$display("[FAIL] tick %0d sec=%0d/%0d",n,seconds,want);end
   for(k=0;k<8;k = k + 1)begin comparisons = comparisons + 1;if(bcd[k*4+:4]!==v_cast_s4(t%10))errors = errors + 1;t=t/10;end
  end

  @(negedge clk);dut.seconds=99999998;dut.bcd=32'h99999998;dut.ticks=0;
  repeat(21)@(posedge clk);#1;comparisons = comparisons + 1;if(seconds!==99999999||bcd!==32'h99999999)errors = errors + 1;
  if(!errors)$display("[PASS] exact seven-clock seconds,all decimal carries through10142s,no reset input,saturation");
  $display("[TB] tb_v3_uptime193 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] uptime watchdog errors=1");$finish;end

function signed [3:0] v_cast_s4; input signed [3:0] value; begin begin v_cast_s4=value; end  end endfunction
endmodule
