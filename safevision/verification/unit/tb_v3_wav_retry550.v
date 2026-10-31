`timescale 1ns/1ps
module tb_v3_wav_retry550;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 wire en,dr,indexed,descriptor_ready;wire[31:0] addr;wire[15:0] len;wire[3:0] valid,found,fallback;wire[127:0] pcm;
 reg ready=1,dv=0,last=0,done=0,reading=0,descriptor_valid=0;reg[7:0] data=0;reg[1:0] descriptor_slot=0;
 reg[3:0] pcm_ready=15;reg[7:0] disk[0:65535];reg[31:0] gold[0:599];
 integer cycles=0,cnt=0,lba=0,received[0:3],comparisons=0,errors=0,requests=0,phase=0,guard=0;
 v3_wav_source #(.PREINDEXED(1)) d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),.cache_keys(64'd0),
 .sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),
 .slot_fill(4'hf),.sector_room(4'hf),.pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pcm_ready),.index_done(indexed),.fallback(fallback),.found(found),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),.data_last(last),.rd_done(done),
 .timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.external_service_ready(1'b0),.core_rsp(837'd0),
 .media_descriptor_valid(descriptor_valid),.media_descriptor_ready(descriptor_ready),.media_descriptor_slot(descriptor_slot),.media_descriptor({32'd54,32'd4}),.media_descriptor_found(1'b1));
 always @(posedge clk)begin
  if(!rst_n)begin ready<=1;dv<=0;last<=0;done<=0;reading<=0;cycles<=0;end
  else begin
   cycles<=cycles+1;done<=0;
   if(en&&ready)begin ready<=0;reading<=1;lba<=addr;cnt<=0;requests=requests+1;
    if(len!=1||addr>=128)begin errors=errors+1;$display("[FAIL] WAV retry sector request");end
   end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycles%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   begin : v_loop_1 integer i; for( i=0;i<4;i=i+1)if(valid[i]&&pcm_ready[i])begin
    comparisons=comparisons+1;
    if(phase==1||pcm[i*32+:32]!==gold[received[i]%600])begin
     errors=errors+1;if(errors<10)$display("[FAIL] retried PCM phase%0d slot%0d n%0d got%h exp%h",phase,i,received[i],pcm[i*32+:32],gold[received[i]%600]);
    end
    received[i]<=received[i]+1;
   end end
  end
 end
 always @(negedge clk)if(rst_n)begin : v_loop_2 integer i; for( i=0;i<4;i=i+1)pcm_ready[i]=cycles%(5+i)!=0; end
 task send_descriptors;begin begin
  begin : v_loop_3 integer s; for( s=0;s<4;s=s+1)begin
   descriptor_slot=s;descriptor_valid=1;while(!descriptor_ready)@(negedge clk);
   @(negedge clk);descriptor_valid=0;repeat(5)@(negedge clk);
  end end
 end  end endtask
 task check(input  ok,input [4095:0] message);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s",message);end   end endtask
 initial begin
  $readmemh("wav_retry_disk.mem",disk);$readmemh("wav_retry_pcm.mem",gold);begin : v_loop_4 integer i; for( i=0;i<4;i=i+1)received[i]=0; end
  repeat(4)@(negedge clk);rst_n=1;send_descriptors();wait(indexed);
  check(found==15&&fallback==0,"all supplied primary descriptors committed before playback");
  guard=0;
  while(!(received[0]>=1200&&received[1]>=1200&&received[2]>=1200&&received[3]>=1200)&&guard<300000)begin @(negedge clk);guard = guard + 1;end
  check(received[0]>=1200&&received[1]>=1200&&received[2]>=1200&&received[3]>=1200,"each real retried WAV emits two complete independently checked PCM loops");
  check(fallback==0,"bad primary and bad directory fallback skipped in favour of real valid arbitrary-name WAV");
  check(requests>32,"real directory/FAT/data reads used rather than fabricated PCM");
  rst_n=0;descriptor_valid=0;phase=1;repeat(4)@(negedge clk);

  disk[30*512]=8'h58;begin : v_loop_5 integer i; for( i=0;i<4;i=i+1)received[i]=0; end requests=0;
  rst_n=1;send_descriptors();wait(indexed);guard=0;
  while(fallback!=15&&guard<300000)begin @(negedge clk);guard=guard+1;end
  check(fallback==15,"all-invalid WAV set terminates in per-slot ROM fallback");
  check(received[0]==0&&received[1]==0&&received[2]==0&&received[3]==0,"invalid headers never emit any PCM");
  check(requests>8&&requests<100,"bounded scan retries do not loop on same failed descriptor");
  if(!errors)$display("[PASS] descriptor acceptance, corrupted WAV rescan, exact stereo PCM across fragmented clusters/EOF loop, finite all-bad ROM fallback");
  $display("[TB] tb_v3_wav_retry550 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin repeat(2000000)@(negedge clk);$display("[FAIL] WAV retry watchdog errors=1");$finish;end
endmodule
