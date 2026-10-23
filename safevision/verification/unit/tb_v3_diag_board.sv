`timescale 1ns/1ps
module tb_v3_diag_board;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire txd;wire[3:0]led;wire scl;tri sda;
 safevision_v3_top dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
 .uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),
 .HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_status_text.mem";
 reg cv=0,query=0;reg signed[31:0] selector=0;integer errors=0,comparisons=0,i,wait_count;
 reg injected_event=0,evt_consume=0;reg[43:0] injected_payload=0;integer event_i;
 reg[31:0] expected[0:15];reg[63:0] settings_before;
 task ck(input bit condition,input string message);begin comparisons++;
  if(!condition)begin errors++;if(errors<10)$display("[FAIL] %s selector=%h actual=%h t=%t",message,selector,dut.b_reply_value,$time);end
 end endtask
 task command(input signed[31:0] bank,input bit ask,input[7:0] code,input[31:0] wanted);begin
  @(negedge dut.sys_clk);selector=bank;query=ask;cv=1;
  @(negedge dut.sys_clk);cv=0;wait_count=0;
  while(!dut.b_reply && wait_count<200)begin @(negedge dut.sys_clk);wait_count++;end
  ck(dut.b_reply && dut.b_reply_code==code,"exactly one bounded reply with expected status");
  if(code==0)ck(dut.b_reply_value===wanted,"board selector returns the intended complete32-bit register");
  @(negedge dut.sys_clk);repeat(8)@(negedge dut.sys_clk);
  ck(!dut.b_reply,"no duplicate reply");
 end endtask
 initial begin
  force dut.err_push=injected_event;force dut.err_ts=injected_payload[43:12];
  force dut.err_code=injected_payload[11:4];force dut.err_src=injected_payload[3:0];
  force dut.evt_ready=evt_consume;
  expected[0]=32'h26102301;expected[1]=32'ha1b2c3d4;expected[2]=32'h000004ab;expected[3]=32'hdeadbeef;
  expected[4]=32'h000af35e;expected[5]=32'h00123400;expected[6]=32'h01234567;expected[7]=32'h89abcdef;
  expected[8]=32'h00025800;expected[9]=32'h00000017;expected[10]=32'h11223344;expected[11]=32'h55667788;
  expected[12]=32'h13579bdf;expected[13]=32'h2468ace0;expected[14]=32'h06ae4740;expected[15]=32'h00830355;
  repeat(10)@(negedge clk);rst_n=1;wait(dut.sys_rst_n && dut.sys_media_rst_n && dut.mem_media_rst_n);
  repeat(20)@(negedge dut.sys_clk);
  force dut.cmd_valid=cv;force dut.cmd_target=8'd66;force dut.cmd_catalog_id=7'd36;force dut.cmd_value=selector;force dut.cmd_query=query;
  force dut.ref_status_sys={12'h4ab,112'd0,32'hdeadbeef,16'd0,32'ha1b2c3d4};
  force dut.sink_state=4'ha;force dut.sink_code=8'hf3;force dut.approved=4'h5;
  force dut.sdr_init_done=1'b1;force dut.adapter_init=1'b1;force dut.guard_fault=1'b1;
  force dut.adapter_fault=1'b0;force dut.memory_error=1'b0;
  force dut.guard_bad_addr=32'h00123400;force dut.guard_expected=32'h01234567;force dut.guard_actual=32'h89abcdef;
  // This diagnostic-only injection forces the source count through its
  // continuous output alias. Keep its redundant zero flag consistent; the
  // live memory invariant remains enabled and all diagnostic checks remain.
  force dut.row_guard.source_first=1'b0;
  force dut.guard_words=32'h00025800;force dut.guard_rows=16'h17;
  force dut.diag_raw_first=32'h11223344;force dut.diag_raw_last=32'h55667788;
  force dut.diag_source_first=32'h13579bdf;force dut.diag_write_first=32'h2468ace0;
  force dut.diag_source_count=9'h1ab;force dut.diag_write_count=9'h123;force dut.diag_raw_count=9'h140;force dut.diag_host_count=9'h106;
  force dut.diag_command_dm=4'h3;force dut.diag_response_dm=4'h5;force dut.app_wr_dm=4'h7;
  force dut.sdr_busy=1'b1;force dut.sdr_ref_valid=1'b0;
  settings_before={dut.brightness,dut.contrast,dut.osd_alpha,dut.bilinear,dut.fit,dut.fade_enable,dut.volume,dut.period_select,dut.field,dut.menu,dut.auto_enabled};
  for(i=0;i<16;i++)command(i,0,0,expected[i]);
  command(0,1,0,32'h26102301);
  command(-1,0,3,0);command(16,0,3,0);command(32'h80000000,0,3,0);command(32'h10000004,0,3,0);
  ck(settings_before==={dut.brightness,dut.contrast,dut.osd_alpha,dut.bilinear,dut.fit,dut.fade_enable,dut.volume,dut.period_select,dut.field,dut.menu,dut.auto_enabled},"all diagnostic selectors preserve user configuration");
  force dut.media_reset=1'b1;repeat(10)@(negedge dut.sys_clk);command(4,0,4,0);
  release dut.media_reset;repeat(30)@(negedge dut.sys_clk);command(4,0,0,expected[4]);
  // A previous ordinary query leaves nonzero data in query banks.
  force dut.cmd_catalog_id=7'd27;query=1;
  @(negedge dut.sys_clk);cv=1;@(posedge dut.sys_clk);#0.001;
  ck(dut.b_reply && dut.b_reply_value===32'hc,"ordinary nonzero reply before asynchronous diagnostic");
  @(negedge dut.sys_clk);cv=0;
  force dut.diag_reply_valid=1'b1;force dut.diag_reply_ok=1'b1;force dut.diag_reply_value=32'h38a64b19;
  @(posedge dut.sys_clk);#0.001;
  ck(dut.b_reply && dut.b_reply_code==0 && dut.b_reply_value===32'h38a64b19,"asynchronous diagnostic replaces prior query class and payload");
  @(negedge dut.sys_clk);release dut.diag_reply_valid;release dut.diag_reply_ok;release dut.diag_reply_value;
  // Exercise the assembled supervisor->register->FIFO boundary through its
  // public output under backpressure. Distinct stamps must stay with codes.
  for(event_i=0;event_i<8;event_i++)begin
   @(negedge dut.sys_clk);injected_event=1;
   injected_payload={32'h3ff83a00+event_i,8'h80+8'(event_i),4'(event_i)};
  end
  @(negedge dut.sys_clk);injected_event=0;injected_payload=44'hffffffffff;
  repeat(8)@(negedge dut.sys_clk);
  ck(dut.evt_full && dut.evt_valid && dut.evt_drops==0,"eight events retained under backpressure");
  injected_event=1;@(negedge dut.sys_clk);injected_event=0;repeat(4)@(negedge dut.sys_clk);
  ck(dut.evt_drops==1,"full event queue records exactly one overflow");
  for(event_i=0;event_i<8;event_i++)begin
   ck(dut.evt_valid && dut.evt_ts===32'h3ff83a00+event_i && dut.evt_value==16'h80+event_i && dut.evt_src==event_i,
       "event source/code/original timestamp preserved in order");
   evt_consume=1;@(negedge dut.sys_clk);evt_consume=0;
  end
  ck(!dut.evt_valid,"event queue drains without duplicates");
  if(errors==0)$display("[PASS] all16 board registers, query identity, invalid ranges and media-reset busy");
  $display("[TB] tb_v3_diag_board done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] board diagnostic watchdog errors=1");$finish;end
endmodule
