`timescale 1ns/1ps
module tb_v3_source_wait_legacy;
 reg clk=0,wrclk=0;always #10 clk=~clk;initial begin #3;forever #10 wrclk=~wrclk;end
 reg rst=0,hint=0,writer_epoch_started=0;integer cycle=0,errors=0,comparisons=0,starts=0,empty_faults=0;
 reg[31:0] random_state=32'h935ad172;
 reg start=0,wvalid=0;reg[15:0] wdin=0;wire wready,oready,req,oreq,wdone,odone,wcrc,ocrc,werr,oerr;
 wire[31:0] addr,oaddr,data,odata;wire[15:0] len,olen,crc,ocrcvalue;wire[18:0] pixels,opixels;
 wire[3:0] slots,oslots;wire[7:0] ec,oec,ed,oed;
 wire ack=cycle%160<30||cycle%160>60||(cycle/160)%7!=0;
 frame_writer #(.FRAME_WIDTH(8),.FRAME_HEIGHT(4),.PIX_PER_FRAME(32),.GAP_TIMEOUT(16)) current_writer(
  .clk(clk),.rst_n(rst),.start(start),.slot_sel(2'd0),.slot_base(32'd0),.din(wdin),.din_valid(wvalid),.din_ready(wready),
  .wr_req(req),.wr_addr(addr),.wr_data(data),.wr_len(len),.wr_ready(ack),.wr_done(wdone),.slot_valid(slots),
  .crc_ok(wcrc),.crc_value(crc),.px_cnt(pixels),.wr_error(werr),.err_code(ec),.err_detail(ed),.source_progress(hint));
 v3_frame_writer_before_source_wait261028 #(.FRAME_WIDTH(8),.FRAME_HEIGHT(4),.PIX_PER_FRAME(32),.GAP_TIMEOUT(16)) original_writer(
  .clk(clk),.rst_n(rst),.start(start),.slot_sel(2'd0),.slot_base(32'd0),.din(wdin),.din_valid(wvalid),.din_ready(oready),
  .wr_req(oreq),.wr_addr(oaddr),.wr_data(odata),.wr_len(olen),.wr_ready(ack),.wr_done(odone),.slot_valid(oslots),
  .crc_ok(ocrc),.crc_value(ocrcvalue),.px_cnt(opixels),.wr_error(oerr),.err_code(oec),.err_detail(oed));
 reg fa=0,sv=0;reg[31:0] sd=0;wire sr,osr,mr,omr,fd,ofd,okay,ookay,sreq,osreq,swap,oswap;
 wire[31:0] sa,osa,sdata,osdata;wire[15:0] slen,oslen,frames,oframes;wire[3:0] ss,oss;wire[7:0] se,ose,sdetail,osdetail,gen,ogen;
 wire[1:0] sslot,osslot;wire scrc,oscrc;wire[18:0] spx,ospx;
 wire sack=cycle%97<70&&!(cycle%1800>=700&&cycle%1800<900);
 bmp_frame_sink #(.FIFO_AW(8),.GAP_TIMEOUT(64),.WRITE_TO_N(96),.RESIDENT_LOAD(1),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1)) current_sink(
  .clk(clk),.wr_clk(wrclk),.rst_n(rst),.px_word(sd),.px_word_valid(sv),.px_word_ready(sr),.frame_active(fa),.top_down(1'b1),.slot(2'd1),
  .mem_ready(mr),.frame_done(fd),.last_frame_ok(okay),.wr_req(sreq),.wr_addr(sa),.wr_data(sdata),.wr_len(slen),.wr_ready(sack),
  .swap_toggle(swap),.swap_slot(sslot),.swap_generation(gen),.swap_crc_ok(scrc),.swap_busy(1'b0),.state_o(ss),.err_code(se),.err_detail(sdetail),
  .frame_cnt(frames),.px_written(spx),.write_drained(1'b1),.verify_done(1'b1),.verify_pass(1'b1),.source_begin(),.source_slot(),.source_top_down(),.source_progress(hint));
 v3_frame_sink_before_source_wait261028 #(.FIFO_AW(8),.GAP_TIMEOUT(64),.WRITE_TO_N(96),.RESIDENT_LOAD(1),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1)) original_sink(
  .clk(clk),.wr_clk(wrclk),.rst_n(rst),.px_word(sd),.px_word_valid(sv),.px_word_ready(osr),.frame_active(fa),.top_down(1'b1),.slot(2'd1),
  .mem_ready(omr),.frame_done(ofd),.last_frame_ok(ookay),.wr_req(osreq),.wr_addr(osa),.wr_data(osdata),.wr_len(oslen),.wr_ready(sack),
  .swap_toggle(oswap),.swap_slot(osslot),.swap_generation(ogen),.swap_crc_ok(oscrc),.swap_busy(1'b0),.state_o(oss),.err_code(ose),.err_detail(osdetail),
  .frame_cnt(oframes),.px_written(ospx),.write_drained(1'b1),.verify_done(1'b1),.verify_pass(1'b1),.source_begin(),.source_slot(),.source_top_down());
 task ck(input  condition,input [4095:0] message);begin begin
  condition = (condition === 1'b1); comparisons = comparisons + 1;if(!condition)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s cycle=%0d",message,cycle);end
 end  end endtask
 always @(negedge clk)begin
  cycle = cycle + 1;
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  rst=cycle>8&&!(cycle>=4000&&cycle<4006)&&!(cycle>=8000&&cycle<8006);
  case(cycle%4)0:hint=1'bx;1:hint=1'bz;2:hint=1;3:hint=0;endcase
  fa=rst&&cycle%1800>=50&&cycle%1800<1200;
  start=rst&&cycle%160==5;
  if(!rst||cycle%160==0)writer_epoch_started=0;
  if(start)begin starts = starts + 1;writer_epoch_started=1;end
  if(!rst||start||werr||pixels>=32||((cycle/160)%5==0&&cycle%160<60))wvalid=0;
  else if(!wvalid||(wready&&oready))begin wvalid=random_state[0]||random_state[3];wdin=random_state[23:8];end
 end
 always @(negedge wrclk)begin
  if(!rst||!fa)sv=0;
  else if(!sv||(sr&&osr))begin sv=(cycle%5!=0);sd=random_state^32'hfedcba98;end
 end
 always @(posedge clk)begin #1;
  if(cycle>8)begin
   ck({wready,req,addr,data,len,wdone,slots,wcrc,crc,pixels,werr,ec,ed}==={oready,oreq,oaddr,odata,olen,odone,oslots,ocrc,ocrcvalue,opixels,oerr,oec,oed},"default writer matches its frozen public interface with X/Z source hints");
   ck({sr,mr,fd,okay,sreq,sa,sdata,slen,swap,sslot,gen,scrc,ss,se,sdetail,frames,spx}==={osr,omr,ofd,ookay,osreq,osa,osdata,oslen,oswap,osslot,ogen,oscrc,oss,ose,osdetail,oframes,ospx},"default sink matches its frozen public interface through reset, starvation and abort");
   if(writer_epoch_started&&(cycle/160)%5==0&&cycle%160==40)begin
    ck(werr&&oerr,"a legacy empty-source interval still expires despite periodic high hints");empty_faults = empty_faults + 1;
   end
  end
  if(cycle==12000)begin
   ck(starts>70,"many small writer frames and fault intervals are exercised");
   ck(empty_faults>10,"deterministic empty-source deadlines are covered across many frames");
   $display("[PASS] exact pre-change Git references, default parameters, randomized backpressure, source X/Z, fault timing and resets");
   $display("PASS tb_v3_source_wait_legacy errors=%0d comparisons=%0d starts=%0d empty_faults=%0d",errors,comparisons,starts,empty_faults);$finish;
  end
 end
endmodule
