`timescale 1ns/1ps
module tb_v3_progress_top176;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 wire txd;wire[3:0]led;wire scl;tri sda;
 safevision_v3_top dut(.clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),
 .uart_rxd(1'b1),.uart_txd(txd),.led(led),.sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),
 .HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_handbook_status_text.mem";
 reg[47:0]mem_source=0;reg[203:0]ref_source=0;
 reg[31:0]old_transactions=0,old_bytes=0;reg[3:0]old_state=0;
 wire expected_mem=dut.mem_status_valid && old_transactions!=dut.mem_status_sys[47:16];
 wire expected_media=dut.ref_status_valid && (old_bytes!=dut.ref_status_sys[79:48]||old_state!=dut.ref_status_sys[15:12]);


 always@(posedge dut.sys_clk or negedge dut.sys_media_rst_n)begin
  if(!dut.sys_media_rst_n)begin old_transactions<=0;old_bytes<=0;old_state<=0;end
  else begin
   if(dut.mem_status_valid)old_transactions<=dut.mem_status_sys[47:16];
   if(dut.ref_status_valid)begin old_bytes<=dut.ref_status_sys[79:48];old_state<=dut.ref_status_sys[15:12];end
  end
 end
 integer errors=0,comparisons=0,k;reg[31:0]rng=32'h176a4bc3;
 always@(posedge dut.sys_clk or negedge dut.sys_clk)begin #0.001;
  if(dut.sys_media_rst_n===1'b0||dut.sys_media_rst_n===1'b1)begin
   comparisons = comparisons + 1;
   if(dut.media_active_predecoded!==(dut.ref_status_sys[15:12]>=2 && dut.ref_status_sys[15:12]!=7 && dut.ref_status_sys[15:12]!=10 && dut.ref_status_sys[15:12]!=11))begin
    errors = errors + 1;if(errors<8)$display("[FAIL] actual media-active predicate differs from same-edge captured state");
   end
   if({dut.mem_progress,dut.media_progress,dut.observed_transactions,dut.observed_bytes,dut.observed_state}!==
      {expected_mem,expected_media,old_transactions,old_bytes,old_state})begin
    errors = errors + 1;if(errors<8)$display("[FAIL] actual top progress/observer mismatch k=%0d reset=%b got=%b%b want=%b%b",k,dut.sys_media_rst_n,dut.mem_progress,dut.media_progress,expected_mem,expected_media);
   end
  end
 end
 initial begin
  force dut.mem_status_data=mem_source;force dut.ref_status_data=ref_source;
  repeat(10)@(negedge clk);rst_n=1;wait(dut.sys_rst_n);
  for(k=0;k<50000;k = k + 1)begin
   @(negedge dut.sys_clk);
   rng=rng*1664525+1013904223;
   if(k%7!=0)mem_source[47:16]=rng;
   rng=rng*1664525+1013904223;
   if(k%5!=0)ref_source[79:48]=rng;
   ref_source[15:12]=k%5;
   if(k%197==0)begin #2;rst_n=0;#1;rst_n=1;end
   if(k%211==0)begin mem_source=0;ref_source=0;end
  end
  repeat(10)@(negedge clk);
  if(errors==0)$display("[PASS] production top,capture/reset/first-valid epochs and original observer edge behavior;50000random source changes including hold/clear/wrap and asynchronous KEY1 resets");
  $display("PASS tb_v3_progress_top176 comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #2000000;$display("[FAIL] actual top progress watchdog errors=1");$finish;end
endmodule
