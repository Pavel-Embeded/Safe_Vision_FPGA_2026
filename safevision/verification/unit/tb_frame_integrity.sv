`timescale 1ns/1ps
module tb_frame_integrity #(parameter integer ACK_FIRST=0,RESPONSE_GAP=2,SOURCE_GAP=0,HEADER_LATE=0);
 reg clk=0;always #12.5 clk=~clk;
 reg rst_n=0,begin_frame=0,td=1,accepted=0,verify_start=0,dma_start=0;
 reg [1:0] slot=0;reg [31:0] wa=0,wd=0;
 wire done,pass,gfault,greq,dreq,dfault,active,ddone,lookup_valid,we;
 wire [31:0] ga,da,lookup_crc,gba,gexp,ggot,dba,dexp,dgot,words,bytes;
 wire [15:0] blocks,pixel,len;
 reg ack=0,busy=0,valid=0,drop=0;reg [31:0] data=0;
 reg [31:0] memory[0:255];integer phase=1,pending=0,index=0,delay_count=0;
 reg [31:0] target_addr;integer checks=0,pixels=0,errors=0;
 reg [15:0] fifo_level=0;
 reg compare_pixels=0,play_completed=0;
 function integer physical_index(input [31:0] address);
   physical_index=(address>=32'h000a0000 ? 128:0)+((address>=32'h000a0000 ? address-32'h000a0000:address)>>2);
 endfunction
 frame_integrity_guard #(.WORDS(128),.ROW_WORDS(64),.TIMEOUT(2000)) guard(
   .clk(clk),.rst_n(rst_n),.frame_abort(1'b0),.frame_begin(begin_frame),.frame_slot(slot),.top_down(td),
   .accepted(accepted),.write_addr(wa),.write_data(wd),.verify_start(verify_start),.verify_allow(1'b1),
   .verify_done(done),.verify_pass(pass),.fault(gfault),.rd_req(greq),.rd_addr(ga),.rd_len(),
   .rd_ack(ack&&phase==1),.rd_busy(busy),.rd_data(data),.rd_valid(valid&&phase==1),
   .lookup_addr(da),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),.bad_addr(gba),
   .bad_expected(gexp),.bad_actual(ggot),.source_words(words),.checked_blocks(blocks));
 video_read_dma_checked #(.FRAME_WORDS(128),.PIX_DEPTH(512),.LOW_WATER(500),.WAIT_TIMEOUT(2000)) dma(
   .clk(clk),.rst_n(rst_n),.start(dma_start),.frame_base(slot[0]?32'h000a0000:0),.pix_fifo_level(fifo_level),
   .rd_req(dreq),.rd_addr(da),.rd_len(len),.rd_ack(ack&&phase==2),.rd_busy(busy),
   .rd_data(data),.rd_data_valid(valid&&phase==2),.expected_crc(lookup_crc),.expected_valid(lookup_valid),
   .fifo_wr_data(pixel),.fifo_wr_en(we),.rd_bytes_cnt(bytes),.active(active),.done(ddone),
   .fault(dfault),.bad_addr(dba),.bad_expected(dexp),.bad_actual(dgot));
 always @(posedge clk)begin
   ack<=0;valid<=0;
   if(!rst_n)begin busy<=0;pending=0;index=0;delay_count=0;end
   else if(!busy&&((phase==1&&greq)||(phase==2&&dreq)))begin
     ack<=1;busy<=1;target_addr=phase==1?ga:da;pending=64;index=0;delay_count=0;
     if(ACK_FIRST&&!drop)begin
       valid<=1;data<=memory[physical_index(target_addr)];pending=63;index=1;
     end
   end else if(busy&&!drop)begin
     if(pending>0)begin
       // Variable latency and gaps exercise the non-backpressured response.
       if(delay_count==RESPONSE_GAP)begin
         valid<=1;data<=memory[physical_index(target_addr)+index];
         index=index+1;pending=pending-1;delay_count=0;
       end else delay_count=delay_count+1;
     end else busy<=0;
   end
   if(rst_n&&we&&compare_pixels)begin
     if(pixel!==(pixels[0]?(32'h76540000+(pixels/2))>>16:(32'h76540000+(pixels/2))&16'hffff))
       $fatal(1,"unverified/wrong pixel %0d: %04x",pixels,pixel);
     pixels=pixels+1;
   end
 end
 task check(input bit okay,input string label);
   checks=checks+1;if(!okay)$fatal(1,"%s",label);$display("[PASS] %s",label);
 endtask
 task reset_all;
   begin @(negedge clk);rst_n=0;begin_frame=0;accepted=0;verify_start=0;dma_start=0;drop=0;phase=1;
     compare_pixels=0;pixels=0;fifo_level=0;repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);end
 endtask
 task build(input bit bottom,input bit which_slot,input integer count);
   integer j,k;reg [31:0] base;
   begin td=HEADER_LATE?bottom:!bottom;slot={1'b0,which_slot};base=which_slot?32'h000a0000:0;
     begin_frame=1;@(negedge clk);begin_frame=0;
     if(HEADER_LATE)begin repeat(5)@(negedge clk);td=!bottom;repeat(3)@(negedge clk);end
     for(j=0;j<count;j=j+1)begin
       k=bottom?(j<64?j+64:j-64):j;wa=base+k*4;wd=32'h76540000+k;accepted=1;
       memory[(which_slot?128:0)+k]=wd;@(negedge clk);
       accepted=0;repeat(SOURCE_GAP+(j%3)*SOURCE_GAP)@(negedge clk);
     end accepted=0;repeat(3)@(negedge clk);
   end
 endtask
 task verify_frame;
   begin verify_start=1;@(negedge clk);verify_start=0;wait(done||gfault);@(negedge clk);end
 endtask
 task play;
   begin phase=2;pixels=0;compare_pixels=1;dma_start=1;@(negedge clk);dma_start=0;
     wait(ddone||dfault);play_completed=ddone;repeat(3)@(negedge clk);compare_pixels=0;end
 endtask
 integer n,corrupt;
 initial begin
   // Constants independently produced by Python zlib.crc32 on little-endian
   // words 0x76540000..0x7654007f; no DUT CRC function in the oracle.
   for(n=0;n<4;n=n+1)begin
     reset_all;build(n[0],n[1],128);verify_frame;
     check(pass&&!gfault&&blocks==2&&words==128,"complete top/bottom image in either slot verifies");
     check(guard.signatures[n[1]?2:0]===32'h87303f7b&&
           guard.signatures[n[1]?3:1]===32'h844c356e,"CRC32 matches independent zlib reference");
     play;check(play_completed&&!dfault&&pixels==256&&bytes==512,"all verified pixels drain in order");
   end
   for(n=0;n<4;n=n+1)begin
     reset_all;build(0,0,128);corrupt=(n==0?0:n==1?63:n==2?64:127);
     memory[corrupt]=memory[corrupt]^32'h00010000;verify_frame;
     check(gfault&&done&&!pass&&!guard.approved[0],"readback corruption rejects publication");
     check(gba==((corrupt/64)*256),"readback reports first bad block address");
     reset_all;build(0,0,128);verify_frame;
     memory[corrupt]=memory[corrupt]^32'h00010000;play;
     // A fast response can detect a bad second block while the previously
     // verified bank is still draining. Fault priority may truncate THAT good
     // bank; the safety guarantee is that no pixel from the bad bank escapes.
     check(dfault&&!ddone&&pixels<=(corrupt<64?0:128),"retention/read corruption emits no pixel from bad block");
     check(dba==((corrupt/64)*256),"playback reports first bad block address");
   end
   reset_all;build(0,0,64);verify_frame;
   check(done&&gfault&&!pass,"truncated image cannot become approved");
   reset_all;build(0,0,0);wa=4;wd=1;accepted=1;@(negedge clk);accepted=0;
   check(gfault&&!guard.approved[0],"out-of-order/aliased source address rejected");
   reset_all;build(0,0,128);drop=1;verify_frame;
   check(done&&gfault&&!pass,"lost read response times out instead of publishing");
   reset_all;build(0,0,128);verify_frame;drop=1;play;
   check(dfault&&!play_completed&&pixels==0&&!we,"lost playback response times out without unchecked pixels");
   dma_start=1;repeat(10)@(negedge clk);dma_start=0;
   check(dfault&&!active&&!dreq,"playback fault remains latched until common reset");
   reset_all;build(0,0,128);verify_frame;
   phase=2;fifo_level=500;dma_start=1;@(negedge clk);dma_start=0;
   repeat(100)@(negedge clk);
   check(active&&!dreq&&!we&&bytes==0,"checked DMA waits for FIFO headroom before issuing a block");
   pixels=0;compare_pixels=1;fifo_level=0;wait(ddone||dfault);repeat(3)@(negedge clk);compare_pixels=0;
   check(!dfault&&pixels==256&&bytes==512,"FIFO headroom release resumes complete exact playback");
   reset_all;build(0,0,128);verify_frame;phase=2;drop=1;
   dma_start=1;@(negedge clk);dma_start=0;wait(busy);repeat(10)@(negedge clk);
   reset_all;
   check(!active&&!dreq&&!we&&!dfault&&!lookup_valid,"reset cancels an outstanding playback ownership epoch");
   build(1,1,128);verify_frame;play;
   check(pass&&play_completed&&!dfault&&pixels==256,"new slot and orientation play correctly after in-flight reset");
   reset_all;check(!lookup_valid&&!gfault&&!dfault,"common reset invalidates all old signatures and faults");
   $display("[PASS] FRAME INTEGRITY ACK_FIRST=%0d RESPONSE_GAP=%0d SOURCE_GAP=%0d HEADER_LATE=%0d checks=%0d",ACK_FIRST,RESPONSE_GAP,SOURCE_GAP,HEADER_LATE,checks);$finish;
 end
 initial begin #20000000;$fatal(1,"integrity watchdog state=%0d words=%0d blocks=%0d",guard.state,words,blocks);end
endmodule
