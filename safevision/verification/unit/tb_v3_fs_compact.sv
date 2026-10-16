`timescale 1ns/1ps
module tb_v3_fs_compact;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,context_load=0,context_enable=0,stream_enable=0;
 reg[135:0] context_in=0;wire[135:0] context_out;
 reg[31:0] first_clus,file_size,data_base;reg[7:0] spc;
 wire idle,busy,done,error;wire[7:0] ec,ed,byte_data,dbg;
 wire[31:0] bytes_rd,wk_cur,rd_addr;wire[3:0] dbg4;
 wire valid,sof,eof,wk_start,wk_reset,rd_en,sd_ready;
 wire[15:0] rd_len;reg ready=0;
 reg[7:0] sd_data=0;reg sd_valid=0,sd_last=0,sd_done=0;
 reg wk_done=0;reg[31:0] wk_next=0;
 v3_file_streamer_compact_ctx dut(.clk(clk),.rst_n(rst_n),.start(start),
  .context_load(context_load),.context_in(context_in),.context_out(context_out),
  .context_enable(context_enable),.stream_enable(stream_enable),.idle_between_sectors(idle),
  .first_clus(first_clus),.file_size(file_size),.busy(busy),.done(done),.error(error),
  .err_code(ec),.err_detail(ed),.bytes_rd(bytes_rd),.dbg_state(dbg4),
  .data(byte_data),.valid(valid),.ready(ready),.sof(sof),.eof(eof),
  .sec_per_clus(spc),.fat_start_lba(32'd1),.data_start_lba(data_base),.total_clus(32'h0fffffff),
  .wk_cur_clus(wk_cur),.wk_start(wk_start),.wk_rst_walk(wk_reset),.wk_busy(1'b0),
  .wk_done(wk_done),.wk_next_clus(wk_next),.wk_eoc(1'b0),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0),
  .sd_rd_addr(rd_addr),.sd_rd_len(rd_len),.sd_rd_en(rd_en),.sd_rd_ready(1'b1),
  .sd_data(sd_data),.sd_data_valid(sd_valid),.sd_data_ready(sd_ready),.sd_data_last(sd_last),
  .sd_rd_done(sd_done),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0));
 integer errors=0,comparisons=0,track=0,geom,variant,t,i,guard;
 integer received[0:3],lengths[0:3],sector_number[0:3];
 reg[135:0] contexts[0:3];reg[3:0] saved,finished;
 reg transaction=0;integer sd_index=0,sector_logical=0;
 integer cycle=0;reg[31:0] current_lba;
 function[7:0] pattern;input integer tr,position;begin
  pattern=(position*13)^(position>>7)^(tr*89)^8'ha7;end endfunction
 function[31:0] cluster;input integer tr,logical_sector;begin
  cluster=32'd17+tr*32'd1024+(logical_sector/spc)*32'd7;end endfunction
 task ck;input condition;input[511:0] label_text;begin
  comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;if(errors<10)$display("[FAIL] %s geom=%0d track=%0d count=%0d",label_text,spc,track,received[track]);end
 end endtask
 // An independent card producer and fragmented-cluster oracle. Changes only
 // on accepted bytes; downstream bubbles never alter SD or output identity.
 always @(posedge clk)if(rst_n)begin
  cycle=cycle+1;
  if(valid&&ready&&context_enable&&stream_enable)begin
   ck(byte_data===pattern(track,received[track]),"logical file byte identity across four resumed contexts");
   ck(sof===(received[track]==0)&&eof===(received[track]==lengths[track]-1),"SOF/EOF only on exact first/final file byte");
   received[track]=received[track]+1;
  end
  if(rd_en)begin
   ck(!transaction&&rd_len==1,"single complete sector transaction");
   current_lba=data_base+(cluster(track,sector_number[track])-2)*spc+(sector_number[track]%spc);
   ck(rd_addr===current_lba,"full 32bit wrapping LBA, SPC and fragmented cluster oracle");
   sector_logical=sector_number[track];sector_number[track]=sector_number[track]+1;
   transaction=1;sd_index=0;
  end
  if(sd_valid&&sd_ready)begin
   if(sd_index==511)begin transaction=0;sd_index=0;end else sd_index=sd_index+1;
  end
 end
 always @(negedge clk)begin
  ready=rst_n&&(cycle%7!=2)&&(cycle%11!=4);
  wk_done=rst_n&&wk_start;wk_next=wk_cur+32'd7;
  sd_valid=transaction&&(cycle%5!=1);sd_last=sd_index==511;
  sd_data=pattern(track,sector_logical*512+sd_index);sd_done=0;
 end
 initial begin
  for(geom=0;geom<8;geom=geom+1)for(variant=0;variant<2;variant=variant+1)begin
   @(negedge clk);rst_n=0;context_enable=0;stream_enable=0;context_load=0;start=0;
   transaction=0;sd_valid=0;cycle=0;spc=1<<geom;
   data_base=variant?32'hffffff70:32'd100;
   saved=0;finished=0;
   for(t=0;t<4;t=t+1)begin received[t]=0;sector_number[t]=0;lengths[t]=(spc+1)*512+t*3+1;end
   repeat(4)@(negedge clk);rst_n=1;track=0;
   while(finished!=4'hf)begin
    if(!finished[track])begin
     first_clus=cluster(track,0);file_size=lengths[track];
     if(saved[track])begin
      context_in=contexts[track];context_load=1;@(negedge clk);context_load=0;
      ck(bytes_rd==received[track]&&!rd_en&&!wk_start&&!valid&&!error,"restore rebuilds safe idle commands and per-track byte count");
     end else begin
      // A new track gets the same reset that the source's Q_RESET provides.
      rst_n=0;@(negedge clk);rst_n=1;
      start=1;context_enable=1;stream_enable=1;@(negedge clk);start=0;
     end
     context_enable=1;stream_enable=1;guard=0;
     // Do not pause before the first live byte of this dispatch.
     i=received[track];
     while(!done&&!(idle&&!valid&&received[track]>i))begin
      @(negedge clk);guard=guard+1;
      if(guard>10000)begin $display("[FAIL] sector progress timeout errors=1");$finish;end
     end
     context_enable=0;stream_enable=0;
     ck(!error&&!transaction&&!rd_en,"yield only after a complete sector and drained byte");
     if(done)begin
      ck(received[track]==lengths[track],"complete file length exactly, no padding bytes published");finished[track]=1;
     end else begin contexts[track]=context_out;saved[track]=1;end
     repeat(3)@(negedge clk);
    end
    track=(track+1)%4;
   end
  end
  if(!errors)$display("[PASS] compact 136bit filesystem contexts across all SPC, wrap, fragments and stalls");
  $display("[TB] tb_v3_fs_compact done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #300000000;$display("[FAIL] filesystem oracle timeout errors=1");$finish;end
endmodule
