// Production 100kHz SPI and production timeout constants. A card staying in
// ACMD41 idle for >200ms must finish initialization instead of premature E1.
`timescale 1ns/1ps
module tb_sd_slow_initialization;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire cs,sck,mosi,miso,ready;wire[7:0]ec,ed;wire[3:0]state,stage;
 wire[7:0]polls;
 sd_bmp_player dut(.clk(clk),.rst_n(rst_n),.run(1'b1),.btn_next(1'b0),.btn_auto(1'b0),.restart(1'b0),
  .sd_ncs(cs),.sd_dclk(sck),.sd_mosi(mosi),.sd_miso(miso),.px_word_ready(1'b0),
  .mem_ready(1'b0),.frame_done(1'b0),.last_frame_ok(1'b0),
  .sd_ready(ready),.err_code(ec),.err_detail(ed),.state_o(state),.fail_stage(stage));
 sd_spi_card_model #(.SLOW_INIT_POLLS(200)) card(.cs_n(cs),.sclk(sck),.mosi(mosi),.miso(miso),
  .i_dead(1'b0),.o_acmd41_cnt(polls));
 initial begin
  #200;rst_n=1;
  wait(ready||state==10);
  if(!ready||ec||stage||$time<=200000000||$time>=1000000000)$fatal(1,"Slow SD init failed time=%0t ready=%b state=%d ec=%h",$time,ready,state,ec);
  $display("[PASS] SLOW SD INIT ready_at=%0t ACMD41_polls=%0d SCLK=100kHz outer_timeout=2s",$time,polls);$finish;
 end
 initial begin #1100000000;$fatal(1,"Slow SD card watchdog");end
endmodule
