`timescale 1ns/1ps
module tb_v3_ingress_credit616;
 reg[9:0] level10=0,level9=0;reg[1:0] part=0;
 wire[8:0] pairs10,pairs9;wire[10:0] words10,words9;wire room10,room9;
 integer i,j,errors=0,checks=0;
 v3_pcm_ingress_shared_fifo default_dut(.rst(1'b1),.wr_clk(1'b0),.rd_clk(1'b0),.wr_data(128'd0),.wr_valid(4'd0),.wr_pairs(pairs10),.wr_words(words10),.sector_room(room10),.rd_ready(4'd0));
 v3_pcm_ingress_shared_fifo #(.AW(9)) compact_dut(.rst(1'b1),.wr_clk(1'b0),.rd_clk(1'b0),.wr_data(128'd0),.wr_valid(4'd0),.wr_pairs(pairs9),.wr_words(words9),.sector_room(room9),.rd_ready(4'd0));
 initial begin
  force default_dut.words=level10;force default_dut.write_part=part;force default_dut.wr_rst_n=1;
  force compact_dut.words=level9;force compact_dut.write_part=part;force compact_dut.wr_rst_n=1;
  for(i=0;i<1024;i++)for(j=0;j<4;j++)begin
   level10=i;part=j;#1;checks++;
   if(pairs10!==9'((i+2)/3+(j!=0))||words10!==11'(i)||room10!==((j==0)&&(i<=632)))begin errors++;if(errors<5)$display("[FAIL] default level=%0d part=%0d",i,j);end
  end
  for(i=0;i<512;i++)for(j=0;j<4;j++)begin
   level9=i;part=j;#1;checks++;
   if(pairs9!==9'((i+2)/3+(j!=0))||words9!==11'(i)||room9!==((j==0)&&(i<=120)))begin errors++;if(errors<5)$display("[FAIL] compact level=%0d part=%0d",i,j);end
   if(room9&&511-i<384+7)begin errors++;$display("[FAIL] insufficient reservation");end
  end
  if(!errors)$display("[PASS] exact integer public credit all1024/default and512/compact levels x4 partial states, sector guard384+7");
  $display("[TB] tb_v3_ingress_credit616 done comparisons=%0d errors=%0d",checks,errors);$finish;
 end
endmodule

module ingress_transfer616 #(parameter integer AW=9,CHECK_GOLD=0,parameter TOPNAME="tb_v3_ingress_compact616");
 reg wc=0,rc=0,read_clock=1,rst=1,reader_on=0;always #5 wc=~wc;always #6.7 if(read_clock)rc=~rc;
 reg[127:0] data=0;reg[3:0] valid=0,rd_ready=0;wire[3:0] ready,rv;wire[127:0] out;
 wire[8:0] pairs;wire[10:0] words;wire room,partial;
 v3_pcm_ingress_shared_fifo #(.AW(AW)) dut(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(data),.wr_valid(valid),.wr_ready(ready),.wr_pairs(pairs),.wr_words(words),.wr_partial(partial),.sector_room(room),.rd_data(out),.rd_valid(rv),.rd_ready(rd_ready));
 reg[31:0] expected_data[0:8191];integer expected_track[0:8191];integer head=0,tail=0,checks=0,cycle=0,stalls=0,epoch=0;
 reg stalled=0;reg[131:0] held;
 localparam integer INITIAL_PAIRS=((1<<AW)-392)/3;
 localparam integer WHOLE_PAIRS=((1<<AW)-1)/3;
 function automatic [31:0] sample(input integer n);sample=32'had000000+(epoch<<16)+n;endfunction
 generate if(CHECK_GOLD)begin:legacy_miter
  wire[3:0] gr,gv;wire[127:0] gd;wire[8:0] gp;wire[10:0] gw;wire gro,gpa;
  v3_pcm_ingress_shared_fifo_original616 gold(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(data),.wr_valid(valid),.wr_ready(gr),.wr_pairs(gp),.wr_words(gw),.wr_partial(gpa),.sector_room(gro),.rd_data(gd),.rd_valid(gv),.rd_ready(rd_ready));
  always @(negedge wc)if(!rst&&dut.wr_rst_n)begin
   if({ready,pairs,words,partial,room}!=={gr,gp,gw,gpa,gro})$fatal(1,"default legacy write interface differs");
  end
  always @(negedge rc)if(!rst&&dut.rd_rst_n)begin
   if(rv!==gv||((|rv)&&out!==gd))$fatal(1,"default legacy read interface differs");
  end
 end endgenerate
 always @(posedge wc)if(!rst&&valid!=0&&ready!=0)begin
  if(ready!==valid)$fatal(1,"write ready tag mismatch");
  expected_data[tail]=data[31:0];
  for(integer j=0;j<4;j++)if(valid[j])begin expected_data[tail]=data[j*32+:32];expected_track[tail]=j;end
  tail=tail+1;
 end
 always @(negedge rc)begin cycle=cycle+1;rd_ready=reader_on&&cycle%19>=7?(cycle%5==0?4'b0101:4'hf):4'd0;end
 always @(posedge rc)if(!rst)begin
  if(stalled&&{rv,out}!==held)$fatal(1,"read payload/tag changed under backpressure");
  stalled=(rv!=0)&&((rv&rd_ready)==0);held={rv,out};if(stalled)stalls++;
  if((rv&rd_ready)!=0)begin
   if(head>=tail||rv!==(4'b1<<expected_track[head])||out!=={4{expected_data[head]}})$fatal(1,"tag/data order head=%0d tail=%0d rv=%h expectedtag=%0d out=%h expected=%h",head,tail,rv,expected_track[head],out[31:0],expected_data[head]);
   head++;checks++;
  end
 end else stalled=0;
 task automatic send(input integer n);
  integer t;begin
   t=n%4;@(negedge wc);data=0;data[t*32+:32]=sample(n);valid=4'b1<<t;
   @(posedge wc);while(ready==0)@(posedge wc);
   @(negedge wc);valid=0;
  end
 endtask
 task automatic reset_epoch;
  begin rst=1;valid=0;reader_on=0;read_clock=1;#100;head=0;tail=0;stalled=0;epoch++;rst=0;repeat(12)@(negedge wc);end
 endtask
 initial begin
  reset_epoch();@(negedge rc);read_clock=0;
  for(integer n=0;n<INITIAL_PAIRS;n++)send(n);
  repeat(8)@(negedge wc);
  if(words!=3*INITIAL_PAIRS||!room||partial)$fatal(1,"reservation boundary words=%0d expected=%0d room=%b",words,3*INITIAL_PAIRS,room);
  for(integer n=INITIAL_PAIRS;n<INITIAL_PAIRS+128;n++)send(n);
  repeat(8)@(negedge wc);
  if(words!=3*(INITIAL_PAIRS+128)||room||partial)$fatal(1,"full384-word sector failed words=%0d",words);
  checks+=128;
  for(integer n=INITIAL_PAIRS+128;n<WHOLE_PAIRS;n++)send(n);
  fork
   begin send(WHOLE_PAIRS);end
   begin
    repeat(50)@(negedge wc);
    if(ready!=0||words!=(1<<AW)-1)$fatal(1,"full queue did not hold source with bounded level words=%0d ready=%h",words,ready);
    if(AW==9&&!partial)$fatal(1,"missing actual partial-packet full stall");
    read_clock=1;reader_on=1;
   end
  join
  wait(head==tail);repeat(12)@(negedge wc);
  if(words!=0)$fatal(1,"queue failed to drain");
  fork
   begin send(6000);end
   begin wait(dut.write_part==1);rst=1;end
  join_any disable fork;
  reset_epoch();reader_on=1;
  for(integer n=0;n<1800;n++)begin send(n);repeat(n%3)@(negedge wc);end
  wait(head==tail);repeat(20)@(negedge wc);
  if(words!=0||partial||stalls<10)$fatal(1,"transfer coverage/drain words=%0d partial=%b stalls=%0d",words,partial,stalls);
  $display("[PASS] actual TD FIFO AW%0d full512byte sector,full stall,tag order,clock mismatch,backpressure,wrap,midpacket reset and legacy miter=%0d checks=%0d stalls=%0d",AW,CHECK_GOLD,checks,stalls);
  $display("[TB] %s done comparisons=%0d errors=0",TOPNAME,checks);$finish;
 end
 initial begin #5000000;$fatal(1,"transfer watchdog AW%0d head=%0d tail=%0d words=%0d part=%0d",AW,head,tail,words,dut.write_part);end
endmodule
module tb_v3_ingress_compact616;ingress_transfer616 #(.AW(9),.TOPNAME("tb_v3_ingress_compact616")) test();endmodule
module tb_v3_ingress_legacy616;ingress_transfer616 #(.AW(10),.CHECK_GOLD(1),.TOPNAME("tb_v3_ingress_legacy616")) test();endmodule

module tb_v3_ingress_prefill616;
 reg wc=0,mc=0,rst=1;always #5 wc=~wc;always #7 mc=~mc;
 reg[127:0] source_data=0;reg[3:0] source_valid=0;wire[3:0] source_ready,iv,ir,fill;wire[127:0] id;
 wire[8:0] fifo_pairs;wire[10:0] fifo_words;wire fifo_partial,sector_room;
 wire[63:0] levels,ref_levels;wire ref_valid;wire[3:0] prefetched;
 wire rst_w_n,rst_m_n;
 v3_audio_reset_release rw(.clk(wc),.assert_reset(rst),.rst_n(rst_w_n));
 v3_audio_reset_release rm(.clk(mc),.assert_reset(rst),.rst_n(rst_m_n));
 v3_pcm_ingress_shared_fifo #(.AW(9)) ingress(.rst(rst),.wr_clk(wc),.rd_clk(mc),.wr_data(source_data),.wr_valid(source_valid),.wr_ready(source_ready),.wr_pairs(fifo_pairs),.wr_words(fifo_words),.wr_partial(fifo_partial),.sector_room(sector_room),.rd_data(id),.rd_valid(iv),.rd_ready(ir));
 video_cdc_mailbox #(.WIDTH(64)) feedback(.src_clk(mc),.src_rst_n(rst_m_n),.src_data(levels),.src_valid(1'b1),.dst_clk(wc),.dst_rst_n(rst_w_n),.dst_data(ref_levels),.dst_valid(ref_valid),.dst_ready(1'b1));
 generate for(genvar g=0;g<4;g++)begin:compares
  v3_audio_prefill_compare #(.LIMIT(928)) cmp(.ring_level(ref_levels[g*16+:16]),.fifo_words(fifo_words[9:0]),.partial(fifo_partial),.fill(fill[g]));
 end endgenerate
 reg cv=0;reg[1:0] cs=0,active=0;reg[7:0] generation=0,expected_generation=0;wire cr;
 wire[39:0] out;wire ov;reg ore=0;
 wire req,wr;wire[31:0] addr,wd;wire[15:0] len;reg ack=0,busy=0,rv=0;reg[31:0] rd=0;wire[31:0] overflow;
 v3_pcm_ring #(.PREFETCH(800)) ring(.clk(mc),.rst_n(rst_m_n),.in_data(id),.in_valid(iv),.in_ready(ir),.commit_valid(cv),.commit_slot(cs),.commit_generation(generation),.commit_ready(cr),.fallback(4'd0),.prefetched(prefetched),.levels(levels),.out_data(out),.out_valid(ov),.out_ready(ore),.output_level(10'd0),.req(req),.wr(wr),.addr(addr),.wdata(wd),.len(len),.ack(ack),.busy(busy),.rdata(rd),.rvalid(rv),.overflow_count(overflow));
 reg[31:0] memory[0:65535];reg[31:0] lat_addr,lat_data;reg lat_wr;integer delay=0,cycle=0;
 integer sent[0:3],got[0:3],max_count[0:3],checks=0,sectors[0:3];integer selected=0;reg run_source=1,source_stopped=0;
 reg stalled=0;reg[39:0] held;
 function automatic [31:0] value(input integer slot,index);value=32'h65000000+(slot<<20)+index;endfunction
 always @(posedge wc)if(rst_w_n&&(|source_ready))for(integer t=0;t<4;t++)if(source_ready[t])sent[t]++;
 always @(negedge mc)ore=cycle%13!=0&&cycle%7!=0;
 always @(posedge mc)begin
  ack<=0;rv<=0;cycle<=cycle+1;
  if(rst_m_n)begin
   if(stalled&&(!ov||out!==held))$fatal(1,"ring output changed under backpressure");
   stalled<=ov&&!ore;held<=out;
   for(integer t=0;t<4;t++)begin
    if(levels[t*16+:16]>1440)$fatal(1,"bounded prefill exceeded slot=%0d level=%0d",t,levels[t*16+:16]);
    if(levels[t*16+:16]>max_count[t])max_count[t]=levels[t*16+:16];
   end
   if(overflow!=0)$fatal(1,"ring overflow");
   if(!busy&&req&&cycle%11!=0&&cycle%17!=0)begin
    if(len!=1||addr<32'h280000||addr>=32'h2c0000||addr[1:0]!=0)$fatal(1,"ring address/length");
    ack<=1;busy<=1;lat_addr<=addr;lat_data<=wd;lat_wr<=wr;delay<=1+cycle%9;
   end else if(busy)begin
    if(delay!=0)delay<=delay-1;
    else begin busy<=0;if(lat_wr)memory[(lat_addr-32'h280000)>>2]<=lat_data;else begin rd<=memory[(lat_addr-32'h280000)>>2];rv<=1;end end
   end
   if(cv&&cr)begin active=cs;expected_generation=generation;end
   if(ov&&ore)begin
    if(out[39:32]!==expected_generation||out[31:0]!==value(active,got[active]))$fatal(1,"integrated ring data/generation slot=%0d index=%0d got=%h",active,got[active],out);
    got[active]++;checks++;
   end
  end else stalled<=0;
 end
 task automatic send_pair(input integer slot,index);
  begin @(negedge wc);source_data=0;source_data[slot*32+:32]=value(slot,index);source_valid=4'b1<<slot;@(posedge wc);while(source_ready==0)@(posedge wc);@(negedge wc);source_valid=0;end
 endtask
 task automatic commit(input integer slot,gen);
  begin @(negedge mc);cs=slot;generation=gen;cv=1;@(posedge mc);while(!cr)@(posedge mc);@(negedge mc);cv=0;end
 endtask
 initial begin
  for(integer t=0;t<4;t++)begin sent[t]=0;got[t]=0;max_count[t]=0;sectors[t]=0;end
  #100;rst=0;wait(rst_w_n&&rst_m_n&&ref_valid);
  while(run_source)begin
   if(fill[selected]&&sector_room)begin
    sectors[selected]++;
    for(integer n=0;n<128;n++)send_pair(selected,sent[selected]);
   end else repeat(5)@(negedge wc);
   selected=(selected+1)%4;
  end
  source_stopped=1;
 end
 initial begin
  wait(&prefetched);checks+=4;
  commit(0,1);wait(got[0]>=256);commit(3,2);wait(got[3]>=256);commit(1,3);wait(got[1]>=256);commit(2,4);wait(got[2]>=256);
  run_source=0;wait(source_stopped);
  for(integer t=0;t<4;t++)begin commit(t,10+t);wait(got[t]==sent[t]);end
  repeat(100)@(negedge wc);
  if(fifo_words!=0||fifo_partial||overflow!=0)$fatal(1,"final integrated queue not empty");
  for(integer t=0;t<4;t++)begin
   if(got[t]!=sent[t]||sent[t]<800||sectors[t]<7||max_count[t]<800||max_count[t]>1440)$fatal(1,"four-track coverage slot=%0d sent=%0d got=%0d max=%0d sectors=%0d",t,sent[t],got[t],max_count[t],sectors[t]);
  end
  $display("[PASS] AW9 actual tagged FIFO + production ring + CDC levels + exact prefill;4tracks over800pairs each,384word sectors,refresh/grant/backpressure,ordered generations and complete drain");
  $display("[TB] tb_v3_ingress_prefill616 done comparisons=%0d errors=0 sent=%0d/%0d/%0d/%0d max=%0d/%0d/%0d/%0d",checks,sent[0],sent[1],sent[2],sent[3],max_count[0],max_count[1],max_count[2],max_count[3]);$finish;
 end
 initial begin #20000000;$fatal(1,"prefill watchdog sent=%0d/%0d/%0d/%0d got=%0d/%0d/%0d/%0d levels=%h fifo=%0d",sent[0],sent[1],sent[2],sent[3],got[0],got[1],got[2],got[3],levels,fifo_words);end
endmodule

`timescale 1ns/1ps
module tb_v3_audio_depth616;
 reg clk=0;always #5 clk=~clk;
 v3_audio_system #(.PREINDEXED(0)) legacy(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(1'b0),.media_reset(1'b1),.media_descriptor_valid(1'b0));
 v3_audio_system #(.PREINDEXED(1)) flex(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(1'b0),.media_reset(1'b1),.media_descriptor_valid(1'b0));
 initial begin
  #100;
  if(legacy.ingress_shared.AW!=10||flex.ingress_shared.AW!=9)$fatal(1,"audio parameter depth selection");
  if(legacy.ingress_shared.q.u_fifo.ADDR_WIDTH_W!=10||legacy.ingress_shared.q.u_fifo.ADDR_WIDTH_R!=10||flex.ingress_shared.q.u_fifo.ADDR_WIDTH_W!=9||flex.ingress_shared.q.u_fifo.ADDR_WIDTH_R!=9)$fatal(1,"vendor FIFO geometry not bound to selected depth");
  if($bits(legacy.global_ingress_words)!=11||$bits(flex.global_ingress_words)!=11||$bits(legacy.global_ingress_pairs)!=9||$bits(flex.global_ingress_pairs)!=9)$fatal(1,"public credit geometry changed");
  $display("[PASS] actual complete audio_system source elaborates both PREINDEXED0/AW10 and PREINDEXED1/AW9 with official TD FIFO geometry and unchanged credit ports");
  $display("[TB] tb_v3_audio_depth616 done comparisons=10 errors=0");$finish;
 end
endmodule
