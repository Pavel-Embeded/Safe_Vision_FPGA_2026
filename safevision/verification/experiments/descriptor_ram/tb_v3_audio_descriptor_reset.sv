`timescale 1ns/1ps
module tb_v3_audio_descriptor_reset;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;wire en;wire [31:0] addr;wire [15:0] len;
 reg ready=1;reg [7:0] data=0;reg dv=0,last=0,done=0;wire dr;
 wire [127:0] pcm;wire [3:0] valid;reg [3:0] pr=4'hf;wire indexed;reg[63:0] keys=64'h0001000100010001;integer oracle_slot=0;reg common_key=1;wire [3:0] fallback,found;
 reg [3:0] fill=4'hf;reg [7:0] disk[0:65535];reg [31:0] gold[0:7999];
 integer cnt=0,lba=0,received[0:3],checks=0,cycle=0;reg reading=0;
 v3_wav_source d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(keys),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pr),.index_done(indexed),.fallback(fallback),.found(found),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0));
 always @(posedge clk)begin
  if(rst_n)begin
   cycle<=cycle+1;done<=0;
   if(en&&ready)begin ready<=0;reading<=1;lba<=addr;cnt<=0;
    if(len!=1||addr>=128)$fatal(1,"WAV sector request");end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycle%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   for(integer i=0;i<4;i=i+1)if(valid[i]&&pr[i])begin
    if(pcm[i*32+:32]!==gold[(common_key?oracle_slot:i)*2000+received[i]%2000])$fatal(1,"WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[(common_key?oracle_slot:i)*2000+received[i]%2000]);
    received[i]<=received[i]+1;checks<=checks+1;
   end
  end
 end
 always @(posedge clk)if(!rst_n)begin
  ready<=1;reading<=0;dv<=0;last<=0;done<=0;cnt<=0;lba<=0;cycle<=0;
  for(integer j=0;j<4;j=j+1)received[j]<=0;
 end
 reg[15:0] descriptor_words=0;
 always@(posedge clk)if(!rst_n)descriptor_words<=0;
 else begin
  if(d.descriptor_write)begin
   if(d.ram_address<128||d.ram_address>143)$fatal(1,"descriptor RAM address outside128..143");
   descriptor_words[d.ram_address-128]<=1;
  end
  if(d.state==d.Q_SAVE&&d.ram_address>71)$fatal(1,"context overwrote descriptors");
 end
 always @(negedge clk)if(rst_n)begin
  for(integer i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0);
 end
 integer pass;
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  // Abandon the very first descriptor after only two of its four words.
  #30;rst_n=1;wait(d.descriptor_write&&d.context_index==1);@(negedge clk);rst_n=0;
  repeat(4)@(negedge clk);
  for(pass=0;pass<3;pass=pass+1)begin
   rst_n=0;repeat(4)@(negedge clk);
   case(pass)
    0:begin keys=64'h0001000100010001;common_key=1;oracle_slot=0;end
    1:begin keys=64'h9999900010000001;common_key=0;oracle_slot=0;end
    2:begin keys=64'h9999999999999999;common_key=1;oracle_slot=3;end
   endcase
   rst_n=1;wait(indexed);
   if(found!=15||fallback!=0||descriptor_words!=16'hffff||d.descriptor_pending!=0)
    $fatal(1,"descriptor scan/pending/physical-word coverage failed pass=%0d",pass);
   wait(received[0]>=2100&&received[1]>=2100&&received[2]>=2100&&received[3]>=2100);
   fill=0;repeat(250000)@(posedge clk);
   if(fallback!=0)$fatal(1,"intentional cache pause timed out");
   fill=15;wait(received[0]>=2300&&received[3]>=2300);
   @(negedge clk);rst_n=0;
  end
  $display("[PASS] shared immutable descriptor RAM, one entry matches four slots, 16 physical words each scan, partial descriptor reset, different-key stale-RAM reset, fragmented PCM EOF loops");
  $display("PASS tb_v3_audio_descriptor_reset errors=0 comparisons=%0d",checks);$finish;
 end
 initial begin #40000000;$fatal(1,"wav watchdog counts %0d %0d %0d %0d",received[0],received[1],received[2],received[3]);end
endmodule
