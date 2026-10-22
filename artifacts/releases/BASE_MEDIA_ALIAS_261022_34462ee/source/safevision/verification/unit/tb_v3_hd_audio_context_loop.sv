`timescale 1ns/1ps
module tb_v3_hd_audio_context_loop;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;wire en;wire [31:0] addr;wire [15:0] len;
 reg ready=1;reg [7:0] data=0;reg dv=0,last=0,done=0;wire dr;
 wire [127:0] pcm;wire [3:0] valid;reg [3:0] pr=4'hf;wire indexed;wire [3:0] fallback,found;
 reg [3:0] fill=4'hf;reg [7:0] disk[0:65535];reg [31:0] gold[0:7999];
 integer cnt=0,lba=0,received[0:3],checks=0,cycle=0;reg reading=0;
 v3_wav_source d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
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
    if(i!=3&&pcm[i*32+:32]!==gold[i*2000+received[i]%2000])$fatal(1,"WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[i*2000+received[i]%2000]);
    received[i]<=received[i]+1;if(i!=3)checks<=checks+1;
   end
  end
 end
 always @(negedge clk)if(rst_n)begin
  for(integer i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0);
 end
 task put32(input integer address,input[31:0] value);
  begin for(integer z=0;z<4;z=z+1)disk[address+z]=value[z*8+:8];end
 endtask
 integer good_before,bad_hops;
 initial begin
  $readmemh("audio_disk_unaligned.mem",disk);$readmemh("audio_pcm_unaligned.mem",gold);
  // Highest slot SV9999: plausible long RIFF but FAT chain 19->23->19 cycles.
  // Other slots loop every 16 clusters, repeatedly resetting their OWN walk epochs.
  put32(16*512+27*32+28,120054);put32(33*512+4,120046);put32(33*512+50,120000);
  put32(512+23*4,19);
  for(integer i=0;i<4;i=i+1)received[i]=0;
  #30;rst_n=1;wait(indexed);wait(fallback[3]);
  if(fallback!=8||received[3]<120*100)$fatal(1,"context-specific cycle counter wrong fb=%h badpairs=%0d",fallback,received[3]);
  good_before=received[0];wait(received[0]>=good_before+500);
  if(fallback!=8||received[1]<2000||received[2]<2000)$fatal(1,"good tracks blocked by bad context");
  $display("[PASS] saved per-track FAT hop limit catches highest-slot cycle despite other tracks resetting and looping");
  $display("PASS tb_v3_hd_audio_context_loop errors=0 comparisons=%0d bad_track_pairs=%0d",checks,received[3]);$finish;
 end
 initial begin #50000000;$fatal(1,"context loop watchdog fb=%h pairs=%0d hop=%0d",fallback,received[3],d.hop_count);end
endmodule
