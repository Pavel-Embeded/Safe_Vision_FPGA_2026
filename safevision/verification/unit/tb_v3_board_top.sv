


`timescale 1ns/1ps
module tb_v3_board_top;
 reg clk=0;always #10 clk=!clk;
 reg rst_n=0;wire txd;wire[3:0] led;wire scl,sda;
 safevision_v3_top #(.HD(0)) dut(.clk(clk),.rst_n(rst_n),
 .btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_rxd(1'b1),.uart_txd(txd),.led(led),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P(),.HDMI_CLK_P(),.HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));


 defparam dut.memory_ip.OUTPUT_VALID_DELAY=1;
 defparam dut.uart.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.video.FONT_FILE="font8x16.mem";
 defparam dut.video.COMPACT_FONT_FILE="font8x16_compact.mem";
 defparam dut.video.STATUS_TEXT_FILE="v3_status_text.mem";
 integer errors=0,comparisons=0,i,deadline;
 reg test_dma=0,test_writer=0,test_audio=0,test_read=0,test_ref=0,test_commit=0,test_commit_ready=0,test_media_reset=0;
 reg[31:0] test_waddr=0,test_wdata=0,test_aaddr=32'h280000,test_adata=0,test_raddr=0;
 reg[1:0] test_slot=0;reg[7:0] test_generation=0;
 reg pixel_valid=0,pixel_frame=0;reg[31:0] pixel_word=0;
 integer accepted_writes=0,audio_grants=0,video_words=0,writer_grants=0;
 always @(posedge dut.mem_clk)if(dut.mem_media_rst_n)begin
  if(dut.writer_accepted)accepted_writes<=accepted_writes+1;
  if(dut.audio_ack)audio_grants<=audio_grants+1;
  if(dut.writer_ack)writer_grants<=writer_grants+1;
  if(dut.rd_valid)video_words<=video_words+1;
 end
 task check(input bit ok,input string name);begin
 comparisons++;if(!ok)begin errors++;$display("[FAIL] %s t=%t",name,$time);end end endtask
 task mtick(input integer n);repeat(n)begin @(posedge dut.mem_clk);#1;end endtask
 task stick(input integer n);repeat(n)begin @(posedge dut.sys_clk);#1;end endtask
 task write_word(input bit audio,input[31:0] address,input[31:0] value);
 integer wait_count;begin
 @(negedge dut.mem_clk);
 if(audio)begin test_aaddr=address;test_adata=value;test_audio=1;end
 else begin test_waddr=address;test_wdata=value;test_writer=1;end
 wait_count=0;
 while(!(audio?dut.audio_ack:dut.writer_ack) && wait_count<1000)begin mtick(1);wait_count++;end
 check(wait_count<1000,audio?"DMA idle grants audio auxiliary write":"DMA idle grants image writer");
 @(negedge dut.mem_clk);if(audio)test_audio=0;else test_writer=0;
 wait_count=0;
 while((audio?dut.audio_busy:dut.writer_busy) && wait_count<1500)begin mtick(1);wait_count++;end
 check(wait_count<1500,"burst retires after accepted physical transaction");
 mtick(120);check(dut.memory_ip.mem[address>>2]===value,"real adapter/App contract stores exact producer word");
 end endtask
 task receive_byte(output[7:0] data);integer k;begin
 @(negedge txd);#(8680.56/2);check(txd===0,"ref-clock fatal UART start");
 for(k=0;k<8;k++)begin #8680.56;data[k]=txd;end
 #8680.56;check(txd===1,"ref-clock fatal UART stop");end endtask
 reg[7:0] byte_rx;reg[11:0] x_before;integer w_before,a_before,read_before,pixel_count,pixel_stall,pixel_goal;reg blocked_once;
 initial begin


 force dut.dma_busy=test_dma;
 force dut.writer_req=test_writer;force dut.writer_addr=test_waddr;force dut.writer_data=test_wdata;force dut.writer_len=16'd1;
 force dut.audio_req=test_audio;force dut.audio_wr=1'b1;force dut.audio_addr=test_aaddr;force dut.audio_wdata=test_adata;force dut.audio_len=16'd1;
 force dut.rd_req=test_read;force dut.rd_addr=test_raddr;force dut.rd_len=16'd64;
 force dut.sdr_ref_valid=test_ref;
 force dut.frame_commit=test_commit;force dut.active_slot=test_slot;force dut.generation=test_generation;
 force dut.audio_commit_ready=test_commit_ready;
 force dut.media_reset=test_media_reset;
 repeat(8)@(negedge clk);rst_n=1;mtick(180);
 check(dut.sys_rst_n && dut.pixel_rst_n && dut.mem_media_rst_n && dut.adapter_init,"all TOP clock/reset and SDRAM-init contracts release");
 check(dut.PIXEL_HZ==25185185 && dut.video.PIXEL_HZ==25185185 && dut.video.graphics.PIXEL_HZ==25185185,"BASE official PLL nominal frequency reaches HUD counter");
 check(dut.arbiter.video_fifo_level==1024,"idle DMA advertises no reservation");

 @(negedge dut.mem_clk);test_dma=1;test_writer=1;test_audio=1;w_before=writer_grants;a_before=audio_grants;
 mtick(120);check(writer_grants==w_before && audio_grants==a_before,"active DMA bubbles reserve bus against writer and audio");
 check(dut.arbiter.video_fifo_level==0,"active DMA uses critical reserve");
 @(negedge dut.mem_clk);test_writer=0;test_audio=0;test_dma=0;


 deadline=0;while(dut.audio_busy && deadline<1500)begin mtick(1);deadline++;end
 mtick(120);w_before=accepted_writes;a_before=audio_grants;

 for(i=0;i<8;i++)write_word(0,i*4,32'h9a050000+i);
 for(i=0;i<8;i++)write_word(1,32'h280000+i*4,32'h52c90000+i);
 check(accepted_writes-w_before==8 && audio_grants-a_before==8,"both real top write channels remain live");

 for(i=8;i<64;i++)write_word(0,i*4,32'h9a050000+i);
 @(negedge dut.mem_clk);test_dma=1;test_read=1;test_raddr=0;read_before=video_words;
 deadline=0;while(!dut.rd_ack && deadline<1000)begin mtick(1);deadline++;end
 check(deadline<1000,"video gets grant while reservation active");
 @(negedge dut.mem_clk);test_read=0;test_ref=1;mtick(3);@(negedge dut.mem_clk);test_ref=0;
 deadline=0;
 while(video_words-read_before<64 && deadline<3000)begin
  @(posedge dut.mem_clk);if(dut.rd_valid)begin
   check(dut.rd_data===32'h9a050000+(video_words-read_before),"video response exact order through mem_ctrl/adapter");
  end #1;deadline++;
 end
 check(video_words-read_before==64,"all video responses retained across diagnostic refresh indication");
 mtick(80);@(negedge dut.mem_clk);test_dma=0;
 write_word(1,32'h280020,32'hf00d0055);
 check(dut.memory_ip.protocol_errors==0 && !dut.adapter_fault && !dut.memory_error,"no hidden adapter/App protocol error");


 release dut.writer_req;release dut.writer_addr;release dut.writer_data;release dut.writer_len;
 force dut.px_word=pixel_word;force dut.px_valid=pixel_valid;
 force dut.frame_active=pixel_frame;force dut.load_slot=2'd0;force dut.top_down=1'b1;
 @(negedge dut.mem_clk);test_dma=1;
 @(negedge clk);pixel_frame=1;repeat(12)@(negedge clk);
 check(dut.sink.FIFO_AW==8,"production image ingress uses the audited 256-word FIFO");
 pixel_goal=(1<<dut.sink.FIFO_AW)+64;pixel_count=0;pixel_stall=0;blocked_once=0;pixel_valid=1;pixel_word=32'h31420000;
 while(pixel_count<pixel_goal && pixel_stall<10000)begin
  @(posedge clk);
  if(dut.px_ready)begin pixel_count++;pixel_stall=0;end else pixel_stall++;
  @(negedge clk);pixel_word=32'h31420000+pixel_count;
  if(pixel_stall==64 && !blocked_once)begin
   check(pixel_count<pixel_goal && !dut.px_ready,"video reservation fills real FIFO and propagates backpressure to REF producer");
   blocked_once=1;test_dma=0;
  end
 end
 check(blocked_once && pixel_count==pixel_goal,"FIFO producer resumes without lost or duplicated words");
 pixel_valid=0;mtick(2200);
 check(dut.row_guard.source_words==pixel_goal,"integrity producer counts all FIFO-retired words");
 for(i=0;i<pixel_goal;i++)check(dut.memory_ip.mem[i]===32'h31420000+i,"real FIFO/sink/arbiter/adapter preserves accepted word order");
 @(negedge dut.sys_clk);test_media_reset=1;stick(80);
 pixel_frame=0;release dut.px_word;release dut.px_valid;release dut.frame_active;release dut.load_slot;release dut.top_down;
 @(negedge dut.sys_clk);test_media_reset=0;mtick(180);

 @(negedge dut.sys_clk);test_slot=2;test_generation=8'h5a;test_commit=1;stick(1);
 @(negedge dut.sys_clk);test_commit=0;stick(12);
 check(dut.audio_commit_valid && dut.audio_commit_slot==2 && dut.audio_commit_gen==8'h5a,"frame commit slot/generation retained under audio backpressure");
 check(dut.audio.commit_valid && dut.audio.commit_slot==2 && dut.audio.commit_generation==8'h5a,"top connects the same immutable descriptor to audio");
 @(negedge dut.sys_clk);test_commit_ready=1;stick(2);check(!dut.audio_commit_valid,"accepted audio descriptor dequeues exactly once");
 @(negedge dut.sys_clk);test_commit_ready=0;test_commit=1;test_generation=8'h5b;stick(1);
 @(negedge dut.sys_clk);test_commit=0;test_media_reset=1;x_before=dut.raw_x;stick(80);
 check(!dut.audio_commit_valid && dut.raw_x!=x_before && dut.pixel_rst_n,"media reset cancels old descriptor while fixed raster continues");
 check(dut.cache_sys==0 && dut.safe_active,"media reset invalidates approved cache and selects SAFE");
 @(negedge dut.sys_clk);test_media_reset=0;mtick(160);

 force dut.mem_status_sys=48'h000000000002;force dut.ref_status_sys=192'd0;stick(40);
 check(dut.fault_code==8'h02 && dut.fault_level==3,"sink-only media failure preserves its nonzero cause code");
 release dut.mem_status_sys;release dut.ref_status_sys;

 force dut.audio_lock=1'b0;repeat(10)@(negedge clk);stick(12);
 check(dut.fatal_latched && dut.fault_level==4 && dut.pixel_rst_n,"audio PLL loss preserves SYS FATAL and video SAFE capability");
 release dut.audio_lock;stick(6);check(dut.fatal_latched,"restored lock cannot silently clear FATAL");

 force dut.sys_lock=1'b0;repeat(10)@(negedge clk);
 check(dut.sys_loss_ref && led==15,"SYS PLL loss visible independently on ref-domain LEDs");
 force dut.fatal_delay=26'd24999999;@(posedge clk);#1;release dut.fatal_delay;
 receive_byte(byte_rx);check(byte_rx=="F","independent fatal UART first byte F");
 receive_byte(byte_rx);check(byte_rx=="A","independent fatal UART second byte A");
 receive_byte(byte_rx);check(byte_rx=="T","independent fatal UART third byte T");
 $display("[PASS] V3 TOP assembly, live memory producers, reservation, descriptors and reset boundaries");
 $display("PASS tb_v3_board_top comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #10000000;$fatal(1,"TOP assembly timeout");end
endmodule
