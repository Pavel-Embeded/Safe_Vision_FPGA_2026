`timescale 1ns/1ps
module tb_v3_wav_context730;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 wire en,dr,indexed,descriptor_ready;wire[31:0]addr;wire[15:0]len;wire[3:0]valid,found,fallback;wire[127:0]pcm;
 reg ready=1,dv=0,last=0,done=0,reading=0,descriptor_valid=0;reg[7:0]data=0;reg[1:0]descriptor_slot=3;
 reg[63:0]descriptor;reg[3:0]pcm_ready=15;reg[7:0]disk[0:524287];reg[31:0]gold[0:1199];
 wire[444:0]cmd;wire[836:0]rsp;
 integer cycles=0,cnt=0,lba=0,received[0:3],comparisons=0,errors=0,requests=0,guard=0;
 integer restores[0:3],saves[0:3];reg[3:0]partial_saved=0;reg[319:0]saved_context[0:3];
 always @*case(descriptor_slot)
    2'd0:descriptor={32'd67282,32'd10};
    2'd1:descriptor={32'd67794,32'd210};
    2'd2:descriptor={32'd68306,32'd410};
    2'd3:descriptor={32'd68818,32'd610};
 endcase
 v3_wav_source #(.EXTERNAL_SERVICE(1),.PREINDEXED(1)) d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),.cache_keys(64'd0),
 .sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd1000),
 .slot_fill(4'hf),.sector_room(4'hf),.pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pcm_ready),.index_done(indexed),.fallback(fallback),.found(found),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),.data_last(last),.rd_done(done),
 .timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.external_service_ready(1'b1),.core_cmd(cmd),.core_rsp(rsp),
 .media_descriptor_valid(descriptor_valid),.media_descriptor_ready(descriptor_ready),.media_descriptor_slot(descriptor_slot),.media_descriptor(descriptor),.media_descriptor_found(1'b1));
 v3_shared_fs_service #(.FLEX_FILES(1)) svc(.clk(clk),.rst_n(rst_n),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd1000),.core_cmd(cmd),.core_rsp(rsp),.name_address(8'd0),.name_data(),.name_length());
 task check(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;if(errors<20)$display("[FAIL] %s",message);end end endtask
 always @(posedge clk)begin
  if(!rst_n)begin ready<=1;dv<=0;last<=0;done<=0;reading<=0;cycles<=0;end
  else begin
   cycles<=cycles+1;done<=0;
   if(en&&ready)begin ready<=0;reading<=1;lba<=addr;cnt<=0;requests++;
    check(len==1&&addr<1024,"bounded single sector geometry");
   end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycles%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   for(integer i=0;i<4;i++)if(valid[i]&&pcm_ready[i])begin
    check(pcm[i*32+:32]===gold[i*300+received[i]%300],"independent per-track stereo data and EOF loop");received[i]<=received[i]+1;
   end
   if(d.state==6&&d.context_index==0)begin
    saved_context[d.active]=d.export_context;saves[d.active]++;
    if(d.wp.state==2&&d.wp.index==6)partial_saved[d.active]=1;
   end
   if(d.state==9)begin restores[d.active]++;check(d.export_context===saved_context[d.active],"all320 bits restored atomically from physical shared context RAM");end
   check(fallback==0,"no per-slot fallback for valid cross-boundary files");
  end
 end
 always @(negedge clk)if(rst_n)for(integer i=0;i<4;i++)pcm_ready[i]=cycles%(5+i)!=0;
 initial begin
  $readmemh("wav730_disk.mem",disk);$readmemh("wav730_pcm.mem",gold);
  for(integer i=0;i<4;i++)begin received[i]=0;restores[i]=0;saves[i]=0;saved_context[i]=0;end
  repeat(4)@(negedge clk);rst_n=1;
  for(integer s=0;s<4;s++)begin descriptor_slot=s;descriptor_valid=1;while(!descriptor_ready)@(negedge clk);@(negedge clk);descriptor_valid=0;repeat(5)@(negedge clk);end
  wait(indexed);$display("[TRACE] found=%h fallback=%h received_mask=%h",found,fallback,d.preindexed_received);check(found==15,"four preindexed descriptors accepted");
  while(!(received[0]>=600&&received[1]>=600&&received[2]>=600&&received[3]>=600)&&guard<3000000)begin @(negedge clk);guard++;end
  for(integer i=0;i<4;i++)begin check(received[i]>=600,"two full exact PCM loops per track");check(saves[i]>100&&restores[i]>100,"real per-track context swapping across many sectors");end
  check(partial_saved==15,"every track saved in middle of length field at byte512");
  check(d.CTX_WORDS==20&&d.CTX_BITS==313,"production extended context geometry");
  if(errors==0)$display("[PASS] four distinct WAVs, split 32-bit odd-length fields, context RAM atomicity, exact stereo PCM, backpressure, EOF loops");
  $display("[TB] tb_v3_wav_context730 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin repeat(4000000)@(negedge clk);$display("[FAIL] context watchdog errors=1");$finish;end
endmodule
