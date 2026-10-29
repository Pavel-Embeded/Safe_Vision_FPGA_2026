`timescale 1ns/1ps
module tb_v3_tone_rom;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,enable=0,tick=0;
 wire[23:0] l,r;reg[23:0] oracle[0:65535];integer i,errors=0,comparisons=0;
 alarm_tone_gen #(.PHASE_INC(1)) d(.audio_clk(clk),.rst_n(rst_n),.enable(enable),.tick(tick),.tone_l(l),.tone_r(r));
 task ck;input c;input[511:0] why;begin begin
  comparisons=comparisons+1;if(!c)begin errors=errors+1;if(errors<=3)$display("[FAIL TONE_ROM] %0s phase=%0d got=%h/%h",why,i,l,r);end
 end  end endtask
 initial begin
  $readmemh("tone_oracle.mem",oracle);repeat(4)@(negedge clk);rst_n=1;enable=1;tick=1;
  for(i=1;i<=65536;i=i+1)begin @(negedge clk);ck(l===oracle[i%65536],"independent sine/quad left");ck(r===oracle[i%65536],"independent sine/quad right");end
  tick=0;repeat(5)begin @(negedge clk);ck(l==0&&r==0,"clock enable holds phase");end
  tick=1;repeat(997)@(negedge clk);rst_n=0;#0.001;ck(l==0&&r==0,"asynchronous reset clears sine phase");
  repeat(3)@(negedge clk);rst_n=1;enable=0;repeat(3)@(negedge clk);ck(l==0&&r==0,"disabled tone returns phase0");
  if(!errors)$display("[PASS] all65536 phases against independent math sine/quadrant oracle, both stereo outputs and reset");
  $display("PASS tb_v3_tone_rom errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL TONE_ROM] watchdog errors=1");$finish;end
endmodule
