`timescale 1ns/1ps
module tb_v3_registered_wav_reset;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;wire en;wire [31:0] addr;wire [15:0] len;
 reg ready=1;reg [7:0] data=0;reg dv=0,last=0,done=0;wire dr;
 wire [127:0] pcm;wire [3:0] valid;reg [3:0] pr=4'hf;wire indexed;wire [3:0] fallback,found;
 reg [3:0] fill=4'hf;reg [7:0] disk[0:65535];reg [31:0] gold[0:7999];
 integer cnt=0,lba=0,received[0:3],checks=0,cycle=0,errors=0,comparisons=0,ri,mask;reg[1:0] forced_rr=0;reg[3:0] forced_found=0;wire[444:0] acmd,bcmd;wire ben,bdr,bindexed;wire[31:0]baddr;wire[15:0]blen;wire[127:0]bpcm;wire[3:0]bvalid,bfallback,bfound;reg reading=0;integer skew_checks=0;realtime last_clk=0,last_reset=0;
 v3_wav_source d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pr),.index_done(indexed),.fallback(fallback),.found(found),.core_cmd(acmd),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0));
 v3_wav_reset_reference original(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(bpcm),.pcm_valid(bvalid),.pcm_ready(pr),.index_done(bindexed),.fallback(bfallback),.found(bfound),.core_cmd(bcmd),
 .rd_en(ben),.rd_addr(baddr),.rd_len(blen),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(bdr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0));
 always@(posedge clk)last_clk=$realtime;
 always@(rst_n)last_reset=$realtime;
 always@(d.kernel_rst_n)if($realtime>100)begin
  comparisons++;
  if($realtime!=last_clk&&$realtime!=last_reset)begin
   errors++;if(errors<12)$display("[FAIL] asynchronous kernel reset decode hazard");
  end
 end


 always@(posedge clk)if(rst_n&&d.state==7&&skew_checks==0)begin
  #0.2;force d.state=4'd7;#0.2;force d.state=4'd2;
  #0.2;force d.state=4'd8;#0.2;release d.state;skew_checks++;
 end
 always @(posedge clk)begin
  if(rst_n)begin
   cycle<=cycle+1;done<=0;
   if(en&&ready)begin ready<=0;reading<=1;lba<=addr;cnt<=0;
    if(len!=1||addr>=128)begin errors++;$display("[FAIL] WAV sector request");end end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycle%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   for(integer i=0;i<4;i=i+1)if(valid[i]&&pr[i])begin
    if(i!=3&&pcm[i*32+:32]!==gold[i*2000+received[i]%2000])begin errors++;if(errors<12)$display("[FAIL] independent WAV PCM decoder");end
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


  put32(16*512+27*32+28,120054);put32(33*512+4,120046);put32(33*512+50,120000);
  put32(512+23*4,19);
  for(integer i=0;i<4;i=i+1)received[i]=0;

  force d.rr=forced_rr;force original.rr=forced_rr;
  force d.found=forced_found;force original.found=forced_found;
  force d.fallback=4'd0;force original.fallback=4'd0;
  for(ri=0;ri<4;ri++)for(mask=0;mask<16;mask++)begin forced_rr=ri;forced_found=mask;#1;
   comparisons++;if(d.chosen!==original.chosen||d.eligible!==original.eligible)begin errors++;$display("[FAIL] exact round-robin selection of all64 request cases");end
  end
  release d.rr;release original.rr;release d.found;release original.found;release d.fallback;release original.fallback;
  repeat(4)@(negedge clk);rst_n=1;
  repeat(2000000)@(negedge clk);
  if(fallback!=8||received[3]<12000||received[0]<2000||received[1]<2000||received[2]<2000)begin errors++;$display("[FAIL] fragmented good/bad context exercise did not complete");end
  if(skew_checks!=1)begin errors++;$display("[FAIL] WAV context transition skew not exercised");end
  if(errors==0)$display("[PASS] all64 round-robin masks, complete stereo tracks, repeated contexts, highest-slot cyclic FAT, full original public/kernel interface");
  $display("[TB] tb_v3_registered_wav_reset done errors=%0d comparisons=%0d PCM=%0d",errors,comparisons,checks);$finish;
 end
 always@(posedge clk)begin #0.001;if(rst_n)begin comparisons++;
  if({pcm,valid,indexed,fallback,found,en,addr,len,dr,acmd}!=={bpcm,bvalid,bindexed,bfallback,bfound,ben,baddr,blen,bdr,bcmd})begin errors++;if(errors<12)$display("[FAIL] complete original WAV/kernel/public interface differs");end
 end end
endmodule
