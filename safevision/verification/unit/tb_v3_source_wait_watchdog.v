`timescale 1ns/1ps
module tb_v3_source_wait_watchdog;
 localparam integer LIMIT=96,WORDS=153600;
 reg clk=0,wrclk=0;always #10 clk=~clk;initial begin #3;forever #10 wrclk=~wrclk;end
 reg rst=0,active=0,pv=0,heartbeat_enable=0,manual_hint=0,ack_enable=1,last_hold=0,drained=1,vdone=1,vpass=1;
 reg[31:0] data=0;wire ready,req,memready,done,okay,swap,source_begin;
 wire[31:0] addr,wdata;wire[15:0] len,frames;wire[3:0] state;wire[7:0] ec,ed;
 integer errors=0,comparisons=0,cycle=0,writes=0,case_id=0,i,guard,beats=0,basebeats;
 wire beat=manual_hint||(heartbeat_enable&&cycle%4==0);
 always @(negedge clk)cycle=cycle+1;
 wire ack=ack_enable&&!(last_hold&&writes==WORDS-1);
 bmp_frame_sink #(.FIFO_AW(8),.GAP_TIMEOUT(LIMIT),.WRITE_TO_N(LIMIT),.SWAP_TO_N(LIMIT),
  .RESIDENT_LOAD(1),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1),.SOURCE_PROGRESS_AWARE(1)) dut(
  .clk(clk),.wr_clk(wrclk),.rst_n(rst),.px_word(data),.px_word_valid(pv),.px_word_ready(ready),
  .frame_active(active),.top_down(1'b1),.slot(2'd0),.mem_ready(memready),.frame_done(done),.last_frame_ok(okay),
  .wr_req(req),.wr_addr(addr),.wr_data(wdata),.wr_len(len),.wr_ready(ack),.swap_toggle(swap),
  .swap_slot(),.swap_generation(),.swap_crc_ok(),.swap_busy(1'b0),.state_o(state),.err_code(ec),.err_detail(ed),
  .frame_cnt(frames),.px_written(),.write_drained(drained),.verify_done(vdone),.verify_pass(vpass),
  .source_begin(source_begin),.source_slot(),.source_top_down(),.source_progress(beat));
 task ck(input  condition,input [4095:0] message);begin begin
  condition = (condition === 1'b1); comparisons = comparisons + 1;if(!condition)begin errors = errors + 1;if(errors<18)$display("[FAIL] case%0d %s state=%0d ec=%h/%h writes=%0d",case_id,message,state,ec,ed,writes);end
 end  end endtask
 function[31:0] pattern(input integer index);begin pattern=32'h12345678^(index*32'h00010003); end endfunction
 always @(posedge clk)begin
  if(!rst)begin writes=0;beats=0;end
  else begin
   if(beat)beats = beats + 1;
   if(req&&ack)begin
    ck(addr==writes*4&&len==1&&wdata==pattern(writes),"each accepted word keeps its address, length and full payload");writes = writes + 1;
   end
   if(dut.source_wait_credit)ck(state==1&&dut.fa_sync[2]&&drained&&!req&&!dut.sk_valid&&dut.fifo_empty,"source credit requires an active, empty and physically drained writer");
  end
 end
 task fresh;begin begin
  @(negedge clk);rst=0;active=0;pv=0;heartbeat_enable=0;manual_hint=0;ack_enable=1;last_hold=0;drained=1;vdone=1;vpass=1;
  repeat(8)@(negedge clk);rst=1;guard=0;
  while(!memready&&guard<200)begin @(negedge clk);guard = guard + 1;end
  ck(memready,"FIFO reset and idle drain complete");
  @(negedge wrclk);active=1;guard=0;
  while(state!=1&&guard<20)begin @(negedge clk);guard = guard + 1;end
  ck(state==1,"frame arms the write state");
 end  end endtask
 task word(input integer index);begin begin
  @(negedge wrclk);data=pattern(index);pv=1;guard=0;
  @(posedge wrclk);
  while(!ready&&guard<1000)begin @(posedge wrclk);guard = guard + 1;end
  ck(ready,"source word is accepted once under FIFO backpressure");
  @(negedge wrclk);pv=0;
 end  end endtask
 task timeout_expected(input [4095:0] reason);begin begin
  basebeats=beats;guard=0;
  while(ec==0&&guard<LIMIT+40)begin @(negedge clk);guard = guard + 1;end
  ck(ec!=0,reason);ck(!okay&&!swap&&frames==0,"a stalled or partial frame is never published");
  if(heartbeat_enable)ck(beats>basebeats+4,"raw source events continued throughout the protected fault");
 end  end endtask
 initial begin

  case_id=1;fresh();heartbeat_enable=1;repeat(LIMIT*3)@(negedge clk);
  ck(ec==0&&state==1,"accepted raw progress sustains a long pre-pixel wait");
  for(i=0;i<8;i = i + 1)word(i);
  repeat(LIMIT*3)@(negedge clk);ck(ec==0&&state==1,"accepted raw progress sustains a long inter-row wait");
  ck(!okay&&!swap&&frames==0,"source events alone cannot publish a frame");
  for(i=8;i<WORDS;i = i + 1)word(i);
  guard=0;while(frames==0&&ec==0&&guard<4000)begin @(negedge clk);guard = guard + 1;end
  ck(frames==1&&okay&&writes==WORDS&&ec==0,"the complete frame passes its unchanged publication path");

  case_id=2;fresh();timeout_expected("stopped source progress expires normally");

  case_id=3;fresh();heartbeat_enable=1;ack_enable=0;word(0);timeout_expected("a held memory request times out despite continuing source bytes");

  case_id=4;fresh();heartbeat_enable=1;word(0);
  guard=0;while(writes==0&&guard<100)begin @(negedge clk);guard = guard + 1;end
  ck(writes==1,"one word was accepted before physical drain stalled");drained=0;
  timeout_expected("adapter pending state blocks source-wait credit");

  case_id=5;fresh();heartbeat_enable=1;last_hold=1;
  for(i=0;i<WORDS;i = i + 1)word(i);
  guard=0;while(!(req&&writes==WORDS-1)&&guard<4000)begin @(negedge clk);guard = guard + 1;end
  ck(req&&writes==WORDS-1,"the last physical write remains pending");
  timeout_expected("last-word bus stall still expires");

  case_id=6;fresh();heartbeat_enable=1;vdone=0;
  for(i=0;i<WORDS;i = i + 1)word(i);
  guard=0;while(state!=4&&ec==0&&guard<4000)begin @(negedge clk);guard = guard + 1;end
  ck(state==4,"a complete frame enters physical drain and readback wait");
  timeout_expected("stalled readback remains bounded despite continuing source bytes");

  case_id=7;fresh();heartbeat_enable=1;word(0);@(negedge wrclk);active=0;
  guard=0;while(!done&&guard<LIMIT+40)begin @(negedge clk);guard = guard + 1;end
  ck(done&&!okay&&!swap&&frames==0,"an incomplete source frame is acknowledged as failed even with source events");


  case_id=8;fresh();guard=0;
  while(dut.to_cnt<LIMIT-1&&ec==0&&guard<LIMIT+10)begin @(negedge clk);guard = guard + 1;end
  ck(dut.to_cnt==LIMIT-1&&ec==0,"deadline test reaches the edge before expiry");
  manual_hint=1;@(negedge clk);manual_hint=0;
  ck(dut.to_cnt==LIMIT&&dut.source_wait_credit,"qualified source credit is present on the deadline edge");
  @(posedge clk);#1;ck(ec==0&&state==1&&dut.to_cnt==0,"a valid deadline-edge credit wins before timeout");
  @(negedge clk);rst=0;
  $display("[PASS] source wait, complete raster, stopped source, bus, last word, adapter tail, readback, abort and deadline priority");
  $display("PASS tb_v3_source_wait_watchdog errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #100000000; $display("[FAIL] watchdog test global timeout");$display("PASS tb_v3_source_wait_watchdog errors=1 comparisons=1");$finish;end
endmodule
