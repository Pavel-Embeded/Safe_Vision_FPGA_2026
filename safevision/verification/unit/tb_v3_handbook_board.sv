`timescale 1ns/1ps
module tb_v3_handbook_board;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 wire txd;wire[3:0]led;wire scl;tri sda;
 safevision_v3_top dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
 .uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),
 .HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 reg cv=0,query=0;reg[7:0]dest=65;reg[6:0]id=0;reg signed[31:0]value=0;
 integer errors=0,comparisons=0,i;reg[98:0]saved;
 task ck(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;$display("[FAIL] %s",message);end end endtask
 task command(input[7:0]d,input[6:0]k,input integer v,input bit ask,input integer want);
  begin @(negedge dut.sys_clk);dest=d;id=k;value=v;query=ask;cv=1;
   @(negedge dut.sys_clk);cv=0;
   if(d!=66)begin
    ck(!dut.controls_reply,"control endpoint has no premature unregistered ACK");
    @(negedge dut.sys_clk);
   end
   ck((d==66?dut.b_reply:dut.controls_reply)&&(d==66?dut.b_reply_code:dut.controls_reply_code)==0,"production numeric catalog endpoint ACK");
   if(ask)ck((d==66?dut.b_reply_value:dut.controls_reply_value)==want,"production query readback");
   repeat(4)@(negedge dut.sys_clk);
  end
 endtask
 initial begin
  repeat(10)@(negedge clk);rst_n=1;wait(dut.sys_rst_n&&dut.config_rst_n);repeat(8)@(negedge dut.sys_clk);
  force dut.cmd_valid=cv;force dut.cmd_target=dest;force dut.cmd_catalog_id=id;force dut.cmd_value=value;force dut.cmd_query=query;
  ck(dut.audio.HANDBOOK_PROFILE==1&&dut.audio.meter.HANDBOOK_PROFILE==1,"production pre-volume handbook energy profile is enabled");
  command(66,36,0,1,32'h26102237);
  command(67,2,0,1,1);command(67,18,0,1,5);command(65,37,0,1,80);command(65,41,0,1,0);command(67,33,0,1,70);
  command(65,37,35,0,0);command(65,37,0,1,35);command(65,41,3,0,0);command(65,41,0,1,3);
  command(67,40,1,0,0);command(67,40,0,1,1);command(67,38,7,0,0);command(67,38,0,1,7);
  ck(dut.cfg_data[98:87]==={1'b0,2'd3,1'b1,8'(-30)},"99-bit atomic CFG preserves AUTO beside negative signed offset");
  command(67,40,0,0,0);command(67,38,0,0,0);saved=dut.cfg_data;
  rst_n=0;repeat(15)@(negedge clk);rst_n=1;wait(dut.sys_rst_n);repeat(8)@(negedge dut.sys_clk);
  command(65,37,0,1,35);command(65,41,0,1,3);command(67,2,0,1,1);command(67,18,0,1,5);
  ck(dut.config_rst_n&&dut.config_power_count==63,"KEY1 cannot restart the configuration epoch");
  force dut.response_latency_ms=16'd321;
  command(66,39,0,1,321);ck(dut.cfg_data[7:0]==255,"HUD latency saturation leaves full UART measurement intact");
  release dut.response_latency_ms;
  if(errors==0)$display("[PASS] production catalog, defaults, signed CFG, warm reset and measured latency endpoint");
  $display("[TB] tb_v3_handbook_board done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000;$display("[FAIL] production profile watchdog errors=1");$finish;end
endmodule
