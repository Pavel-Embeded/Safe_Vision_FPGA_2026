// Board control fault injection, not real card/vendor-IP/SDRAM AC validation.
// Uses actual board RTL and independent 50/100/125/pixel/serial clocks.
// Producer completion and video/ready are injected deliberately; scan, mailbox,
// ownership, AXIS queue and transmitter/PHY reset wiring remain actual RTL.
`timescale 1ns/1ps
module tb_safevision_board_recovery;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0;
 wire uart_txd;wire [3:0] led;wire cs,sclk,mosi,d0,d1,d2,dc,ddc;
 wire sda;
 safevision_top #(.HD(0),.MODE_TO_N(32'd100),.RPT_PERIOD_N(32'd1000000),
   .FONT_FILE("font8x16.mem")) dut(
   .clk(clk),.rst_n(rst_n),.btn_next(1'b1),.btn_auto(1'b1),
   .uart_txd(uart_txd),.led(led),.sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),
   .sd_miso(1'b1),.HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),
   .HDMI_CLK_P(dc),.HDMI_DDC_SCL(ddc),.HDMI_DDC_SDA(sda));
 integer errors=0,checks=0,frames=0,accepted=0,expected_count=4,resyncs=0,scan_steps=0;
 task check(input bit ok,input string msg);
 begin checks=checks+1;if(ok)$display("[PASS] %s",msg);
   else begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 reg card_available=0,busy=0,swap_busy=0,fb_done=0,fb_event=0,sk_event=0;
 reg [1:0] sk_slot=2;reg sk_crc=1;
 reg [10:0] observed[0:3];
 reg [23:0] video_rgb=0;reg video_de=0,ready=1;
 reg [11:0] video_x=0,video_y=0;
 reg [25:0] expected[0:7],held;
 reg score_enable=0,watch_scan=0;
 reg [11:0] previous_scan_x;
 integer short_base,frame_base,i;

 always @(posedge dut.sys_clk)if(dut.sys_rst_n&&dut.frame_ready)begin
   observed[frames]={dut.crc_sys,dut.slot_sys,dut.gen_sys};frames=frames+1;
   if(frames>3)$fatal(1,"Unexpected extra mailbox publication");
 end
 always @(posedge dut.pixel_clk)begin
   if(score_enable&&dut.axis_valid&&dut.axis_ready)begin
     if(accepted>=expected_count)$fatal(1,"Unexpected AXIS beat during bounded-stall test");
     if({dut.axis_user,dut.axis_last,dut.axis_data}!==expected[accepted])
       $fatal(1,"AXIS ordering/tag mismatch beat=%0d",accepted);
     accepted=accepted+1;
   end
   if(watch_scan)begin
     if(dut.core.scan_x!==((previous_scan_x==799)?0:previous_scan_x+1))
       $fatal(1,"Native scan stopped or skipped during HDMI fault");
     scan_steps=scan_steps+1;
   end
   previous_scan_x=dut.core.scan_x;
   #0.001;if(dut.hdmi_resync)resyncs=resyncs+1;
 end
 task mem_edges(input integer n);begin repeat(n)@(posedge dut.mem_clk);#0.001;end endtask
 task pixel(input bit de,input integer x,input integer y,input [23:0] rgb);
 begin @(negedge dut.pixel_clk);video_de=de;video_x=x;video_y=y;video_rgb=rgb;
   @(posedge dut.pixel_clk);#0.002;end endtask

 // Check the actual asynchronous reset assertion and two serial-clock release
 // edges. No claimed physical PLL jitter/metastability simulation is implied.
 reg reset_watch_done=0;
 initial begin
   wait(dut.hdmi_resync===1);#0.001;
   check(dut.tx_reset===1,"overflow drives transmitter reset");
   check(dut.phy_rst_n===0&&dut.serializer.I_rst===1,
     "overflow asynchronously asserts serial PHY reset");
   @(negedge dut.tx_reset);
   @(posedge dut.serial_clk);#0.001;
   check(dut.phy_rst_n===0,"PHY reset remains asserted at first serial release edge");
   @(posedge dut.serial_clk);#0.001;
   check(dut.phy_rst_n===1&&dut.serializer.I_rst===0,
     "PHY reset releases at second serial edge");reset_watch_done=1;
 end

 initial begin
   // Disable real frame writers, inject completion metadata/events at their
   // documented boundary. The publisher/mailbox/ownership logic is not forced.
   force dut.pl_card_usable=card_available;
   force dut.pl_frame_active=1'b0;
   force dut.sk_wr_req=1'b0;force dut.fb_wr_req=1'b0;
   force dut.prod_wr_busy=busy;force dut.swap_busy_mem=swap_busy;
   force dut.fb_submitted=fb_done;force dut.fb_toggle=fb_event;
   force dut.fb_crc_ok=1'b1;force dut.sk_swap_toggle=sk_event;
   force dut.sk_swap_slot=sk_slot;force dut.sk_swap_crc_ok=sk_crc;
   force dut.sk_swap_gen=8'ha5;
   force dut.rgb=video_rgb;force dut.out_de=video_de;
   force dut.out_x=video_x;force dut.out_y=video_y;
   force dut.axis_ready=ready;
   repeat(10)@(posedge clk);@(negedge clk);rst_n=1;
   wait(dut.mem_rst_n&&dut.pixel_rst_n&&dut.sys_rst_n&&dut.sdr_init_done);
   wait(dut.card_mode===0);mem_edges(8);
   check(dut.fb_go===1,"card timeout selects fallback writer ownership");
   check(frames==0&&dut.publish_toggle==0,"no frame publishes before a completed producer");
   @(negedge dut.mem_clk);sk_event=1;mem_edges(12);
   check(frames==0&&dut.publish_toggle==0,"unselected card toggle is consumed without publication");
   @(negedge dut.mem_clk);card_available=1;mem_edges(12);
   check(dut.t_card===1&&dut.card_mode===0,
     "late card is held off while fallback has no swap acknowledgement");
   @(negedge dut.mem_clk);fb_done=1;fb_event=1;
   wait(frames==1);mem_edges(12);
   check(observed[0]=={1'b1,2'd0,8'd1},"fallback slot CRC and generation arrive atomically in SYS");
   check(dut.card_mode===0&&dut.fb_swap_acked===0,
     "fallback publish alone cannot authorize late-card takeover");
   @(negedge dut.mem_clk);sk_event=0;swap_busy=1;mem_edges(6);
   check(dut.fb_swap_seen===1&&dut.card_mode===0,"swap-busy assertion retains fallback ownership");
   @(negedge dut.mem_clk);busy=1;swap_busy=0;mem_edges(6);
   check(dut.fb_swap_acked===1&&dut.card_mode===0,
     "acknowledged fallback still fences an in-flight writer");
   frame_base=frames;@(negedge dut.mem_clk);busy=0;mem_edges(20);
   check(dut.card_mode===1,"idle writer and acknowledged fallback allow late-card takeover");
   check(frames==frame_base&&dut.publish_toggle==1,
     "owner change between opposite source toggles creates no false event");
   @(negedge dut.mem_clk);sk_slot=2;sk_crc=1;mem_edges(4);
   check(frames==1,"metadata changes without a producer event do not publish");
   @(negedge dut.mem_clk);sk_event=1;wait(frames==2);mem_edges(20);
   check(observed[1]=={1'b1,2'd2,8'd2},"card metadata publishes once with shared monotonic generation");
   check(frames==2&&dut.submit_valid===0&&dut.submit_ready===1,
     "mailbox acknowledgement drains the selected event with no duplicates");

   expected[0]={1'b1,1'b0,24'h102030};expected[1]={1'b0,1'b1,24'h405060};
   expected[2]={1'b0,1'b0,24'h708090};expected[3]={1'b0,1'b0,24'ha0b0c0};
   score_enable=1;ready=0;
   pixel(1,0,0,24'h102030);held={dut.axis_user,dut.axis_last,dut.axis_data};
   check(dut.axis_valid&&held==expected[0],"SOF is queued before a short receiver stall");
   pixel(1,639,0,24'h405060);
   check(dut.axis_valid&&{dut.axis_user,dut.axis_last,dut.axis_data}===held,
     "AXIS data SOF and EOL stay stable under stall edge 1");
   pixel(1,0,1,24'h708090);
   check(dut.axis_valid&&{dut.axis_user,dut.axis_last,dut.axis_data}===held,
     "AXIS data SOF and EOL stay stable under stall edge 2");
   pixel(1,1,1,24'ha0b0c0);
   check(dut.axis_valid&&{dut.axis_user,dut.axis_last,dut.axis_data}===held,
     "AXIS data SOF and EOL stay stable under stall edge 3");
   @(negedge dut.pixel_clk);ready=1;video_de=0;
   repeat(6)@(posedge dut.pixel_clk);#0.002;
   check(accepted==4&&dut.hdmi_queue_level==0&&dut.hdmi_dropped_frames==0,
     "bounded stall preserves all four ordered beats including EOL");
   expected[4]={1'b0,1'b1,24'hc01020};expected[5]={1'b0,1'b0,24'hd03040};
   expected_count=6;ready=0;
   pixel(1,639,1,24'hc01020);held={dut.axis_user,dut.axis_last,dut.axis_data};
   check(dut.axis_valid&&held==expected[4],"EOL beat is queued before receiver stall");
   pixel(1,0,2,24'hd03040);
   check(dut.axis_valid&&dut.axis_last&&{dut.axis_user,dut.axis_last,dut.axis_data}===held,
     "asserted EOL tag and data remain stable under receiver stall");
   @(negedge dut.pixel_clk);video_de=0;ready=1;
   repeat(4)@(posedge dut.pixel_clk);#0.002;
   check(accepted==6&&dut.hdmi_queue_level==0&&dut.hdmi_dropped_frames==0,
     "stalled EOL and following line restart drain in exact order");
   score_enable=0;watch_scan=1;ready=0;
   for(i=0;i<20;i=i+1)pixel(1,100+i,2,24'h550000+i);
   check(resyncs==1&&dut.hdmi_dropped_frames==1&&dut.hdmi_backpressure===1,
     "long stall produces exactly one overflow drop and sticky fault");
   check(dut.hdmi_queue_level==0&&dut.hdmi_queue.wait_sof===1,
     "overflow clears the damaged stream and waits for fresh SOF");
   check(reset_watch_done,"serial-domain reset recovery completed");
   @(negedge dut.pixel_clk);ready=1;
   for(i=0;i<12;i=i+1)begin
     pixel(1,300+i,3,24'h660000+i);
     if(dut.axis_valid)$fatal(1,"Mid-frame beat escaped recovery SOF fence");
   end
   check(dut.hdmi_queue_level==0&&dut.hdmi_dropped_frames==1,
     "receiver ready cannot restart an incomplete frame");
   pixel(1,0,0,24'habcdef);
   check(dut.axis_valid&&dut.axis_user&&dut.axis_data==24'habcdef,
     "recovery resumes on a complete new-frame SOF");
   pixel(0,1,0,0);pixel(0,2,0,0);
   check(dut.hdmi_queue_level==0&&dut.hdmi_resync==0&&dut.phy_rst_n==1,
     "post-recovery SOF drains and both transmitter and PHY leave reset");
   check(scan_steps>=34,"native fixed-rate scan continues through stalls overflow and recovery");
   check(frames==2,"HDMI recovery does not duplicate memory-frame publications");
   check(dut.memory_ip.protocol_errors==0&&dut.memory_ip.write_bursts==0&&dut.memory_ip.read_bursts==0,
     "control injection scope performs no physical memory transaction");

   // A lost SYS swap ACK can coexist with a committed PIX slot. Local player
   // restart must not recycle that slot; only the common reset clears the fence.
   force dut.pl_fail_stage=4'd1;
   force dut.sk_ec=8'hf1;repeat(12)@(posedge clk);#0.001;
   check(dut.player.mem_ready===0,"F1 swap ambiguity fences new frame admission");
   force dut.btn_next_db=1'b1;#0.001;
   check(dut.player.restart===0,"F1 swap ambiguity blocks local KEY2 restart");
   release dut.pl_frame_active;
   force dut.player.state_o=4'd10;@(posedge clk);#0.001;release dut.player.state_o;
   repeat(12)@(posedge clk);#0.001;
   check(dut.player.state_o===4'd10&&dut.pl_frame_active===0,
     "failed player remains stopped without launching another frame");
   release dut.sk_ec;repeat(12)@(posedge clk);#0.001;
   check(dut.player.restart===0&&dut.player.mem_ready===0,
     "clearing F1 telemetry cannot bypass the latched slot-ownership fence");
   release dut.btn_next_db;watch_scan=0;
   @(negedge clk);rst_n=0;card_available=1;sk_event=0;fb_event=0;fb_done=0;
   repeat(6)@(posedge clk);@(negedge clk);rst_n=1;
   wait(dut.sdr_init_done&&dut.sk_mem_ready&&dut.card_mode);
   repeat(12)@(posedge clk);#0.001;
   force dut.pl_fail_stage=4'd7;force dut.btn_next_db=1'b1;#0.001;
   check(dut.player.restart===0,"KEY2 cannot retry an aborted media stream with dirty child state");
   force dut.pl_fail_stage=4'd1;#0.001;
   check(dut.player.restart===1&&dut.player.mem_ready===1,
     "common KEY1 reset restores INIT-only KEY2 retry and frame admission");
   release dut.btn_next_db;release dut.pl_fail_stage;
   if(errors)$fatal(1,"BOARD RECOVERY FAILED checks=%0d errors=%0d",checks,errors);
   $display("[PASS] BOARD RECOVERY checks=%0d mailbox_frames=%0d AXIS_beats=%0d scan_edges=%0d",checks,frames,accepted,scan_steps);
   $finish;
 end
 initial begin #1000000;$fatal(1,"Board recovery watchdog");end
endmodule
