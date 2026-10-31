`timescale 1ns/1ps
module setting_wave_board_case198 #(parameter HD=0)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg clk=0,rst=0;always #10 clk=~clk;
 safevision_v3_top #(.HD(HD)) dut(.clk(clk),.rst_n(rst),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.sd_miso(1'b1));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 reg cv=0,ask=0;reg[7:0]dest=67;reg[6:0]id=33;reg signed[31:0]value=0;
 integer k,v;reg[6:0]eng=20;
 task ck(input  ok,input [4095:0] msg);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] real raster HD=%0d %s volume=%d cfg=%d setting=%d scope_ready=%b",HD,msg,dut.volume,dut.video.cfg[67:61],dut.video.graphics.decimal_digits[4],dut.video.graphics.spectrum_ready);end   end endtask
 task setvolume(input integer vol);begin
  @(negedge dut.sys_clk);dest=67;id=33;value=vol;ask=0;cv=1;
  @(negedge dut.sys_clk);cv=0;@(negedge dut.sys_clk);ck(dut.controls_reply&&dut.controls_reply_code==0,"production C:VOL endpoint accepted");
  repeat(4)@(negedge dut.sys_clk);ck(dut.volume==vol,"actual SYS control register");
   end endtask
 task diag;begin
  @(negedge dut.sys_clk);dest=66;id=36;value=100;ask=0;cv=1;
  @(negedge dut.sys_clk);cv=0;ck(dut.b_reply&&dut.b_reply_code==0,"read-only DIAG100 accepted");
  ck(dut.b_reply_value==((eng<<7)|v),"DIAG100 captures live pre-volume energy and volume on original edge");repeat(4)@(negedge dut.sys_clk);
   end endtask
 initial begin
  repeat(10)@(negedge clk);rst=1;wait(dut.sys_rst_n&&dut.config_rst_n);repeat(8)@(negedge dut.sys_clk);
  force dut.cmd_valid=cv;force dut.cmd_target=dest;force dut.cmd_catalog_id=id;force dut.cmd_value=value;force dut.cmd_query=ask;force dut.energy=eng;
  ck(dut.video.USER_FEATURES==1&&dut.video.FLEX_SPECTRUM==1&&dut.video.VOLUME_SETTING==0&&dut.video.VOLUME_COLUMNS==0,"latest user request replaces columns with real PCM frequency spectrum");
  ck(dut.video.graphics.RASTER_PREDECODE==HD,"production core actually enables HD row predecode");
  for(k=0;k<3;k = k + 1)begin
   v=k==0 ? 0:k==1 ? 100:70;setvolume(v);diag();


   repeat(3)@(posedge dut.video.frame_start);repeat(116)@(negedge dut.pixel_clk);
   ck(dut.video.cfg[67:61]==v&&dut.video.cfg[54:48]==eng,"real config mailbox with continuous source-valid and actual raster");
   ck(dut.video.graphics.decimal_digits[4]==((v/100)*256+((v/10)%10)*16+v%10),"visible VOL decimal matches acknowledged setting");
   ck(dut.video.graphics.spectrum_ready,"real PCM spectrum publishes complete captures");
  end
  done=1;
 end
endmodule
`ifdef HD_SETTING_SOURCE
module tb_v3_setting_wave_board_hd198;
 wire done;wire signed [31:0] errors,comparisons;setting_wave_board_case198 #(.HD(1)) d(done,errors,comparisons);
 initial begin wait(done);#2;if(errors==0)$display("[PASS] production C:VOL/DIAG100,full99-bit mailbox,real HD raster/predecode and numeric VOL and actual PCM spectrum readiness");$display("PASS tb_v3_setting_wave_board_hd198 errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #300000000;$display("[FAIL] real HD volume watchdog errors=1");$finish;end
endmodule
`else
module tb_v3_setting_wave_board_base198;
 wire done;wire signed [31:0] errors,comparisons;setting_wave_board_case198 #(.HD(0)) d(done,errors,comparisons);
 initial begin wait(done);#2;if(errors==0)$display("[PASS] production C:VOL/DIAG100,full99-bit mailbox,real BASE raster and numeric VOL and actual PCM spectrum readiness");$display("PASS tb_v3_setting_wave_board_base198 errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #300000000;$display("[FAIL] real BASE volume watchdog errors=1");$finish;end
endmodule
`endif
