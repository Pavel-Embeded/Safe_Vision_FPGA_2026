`timescale 1ns/1ps
module tb_v3_handbook_cfg_atomic;
 reg sys=0,mem=0,pix=0,rst=0,cvalid=0,fs=0;always #5 sys=~sys;always #10 mem=~mem;always #6.734 pix=~pix;
 reg[98:0]cfg=0;wire ready;reg[98:0]observed=0;reg old_fs;
 reg[31:0]seed=32'h6b7c2618;integer errors=0,comparisons=0,k,j;
 v3_video_display_core #(.HD(1),.HANDBOOK_PROFILE(1),.PACKED_CACHE(1),
 .COMPACT_FONT_FILE("font8x16_compact.mem"),.STATUS_TEXT_FILE("v3_handbook_status_text.mem")) d(
 .sys_clk(sys),.mem_clk(mem),.pixel_clk(pix),.sys_rst_n(rst),.mem_rst_n(rst),.pixel_rst_n(rst),
 .media_reset(1'b0),.cfg_valid(cvalid),.cfg_ready(ready),.cfg_data(cfg),.cache_valid(4'd0),.next_request(1'b0),.safety_active(1'b1),
 .media_ready(1'b0),.media_ready_generation(8'd0),.rd_ack(1'b0),.rd_busy(1'b0),.rd_data(32'd0),.rd_valid(1'b0),.lookup_crc(32'd0),.lookup_valid(1'b0));
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<8)$display("[FAIL] %s",msg);end end  end endtask
 always @(posedge pix)begin old_fs=fs;#1;
  if(rst)begin ck(d.cfg===observed||old_fs,"configuration never changes outside the permitted frame boundary");observed=d.cfg;end
  else observed=0;
 end
 initial begin
  force d.frame_start=fs;
  repeat(5)@(negedge sys);rst=1;
  for(k=0;k<96;k = k + 1)begin
   @(negedge sys);while(!ready)@(negedge sys);seed=seed*1664525+1013904223;
   cfg={seed[2:0],seed,seed^32'h7f261801,~seed};cvalid=1;
   @(negedge sys);cvalid=0;
   repeat(25+(k%17))@(negedge pix);ck(d.cfg===observed,"backpressured payload held before frame boundary");
   fs=1;@(negedge pix);fs=0;repeat(3)@(negedge pix);
   ck(d.cfg===cfg,"all99 configuration bits commit together with full payload identity");
  end
  if(errors==0)$display("[PASS]96 asynchronous atomic configuration transfers, frame backpressure and all99 payload bits");
  $display("[TB] tb_v3_handbook_cfg_atomic done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] atomic configuration watchdog errors=1");$finish;end
endmodule
