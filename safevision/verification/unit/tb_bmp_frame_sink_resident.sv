`timescale 1ns/1ps
module tb_bmp_frame_sink_resident;
 reg clk=0;always #12.5 clk=~clk;reg wrclk=0;always #10 wrclk=~wrclk;
 reg rst=0,fa=0,cached=0,abort=0,preload=0,stream_good=0,pxvalid=0,busy=0,verified=0;
 reg [1:0] slot=1;reg [31:0] px=0;
 wire pxready,mready,fd,ok,req,st,crc,begin_frame,abort_out;
 wire [31:0] address,data;wire [15:0] len,frames;wire [18:0] pixels;
 wire [1:0] published,source_slot;wire [7:0] gen,ec,ed;wire [3:0] state;wire td;
 bmp_frame_sink #(.REQUIRE_STREAM_DONE(1),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1),.GAP_TIMEOUT(10000000),.WRITE_TO_N(20000000),.SWAP_TO_N(2000)) dut(
 .clk(clk),.rst_n(rst),.wr_clk(wrclk),.cached_frame(cached),.abort_frame(abort),.preload_only(preload),.source_stream_ok(stream_good),
 .px_word(px),.px_word_valid(pxvalid),.px_word_ready(pxready),.frame_active(fa),.top_down(1'b1),.slot(slot),
 .mem_ready(mready),.frame_done(fd),.last_frame_ok(ok),.wr_req(req),.wr_addr(address),.wr_data(data),.wr_len(len),.wr_ready(1'b1),
 .swap_toggle(st),.swap_slot(published),.swap_generation(gen),.swap_crc_ok(crc),.swap_busy(busy),
 .state_o(state),.err_code(ec),.err_detail(ed),.frame_cnt(frames),.px_written(pixels),
 .write_drained(1'b1),.verify_done(verified),.verify_pass(1'b1),
 .source_begin(begin_frame),.source_abort(abort_out),.source_slot(source_slot),.source_top_down(td));
 integer writes=0,pubs=0,checks=0,i;reg st_d=0;
 always @(posedge clk)if(rst)begin
   if(req)writes=writes+1;
   if(st!=st_d)pubs=pubs+1;st_d=st;
 end
 task check(input bit condition,input string message);
 begin checks=checks+1;if(!condition)$fatal(1,"SINK RESIDENT: %s writes=%0d pubs=%0d state=%0d ec=%x",message,writes,pubs,state,ec);end endtask
 task load(input [1:0] target,input bit background,input bit tail_abort);
 reg last_fd;
 begin
   wait(mready);@(negedge wrclk);slot=target;cached=0;preload=background;verified=0;stream_good=0;
   repeat(5)@(negedge wrclk);last_fd=fd;fa=1;wait(state==1);
   for(i=0;i<153600;i=i+1)begin
     if(target==1&&i==1000)begin
       @(negedge wrclk);pxvalid=0;repeat(400000)@(negedge clk);
       check(state==1&&ec==0,"10 ms SD stall is legal and must not trigger a 4 ms pixel-gap failure");
     end
     @(negedge wrclk);px={target,14'b0,target,14'b0}^i;pxvalid=1;
     @(posedge wrclk);while(!pxready)@(posedge wrclk);
   end
   @(negedge wrclk);pxvalid=0;wait(state==4);repeat(25)@(negedge clk);verified=1;repeat(25)@(negedge clk);
   check(state==4&&fd==last_fd,"memory verification alone cannot commit before SD tail CRC");
   if(tail_abort)begin abort=1;end else stream_good=1;
   if(!background&&!tail_abort)begin wait(state==2);busy=1;repeat(10)@(negedge clk);busy=0;end
   wait(fd!=last_fd);@(negedge wrclk);fa=0;wait(mready);repeat(10)@(negedge clk);abort=0;
 end endtask
 reg last_fd;integer saved_writes,saved_pubs;
 initial begin
   repeat(6)@(negedge clk);rst=1;load(1,0,0);
   check(writes==153600&&pubs==1&&frames==1&&ok,"first image publishes only after verify and swap ACK");
   load(2,1,0);
   check(writes==307200&&pubs==1&&frames==2&&ok,"background load completes without changing display ownership");
   saved_writes=writes;wait(mready);@(negedge wrclk);slot=2;cached=1;preload=0;
   repeat(5)@(negedge wrclk);last_fd=fd;fa=1;wait(state==2);
   busy=1;repeat(10)@(negedge clk);busy=0;wait(fd!=last_fd);fa=0;wait(mready);repeat(10)@(negedge clk);
   check(writes==saved_writes&&pubs==2&&frames==3&&published==2,"cached selection writes no pixels and waits for display ACK");
   @(negedge wrclk);slot=3;cached=0;preload=1;repeat(5)@(negedge wrclk);last_fd=fd;fa=1;
   wait(state==1);repeat(10)@(negedge clk);abort=1;fa=0;wait(fd!=last_fd);wait(mready);abort=0;repeat(10)@(negedge clk);
   check(pubs==2&&writes==saved_writes&&frames==3&&!ok&&ec==0,"bad-file abort drains without publishing or counting success");
   load(3,1,1);
   check(pubs==2&&frames==3&&!ok&&ec==0,"late SD tail abort cancels verified memory without publication or success count");
   $display("PASS tb_bmp_frame_sink_resident checks=%0d: verified first/background/cache/abort",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"resident sink watchdog");end
endmodule
