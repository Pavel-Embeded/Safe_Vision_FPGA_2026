`timescale 1ns/1ps
module tb_v3_flexible540;
 reg clk=0,rst_n=0,start=0,bv=0;always #5 clk=~clk;reg[4:0] off=0;reg[7:0] data=0;
 wire busy,lfn;wire[15:0] name_data;wire[8:0] length;wire[7:0] index_address;
 reg manual=0;reg[7:0] manual_address=0;
 v3_fat_name_store names(.clk(clk),.rst_n(rst_n),.scan_start(start),.byte_valid(bv),.byte_offset(off),.data(data),.read_address(manual ? manual_address:index_address),.read_data(name_data),.name_length(length),.busy(busy),.lfn_valid(lfn));
 reg clear=0,commit=0,ev=0;reg[15:0] cursor=0,ei=0;reg[1:0] slot=0;reg[87:0] en=0;reg[7:0] attr=0;reg[31:0] clus=0,size=0;
 wire er,rescan,done,valid,wav_valid;wire[3:0] count,mask;wire[15:0] key,bc,wc;wire[31:0] sc,ss,wsc,wss;
 v3_flexible_media_index idx(.clk(clk),.rst_n(rst_n),.idx_clear(clear),.idx_commit(commit),.cursor_key(cursor),.resident_slot(slot),.ent_name(en),.ent_attr(attr),.ent_first_clus(clus),.ent_size(size),.ent_index(ei),.ent_valid(ev),.ent_ready(er),.name_address(index_address),.name_data(name_data),.name_length(length),.rescan_request(rescan),.idx_done(done),.file_cnt(count),.file_valid(mask),.sel_key(key),.sel_first_clus(sc),.sel_size(ss),.sel_valid(valid),.sel_wav_first_clus(wsc),.sel_wav_size(wss),.sel_wav_valid(wav_valid),.bmp_seen(bc),.wav_seen(wc));
 reg[7:0] directory[0:4032-1];reg[15:0] expected_names[0:33*256-1];reg[8:0] expected_lengths[0:33-1];reg[79:0] expected[0:15-1];
 integer errors=0,comparisons=0,e,b,n,k,pass;reg[87:0] assembled;
 task check(input  ok,input [4095:0] message);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s pass%0d entry%0d char%0d",message,pass,e,k);end   end endtask
 task scan;begin
  start=1;@(negedge clk);start=0;n=0;
  for(e=0;e<126;e=e+1)begin
   assembled=0;
   for(b=0;b<32;b=b+1)begin
    while(busy)@(negedge clk);
    off=b;data=directory[e*32+b];bv=1;if(b<11)assembled={assembled[79:0],data};@(negedge clk);bv=0;
    if((b+e)%5==0)repeat(2)@(negedge clk);
   end
   while(busy)@(negedge clk);
   if(directory[e*32+11]!=15)begin
    manual=1;repeat(2)@(negedge clk);check(length==expected_lengths[n],"validated complete name length including255-unit maximum");
    for(k=0;k<length;k=k+1)begin manual_address=k;repeat(2)@(negedge clk);check(name_data===expected_names[n*256+k],"every UTF16 character, checksum fallback and exact13-character LFN");end
    manual=0;en=assembled;attr=directory[e*32+11];clus={directory[e*32+21],directory[e*32+20],directory[e*32+27],directory[e*32+26]};size={directory[e*32+31],directory[e*32+30],directory[e*32+29],directory[e*32+28]};ei=e;ev=1;
    while(!er)@(negedge clk);@(negedge clk);ev=0;n=n+1;
   end
  end
  commit=1;@(negedge clk);commit=0;
   end endtask
 initial begin
  $readmemh("flexible_directory540.mem",directory);$readmemh("flexible_names540.mem",expected_names);$readmemh("flexible_lengths540.mem",expected_lengths);$readmemh("flexible_expected540.mem",expected);
  repeat(4)@(negedge clk);rst_n=1;
  for(pass=0;pass<15;pass=pass+1)begin
   slot=pass%4;clear=1;@(negedge clk);clear=0;
   scan();wait(rescan);@(negedge clk);scan();wait(done);@(negedge clk);
   check(valid&&count==1&&mask==1,"one frozen minimum strictly above cursor");
   check({key,sc,wsc}===expected[pass],"full Unicode filename ordering and matching/fallback WAV beyond8 entries");
   check(wav_valid&&ss==921654&&wss==1536044,"frozen metadata retained through second directory scan");cursor=key;
  end
  clear=1;@(negedge clk);clear=0;scan();wait(done);@(negedge clk);check(count==0&&!valid,"finite exhaustion after all valid candidates");
  if(errors==0)$display("[PASS] validated FAT long names, complete Unicode sorting/cursor, all metadata, exact audio pairing and ordinal fallback");
  $display("[TB] tb_v3_flexible540 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #300000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
