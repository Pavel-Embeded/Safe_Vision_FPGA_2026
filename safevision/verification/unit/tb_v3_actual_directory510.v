`timescale 1ns/1ps
module tb_v3_actual_directory510;
 reg clk=0,rst_n=0,start=0,ready=0;always #5 clk=~clk;
 reg[7:0]sector[0:4095],data=0;reg[175:0]expected[0:19];reg valid=0,rdone=0;wire take,request,done,bad,ev,ws;wire[87:0]name;
 wire[31:0]clus,size,addr;wire[15:0]index;wire[7:0]attr;reg walking_done=0;
 fat32_directory_scanner #(.SV_MEDIA_ONLY(1)) scan(.clk(clk),.rst_n(rst_n),.scan_en(start),.scan_done(done),.dir_bad(bad),.err_code(),.err_detail(),.dbg_state(),
 .sec_per_clus(8'd8),.root_clus(32'd2),.root_dir_lba(32'd40960),.data_start_lba(32'd40960),.ent_name(name),.ent_attr(attr),.ent_first_clus(clus),.ent_size(size),.ent_index(index),.ent_valid(ev),.ent_ready(ready),
 .sd_rd_addr(addr),.sd_rd_len(),.sd_rd_en(request),.sd_rd_ready(1'b1),.sd_data(data),.sd_data_valid(valid),.sd_data_ready(take),.sd_data_last(1'b0),.sd_rd_done(rdone),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0),
 .wk_cur_clus(),.wk_start(ws),.wk_rst_walk(),.wk_busy(1'b0),.wk_done(walking_done),.wk_next_clus(32'd0),.wk_eoc(1'b1),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0));
 reg clear_index=0,commit_index=0;reg[1:0]select_slot=0;wire index_done,select_valid,wav_valid;
 wire[3:0]file_count,file_valid;wire[15:0]selected_key;wire[31:0]selected_cluster,wav_cluster;
 file_index idx(.clk(clk),.rst_n(rst_n),.ent_name(name),.ent_attr(attr),.ent_first_clus(clus),.ent_size(size),.ent_index(index),.ent_valid(ev&&ready),.ent_ready(),
 .idx_clear(clear_index),.idx_commit(commit_index),.idx_done(index_done),.file_cnt(file_count),.file_valid(file_valid),.insufficient(),.err_code(),.err_detail(),
 .cursor_key(16'd0),.sel_key(selected_key),.sel_slot(select_slot),.sel_first_clus(selected_cluster),.sel_size(),.sel_valid(select_valid),.sel_wav_first_clus(wav_cluster),.sel_wav_size(),.sel_wav_valid(wav_valid),.bmp_seen(),.wav_seen());
 integer errors=0,comparisons=0,p=0,received=0,cycle=0,base=0,requests=0,pending_walk=0;reg sending=0;
 reg holding=0;reg[175:0]held;
 task check(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<8)$display("[FAIL] %s entry%0d",msg,received);end end  end endtask
 always @(negedge clk)begin cycle=cycle+1;ready=(cycle%31>9);end
 always @(posedge clk)begin
  rdone<=0;walking_done<=0;
  if(!rst_n)begin sending<=0;valid<=0;holding<=0;end
  else begin
   if(holding)check(ev&&{name,attr,clus,size,index}===held,"published entry stays immutable");
   holding<=ev&&!ready;held<={name,attr,clus,size,index};
   if(ev&&ready)begin check(received<20,"no deleted/LFN/invalid entry");check({name,attr,clus,size,index}===expected[received],"actual card directory name and all metadata");received=received+1;end
   if(request)begin
    check(addr==40960+requests,"each of eight exact physical root sectors requested once");requests=requests+1;
    base<=(addr-40960)*512;sending<=1;p<=0;data<=sector[(addr-40960)*512];valid<=1;
   end else if(sending)begin
    if(valid&&take)begin
     if(p==511)begin sending<=0;valid<=0;rdone<=1;end
     else begin p<=p+1;data<=sector[base+p+1];valid<=cycle%7!=0;end
    end else if(!valid)valid<=1;
   end
   if(ws)pending_walk<=3;
   else if(pending_walk!=0)begin pending_walk<=pending_walk-1;if(pending_walk==1)walking_done<=1;end
  end
 end
 reg[31:0]bc[0:3],wc[0:3];integer slot;
 initial begin
  $readmemh("actual_root509.mem",sector);$readmemh("actual_entries509.mem",expected);
  bc[0]=6;bc[1]=288;bc[2]=514;bc[3]=2736;wc[0]=2264;wc[1]=1136;wc[2]=1512;wc[3]=1888;
  repeat(4)@(negedge clk);rst_n=1;clear_index=1;@(negedge clk);clear_index=0;start=1;@(negedge clk);start=0;
  wait(done);repeat(3)@(negedge clk);check(!bad&&received==20&&requests==8,"all real card root entries consumed");
  commit_index=1;@(negedge clk);commit_index=0;wait(index_done);repeat(2)@(negedge clk);
  check(file_count==4&&file_valid==15,"four new pictures selected ahead of old group");
  for(slot=0;slot<4;slot=slot+1)begin select_slot=slot;repeat(4)@(negedge clk);
   check(select_valid&&selected_key==slot+1&&selected_cluster==bc[slot],"actual new BMP cluster and numeric ID");
   check(wav_valid&&wav_cluster==wc[slot],"actual matching WAV cluster");
  end
  if(errors==0)$display("[PASS] CRC-captured physical card directory replay, complete metadata, new selection and four WAV pairs");
  $display("[TB] tb_v3_actual_directory510 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
