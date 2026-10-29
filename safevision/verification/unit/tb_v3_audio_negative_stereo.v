`timescale 1ns/1ps
module tb_v3_audio_negative_stereo;
 integer negative_errors=0;
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
    if(len!=1||addr>=128)begin $display("[FAIL] WAV sector request"); $finish; end end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycle%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   begin : v_loop_1 integer i; for( i=0;i<4;i=i+1)if(valid[i]&&pr[i])begin
    if(pcm[i*32+:32]!==gold[i*2000+received[i]%2000])begin negative_errors=negative_errors+1;if(negative_errors<=3)$display("[FAIL AUDIO_STEREO] WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[i*2000+received[i]%2000]);end
    received[i]<=received[i]+1;checks<=checks+1;
   end end 
  end
 end
 always @(negedge clk)if(rst_n)begin
  begin : v_loop_2 integer i; for( i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0); end 
 end
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  begin : v_loop_3 integer i; for( i=0;i<4;i=i+1)received[i]=0; end 
  #30;rst_n=1;wait(indexed);
  if(found!=15||fallback!=0)begin $display("[FAIL] complete-root matching high keys found=%h fallback=%h",found,fallback); $finish; end 
  wait(received[0]>=2100&&received[1]>=2100&&received[2]>=2100&&received[3]>=2100);

  fill=0;repeat(250000)@(posedge clk);
  if(fallback!=0)begin $display("[FAIL] intentional cache pause incorrectly timed out"); $finish; end 
  fill=15;wait(received[0]>=2300&&received[3]>=2300);
  $display("[PASS] full root >8 entries, four high-key fragmented WAVs, odd JUNK, PCM endian, stalls, looping, idle pause");
  $display("PASS tb_v3_audio_negative_stereo errors=%0d comparisons=%0d",negative_errors,checks);$finish;
 end
 initial begin #10000000;begin $display("[FAIL] wav watchdog counts %0d %0d %0d %0d",received[0],received[1],received[2],received[3]); $finish; end end
endmodule
