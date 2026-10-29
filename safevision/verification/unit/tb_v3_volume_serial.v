`timescale 1ns/1ps
module tb_v3_volume_serial;
 reg clk=0,rst_n=0,valid=0;always #5 clk=~clk;
 reg[23:0] l=0,r=0;reg[6:0] volume=0;wire ov,busy;wire[23:0] ol,orr;
 v3_audio_volume dut(.clk(clk),.rst_n(rst_n),.valid_in(valid),.left_in(l),.right_in(r),
 .volume(volume),.valid_out(ov),.left_out(ol),.right_out(orr),.busy(busy));
 integer checks=0,errors=0;reg signed[63:0] expected_l,expected_r;reg signed[23:0] sl,sr;
 reg[31:0] random_state=32'h87291bcf;
 task check(input  condition,input [4095:0] message);begin begin condition = (condition === 1'b1); checks = checks + 1;if(!condition)begin errors = errors + 1;if(errors<6)$display("[FAIL] %s",message);end end  end endtask
 task pair(input[23:0] a,b,input integer gain);
  integer wait_cycles;begin begin
   @(negedge clk);l=a;r=b;volume=gain;valid=1;sl=a;sr=b;
   expected_l=sl;expected_r=sr;expected_l=expected_l*(gain>100 ? 100:gain)/100;expected_r=expected_r*(gain>100 ? 100:gain)/100;
   @(negedge clk);valid=0;l=~a;r=~b;volume=127-gain;wait_cycles=0;
   while(!ov&&wait_cycles<82)begin @(negedge clk);wait_cycles = wait_cycles + 1;end
   check(ov,"bounded complete");check(ol===expected_l[23:0],"left exact signed /100");check(orr===expected_r[23:0],"right exact signed /100");
   check(!busy,"busy deasserts with valid");
   @(negedge clk);check(!ov,"single output pulse");
  end
  end endtask
 initial begin
  #30;rst_n=1;
  begin : v_loop_1 integer g; for( g=0;g<=127;g = g + 1)begin
   pair(24'h800000,24'h7fffff,g);pair(24'hffffff,24'h000001,g);
   pair(24'h987654,24'h123456,g);pair(24'd0,24'd0,g);
   begin : v_loop_2 integer j; for( j=0;j<32;j = j + 1)begin random_state=random_state*32'd1664525+32'd1013904223;l=random_state[23:0];random_state=random_state*32'd1664525+32'd1013904223;pair(l,random_state[23:0],g);end end 
  end end 
  begin : v_loop_3 integer phase; for( phase=0;phase<74;phase = phase + 1)begin
   @(negedge clk);l=24'h800001;r=24'h123456;volume=73;valid=1;
   @(negedge clk);valid=0;
   repeat(phase)@(negedge clk);
   #2;rst_n=0;#1;check(!ov&&!busy,"asynchronous phase reset aborts transaction");
   @(negedge clk);rst_n=1;
   repeat(80)begin @(negedge clk);check(!ov,"aborted result never appears");end
   pair(24'hfedcba,24'h123456,47);
  end end 
  $display("[PASS] full24 signed volume every gain, busy data changes, 74 reset phases");
  $display("PASS tb_v3_volume_serial errors=%0d comparisons=%0d",errors,checks);$finish;
 end
 initial begin #10000000;begin $display("[FAIL] volume watchdog"); $finish; end end
endmodule
