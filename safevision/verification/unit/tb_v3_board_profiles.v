`timescale 1ns/1ps
module v3_board_profile_probe #(
 parameter integer PROFILE=0,TICKER=0,
 parameter [31:0] ID=PROFILE ? 32'h26102801 : 32'h26102301
)(output reg done=0,output integer errors=0);
 wire txd,scl;
 wire[3:0] led;
 tri sda;
 safevision_v3_top #(.TICKER_ENABLE(TICKER),.MEDIA_PIPELINE_PROFILE(PROFILE),.FIRMWARE_ID(ID)) dut(
 .clk(1'b0),.rst_n(1'b0),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
 .uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),
 .HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_status_text.mem";
 defparam dut.video.graphics.spectrum.analyzer.PACKED_INIT_FILE="v3_spectrum_ticker32.mem";
 generate if(TICKER)begin:font_path
  defparam dut.scrolling.ticker.BITMAP_FILE="v3_ticker16.mem";
 end endgenerate
 task check(input condition,input[511:0] message);
 begin
  if(condition!==1'b1)begin
   errors=errors+1;
   $display("[FAIL] profile=%0d ticker=%0d %s",PROFILE,TICKER,message);
  end
 end endtask
 initial begin
  force dut.cmd_query=1'b1;
  #1;
  check(dut.player.REGISTERED_RESIDENT_READY==PROFILE,"resident ready policy");
  check(dut.sink.SOURCE_PROGRESS_AWARE==PROFILE,"source progress policy");
  check(dut.audio.DIRECT_RING_COMPARE==PROFILE,"audio ring policy");
  check(dut.audio.ring.DIRECT_POINTER_COMPARE==PROFILE,"audio ring instance");
  check(dut.TICKER_ENABLE==TICKER,"ticker feature selection");
  check(dut.b_diag_next0===ID,"firmware identity independent of ticker");
  release dut.cmd_query;
  done=1;
 end
endmodule

module tb_v3_board_profiles;
 wire[4:0] done;
 wire signed[31:0] e0,e1,e2,e3,e4;
 integer errors;
 v3_board_profile_probe #(.PROFILE(0),.TICKER(0)) p00(done[0],e0);
 v3_board_profile_probe #(.PROFILE(0),.TICKER(1)) p01(done[1],e1);
 v3_board_profile_probe #(.PROFILE(1),.TICKER(0)) p10(done[2],e2);
 v3_board_profile_probe #(.PROFILE(1),.TICKER(1)) p11(done[3],e3);
 v3_board_profile_probe #(.PROFILE(1),.TICKER(0),.ID(32'h13579bdf)) custom_id(done[4],e4);
 initial begin
  wait(&done);
  errors=e0+e1+e2+e3+e4;
  if(errors==0)$display("[PASS] independent media profile, ticker and firmware ID across five configurations");
  $display("PASS tb_v3_board_profiles errors=%0d comparisons=30",errors);
  $finish;
 end
 initial begin #1000;$display("[FAIL] profile watchdog errors=1");$finish;end
endmodule
