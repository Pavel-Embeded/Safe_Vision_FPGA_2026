// Actual board memory profile (50MHz/8ns), adapter, DMA, FIFO and pixel scan.
// Preload the memory model to isolate display bandwidth from SD loading time.
// Every image pixel is compared at the accepted HDMI AXIS boundary.
`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_safevision_memory_display #(parameter integer HD=0,RD_LAT=4,WR_LOAD=0);
 reg clk=0;always #10 clk=~clk;reg rst_n=0;
 wire cs,sck,mosi,uart;wire[3:0]led;wire d0,d1,d2,dc,scl;tri1 sda;
 safevision_top #(.HD(HD),.FONT_FILE("font8x16.mem")) dut(.clk(clk),.rst_n(rst_n),
  .btn_next(1'b1),.btn_auto(1'b1),.btn_emergency(1'b1),.uart_txd(uart),.led(led),
  .sd_ncs(cs),.sd_dclk(sck),.sd_mosi(mosi),.sd_miso(1'b1),
  .HDMI_D0_P(d0),.HDMI_D1_P(d1),.HDMI_D2_P(d2),.HDMI_CLK_P(dc),
  .HDMI_DDC_SCL(scl),.HDMI_DDC_SDA(sda));
 defparam dut.memory_ip.RD_LAT=RD_LAT;
 function [15:0] pixel(input integer x,y);
  reg[7:0]r,g,b;begin r=x^y;g=x+y;b=(x*3)^(y*5)^((x>>8)<<6)^((y>>8)<<5);pixel={r[7:3],g[7:2],b[7:3]};end
 endfunction
 function [23:0] expand(input[15:0]p);begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
 integer i,x,y,k=0,frames=0,compared=0;reg compare=0;
 localparam integer CW=HD?1280:640,CH=HD?720:480,OX=HD?320:0,OY=HD?120:0;
 reg[23:0]expected;
 reg write_req=0,stop_load=0;reg[31:0]write_addr=0,write_data=0;
 integer write_offers=0,write_index=0;
 initial if(WR_LOAD==1)begin
  force dut.prod_wr_req=write_req;force dut.prod_wr_addr=write_addr;
  force dut.prod_wr_data=write_data;force dut.prod_wr_len=16'd1;
  wait(dut.active);
  while(!stop_load)begin
   @(negedge dut.mem_clk);write_addr=`SV_IMG0_BASE+write_index*4;
   write_data=32'hfeca0000+write_index;write_req=1;
   do @(posedge dut.mem_clk);while(!dut.prod_wr_ack);
   @(negedge dut.mem_clk);write_req=0;
   // The writer's data stays stable until physical word acceptance/busy end.
   wait(!dut.prod_wr_busy);write_offers=write_offers+1;write_index=write_index+1;
   if(write_index==153600)write_index=0;
   // At most 0.5 million words/s (2 MB/s RGB565) before arbitration stalls:
   // comparable to a 25 Mbit/s SD/BMP producer; accepted writes cannot vanish.
   repeat(100)@(negedge dut.mem_clk);
  end
 end
 reg stream_valid=0,stream_done=0;reg[31:0]stream_word=0;
 initial if(WR_LOAD==2)begin
  // Drive the real board sink/FIFO/frame writer with a fast queued pixel
  // source. A grant-based completion corrupts words under DMA contention.
  force dut.pl_slot=0;force dut.pl_top_down=1;
  force dut.pl_px_word_valid=stream_valid;force dut.pl_px_word=stream_word;
  wait(dut.active);force dut.pl_frame_active=1;
  // Frame-active is synchronized before the sink leaves its idle drain mode.
  // Real BMP headers provide this delay; this direct source waits explicitly.
  wait(dut.sk_state==4'd1);
  for(write_index=0;write_index<153600;write_index=write_index+1)begin
   @(negedge clk);stream_word=32'hfeca0000+write_index;stream_valid=1;
   do @(posedge clk);while(!dut.pl_px_word_ready);
   @(negedge clk);stream_valid=0;write_offers=write_offers+1;
  end
  stream_done=1;
 end
 always @(posedge dut.pixel_clk)if(dut.axis_valid&&dut.axis_ready)begin
  if(dut.axis_user)begin compare=(frames<3)&&dut.active&&!dut.safety_active&&!dut.frame_fault;k=0;end
  if(compare)begin
   x=k%CW;y=k/CW;
   expected=(x>=OX&&x<OX+640&&y>=OY&&y<OY+480)?expand(pixel(x-OX,y-OY)):24'd0;
   if(dut.axis_data!==expected)$fatal(1,"HD=%0d display mismatch (%0d,%0d) got=%06x expected=%06x",HD,x,y,dut.axis_data,expected);
   if(dut.axis_last!==(x==CW-1))$fatal(1,"Wrong EOL");
   if(x>=OX&&x<OX+640&&y>=OY&&y<OY+480)compared=compared+1;
   k=k+1;
   if(k==CW*CH)begin frames=frames+1;compare=0;
    $display("[PASS] MEMORY DISPLAY HD=%0d frame=%0d media_pixels=%0d",HD,frames,compared);end
  end
 end
 initial begin
  force dut.pl_card_usable=1;force dut.pl_state=4'd7;force dut.pl_frame_active=0;
  force dut.sk_swap_slot=2'd1;force dut.sk_swap_crc_ok=1;force dut.sk_swap_gen=1;force dut.sk_swap_toggle=0;
  for(i=0;i<153600;i=i+1)begin
   dut.memory_ip.mem[(`SV_IMG1_BASE>>2)+i]={pixel((2*i+1)%640,(2*i+1)/640),pixel((2*i)%640,(2*i)/640)};
  end
  #200;rst_n=1;wait(dut.adapter_init);repeat(20)@(posedge dut.mem_clk);
  force dut.sk_swap_toggle=1;
  wait(frames==3);
  if(WR_LOAD)begin
   if(WR_LOAD==2)begin wait(stream_done);wait(dut.sk_px_written==307200);end
   stop_load=1;wait(!dut.prod_wr_req&&!dut.prod_wr_busy&&dut.adapter_write_idle);
   if(write_offers<1000||dut.memory_ip.stored_words!=write_offers)$fatal(1,"Concurrent write loss offers=%0d stored=%0d",write_offers,dut.memory_ip.stored_words);
   for(i=0;i<write_offers;i=i+1)
    if(dut.memory_ip.mem[(`SV_IMG0_BASE>>2)+i]!==32'hfeca0000+i)$fatal(1,"Concurrent write data mismatch at %0d",i);
   $display("[PASS] CONCURRENT SD-RATE WRITE HD=%0d words=%0d bytes=%0d U=%0d O=%0d",HD,write_offers,write_offers*4,dut.underflows,dut.overflows);
  end
  if(dut.underflows||dut.overflows||dut.memory_error||dut.adapter_fault||dut.memory_ip.protocol_errors||dut.hdmi_backpressure)
   $fatal(1,"HD=%0d bandwidth/contract failure U=%0d O=%0d mem=%b",HD,dut.underflows,dut.overflows,dut.memory_error);
  if(compared!=921600)$fatal(1,"Incomplete pixel comparison");
  $display("[PASS] MEMORY BANDWIDTH HD=%0d clocks=50MHz/8ns frames=%0d pixels=%0d underflows=0 overflows=0 physical_read_bursts=%0d",HD,frames,compared,dut.memory_ip.read_bursts);$finish;
 end
 initial begin #120000000;$fatal(1,"Memory display watchdog HD=%0d frames=%0d active=%b safety=%b U=%0d O=%0d state=%0d level=%0d DMA=%0d memory_fault=%b",HD,frames,dut.active,dut.safety_active,dut.underflows,dut.overflows,dut.core.display.mem_fetch_state,dut.core.display.mem_fifo_pixels,dut.core.display.mem_dma_bytes,dut.memory_error);end
endmodule
