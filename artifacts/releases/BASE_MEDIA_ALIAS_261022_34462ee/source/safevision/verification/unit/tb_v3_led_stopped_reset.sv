`timescale 1ns/1ps
module tb_v3_led_stopped_reset;
 reg refclk=1,sysclk=1,sys_enable=1,rrst=0,srst=0,expect_zero=1;
 always #10 refclk=~refclk;
 always #5 if(sys_enable)sysclk=~sysclk;else sysclk=0;
 wire[3:0] got,want;wire gu,wu;integer errors=0,comparisons=0,k;
 // SAFE can be combinationally asserted while the SYS cache remains reset.
 v3_led_publication_candidate dut(refclk,sysclk,srst,rrst,1'b1,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,gu,got);
 v3_led_publication_reference reference(refclk,sysclk,srst,rrst,1'b1,1'b0,1'b0,1'b1,1'b0,1'b0,1'b0,wu,want);
 always @(posedge refclk)begin
  #0.01;comparisons++;
  if(got!==want||gu!==wu||(expect_zero&&got!==0))begin errors++;if(errors<8)$display("[FAIL] stopped SYS reset publication got=%h reference=%h expect_zero=%b",got,want,expect_zero);end
 end
 initial begin
  repeat(3)@(posedge sysclk);srst<=1;@(negedge sysclk);expect_zero=0;
  repeat(2)@(posedge refclk);rrst<=1;repeat(4)@(posedge refclk);
  for(k=0;k<16;k++)begin
   @(negedge sysclk);#0.1;sys_enable=0;srst=0;expect_zero=1;
   repeat(4)@(posedge refclk);@(negedge refclk);srst=1;
   repeat(4)@(posedge refclk);
   @(negedge refclk);#5.1;sys_enable=1;
   @(negedge sysclk);expect_zero=0;repeat(4)@(posedge refclk);
  end
  #1;if(comparisons<190)begin errors++;$display("[FAIL] insufficient stopped reset observations");end
  if(errors==0)$display("[PASS] 16 stopped-SYS reset/release/resume cycles retain original LED blanking,even with SAFE asserted before the first SYS falling edge");
  $display("[TB] tb_v3_led_stopped_reset done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #100000;errors++;$display("[FAIL] stopped reset watchdog");$display("[TB] tb_v3_led_stopped_reset done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
