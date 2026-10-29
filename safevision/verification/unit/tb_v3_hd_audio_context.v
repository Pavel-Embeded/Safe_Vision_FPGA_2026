`timescale 1ns/1ps
module tb_v3_hd_audio_context;
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
    if(pcm[i*32+:32]!==gold[i*2000+received[i]%2000])begin $display("[FAIL] WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[i*2000+received[i]%2000]); $finish; end 
    received[i]<=received[i]+1;checks<=checks+1;
   end end 
  end
 end
 always @(negedge clk)if(rst_n)begin
  begin : v_loop_2 integer i; for( i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0); end 
 end
 reg[17:0] saved_words[0:3];reg[3:0] split_sample_seen=0;reg highest_address_seen=0;
 initial begin : v_loop_3 integer t; for( t=0;t<4;t=t+1)saved_words[t]=0; end 
 always @(posedge clk)if(rst_n)begin
  if(d.state==d.Q_SAVE)begin
   if(d.context_address>71||d.context_index>17||(d.context_index==0&&(!d.pauseable||d.fvalid||d.sample_valid)))
    begin $display("[FAIL] context save outside RAM/sector quiescence addr=%0d index=%0d",d.context_address,d.context_index); $finish; end 
   saved_words[d.active][d.context_index]<=1;
   if(d.context_address==71)highest_address_seen<=1;
   if(d.context_index==0&&d.wp.phase==2)split_sample_seen[d.active]<=1;
  end
  if(d.load_context&&d.phase!=0)begin $display("[FAIL] context restore before sector owner retires"); $finish; end 
 end
 initial begin
  $readmemh("audio_disk_unaligned.mem",disk);$readmemh("audio_pcm_unaligned.mem",gold);
  begin : v_loop_4 integer i; for( i=0;i<4;i=i+1)received[i]=0; end 
  #30;rst_n=1;wait(indexed);
  if(found!=15||fallback!=0)begin $display("[FAIL] complete-root matching high keys found=%h fallback=%h",found,fallback); $finish; end 
  wait(received[0]>=2100&&received[1]>=2100&&received[2]>=2100&&received[3]>=2100);

  fill=0;repeat(250000)@(posedge clk);
  if(fallback!=0)begin $display("[FAIL] intentional cache pause incorrectly timed out"); $finish; end 
  fill=15;wait(received[0]>=2300&&received[3]>=2300);
  begin : v_loop_5 integer t; for( t=0;t<4;t=t+1)if(!(&saved_words[t]))begin $display("[FAIL] uncovered context words slot=%0d mask=%h",t,saved_words[t]); $finish; end  end 
  if(!highest_address_seen||split_sample_seen!=15)begin $display("[FAIL] context last address or cross-sector half-sample missing"); $finish; end 
  $display("[PASS] four18word contexts addresses0..71, highest BCD9999, half-PCM split at allsector boundaries, EOFloop, stalls");
  $display("PASS tb_v3_hd_audio_context errors=0 comparisons=%0d",checks);$finish;
 end
 initial begin #10000000;begin $display("[FAIL] wav watchdog counts %0d %0d %0d %0d",received[0],received[1],received[2],received[3]); $finish; end end

 reg[287:0] before_save;reg check_rotation=0;
 always @(posedge clk)if(rst_n)begin
  if(d.state==d.Q_SAVE0)before_save<=d.export_context;
  if(d.state==d.Q_SAVE)begin
   if(d.rd_en||d.pcm_valid!=0)begin $display("[FAIL] SAVE shift leaked SD/PCM output"); $finish; end 
   if(d.context_index==17)check_rotation<=1;
  end
  if(check_rotation)begin
   if(d.export_context!==before_save)begin $display("[FAIL] 18-word context rotation failed exact restoration"); $finish; end 
   check_rotation<=0;
  end
 end else check_rotation<=0;
endmodule
