// Full board scan under absent SDRAM initialization. Verify accepted HDMI AXIS
// pixels and tags, then fault/manual changes at frame boundaries. Vendor HDMI
// and physical memory remain contract models; this is not hardware acceptance.
`timescale 1ns/1ps
module tb_safevision_fault_display;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,manual=1;
 wire uart;wire[3:0]led;wire cs,sck,mosi,d0,d1,d2,dc,scl;tri1 sda;
 safevision_top #(.RESIDENT_FRAMES(0),.STORAGE_INTEGRITY(0),.FONT_FILE("font8x16.mem")) dut(.clk(clk),.rst_n(rst_n),
  .btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(manual),.uart_txd(uart),.led(led),
  .sd_ncs(cs),.sd_dclk(sck),.sd_mosi(mosi),.sd_miso(1'b1),
  .HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),.HDMI_CLK_P(dc),
  .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 integer pixels=0,frames=0,checks=0,k=0;reg started=0;
 reg[23:0] expected_color=24'h00ff00;
 always @(posedge dut.pixel_clk)if(dut.axis_valid&&dut.axis_ready)begin
  if(dut.axis_user)begin
   if(started&&k!=307200)$fatal(1,"Incomplete safety frame: %0d",k);
   started=1;k=0;
   expected_color=dut.safety_level==0?24'h00ff00:(dut.safety_level==1?24'hffff00:24'hff3030);
  end
  if(started)begin
   if(dut.axis_last!==((k%640)==639))$fatal(1,"Wrong EOL at pixel %0d",k);
   if(k==0||k==639||k==306560||k==307199)begin
    if(dut.axis_data!==expected_color)$fatal(1,"Safety border mismatch %0d %06x %06x",k,dut.axis_data,expected_color);
    checks=checks+1;
   end
   if(k==6410)begin
    if(dut.axis_data!==(dut.safety_level<2?24'h001008:24'h180000))$fatal(1,"Safety background mismatch");
    checks=checks+1;
   end
   pixels=pixels+1;k=k+1;if(k==307200)frames=frames+1;
  end
 end
 task boundary;begin @(posedge dut.scan_frame_start);repeat(12)@(posedge dut.pixel_clk);end endtask
 initial begin
  force dut.sdr_init_done=0;
  #200;rst_n=1;
  wait(frames==1);
  if(dut.memory_ip.write_bursts||dut.memory_ip.read_bursts||!dut.safety_active)$fatal(1,"Safety scene used external memory");
  @(negedge clk);manual=0;boundary;
  if(!dut.safety_active||dut.safety_level!=1)$fatal(1,"KEY3 safety level missing");
  wait(frames==2);manual=1;
  force dut.memory_error=1;boundary;
  if(!dut.safety_active||dut.safety_level!=2)$fatal(1,"Memory fault safety level missing");
  wait(frames==3);
  if(dut.tx_reset||dut.hdmi_backpressure||dut.hdmi_dropped_frames)$fatal(1,"Media fault reset or disrupted HDMI");
  if(dut.memory_ip.write_bursts||dut.memory_ip.read_bursts)$fatal(1,"Safety rendering requires SDRAM");
  $display("[PASS] BOARD SAFETY frames=%0d pixels=%0d sample_checks=%0d: absent memory, KEY3, memory fault; complete SOF/EOL; no HDMI reset",frames,pixels,checks);$finish;
 end
 initial begin #100000000;$fatal(1,"Safety display watchdog");end
endmodule
