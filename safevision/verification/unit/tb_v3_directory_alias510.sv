`timescale 1ns/1ps
module tb_v3_directory_alias510;
 reg clk=0,rst_n=0,start=0,ready=0;always #5 clk=~clk;
 reg[7:0]sector[0:511],data=0;reg valid=0,rdone=0;wire take,request,done,bad,ev;wire[87:0]name;
 wire[31:0]clus,size;wire[15:0]index;wire[7:0]attr;reg walking_done=0;
 fat32_directory_scanner #(.SV_MEDIA_ONLY(1)) scan(.clk(clk),.rst_n(rst_n),.scan_en(start),.scan_done(done),.dir_bad(bad),.err_code(),.err_detail(),.dbg_state(),
 .sec_per_clus(8'd1),.root_clus(32'd2),.root_dir_lba(32'd8192),.data_start_lba(32'd8192),.ent_name(name),.ent_attr(attr),.ent_first_clus(clus),.ent_size(size),.ent_index(index),.ent_valid(ev),.ent_ready(ready),
 .sd_rd_addr(),.sd_rd_len(),.sd_rd_en(request),.sd_rd_ready(1'b1),.sd_data(data),.sd_data_valid(valid),.sd_data_ready(take),.sd_data_last(1'b0),.sd_rd_done(rdone),.sd_timeout_err(1'b0),.sd_crc16_err(1'b0),.sd_err_code(8'd0),.sd_err_detail(8'd0),
 .wk_cur_clus(),.wk_start(),.wk_rst_walk(),.wk_busy(1'b0),.wk_done(walking_done),.wk_next_clus(32'd0),.wk_eoc(1'b1),.wk_error(1'b0),.wk_err_code(8'd0),.wk_err_detail(8'd0));
 integer errors=0,comparisons=0,round,slot,k,p=0,received=0,cycle=0;reg sending=0;
 reg[87:0]names[0:15],expected[0:15];integer want;
 reg clear_index=0,commit_index=0;reg[1:0]select_slot=0;wire index_done,select_valid,wav_valid;
 wire[3:0]file_count,file_valid;wire[15:0]selected_key;wire[31:0]selected_cluster,wav_cluster;
 reg[31:0]expected_bmp[0:3],expected_wav[0:3];integer selected_id;
 file_index idx(.clk(clk),.rst_n(rst_n),.ent_name(name),.ent_attr(attr),.ent_first_clus(clus),.ent_size(size),.ent_index(index),.ent_valid(ev&&ready),.ent_ready(),
 .idx_clear(clear_index),.idx_commit(commit_index),.idx_done(index_done),.file_cnt(file_count),.file_valid(file_valid),.insufficient(),.err_code(),.err_detail(),
 .cursor_key(16'd0),.sel_key(selected_key),.sel_slot(select_slot),.sel_first_clus(selected_cluster),.sel_size(),.sel_valid(select_valid),.sel_wav_first_clus(wav_cluster),.sel_wav_size(),.sel_wav_valid(wav_valid),.bmp_seen(),.wav_seen());
 reg holding=0;reg[175:0]held;
 task check(input bit ok,input string msg);begin comparisons++;if(!ok)begin errors++;if(errors<8)$display("[FAIL] %s round%0d entry%0d",msg,round,received);end end endtask
 always @(negedge clk)begin cycle=cycle+1;ready=(cycle%17>4);end
 always @(posedge clk)begin
  rdone<=0;
  if(!rst_n)begin sending<=0;valid<=0;holding<=0;end
  else begin
   if(holding)check(ev&&{name,attr,clus,size,index}===held,"all metadata immutable during backpressure");
   holding<=ev&&!ready;held<={name,attr,clus,size,index};
   if(ev&&ready)begin
    check(received<want,"no invalid entry escapes");check(name===expected[received],"independent canonical name");
    check(clus===32'hfedc0000+index&&size===32'h8abc0000+index,"all cluster/size bits preserved");received=received+1;
   end
   if(request)begin sending<=1;p<=0;data<=sector[0];valid<=1;end
   else if(sending)begin
    if(valid&&take)begin
     if(p==511)begin sending<=0;valid<=0;rdone<=1;end
     else begin p<=p+1;data<=sector[p+1];valid<=cycle%7!=0;end
    end else if(!valid)valid<=1;
   end
  end
 end
 reg[31:0]c,z;reg[87:0]raw;
 initial begin
  // Three-digit aliases immediately follow nonzero four-digit IDs. This
  // catches a stale high nibble that a clean-reset-only test would miss.
  names[0]="SV9876  BMP";names[1]="SV001   BMP";names[2]="SV0001  WAV";
  names[3]="SV002   BMP";names[4]="SV0002  WAV";names[5]="SV003   BMP";
  names[6]="SV0003  WAV";names[7]="SV004   BMP";names[8]="SV0004  WAV";
  names[9]="SV999   BMP";names[10]="SV0100  BMP";names[11]="SV0101  WAV";
  names[12]="SV12    BMP";names[13]="SV12A   BMP";names[14]="SV123_  BMP";names[15]="SV123  _BMP";
  for(round=0;round<64;round=round+1)begin
   names[2]=round[0]?"SV001   WAV":"SV0001  WAV";names[4]=round[0]?"SV002   WAV":"SV0002  WAV";
   names[6]=round[0]?"SV003   WAV":"SV0003  WAV";names[8]=round[0]?"SV004   WAV":"SV0004  WAV";
   @(negedge clk);rst_n=0;repeat(3)@(negedge clk);received=0;want=12;
   for(slot=0;slot<16;slot=slot+1)begin
    p=slot*32;raw=names[(slot+round)%16];for(k=0;k<32;k=k+1)sector[p+k]=0;
    for(k=0;k<11;k=k+1)sector[p+k]=raw[87-k*8-:8];sector[p+11]=8'h20;
    c=32'hfedc0000+slot;z=32'h8abc0000+slot;
    sector[p+20]=c[23:16];sector[p+21]=c[31:24];sector[p+26]=c[7:0];sector[p+27]=c[15:8];
    for(k=0;k<4;k=k+1)sector[p+28+k]=z[k*8+:8];
   end
   k=0;
   for(slot=0;slot<16;slot=slot+1)if((slot+round)%16<12)begin
    raw=names[(slot+round)%16];
    if(raw[47:40]==" ")expected[k]={"SV0",raw[71:48],"  ",raw[23:0]};else expected[k]=raw;
    selected_id=expected[k][47:40]-"1";
    if(expected[k][71:48]=="000"&&selected_id>=0&&selected_id<4)begin
     if(expected[k][23:0]=="BMP")expected_bmp[selected_id]=32'hfedc0000+slot;
     else expected_wav[selected_id]=32'hfedc0000+slot;
    end
    k=k+1;
   end
   rst_n=1;clear_index=1;@(negedge clk);clear_index=0;start=1;@(negedge clk);start=0;
   wait(scan.wk_start);@(negedge clk);walking_done=1;@(negedge clk);walking_done=0;
   wait(done);repeat(3)@(negedge clk);check(!bad&&received==want,"exact accepted count, complete scan");
   commit_index=1;@(negedge clk);commit_index=0;wait(index_done);repeat(2)@(negedge clk);
   check(file_count==4&&file_valid==15,"four smallest valid images retained");
   for(slot=0;slot<4;slot=slot+1)begin
    select_slot=slot;repeat(4)@(negedge clk);
    check(select_valid&&selected_key==slot+1&&selected_cluster==expected_bmp[slot],"numeric ordering and original BMP cluster");
    check(wav_valid&&wav_cluster==expected_wav[slot],"three/four-digit WAV pairs join the right image");
   end
  end
  if(errors==0)$display("[PASS] mixed3/4 digit IDs, WAV pairing keys, invalid names, all metadata and stalls");
  $display("[TB] tb_v3_directory_alias510 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
