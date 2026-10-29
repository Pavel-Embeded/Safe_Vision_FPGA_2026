`timescale 1ns/1ps
module tb_v3_volume_dsp_equivalence;
 reg clk=0,rst=0,valid=0;always #5 clk=~clk;
 reg[23:0]l=0,r=0;reg[6:0]v=0;
 wire[49:0]a,b;
 v3_audio_volume dut(clk,rst,valid,l,r,v,a[0],a[24:1],a[48:25],a[49]);
 v3_audio_volume_reference ref_volume(clk,rst,valid,l,r,v,b[0],b[24:1],b[48:25],b[49]);
 integer errors=0,comparisons=0,k,g,phase;reg[31:0]seed=32'h9f5a2618;
 always @(posedge clk)begin #1;comparisons = comparisons + 1;if(a!==b)begin errors = errors + 1;if(errors<8)$display("[FAIL] public cycle mismatch gain=%0d phase=%0d a=%h b=%h",g,phase,a,b);end end
 task pair(input[23:0]il,ir,input integer gain);begin begin
  @(negedge clk);l=il;r=ir;v=gain;valid=1;@(negedge clk);valid=0;
  for(phase=0;phase<77;phase = phase + 1)begin seed=seed*1664525+1013904223;l=seed[23:0];r=~seed[23:0];v=seed[6:0];@(negedge clk);end
 end  end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(g=0;g<128;g = g + 1)begin
   pair(24'h800000,24'h7fffff,g);pair(24'hffffff,24'h000001,g);pair(0,0,g);
   for(k=0;k<256;k = k + 1)begin seed=seed*1664525+1013904223;pair(seed[23:0],~seed[23:0],g);end
  end
  for(k=0;k<75;k = k + 1)begin
   @(negedge clk);valid=1;l=24'h800001;r=24'h654321;v=73;@(negedge clk);valid=0;
   repeat(k)@(negedge clk);#2;rst=0;#1;if(a!==b)begin errors = errors + 1;$display("[FAIL] async reset differs");end
   @(negedge clk);rst=1;repeat(80)@(negedge clk);
  end
  if(errors==0)$display("[PASS] every public pin, original37/74-clock timing, all128 gains, changed busy inputs and75 asynchronous reset phases");
  $display("[TB] tb_v3_volume_dsp_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #30000000;$display("[FAIL] volume miter watchdog errors=1");$finish;end
endmodule
