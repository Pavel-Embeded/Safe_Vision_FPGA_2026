`timescale 1ns/1ps
module tb_v3_led_publication;
 reg refclk=1,sysclk=1,sys_enable=1,hold_high=0,rrst=0,srst=0,loss=0;
 always #10 refclk=~refclk;
 always #5 if(sys_enable)sysclk=~sysclk;else sysclk=hold_high;
 reg[3:0] flags=0;reg normal_bit=1,fatal_bit=1;
 always @(posedge sysclk or negedge srst)if(!srst)begin flags<=0;normal_bit<=1;end else begin flags<=flags+1'b1;normal_bit<=~normal_bit;end
 always @(negedge refclk)fatal_bit<=~fatal_bit;
 wire[3:0] got,want;wire gu,wu;
 v3_led_publication_candidate dut(refclk,sysclk,srst,rrst,normal_bit,loss,fatal_bit,flags[3],flags[2],flags[1],flags[0],gu,got);
 v3_led_publication_reference reference(refclk,sysclk,srst,rrst,normal_bit,loss,fatal_bit,flags[3],flags[2],flags[1],flags[0],wu,want);
 integer comparisons=0,errors=0,k;reg[3:0] mathematical;reg[15:0] seen=0;
 always @(posedge refclk)begin
  mathematical=!rrst?4'd0:(loss?4'hf:(srst?flags:4'd0));
  #0.01;comparisons++;
  if(got!==want||got!==mathematical||gu!==wu)begin errors++;if(errors<8)$display("[FAIL] publication got=%h want=%h mathematical=%h uart=%b/%b",got,want,mathematical,gu,wu);end
  if(rrst&&srst&&!loss)seen[got]=1;
 end
 initial begin
  repeat(3)@(posedge sysclk);srst<=1;@(posedge refclk);rrst<=1;
  for(k=0;k<40;k++)begin
   repeat(201+k)@(posedge sysclk);
   @(negedge sysclk);#0.2;srst=0;repeat(2)@(posedge sysclk);srst<=1;
   if(k%4==0)begin @(negedge refclk);#0.3;rrst=0;repeat(2)@(posedge refclk);rrst<=1;end
   if(k%5==0)begin
    @(negedge sysclk);sys_enable=0;hold_high=0;repeat(8)@(posedge refclk);
    @(negedge refclk);loss=1;repeat(8)@(posedge refclk);
    @(negedge refclk);#5.1;sys_enable=1;repeat(4)@(posedge refclk);@(negedge refclk);loss=0;
   end
  end
  repeat(20)@(posedge refclk);#1;
  if(seen!==16'hffff)begin errors++;$display("[FAIL] not all16 LED codes exercised");end
  if(errors==0)$display("[PASS] exact REF-edge LED/UART publication,independent live-status oracle,all16 codes,40 SYS resets,10 REF resets,8 stopped-SYS/FATAL intervals");
  $display("[TB] tb_v3_led_publication done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000;errors++;$display("[FAIL] publication watchdog");$display("[TB] tb_v3_led_publication done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
