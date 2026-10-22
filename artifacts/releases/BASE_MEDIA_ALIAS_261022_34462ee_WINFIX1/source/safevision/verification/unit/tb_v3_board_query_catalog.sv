`timescale 1ns/1ps
module tb_v3_board_query_catalog;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire txd,cs,sclk,mosi,d0,d1,d2,dc,scl;tri sda;wire[3:0] led;
 safevision_v3_top #(.HD(0)) dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(1'b1),.HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),.HDMI_CLK_P(dc),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 reg cmd_valid=0,cmd_query=1;reg[7:0] cmd_target=66;reg[95:0] cmd_name=0;reg[6:0] cmd_id=0;
 reg[191:0] ref_status_sys=0;
 reg[1:0] active_slot=0;
 reg[3:0] cache_sys=0;
 reg[7:0] generation=0;
 reg[31:0] audio_underflows=0;
 reg[31:0] video_underflows=0;
 reg[7:0] fault_code=0;
 reg presentation_fault=0;
 reg[47:0] mem_status_sys=0;
 reg video_fault=0;
 reg[2:0] fault_level=0;
 reg[2:0] recovery_state=0;
 reg[1:0] recovery_attempts=0;
 reg[3:0] audio_fallback=0;
 reg[31:0] audio_overflows=0;
 reg[15:0] evt_drops=0;
 reg[31:0] uart_rejected=0;
 reg[31:0] uart_framing=0;
 reg[31:0] uart_overrun=0;
 reg[31:0] uart_reply_dropped=0;
 wire ref_reply;wire[7:0] ref_code;wire signed[31:0] ref_value;integer i,errors=0,comparisons=0;reg[31:0] rng=32'h62ce1845;
 v3_board_query_reference reference(.sys_clk(dut.sys_clk),.sys_rst_n(dut.sys_rst_n),.cmd_valid(cmd_valid),.cmd_target(cmd_target),.cmd_name(cmd_name),.cmd_query(cmd_query),
 .ref_status_sys(ref_status_sys),.active_slot(active_slot),.cache_sys(cache_sys),.generation(generation),.audio_underflows(audio_underflows),.video_underflows(video_underflows),.fault_code(fault_code),.presentation_fault(presentation_fault),.mem_status_sys(mem_status_sys),.video_fault(video_fault),.fault_level(fault_level),.recovery_state(recovery_state),.recovery_attempts(recovery_attempts),.audio_fallback(audio_fallback),.audio_overflows(audio_overflows),.evt_drops(evt_drops),.uart_rejected(uart_rejected),.uart_framing(uart_framing),.uart_overrun(uart_overrun),.uart_reply_dropped(uart_reply_dropped),.b_reply(ref_reply),.b_reply_code(ref_code),.b_reply_value(ref_value));
 initial begin
  repeat(20)@(negedge clk);rst_n=1;wait(dut.sys_rst_n===1);repeat(4)@(negedge dut.sys_clk);
  force dut.cmd_valid=cmd_valid;force dut.cmd_target=cmd_target;force dut.cmd_name=cmd_name;force dut.cmd_query=cmd_query;force dut.cmd_catalog_id=cmd_id;
  force dut.ref_status_sys=ref_status_sys;
  force dut.active_slot=active_slot;
  force dut.cache_sys=cache_sys;
  force dut.generation=generation;
  force dut.audio_underflows=audio_underflows;
  force dut.video_underflows=video_underflows;
  force dut.fault_code=fault_code;
  force dut.presentation_fault=presentation_fault;
  force dut.mem_status_sys=mem_status_sys;
  force dut.video_fault=video_fault;
  force dut.fault_level=fault_level;
  force dut.recovery_state=recovery_state;
  force dut.recovery_attempts=recovery_attempts;
  force dut.audio_fallback=audio_fallback;
  force dut.audio_overflows=audio_overflows;
  force dut.evt_drops=evt_drops;
  force dut.uart_rejected=uart_rejected;
  force dut.uart_framing=uart_framing;
  force dut.uart_overrun=uart_overrun;
  force dut.uart_reply_dropped=uart_reply_dropped;
  for(i=0;i<4096;i=i+1)begin
   @(negedge dut.sys_clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   cmd_valid=1;cmd_query=1;cmd_target=66;
   ref_status_sys={(rng^32'h6d2b79f5),(rng^32'h0b62f3ae),(rng^32'ha99a6d67),(rng^32'h47d1e720),(rng^32'he60960d9),(rng^32'h8440da92)};
   active_slot=(rng^32'hda56f3ea);
   cache_sys=(rng^32'h47826ddf);
   generation=(rng^32'hb4ade7d4);
   audio_underflows=(rng^32'h21d961c9);
   video_underflows=(rng^32'h8f04dbbe);
   fault_code=(rng^32'hfc3055b3);
   presentation_fault=(rng^32'h695bcfa8);
   mem_status_sys={(rng^32'hd687499d),(rng^32'h74bec356)};
   video_fault=(rng^32'h43b2c392);
   fault_level=(rng^32'hb0de3d87);
   recovery_state=(rng^32'h1e09b77c);
   recovery_attempts=(rng^32'h8b353171);
   audio_fallback=(rng^32'hf860ab66);
   audio_overflows=(rng^32'h658c255b);
   evt_drops=(rng^32'hd2b79f50);
   uart_rejected=(rng^32'h3fe31945);
   uart_framing=(rng^32'had0e933a);
   uart_overrun=(rng^32'h1a3a0d2f);
   uart_reply_dropped=(rng^32'h87658724);
   case(i%29)
    0:begin cmd_name="STATUS";cmd_id=7'd27;end
    1:begin cmd_name="SLOT";cmd_id=7'd26;end
    2:begin cmd_name="CACHE";cmd_id=7'd6;end
    3:begin cmd_name="GEN";cmd_id=7'd11;end
    4:begin cmd_name="UNDERFLOW";cmd_id=7'd32;end
    5:begin cmd_name="VUNDERFLOW";cmd_id=7'd34;end
    6:begin cmd_name="FAULT";cmd_id=7'd10;end
    7:begin cmd_name="PRESENTATION";cmd_id=7'd19;end
    8:begin cmd_name="INTEGRITY";cmd_id=7'd14;end
    9:begin cmd_name="LEVEL";cmd_id=7'd15;end
    10:begin cmd_name="RECOVERY";cmd_id=7'd21;end
    11:begin cmd_name="RETRIES";cmd_id=7'd23;end
    12:begin cmd_name="REJECTED";cmd_id=7'd22;end
    13:begin cmd_name="IDLOW";cmd_id=7'd13;end
    14:begin cmd_name="IDHIGH";cmd_id=7'd12;end
    15:begin cmd_name="BADERROR";cmd_id=7'd3;end
    16:begin cmd_name="BADID";cmd_id=7'd4;end
    17:begin cmd_name="WAVFALLBACK";cmd_id=7'd35;end
    18:begin cmd_name="OVERFLOW";cmd_id=7'd17;end
    19:begin cmd_name="EVENTDROP";cmd_id=7'd8;end
    20:begin cmd_name="UARTREJECT";cmd_id=7'd31;end
    21:begin cmd_name="UARTFRAME";cmd_id=7'd29;end
    22:begin cmd_name="UARTOVERRUN";cmd_id=7'd30;end
    23:begin cmd_name="UARTDROP";cmd_id=7'd28;end
    24:begin cmd_name="UNKNOWN";cmd_id=0;end
    25:begin cmd_name="BRIGHT";cmd_id=5;end
    26:begin cmd_name="STATUS";cmd_id=27;cmd_query=0;end
    27:begin cmd_name="STATUS";cmd_id=27;cmd_target=67;end
    28:begin cmd_name="STATUS";cmd_id=27;cmd_valid=0;end
   endcase
   @(posedge dut.sys_clk);#0.001;comparisons=comparisons+3;
   if(dut.b_reply!==ref_reply || dut.b_reply_code!==ref_code || dut.b_reply_value!==ref_value)begin errors=errors+1;if(errors<10)$display("[FAIL] exact old board query differs name=%s id=%0d",cmd_name,cmd_id);end
  end
  if(errors==0)$display("[PASS] all24 numeric board queries match original ASCII block cycle exact");
  $display("[TB] tb_v3_board_query_catalog done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] board query oracle watchdog errors=1");$finish;end
endmodule
