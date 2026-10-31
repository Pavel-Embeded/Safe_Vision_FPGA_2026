`timescale 1ns/1ps
module v3_hd_stream_budget_test #(parameter integer MEM_MHZ=50,MODE=0,READ_LAT=4)(output reg done);
 initial begin done = 0; end

 localparam[1:0] SCALE=MODE;
 localparam integer IW=MODE==0 ? 640:MODE==1 ? 960:MODE==2 ? 320:160;
 localparam integer IH=MODE==0 ? 480:MODE==1 ? 720:MODE==2 ? 240:120;
 localparam integer LEFT=(1280-IW)/2,TOP=(720-IH)/2,STEP=MODE==2 ? 2:MODE==3 ? 4:1;
 function integer source_y(input integer oy);begin
  source_y=oy<TOP ? 0:oy>=TOP+IH ? 479:MODE==1 ? (oy-TOP)*2/3:(oy-TOP)*STEP;
   end endfunction
 reg mem=0,pix=0,audio=0,rst=0; reg sys=0; always #5 sys=~sys;
 always #(500.0/MEM_MHZ)mem=~mem;
 always #6.734006734 pix=~pix;
 always #40.690104167 audio=~audio;
 integer errors=0,comparisons=0,missing=0,audio_pairs=0,audio_missing=0;
 reg request=0;wire request_ready,response_valid;reg[25:0] descriptor=0;wire[25:0] response;
 always @(posedge pix)if(request&&request_ready)request<=0;
 reg prepare_valid=0;reg[9:0] prepare_sy=0;reg[9:0] sx=0,sy=0;reg coord_valid=0;wire rows_ready,sample_valid,primed,fault,dma_busy;
 wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11;
 wire rd_req,rd_ack,rd_busy,rd_valid;wire[31:0] rd_addr,rd_data,lookup_addr;wire[15:0] rd_len;
 reg[31:0] lookup_crc=0;reg lookup_valid=0;
 reg[31:0] signatures[0:959];
 v3_line_cache #(.PACKED_ROWS(1),.HANDBOOK_PROFILE(1)) cache(.write_clk(sys),.write_rst_n(rst),.prepare_valid(prepare_valid),.prepare_sy(prepare_sy),.mem_clk(mem),.mem_rst_n(rst),.pixel_clk(pix),.pixel_rst_n(rst),
 .request_valid(request),.request_ready(request_ready),.request_data(descriptor),
 .response_valid(response_valid),.response_ready(1'b1),.response_data(response),
 .sx(sx),.sy(sy),.scale_select(SCALE),.coord_valid(coord_valid),.current_slot(2'd0),.target_slot(2'd1),.dual_needed(1'b1),
 .primed(primed),.a00(a00),.a10(a10),.a01(a01),.a11(a11),.b00(b00),.b10(b10),.b01(b01),.b11(b11),
 .rows_ready(rows_ready),.sample_valid(sample_valid),.rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),
 .rd_ack(rd_ack),.rd_busy(rd_busy),.rd_valid(rd_valid),.rd_data(rd_data),
 .lookup_addr(lookup_addr),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),
 .fault(fault),.dma_busy(dma_busy),.dma_progress());
 wire ar,aw,aa,ab,av;wire[31:0] ad,awd,ard;wire[15:0] al;
 reg[127:0] ingress;reg[3:0] ingress_valid=0;wire[3:0] ingress_ready,prefetched;
 reg commit=0;wire commit_ready;wire[39:0] samples;wire sample_push,sample_room;
 wire[7:0] fifo_wlevel,fifo_rlevel;wire[39:0] audio_data;wire audio_valid;reg audio_pop=0;
 reg running=0;integer written[0:3];integer wi;
 v3_pcm_ring ring(.clk(mem),.rst_n(rst),.in_data(ingress),.in_valid(ingress_valid),.in_ready(ingress_ready),
 .commit_valid(commit),.commit_slot(2'd0),.commit_generation(8'd1),.commit_ready(commit_ready),
 .fallback(4'd0),.prefetched(prefetched),.levels(),.out_data(samples),.out_valid(sample_push),.out_ready(sample_room),
 .output_level({2'd0,fifo_wlevel}),.req(ar),.wr(aw),.addr(ad),.wdata(awd),.len(al),
 .ack(aa),.busy(ab),.rdata(ard),.rvalid(av),.overflow_count());
 sv_async_fifo #(.WIDTH(40),.AW(8)) pcm(.rst(!rst),.wr_clk(mem),.rd_clk(audio),
 .wr_data(samples),.wr_valid(sample_push),.wr_ready(sample_room),.wr_level(fifo_wlevel),
 .rd_data(audio_data),.rd_valid(audio_valid),.rd_ready(audio_pop),.rd_level(fifo_rlevel));
 function[31:0] pcm_at(input integer slot,index);begin  pcm_at={v_cast_s16(slot*4096+index),v_cast_u16(32'hc357^index)};  end endfunction
 always @*begin
  for(wi=0;wi<4;wi=wi+1)begin
   ingress[wi*32+:32]=pcm_at(wi,written[wi]);
   ingress_valid[wi]=rst&&written[wi]<(running ? 1100+audio_pairs+audio_missing:1100);
  end
 end
 integer tick=0;
 always @(posedge audio)begin
  audio_pop<=0;
  if(!rst)tick<=0;
  else if(running)begin
   if(tick==255)begin tick<=0;audio_pop<=1;end else tick<=tick+1;
   if(audio_pop)begin
    if(!audio_valid)begin audio_missing=audio_missing+1;end
    else begin
     if(audio_data!=={8'd1,pcm_at(0,audio_pairs)})begin
      if(errors<5)$display("[FAIL] PCM pair %0d got=%h expected=%h",audio_pairs,audio_data,{8'd1,pcm_at(0,audio_pairs)});
      errors=errors+1;
     end
     audio_pairs=audio_pairs+1;
    end
   end
  end
 end
 wire qr,qw,qa,qb,qv;wire[31:0] qd,qwd,qrd;wire[15:0] ql;
 v3_aux_mux mux(.clk(mem),.rst_n(rst),.verify_req(1'b0),.verify_addr(32'd0),.verify_len(16'd0),
 .verify_ack(),.verify_busy(),.verify_valid(),.verify_data(),
 .audio_req(ar),.audio_wr(aw),.audio_addr(ad),.audio_wdata(awd),.audio_len(al),
 .audio_ack(aa),.audio_busy(ab),.audio_valid(av),.audio_data(ard),
 .sd_req(qr),.sd_wr(qw),.sd_addr(qd),.sd_wdata(qwd),.sd_len(ql),.sd_ack(qa),.sd_busy(qb),.sd_valid(qv),.sd_data(qrd));
 wire mr,mw,mready,mvalid;wire[31:0] ma,mwd,mrd;wire[3:0] ms;
 memory_arbiter #(.COMPACT_CONSEC_COUNTER(1),.HIGH_WATER(640),.CRITICAL_WATER(320)) arbiter(
 .clk(mem),.rst_n(rst),.video_fifo_level(dma_busy ? 16'd0:16'd1024),
 .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_data_valid(rd_valid),
 .wr_req(1'b0),.wr_addr(32'd0),.wr_data(32'd0),.wr_len(16'd0),.wr_ack(),.wr_busy(),
 .sd_req(qr),.sd_wr(qw),.sd_addr(qd),.sd_wdata(qwd),.sd_len(ql),.sd_ack(qa),.sd_busy(qb),.sd_rdata(qrd),.sd_rdata_valid(qv),
 .mem_req(mr),.mem_wr(mw),.mem_addr(ma),.mem_wdata(mwd),.mem_wstrb(ms),.mem_ready(mready),.mem_rdata(mrd),.mem_rdata_valid(mvalid),
 .wr_starve_cnt(),.rd_starve_cnt());
 wire cr,cw,cready,cv,cinit,mem_error;wire[31:0] ca,cwd,crd;wire[3:0] cs;
 mem_ctrl ctrl(.clk(mem),.rst_n(rst),.init_done(),.req(mr),.wr(mw),.addr(ma),.wdata(mwd),.wstrb(ms),
 .rdata(mrd),.rdata_valid(mvalid),.ready(mready),.mem_error(mem_error),
 .sdram_req(cr),.sdram_wr(cw),.sdram_addr(ca),.sdram_wdata(cwd),.sdram_wstrb(cs),
 .sdram_rdata(crd),.sdram_rdata_valid(cv),.sdram_ready(cready),.sdram_init_done(cinit));
 wire init,refresh,physical_busy,we,re,rv,adapter_fault;
 reg rv_delayed=0;
 wire[20:0] wa,ra;wire[31:0] wd,rr;wire[3:0] dm;
 sdram_app_adapter #(.FAST_READ(1),.PREFETCH_READ(1),.READ_DATA_LEADS_VALID(1)) adapter(.clk(mem),.rst_n(rst),
 .req(cr),.wr(cw),.addr(ca),.wdata(cwd),.wstrb(cs),.rdata(crd),.rdata_valid(cv),.ready(cready),.init_done(cinit),
 .Sdr_init_done(init),.Sdr_init_ref_vld(refresh),.Sdr_busy(physical_busy),
 .App_wr_en(we),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(re),.App_rd_addr(ra),
 .Sdr_rd_en(rv_delayed),.Sdr_rd_dout(rr),.write_idle(),.protocol_fault(adapter_fault));
 always @(posedge mem)if(!rst)rv_delayed<=0;else rv_delayed<=rv;
 v3_hd_pressure_app_model #(.REFRESH_CYCLES(MEM_MHZ*78/10),.READ_LAT(READ_LAT)) physical(.clk(mem),.rst(!rst),
 .wr_en(we),.rd_en(re),.wr_addr(wa),.rd_addr(ra),.wr_data(wd),.wr_dm(dm),
 .initialized(init),.ref_valid(refresh),.busy(physical_busy),.valid(rv),.data(rr));
 function[15:0] image_at(input integer slot,row,col);begin
  image_at=v_cast_u16((slot*16381)^(row*73)^(col*193)^32'h59a6);
   end endfunction
 function[31:0] word_at(input integer slot,row,col);begin
  word_at={image_at(slot,row,col*2+1),image_at(slot,row,col*2)};
   end endfunction
 function[31:0] checksum(input integer slot,row);
  integer c,b;reg[31:0] v;begin  v=32'hffffffff;
   for(c=0;c<320;c=c+1)begin v=v^word_at(slot,row,c);
    for(b=0;b<32;b=b+1)v=v[0] ? (v>>1)^32'hedb88320:v>>1;
   end checksum=~v;

  end endfunction
 integer lookup_slot,lookup_row;
 always @(posedge mem)begin
  begin : v_loop_1 integer k; for( k=0;k<4;k=k+1)if(rst&&ingress_ready[k]&&ingress_valid[k])written[k]<=written[k]+1; end
  lookup_slot=lookup_addr/32'ha0000;lookup_row=(lookup_addr%32'ha0000)/1280;
  lookup_valid<=rst&&lookup_slot<2&&lookup_row<480;
  if(lookup_slot<2&&lookup_row<480)lookup_crc<=signatures[lookup_slot*480+lookup_row];
 end
 task prime;integer t;begin
  @(negedge pix);descriptor={SCALE,2'd0,2'd1,1'b1,10'd0,v_cast_s9(MODE>=2 ? 0:1)};request=1;
  while(!request_ready)@(negedge pix);
  @(negedge pix);request=0;t=0;
  while(!primed&&t<50000)begin @(negedge pix);t=t+1;end
  if(!primed)begin errors=errors+1;$display("[FAIL] initial rows not primed fault=%b",fault);end
   end endtask
 integer row,col,slot,srcrow,srcx,future,nextx,nextr,timer;
 reg[127:0] expected,observed;
 initial begin:run_test
  for(slot=0;slot<4;slot=slot+1)written[slot]=0;
  for(slot=0;slot<2;slot=slot+1)for(row=0;row<480;row=row+1)begin
   signatures[slot*480+row]=checksum(slot,row);
   for(col=0;col<320;col=col+1)physical.memory[(slot*32'ha0000+row*1280)/4+col]=word_at(slot,row,col);
  end
  #100;rst=1;timer=0;
  while(prefetched!=15&&timer<2000000)begin @(negedge mem);timer=timer+1;end
  if(prefetched!=15)begin errors=errors+1;$display("[FAIL] ring prefill timeout %b",prefetched);end
  timer=0;while(!commit_ready&&timer<2000000)begin @(negedge mem);timer = timer + 1;end
  if(!commit_ready)begin errors = errors + 1;$display("[FAIL] bounded PCM commit readiness timeout");done=1;disable run_test;end
  commit=1;@(negedge mem);commit=0;
  timer=0;while(fifo_rlevel<200&&timer<25000)begin @(negedge audio);timer = timer + 1;end
  if(fifo_rlevel<200)begin errors = errors + 1;$display("[FAIL] bounded PCM FIFO prefill timeout");done=1;disable run_test;end
  prime();$display("[PASS] four PCM ring partitions and both initial source rows primed");
  running=1;
  for(row=0;row<750;row=row+1)begin
   future=source_y(row+2);
   for(col=0;col<1650;col=col+1)begin
    @(negedge pix);
    if(col==0&&row+2>=TOP&&row+2<TOP+IH)begin
     if(request)begin errors = errors + 1;if(errors<5)$display("[FAIL] descriptor mailbox overrun y=%0d",row);end
     descriptor={SCALE,2'd0,2'd1,1'b1,v_cast_s10(future),v_cast_s9(MODE>=2 ? future:future==479 ? 479:future+1)};request=1;
    end
    prepare_valid=col==1280;prepare_sy=source_y(row+1);
    coord_valid=row>=TOP&&row<TOP+IH&&col>=LEFT&&col<LEFT+IW;
    srcrow=source_y(row);
    srcx=MODE==1 ? (col-LEFT)*2/3:(col-LEFT)*STEP;if(srcx<0)srcx=0;if(srcx>639)srcx=639;
    sx=srcx;sy=srcrow;
    @(posedge pix);#1;
    if(coord_valid)begin
     if(!sample_valid||!rows_ready)begin
      missing=missing+1;if(missing<5)$display("[FAIL] row deadline MEM=%0d y=%0d x=%0d src=%0d dma=%b",MEM_MHZ,row,col,srcrow,dma_busy);
     end else begin
      nextx=srcx+STEP>639 ? 639:srcx+STEP;nextr=MODE>=2 ? srcrow:srcrow==479 ? 479:srcrow+1;
      expected={image_at(0,srcrow,srcx),image_at(0,srcrow,nextx),image_at(0,nextr,srcx),image_at(0,nextr,nextx),
       image_at(1,srcrow,srcx),image_at(1,srcrow,nextx),image_at(1,nextr,srcx),image_at(1,nextr,nextx)};
      observed={a00,a10,a01,a11,b00,b10,b01,b11};
      if(observed!==expected)begin errors=errors+1;if(errors<5)$display("[FAIL] neighbor y=%0d x=%0d expected=%h actual=%h",row,col,expected,observed);end
      comparisons=comparisons+8;
     end
    end
   end
  end
  running=0;coord_valid=0;errors=errors+missing+audio_missing;
  if(fault||adapter_fault||mem_error||physical.protocol_errors)errors=errors+1;
  if(audio_pairs<790||physical.refresh_events<100)errors=errors+1;
  $display("[TB] geometry mode=%0d RD_LAT=%0d",MODE,READ_LAT);
  $display("[TB] pressure MEM=%0d pixel_comparisons=%0d missing_pixels=%0d PCM=%0d missing_PCM=%0d refresh=%0d errors=%0d",MEM_MHZ,comparisons,missing,audio_pairs,audio_missing,physical.refresh_events,errors);
  if(!errors)$display("[PASS] full HD dual-stream eight-neighbor scan plus live 48kHz PCM through shared physical App bus");
  done=1;
 end
 initial begin #100000000;if(!done)begin errors = errors + 1;$display("[FAIL] bounded shared memory timeout");done=1;end end

function signed [8:0] v_cast_s9; input signed [8:0] value; begin  v_cast_s9=value;   end endfunction
function signed [9:0] v_cast_s10; input signed [9:0] value; begin  v_cast_s10=value;   end endfunction
function [15:0] v_cast_u16; input [15:0] value; begin  v_cast_u16=value;   end endfunction
function signed [15:0] v_cast_s16; input signed [15:0] value; begin  v_cast_s16=value;   end endfunction
endmodule
module tb_v3_hd_stream_budget_0_lat4;
 wire done;v3_hd_stream_budget_test #(.MODE(0),.READ_LAT(4)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_hd_stream_budget_0_lat4 done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
module tb_v3_hd_stream_budget_1_lat4;
 wire done;v3_hd_stream_budget_test #(.MODE(1),.READ_LAT(4)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_hd_stream_budget_1_lat4 done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
module tb_v3_hd_stream_budget_2_lat4;
 wire done;v3_hd_stream_budget_test #(.MODE(2),.READ_LAT(4)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_hd_stream_budget_2_lat4 done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
module tb_v3_hd_stream_budget_3_lat4;
 wire done;v3_hd_stream_budget_test #(.MODE(3),.READ_LAT(4)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_hd_stream_budget_3_lat4 done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
module tb_v3_hd_stream_budget_0_lat11;
 wire done;v3_hd_stream_budget_test #(.MODE(0),.READ_LAT(11)) t(done);
 initial begin wait(done);$display("[TB] tb_v3_hd_stream_budget_0_lat11 done comparisons=%0d errors=%0d",t.comparisons,t.errors);$finish;end
endmodule
