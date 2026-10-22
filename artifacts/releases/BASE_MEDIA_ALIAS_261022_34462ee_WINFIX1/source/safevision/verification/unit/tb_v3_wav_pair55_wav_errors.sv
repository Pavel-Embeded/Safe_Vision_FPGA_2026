`timescale 1ns/1ps
module tb_v3_wav_pair55_wav_errors;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;wire en;wire [31:0] addr;wire [15:0] len;
 reg ready=1;reg [7:0] data=0;reg dv=0,last=0,done=0;wire dr;
 wire [127:0] pcm;wire [3:0] valid;reg [3:0] pr=4'hf;wire indexed;wire [3:0] fallback,found;
 reg [3:0] fill=4'hf;reg [7:0] disk[0:65535];reg [31:0] gold[0:7999];
 integer cnt=0,lba=0,received[0:3],checks=0,cycle=0;reg reading=0;reg crc=0;reg [1:0] scenario=0;integer rejected=0;
 wire[127:0]r_pcm;wire[3:0]r_valid,r_fallback,r_found;wire r_indexed,r_en,r_dr;wire[31:0]r_addr;wire[15:0]r_len;wire[444:0]d_core,r_core;integer miter_errors=0,miter_comparisons=0;
 always@(posedge clk or negedge rst_n)begin #1;miter_comparisons++;if({pcm,valid,indexed,fallback,found,en,addr,len,dr,d_core}!=={r_pcm,r_valid,r_indexed,r_fallback,r_found,r_en,r_addr,r_len,r_dr,r_core})begin miter_errors++;if(miter_errors<8)$display("[FAIL] full WAV public-interface miter");end end
 v3_wav_source d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pr),.index_done(indexed),.fallback(fallback),.found(found),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(crc),.err_code(8'h02),.err_detail(8'h22),.core_cmd(d_core));
 v3_wav_fallback_reference55 old_source(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(r_pcm),.pcm_valid(r_valid),.pcm_ready(pr),.index_done(r_indexed),.fallback(r_fallback),.found(r_found),
 .rd_en(r_en),.rd_addr(r_addr),.rd_len(r_len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(r_dr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(crc),.err_code(8'h02),.err_detail(8'h22),.core_cmd(r_core));
 always @(posedge clk)begin
  if(!rst_n)begin ready<=1;reading<=0;dv<=0;last<=0;done<=0;cnt<=0;crc<=0;end
  else begin
   cycle<=cycle+1;done<=0;crc<=0;
   if(en&&ready)begin
    if((scenario==0&&addr==17)||(scenario==1&&addr==31))begin
     crc<=1;done<=1;ready<=1;reading<=0;rejected<=rejected+1;
    end else begin ready<=0;reading<=1;lba<=addr;cnt<=0;end
    if(len!=1||addr>=128)$fatal(1,"WAV sector request");end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycle%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   for(integer i=0;i<4;i=i+1)if(valid[i]&&pr[i])begin
    if(pcm[i*32+:32]!==gold[i*2000+received[i]%2000])$fatal(1,"WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[i*2000+received[i]%2000]);
    received[i]<=received[i]+1;checks<=checks+1;
   end
  end
 end
 always @(negedge clk)if(rst_n)begin
  for(integer i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0);
 end
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  for(integer i=0;i<4;i=i+1)received[i]=0;
  #30;rst_n=1;wait(indexed);repeat(20)@(posedge clk);
  if(fallback!=15||received[0]!=0||received[3]!=0)$fatal(1,"directory CRC must reject scan before playback");
  rst_n=0;scenario=1;
  // Missing SV9999.WAV; malformed 44.1kHz SV9000.WAV; CRC-failed first sector SV1000.WAV.
  disk[16*512+27*32]=8'he5;disk[32*512+24]=8'h44;disk[32*512+25]=8'hac;
  for(integer i=0;i<4;i=i+1)received[i]=0;
  #30;rst_n=1;wait(indexed);wait(fallback==14);wait(received[0]>=300);
  if(received[1]!=0||received[2]!=0||received[3]!=0||rejected!=2)$fatal(1,"bad/missing WAV leaked PCM or CRC transaction count");
  $display("[PASS] zero-byte checked-sector CRC failures, incomplete directory, missing key, bad rate, independent good WAV");
  $display("PASS tb_v3_wav_pair55_wav_errors errors=%0d comparisons=%0d",miter_errors,miter_comparisons);$finish;
 end
 initial begin #5000000;$fatal(1,"WAV error watchdog fb=%h indexed=%b received=%0d",fallback,indexed,received[0]);end
endmodule
