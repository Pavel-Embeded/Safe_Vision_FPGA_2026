`timescale 1ns/1ps
module board_clock_case #(parameter HD=0,EXPECTED_HZ=25185185)(input clk,output reg done=0,output integer errors=0,comparisons=0);
 reg rst_n=0;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 // Same measured MEM50/+8ns data-before-valid relation as real board.
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 task check(input bit ok,input string message);begin comparisons=comparisons+1;if(!ok)begin errors=errors+1;$display("[FAIL] HD=%0d %s",HD,message);end end endtask
 always @(posedge clk)begin #1;
  if(!done&&(dut.media_common_rst_n===1'b0||dut.media_common_rst_n===1'b1))
   check(dut.audio.media_reset_any===!dut.media_common_rst_n,"audio raw media reset includes the canonical global/media epoch");
 end
 initial begin
  repeat(10)@(negedge clk);rst_n=1;wait(dut.pixel_rst_n);repeat(5)@(negedge dut.pixel_clk);
  check(dut.PIXEL_HZ==EXPECTED_HZ && dut.video.PIXEL_HZ==EXPECTED_HZ && dut.video.graphics.PIXEL_HZ==EXPECTED_HZ,"official PLL parameter propagated through board/core/HUD");
  check($bits(dut.video.graphics.second_count)==$clog2(EXPECTED_HZ/2),"bounded half-second physical counter width");
  force dut.video.frame_start=1'b0;
  dut.video.graphics.second_count=EXPECTED_HZ/2-2;dut.video.graphics.frame_count=8'd77;dut.video.graphics.fps=8'd13;
  @(posedge dut.pixel_clk);#1;check(dut.video.graphics.second_count==EXPECTED_HZ/2-1 && dut.video.graphics.fps==13,"one edge before exact half-second terminal count");
  @(negedge dut.pixel_clk);force dut.video.frame_start=1'b1;
  @(posedge dut.pixel_clk);#1;check(dut.video.graphics.second_count==0 && dut.video.graphics.fps==156 && dut.video.graphics.frame_count==0,"half-second count includes coincident frame exactly once and converts to frames per second");
  @(negedge dut.pixel_clk);release dut.video.frame_start;
  wait(dut.control_common_rst_n);repeat(3)@(negedge clk);
  force dut.media_reset=1'b1;#1;
  check(dut.audio.media_reset_any&&!dut.media_common_rst_n,"media recovery asserts the complete canonical audio reset");
  repeat(5)@(negedge clk);release dut.media_reset;
  repeat(5)@(negedge clk);
  check(!dut.audio.media_reset_any&&dut.media_common_rst_n,"media release returns the same raw epoch in both clock profiles");
  rst_n=0;repeat(5)@(negedge clk);check(dut.video.graphics.fps==0 && dut.video.graphics.second_count==0,"global reset clears new interval");
  done=1;
 end
endmodule
module tb_v3_board_clocks;
 reg clk=0;always #10 clk=~clk;
 wire d0,d1;wire[31:0] e0,e1,c0,c1;integer errors,comparisons;
 board_clock_case #(.HD(0),.EXPECTED_HZ(25185185)) base(clk,d0,e0,c0);
 board_clock_case #(.HD(1),.EXPECTED_HZ(74166667)) hd(clk,d1,e1,c1);
 initial begin wait(d0&&d1);#2;errors=e0+e1;comparisons=c0+c1;
 if(errors==0)$display("[PASS] both board PLL nominal frequencies, core/HUD parameter paths and seeded terminal-count boundaries");
 $display("[TB] tb_v3_board_clocks done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #100000;$display("[FAIL] board clocks watchdog errors=1");$finish;end
endmodule
