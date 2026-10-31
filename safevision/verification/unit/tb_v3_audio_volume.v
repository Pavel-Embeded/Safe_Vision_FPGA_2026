`timescale 1ns/1ps
module tb_v3_audio_volume;
 reg clk=0,rst_n=0,valid=0;always #5 clk=~clk;
 reg[23:0] l=0,r=0;reg[6:0] volume=0;wire ov,busy;wire[23:0] ol,orr;
 v3_audio_volume dut(.clk(clk),.rst_n(rst_n),.valid_in(valid),.left_in(l),.right_in(r),
 .volume(volume),.valid_out(ov),.left_out(ol),.right_out(orr),.busy(busy));
 integer checks=0,cycles=0;reg signed[63:0] expected_l,expected_r;reg signed[23:0] sl,sr;
 task pair(input[23:0] a,b,input integer gain);
  integer wait_cycles;begin
   @(negedge clk);l=a;r=b;volume=gain;valid=1;sl=a;sr=b;
   expected_l=sl;expected_r=sr;expected_l=expected_l*(gain>100 ? 100:gain)/100;expected_r=expected_r*(gain>100 ? 100:gain)/100;
   @(negedge clk);valid=0;wait_cycles=0;
   while(!ov&&wait_cycles<82)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(!ov||ol!==expected_l[23:0]||orr!==expected_r[23:0])begin $display("[FAIL] serial exact volume gain=%0d L=%h R=%h got=%h,%h expected=%h,%h",gain,a,b,ol,orr,expected_l[23:0],expected_r[23:0]); $finish; end
   checks=checks+2;@(negedge clk);

  end endtask
 initial begin
  #30;rst_n=1;
  begin : v_loop_1 integer g; for( g=0;g<=100;g=g+1)begin
   pair(24'h800000,24'h7fffff,g);pair(24'hffffff,24'h000001,g);
   pair(24'h987654,24'h123456,g);pair($random,$random,g);
  end end
  pair(24'h800001,24'h7ffffe,127);
  $display("[PASS] serial volume all0..100 signed boundaries random and >100 clamp");
  $display("PASS tb_v3_audio_volume errors=0 comparisons=%0d",checks);$finish;
 end
 initial begin #1000000;begin $display("[FAIL] volume watchdog"); $finish; end end
endmodule
