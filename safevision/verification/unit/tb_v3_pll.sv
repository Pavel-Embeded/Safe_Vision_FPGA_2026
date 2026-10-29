
`timescale 1ns/1ps
module tb_v3_pll;
 reg refclk=0,reset=1;always #10 refclk=!refclk;
 wire lock,sys,mem,shift;
 sv_v3_memory_pll dut(.refclk(refclk),.reset(reset),.extlock(lock),.clk0_out(sys),.clk1_out(mem),.clk2_out(shift));
 integer errors=0,comparisons=0,i;time a,b,last_mem;
 task check(input bit ok,input string label);begin comparisons++;if(!ok)begin errors++;$display("[FAIL] %s a=%t b=%t",label,a,b);end end endtask
 initial begin
 #100;reset=0;wait(lock===1);repeat(20)@(posedge sys);
 for(i=0;i<100;i++)begin @(posedge sys);a=$time;@(posedge sys);b=$time;check(b-a==10,"SYS100MHz exact period");end
 for(i=0;i<100;i++)begin @(posedge mem);a=$time;@(posedge mem);b=$time;check(b-a==20,"MEM50MHz exact period");end
 for(i=0;i<100;i++)begin @(posedge mem);a=$time;@(posedge shift);b=$time;check(b-a==8,"SDRAM50MHz rising edge +8ns from MEM");end
 check(lock===1,"PLL lock remains asserted under its official behavioral model");
 if(errors!=0)$fatal(1,"PLL clock/phase contract errors=%0d comparisons=%0d",errors,comparisons);
 $display("[PASS] official PLL simulation frequencies and phase");
 $display("PASS tb_v3_pll comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000;$fatal(1,"official PLL did not lock");end
endmodule
