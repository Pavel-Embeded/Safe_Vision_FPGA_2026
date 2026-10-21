`timescale 1ns/1ps
`include "pixel_format_defs.vh"
// Actual SPI/FAT32/streamer/parser/FIFO/row-mapping path; no forced DUT signals.
// Distinct Pillow-decoded references check all four complete resident frames.
module tb_v3_shared_storage;
 reg clk=0;always #10 clk=~clk; // actual V3 MEM 50MHz
 reg refclk=0;always #10 refclk=~refclk; // real independent REF 50MHz
 reg rst=0,run=0;
 wire cs,sclk,mosi,miso,ready,active,td,mr,fd,ok;
 wire[31:0] word;wire valid;wire[1:0] slot;wire[3:0] state,stage,cv;
 wire[7:0] ec,ed;wire mounted;wire[2:0] count;wire[63:0] keys;wire[15:0] rejected,frames;
 wire req,ack;wire[31:0] addr,data;wire[15:0] len;
 wire[3:0] sinkstate;wire[7:0] sinkerr;
 wire source_begin,source_td,verify_done,verify_pass,integrity_fault;
 wire[15:0] last_reject_error,last_reject_key;wire[31:0] progress_count;
 wire[1:0] source_slot;wire[3:0] approved;reg verify_started=0;
 wire vreq;wire[31:0] vaddr;wire[15:0] vlen;
 reg vack=0,vbusy=0,vvalid=0;reg[31:0] vdata=0;
 wire write_drained;
 wire[5:0] cmd;wire cmdvalid;
 sd_spi_card_model #(.VOL_BASE(16),.VOL_SECTORS(8192)) card(
 .sclk(sclk),.cs_n(cs),.mosi(mosi),.miso(miso),.i_dead(1'b0),
 .o_cmd(cmd),.o_arg(),.o_acmd41_arg(),.o_cmd_cnt(),.o_acmd41_cnt(),.o_cmd_valid(cmdvalid));

 wire[444:0] core_cmd;wire[836:0] core_rsp;wire service_ready;
 wire a_en,a_dr,a_ready,a_valid,a_last,a_done,a_timeout,a_crc;
 wire[31:0] a_addr,fat,data_base,root_lba,root,total;wire[15:0] a_len;wire[7:0] a_data,a_ec,a_ed,spc;
 wire[127:0] audio_pairs;wire[3:0] audio_valid,audio_found,audio_fallback;wire audio_indexed;
 reg[3:0] audio_ready=0;reg[31:0] audio_gold[0:23999];integer audio_count[0:3],audio_comparisons=0,refcycles=0,gap_cycles=0;
 reg owner_seen=0,ready_seen=0;
 v3_wav_source #(.EXTERNAL_SERVICE(1)) wav(.clk(refclk),.rst_n(rst),.mounted(mounted),.cache_ready(cv==15),
 .cache_keys(keys),.sec_per_clus(spc),.fat_start_lba(fat),.data_start_lba(data_base),.root_dir_lba(root_lba),.root_clus(root),.total_clus(total),
 .slot_fill(4'hf),.sector_room(4'hf),.pcm_data(audio_pairs),.pcm_valid(audio_valid),.pcm_ready(audio_ready),.index_done(audio_indexed),.fallback(audio_fallback),.found(audio_found),
 .external_service_ready(service_ready),.core_cmd(core_cmd),.core_rsp(core_rsp),
 .rd_en(a_en),.rd_addr(a_addr),.rd_len(a_len),.rd_ready(a_ready),.data(a_data),.data_valid(a_valid),.data_ready(a_dr),.data_last(a_last),.rd_done(a_done),.timeout_err(a_timeout),.crc16_err(a_crc),.err_code(a_ec),.err_detail(a_ed));
 always @(posedge refclk)if(rst)begin
  refcycles<=refcycles+1;
  if(player.ext_owner&&!service_ready)begin gap_cycles<=gap_cycles+1;if(core_rsp!==0)$fatal(1,"ownership gap leaked old response");end
  if(service_ready&&!ready_seen)begin
   ready_seen<=1;
   if(player.svc_d_scan_done||gap_cycles<1)$fatal(1,"stale BMP scan_done survived WAV ownership handoff");
  end
  if(!service_ready&&wav.scan_start)$fatal(1,"WAV scanned before shared service ready");
  for(integer ag=0;ag<4;ag=ag+1)if(audio_valid[ag]&&audio_ready[ag])begin
   if(audio_pairs[ag*32+:32]!==audio_gold[ag*6000+audio_count[ag]%6000])$fatal(1,"SPI shared WAV PCM slot=%0d idx=%0d got=%h exp=%h",ag,audio_count[ag],audio_pairs[ag*32+:32],audio_gold[ag*6000+audio_count[ag]%6000]);
   audio_count[ag]<=audio_count[ag]+1;audio_comparisons<=audio_comparisons+1;
  end
 end
 always @(negedge refclk)if(rst)for(integer ag=0;ag<4;ag=ag+1)audio_ready[ag]=(refcycles%(7+ag)!=0);
 initial begin for(integer ag=0;ag<4;ag=ag+1)audio_count[ag]=0;$readmemh("lifecycle_pcm.mem",audio_gold);end

 sd_bmp_player #(.SHARED_SERVICE(1),.RESIDENT_CACHE(1),.GUARDED_CS(1),.CLK_HZ(50000000),.CLK_DIV_INIT(249),.CLK_DIV_FAST(0)) player(
 .clk(refclk),.rst_n(rst),.cs_guard_rst_n(rst),.run(run),.btn_next(1'b1),.btn_auto(1'b1),.restart(1'b0),
 .sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(miso),
 .px_word(word),.px_word_valid(valid),.px_word_ready(ready),.frame_active(active),.top_down_o(td),.slot_o(slot),
 .mem_ready(mr),.frame_done(fd),.last_frame_ok(ok),.state_o(state),.fail_stage(stage),.err_code(ec),.err_detail(ed),
 .sd_ready(),.card_usable(mounted),.cache_valid(cv),.cache_count(count),.cache_keys(keys),
 .rejected_files(rejected),.frame_cnt(frames),.external_core_cmd(core_cmd),.external_core_rsp(core_rsp),.external_service_ready(service_ready),
 .ext_rd_en(a_en),.ext_rd_addr(a_addr),.ext_rd_len(a_len),.ext_data_ready(a_dr),
 .ext_rd_ready(a_ready),.ext_data(a_data),.ext_data_valid(a_valid),.ext_data_last(a_last),.ext_rd_done(a_done),
 .ext_timeout(a_timeout),.ext_crc_error(a_crc),.ext_err_code(a_ec),.ext_err_detail(a_ed),
 .fs_sec_per_clus(spc),.fs_fat_start_lba(fat),.fs_data_start_lba(data_base),.fs_root_dir_lba(root_lba),.fs_root_clus(root),.fs_total_clus(total),
 .last_reject_error(last_reject_error),.last_reject_key(last_reject_key),.progress_count(progress_count));
 bmp_frame_sink #(.RESIDENT_LOAD(1),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1)) sink(
 .clk(clk),.rst_n(rst),.wr_clk(refclk),.px_word(word),.px_word_valid(valid),.px_word_ready(ready),
 .frame_active(active),.top_down(td),.slot(slot),.mem_ready(mr),.frame_done(fd),.last_frame_ok(ok),
 .wr_req(req),.wr_addr(addr),.wr_data(data),.wr_len(len),.wr_ready(ack),
 .swap_toggle(),.swap_slot(),.swap_generation(),.swap_crc_ok(),.swap_busy(1'b0),
 .state_o(sinkstate),.err_code(sinkerr),.err_detail(),.frame_cnt(),.px_written(),
 .write_drained(write_drained),.verify_done(verify_done),.verify_pass(verify_pass),
 .source_begin(source_begin),.source_slot(source_slot),.source_top_down(source_td));
 wire verify_start=(sinkstate==4) && write_drained && !verify_started;
 always @(posedge clk)if(!rst || source_begin)verify_started<=0;else if(verify_start)verify_started<=1;
 v3_row_integrity guard_crc(.clk(clk),.rst_n(rst),.frame_begin(source_begin),.frame_slot(source_slot),
 .top_down(source_td),.accepted(req && ack),.write_addr(addr),.write_data(data),
 .verify_start(verify_start),.verify_allow(1'b1),.verify_done(verify_done),.verify_pass(verify_pass),
 .fault(integrity_fault),.approved(approved),.rd_req(vreq),.rd_addr(vaddr),.rd_len(vlen),
 .rd_ack(vack),.rd_busy(vbusy),.rd_valid(vvalid),.rd_data(vdata),.lookup_addr(32'd0),
 .lookup_crc(),.lookup_valid(),.bad_addr(),.bad_expected(),.bad_actual(),.source_words(),.checked_rows());
 reg[31:0] memory[0:1048575],exp0[0:153599],exp1[0:153599],exp2[0:153599],exp3[0:153599];
 reg[6:0] stalls=0;always @(posedge clk)stalls<=stalls+1'b1;
 // Multi-cycle backpressure, including a 24-clock pause at every 128 clocks.
 reg write_pending=0;reg[3:0] write_delay=0;reg[31:0] pending_addr=0,pending_data=0;
 integer read_left=0,read_index=0;
 assign write_drained=!write_pending;
 assign ack=(stalls<104) && !write_pending;
 integer errors=0,writes=0,comparisons=0,commands=0,n,i,base,guard,bad,saved_commands;
 reg previous_cmdvalid=0;reg[31:0] expected;
 reg[3:0] ps=0,ss=0;reg[2:0] cc=0;
 always @(posedge clk)begin
  if(state!=ps || sinkstate!=ss || count!=cc)
   $display("[EVENT] t=%0t pl=%0d sink=%0d count=%0d mr=%b active=%b kick=%b fd=%b pending=%b done=%b fst=%b ec=%h/%h sk=%h",$time,
    state,sinkstate,count,mr,active,player.stream_kicked,fd,player.fd_pending,player.file_done_seen,player.fst_busy,ec,ed,sinkerr);
  ps<=state;ss<=sinkstate;cc<=count;
 end
 always @(posedge clk)begin
  previous_cmdvalid<=cmdvalid;
  if(cmdvalid && !previous_cmdvalid)commands=commands+1;
  if(req && ack)begin
   if(addr[1:0]!=0 || len!=1 || addr>=`SV_AUDIO_RING_BASE)begin
    errors=errors+1;$display("[FAIL] write address/length %h %0d",addr,len);
   end
   // Grant precedes physical completion by seven clocks, as in the adapter.
   pending_addr<=addr;pending_data<=data;write_pending<=1;write_delay<=6;writes=writes+1;
  end
  if(write_pending)begin
   if(write_delay==0)begin memory[pending_addr>>2]<=pending_data;write_pending<=0;end
   else write_delay<=write_delay-1'b1;
  end
  vack<=0;vvalid<=0;
  if(vreq && !vbusy)begin vack<=1;vbusy<=1;read_left<=vlen;read_index<=vaddr>>2;end
  else if(vbusy && stalls<104)begin
   vdata<=memory[read_index];vvalid<=1;read_index<=read_index+1;read_left<=read_left-1;
   if(read_left==1)vbusy<=0;
  end
 end
 task check;input c;input[511:0] msg;begin
  if(c)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end
 end endtask
 initial begin
  if(player.GUARDED_CS!=1)$fatal(1,"production CS guard branch not enabled");
  repeat(5)@(negedge clk);
  $readmemh("resident_card.mem",card.vol);
  for(i=0;i<8192;i=i+1)card.vol_used[i]=1;
  card.sector[450]=8'h0c;card.sector[454]=16;card.sector[455]=0;card.sector[456]=0;card.sector[457]=0;
  card.sector[458]=0;card.sector[459]=32;card.sector[460]=0;card.sector[461]=0;
  card.sector[510]=8'h55;card.sector[511]=8'haa;
  $readmemh("expected0.mem",exp0);$readmemh("expected1.mem",exp1);
  $readmemh("expected2.mem",exp2);$readmemh("expected3.mem",exp3);
  rst=1;repeat(8)@(negedge clk);run=1;
  guard=0;
  while(!mounted && state!=10 && guard<180000000)begin
   @(negedge clk);guard=guard+1;
   if(guard%30000000==0)$display("[PROGRESS] state=%0d caches=%0d rejected=%0d",state,count,rejected);
  end
  $display("[STATUS] state=%0d stage=%0d ec=%h/%h sink=%0d/%h count=%0d keys=%h writes=%0d",
   state,stage,ec,ed,sinkstate,sinkerr,count,keys,writes);
  check(mounted && cv==15 && count==4,"four verified load completions, no partial cache publication");
  check(rejected==4,"four broken early candidates skipped and directory rescanned");
  check(last_reject_error==16'h0337 && last_reject_key==4,"bad file ID and precise signature error retained after successful load");
  check(progress_count>4*921654,"watchdog progress counts actual consumed directory/FAT/media payload");
  check(keys==64'h0008000700060005,"first four LEGAL numeric IDs selected in order");
  check(frames==4 && writes==4*153600,"exactly four complete frames written");
  check(approved==15 && !integrity_fault,"all four producer row CRCs match delayed physical readback");
  repeat(64)@(negedge clk);
  for(i=0;i<4;i=i+1)begin
   base=i*163840;bad=0;
   for(n=0;n<153600;n=n+1)begin
    case(i)0:expected=exp0[n];1:expected=exp1[n];2:expected=exp2[n];3:expected=exp3[n];endcase
    comparisons=comparisons+1;
    if(memory[base+n]!==expected)begin
     if(bad==0)$display("[MISMATCH] slot=%0d word=%0d actual=%h expected=%h",i,n,memory[base+n],expected);
     bad=bad+1;
    end
   end
   check(bad==0,"complete raster matches independent BMP decoder");
  end
  saved_commands=commands;
  wait(audio_count[0]>=6000&&audio_count[1]>=6000&&audio_count[2]>=6000&&audio_count[3]>=6000);
  check(audio_indexed&&audio_fallback==0&&audio_found==15,"shared kernel rescanned full directory and matched four WAV beyond first eight candidates");
  check(commands>saved_commands&&state==7&&gap_cycles>=1,"real SPI ownership handed over after full frames, old done cleared before WAV scan");
  check(audio_comparisons>=24000,"all four fragmented WAV tracks cross cluster and preserve half-sample contexts");
  $display("PASS tb_v3_shared_storage errors=%0d comparisons=%0d PCM=%0d",errors,comparisons,audio_comparisons);$finish;
 end
 initial begin repeat(185000000)@(negedge clk);$display("[FAIL] global timeout");$finish;end
endmodule
