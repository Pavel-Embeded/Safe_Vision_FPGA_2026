`timescale 1ns/1ps
module tb_v3_coordinate_base210;
 reg clk=0,rst=0;always #10 clk=~clk;integer errors=0,comparisons=0,frames=0,k;
 safevision_v3_top dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 always@(negedge dut.pixel_clk)if(dut.pixel_rst_n)begin
  comparisons+=2;
  if(dut.video.coordinates19!==dut.video.tags[19][23:0]||{dut.out_x,dut.out_y}!==dut.video.tags[20][23:0])begin
   errors++;if(errors<8)$display("[FAIL] BASE coordinate latency raw=%0d/%0d arithmetic=%h/%h expected=%h/%h",dut.raw_x,dut.raw_y,dut.video.coordinates19,{dut.out_x,dut.out_y},dut.video.tags[19][23:0],dut.video.tags[20][23:0]);
  end
  if(dut.raw_fs)frames++;
 end
 initial begin
  repeat(10)@(negedge clk);rst=1;wait(dut.pixel_rst_n);
  for(k=0;k<8;k++)begin repeat(31+k*7)@(negedge dut.pixel_clk);#1;rst=0;repeat(7)@(negedge clk);rst=1;wait(dut.pixel_rst_n);end
  wait(frames>=3);repeat(40)@(negedge dut.pixel_clk);
  if(!errors)$display("[PASS] BASE800x525: every raster coordinate matches original21-stage shift registers;startup,8 asynchronous resets,line/frame wrap");
  $display("[TB] tb_v3_coordinate_base210 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #80000000;$display("[FAIL] BASE coordinates watchdog errors=1");$finish;end
endmodule
