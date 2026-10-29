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
  for(i=0;i<1024;i = i + 1)for(j=0;j<4;j = j + 1)begin
   level10=i;part=j;#1;checks = checks + 1;
   if(pairs10!==v_cast_u9((i+2)/3+(j!=0))||words10!==v_cast_s11(i)||room10!==((j==0)&&(i<=632)))begin errors = errors + 1;if(errors<5)$display("[FAIL] default level=%0d part=%0d",i,j);end
  end
  for(i=0;i<512;i = i + 1)for(j=0;j<4;j = j + 1)begin
   level9=i;part=j;#1;checks = checks + 1;
   if(pairs9!==v_cast_u9((i+2)/3+(j!=0))||words9!==v_cast_s11(i)||room9!==((j==0)&&(i<=120)))begin errors = errors + 1;if(errors<5)$display("[FAIL] compact level=%0d part=%0d",i,j);end
   if(room9&&511-i<384+7)begin errors = errors + 1;$display("[FAIL] insufficient reservation");end
  end
  if(!errors)$display("[PASS] exact integer public credit all1024/default and512/compact levels x4 partial states, sector guard384+7");
  $display("[TB] tb_v3_ingress_credit616 done comparisons=%0d errors=%0d",checks,errors);$finish;
 end

function [8:0] v_cast_u9; input [8:0] value; begin begin v_cast_u9=value; end  end endfunction
function signed [10:0] v_cast_s11; input signed [10:0] value; begin begin v_cast_s11=value; end  end endfunction
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
 function automatic [31:0] sample(input integer n);begin sample=32'had000000+(epoch<<16)+n; end endfunction
 generate if(CHECK_GOLD)begin:legacy_miter
  wire[3:0] gr,gv;wire[127:0] gd;wire[8:0] gp;wire[10:0] gw;wire gro,gpa;
  v3_pcm_ingress_shared_fifo_original616 gold(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(data),.wr_valid(valid),.wr_ready(gr),.wr_pairs(gp),.wr_words(gw),.wr_partial(gpa),.sector_room(gro),.rd_data(gd),.rd_valid(gv),.rd_ready(rd_ready));
  always @(negedge wc)if(!rst&&dut.wr_rst_n)begin
   if({ready,pairs,words,partial,room}!=={gr,gp,gw,gpa,gro})begin $display("[FAIL] default legacy write interface differs"); $finish; end 
  end
  always @(negedge rc)if(!rst&&dut.rd_rst_n)begin
   if(rv!==gv||((|rv)&&out!==gd))begin $display("[FAIL] default legacy read interface differs"); $finish; end 
  end
 end endgenerate
 always @(posedge wc)if(!rst&&valid!=0&&ready!=0)begin
  if(ready!==valid)begin $display("[FAIL] write ready tag mismatch"); $finish; end 
  expected_data[tail]=data[31:0];
  begin : v_loop_1 integer j; for( j=0;j<4;j = j + 1)if(valid[j])begin expected_data[tail]=data[j*32+:32];expected_track[tail]=j;end end 
  tail=tail+1;
 end
 always @(negedge rc)begin cycle=cycle+1;rd_ready=reader_on&&cycle%19>=7 ? (cycle%5==0 ? 4'b0101:4'hf):4'd0;end
 always @(posedge rc)if(!rst)begin
  if(stalled&&{rv,out}!==held)begin $display("[FAIL] read payload/tag changed under backpressure"); $finish; end 
  stalled=(rv!=0)&&((rv&rd_ready)==0);held={rv,out};if(stalled)stalls = stalls + 1;
  if((rv&rd_ready)!=0)begin
   if(head>=tail||rv!==(4'b1<<expected_track[head])||out!=={4{expected_data[head]}})begin $display("[FAIL] tag/data order head=%0d tail=%0d rv=%h expectedtag=%0d out=%h expected=%h",head,tail,rv,expected_track[head],out[31:0],expected_data[head]); $finish; end 
   head = head + 1;checks = checks + 1;
  end
 end else stalled=0;
 task automatic send(input integer n);
  integer t;begin begin
   t=n%4;@(negedge wc);data=0;data[t*32+:32]=sample(n);valid=4'b1<<t;
   @(posedge wc);while(ready==0)@(posedge wc);
   @(negedge wc);valid=0;
  end
  end endtask
 task automatic reset_epoch;
  begin begin rst=1;valid=0;reader_on=0;read_clock=1;#100;head=0;tail=0;stalled=0;epoch = epoch + 1;rst=0;repeat(12)@(negedge wc);end
  end endtask
 initial begin
  reset_epoch();@(negedge rc);read_clock=0;
  begin : v_loop_2 integer n; for( n=0;n<INITIAL_PAIRS;n = n + 1)send(n); end 
  repeat(8)@(negedge wc);
  if(words!=3*INITIAL_PAIRS||!room||partial)begin $display("[FAIL] reservation boundary words=%0d expected=%0d room=%b",words,3*INITIAL_PAIRS,room); $finish; end 
  begin : v_loop_3 integer n; for( n=INITIAL_PAIRS;n<INITIAL_PAIRS+128;n = n + 1)send(n); end 
  repeat(8)@(negedge wc);
  if(words!=3*(INITIAL_PAIRS+128)||room||partial)begin $display("[FAIL] full384-word sector failed words=%0d",words); $finish; end 
  checks = checks + (128);
  begin : v_loop_4 integer n; for( n=INITIAL_PAIRS+128;n<WHOLE_PAIRS;n = n + 1)send(n); end 
  fork
   begin send(WHOLE_PAIRS);end
   begin
    repeat(50)@(negedge wc);
    if(ready!=0||words!=(1<<AW)-1)begin $display("[FAIL] full queue did not hold source with bounded level words=%0d ready=%h",words,ready); $finish; end 
    if(AW==9&&!partial)begin $display("[FAIL] missing actual partial-packet full stall"); $finish; end 
    read_clock=1;reader_on=1;
   end
  join
  wait(head==tail);repeat(12)@(negedge wc);
  if(words!=0)begin $display("[FAIL] queue failed to drain"); $finish; end 
  fork : v_race_1 
   begin : v_branch_1 begin send(6000);end disable v_race_1; end 
   begin : v_branch_2 begin wait(dut.write_part==1);rst=1;end disable v_race_1; end 
  join 
  reset_epoch();reader_on=1;
  begin : v_loop_5 integer n; for( n=0;n<1800;n = n + 1)begin send(n);repeat(n%3)@(negedge wc);end end 
  wait(head==tail);repeat(20)@(negedge wc);
  if(words!=0||partial||stalls<10)begin $display("[FAIL] transfer coverage/drain words=%0d partial=%b stalls=%0d",words,partial,stalls); $finish; end 
  $display("[PASS] actual TD FIFO AW%0d full512byte sector,full stall,tag order,clock mismatch,backpressure,wrap,midpacket reset and legacy miter=%0d checks=%0d stalls=%0d",AW,CHECK_GOLD,checks,stalls);
  $display("[TB] %s done comparisons=%0d errors=0",TOPNAME,checks);$finish;
 end
 initial begin #5000000;begin $display("[FAIL] transfer watchdog AW%0d head=%0d tail=%0d words=%0d part=%0d",AW,head,tail,words,dut.write_part); $finish; end end
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
 generate for(genvar g=0;g<4;g = g + 1)begin:compares
  v3_audio_prefill_compare #(.LIMIT(928)) cmp(.ring_level(ref_levels[g*16+:16]),.fifo_words(fifo_words[9:0]),.partial(fifo_partial),.fill(fill[g]));
 end endgenerate
 reg cv=0;reg[1:0] cs=0,active=0;reg[7:0] generation=0,expected_generation=0;wire cr;
 wire[39:0] out;wire ov;reg ore=0;
 wire req,wr;wire[31:0] addr,wd;wire[15:0] len;reg ack=0,busy=0,rv=0;reg[31:0] rd=0;wire[31:0] overflow;
 v3_pcm_ring #(.PREFETCH(800)) ring(.clk(mc),.rst_n(rst_m_n),.in_data(id),.in_valid(iv),.in_ready(ir),.commit_valid(cv),.commit_slot(cs),.commit_generation(generation),.commit_ready(cr),.fallback(4'd0),.prefetched(prefetched),.levels(levels),.out_data(out),.out_valid(ov),.out_ready(ore),.output_level(10'd0),.req(req),.wr(wr),.addr(addr),.wdata(wd),.len(len),.ack(ack),.busy(busy),.rdata(rd),.rvalid(rv),.overflow_count(overflow));
 reg[31:0] memory[0:65535];reg[31:0] lat_addr,lat_data;reg lat_wr;integer delay=0,cycle=0;
 integer sent[0:3],got[0:3],max_count[0:3],checks=0,sectors[0:3];integer selected=0;reg run_source=1,source_stopped=0;
 reg stalled=0;reg[39:0] held;
 function automatic [31:0] value(input integer slot,index);begin value=32'h65000000+(slot<<20)+index; end endfunction
 always @(posedge wc)if(rst_w_n&&(|source_ready))begin : v_loop_6 integer t; for( t=0;t<4;t = t + 1)if(source_ready[t])sent[t] = sent[t] + 1; end 
 always @(negedge mc)ore=cycle%13!=0&&cycle%7!=0;
 always @(posedge mc)begin
  ack<=0;rv<=0;cycle<=cycle+1;
  if(rst_m_n)begin
   if(stalled&&(!ov||out!==held))begin $display("[FAIL] ring output changed under backpressure"); $finish; end 
   stalled<=ov&&!ore;held<=out;
   begin : v_loop_7 integer t; for( t=0;t<4;t = t + 1)begin
    if(levels[t*16+:16]>1440)begin $display("[FAIL] bounded prefill exceeded slot=%0d level=%0d",t,levels[t*16+:16]); $finish; end 
    if(levels[t*16+:16]>max_count[t])max_count[t]=levels[t*16+:16];
   end end 
   if(overflow!=0)begin $display("[FAIL] ring overflow"); $finish; end 
   if(!busy&&req&&cycle%11!=0&&cycle%17!=0)begin
    if(len!=1||addr<32'h280000||addr>=32'h2c0000||addr[1:0]!=0)begin $display("[FAIL] ring address/length"); $finish; end 
    ack<=1;busy<=1;lat_addr<=addr;lat_data<=wd;lat_wr<=wr;delay<=1+cycle%9;
   end else if(busy)begin
    if(delay!=0)delay<=delay-1;
    else begin busy<=0;if(lat_wr)memory[(lat_addr-32'h280000)>>2]<=lat_data;else begin rd<=memory[(lat_addr-32'h280000)>>2];rv<=1;end end
   end
   if(cv&&cr)begin active=cs;expected_generation=generation;end
   if(ov&&ore)begin
    if(out[39:32]!==expected_generation||out[31:0]!==value(active,got[active]))begin $display("[FAIL] integrated ring data/generation slot=%0d index=%0d got=%h",active,got[active],out); $finish; end 
    got[active] = got[active] + 1;checks = checks + 1;
   end
  end else stalled<=0;
 end
 task automatic send_pair(input integer slot,index);
  begin begin @(negedge wc);source_data=0;source_data[slot*32+:32]=value(slot,index);source_valid=4'b1<<slot;@(posedge wc);while(source_ready==0)@(posedge wc);@(negedge wc);source_valid=0;end
  end endtask
 task automatic commit(input integer slot,gen);
  begin begin @(negedge mc);cs=slot;generation=gen;cv=1;@(posedge mc);while(!cr)@(posedge mc);@(negedge mc);cv=0;end
  end endtask
 initial begin
  begin : v_loop_8 integer t; for( t=0;t<4;t = t + 1)begin sent[t]=0;got[t]=0;max_count[t]=0;sectors[t]=0;end end 
  #100;rst=0;wait(rst_w_n&&rst_m_n&&ref_valid);
  while(run_source)begin
   if(fill[selected]&&sector_room)begin
    sectors[selected] = sectors[selected] + 1;
    begin : v_loop_9 integer n; for( n=0;n<128;n = n + 1)send_pair(selected,sent[selected]); end 
   end else repeat(5)@(negedge wc);
   selected=(selected+1)%4;
  end
  source_stopped=1;
 end
 initial begin
  wait(&prefetched);checks = checks + (4);
  commit(0,1);wait(got[0]>=256);commit(3,2);wait(got[3]>=256);commit(1,3);wait(got[1]>=256);commit(2,4);wait(got[2]>=256);
  run_source=0;wait(source_stopped);
  begin : v_loop_10 integer t; for( t=0;t<4;t = t + 1)begin commit(t,10+t);wait(got[t]==sent[t]);end end 
  repeat(100)@(negedge wc);
  if(fifo_words!=0||fifo_partial||overflow!=0)begin $display("[FAIL] final integrated queue not empty"); $finish; end 
  begin : v_loop_11 integer t; for( t=0;t<4;t = t + 1)begin
   if(got[t]!=sent[t]||sent[t]<800||sectors[t]<7||max_count[t]<800||max_count[t]>1440)begin $display("[FAIL] four-track coverage slot=%0d sent=%0d got=%0d max=%0d sectors=%0d",t,sent[t],got[t],max_count[t],sectors[t]); $finish; end 
  end end 
  $display("[PASS] AW9 actual tagged FIFO + production ring + CDC levels + exact prefill;4tracks over800pairs each,384word sectors,refresh/grant/backpressure,ordered generations and complete drain");
  $display("[TB] tb_v3_ingress_prefill616 done comparisons=%0d errors=0 sent=%0d/%0d/%0d/%0d max=%0d/%0d/%0d/%0d",checks,sent[0],sent[1],sent[2],sent[3],max_count[0],max_count[1],max_count[2],max_count[3]);$finish;
 end
 initial begin #20000000;begin $display("[FAIL] prefill watchdog sent=%0d/%0d/%0d/%0d got=%0d/%0d/%0d/%0d levels=%h fifo=%0d",sent[0],sent[1],sent[2],sent[3],got[0],got[1],got[2],got[3],levels,fifo_words); $finish; end end
endmodule

`timescale 1ns/1ps
module tb_v3_audio_depth616;
 reg clk=0;always #5 clk=~clk;
 v3_audio_system #(.PREINDEXED(0)) legacy(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(1'b0),.media_reset(1'b1),.media_descriptor_valid(1'b0));
 v3_audio_system #(.PREINDEXED(1)) flex(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(1'b0),.media_reset(1'b1),.media_descriptor_valid(1'b0));
 initial begin
  #100;
  if(legacy.ingress_shared.AW!=10||flex.ingress_shared.AW!=9)begin $display("[FAIL] audio parameter depth selection"); $finish; end 
  if(legacy.ingress_shared.q.u_fifo.ADDR_WIDTH_W!=10||legacy.ingress_shared.q.u_fifo.ADDR_WIDTH_R!=10||flex.ingress_shared.q.u_fifo.ADDR_WIDTH_W!=9||flex.ingress_shared.q.u_fifo.ADDR_WIDTH_R!=9)begin $display("[FAIL] vendor FIFO geometry not bound to selected depth"); $finish; end 
  force legacy.global_ingress_words=32'hffffffff;
  force flex.global_ingress_words=32'hffffffff;
  force legacy.global_ingress_pairs=32'hffffffff;
  force flex.global_ingress_pairs=32'hffffffff;
  #1;
  if(legacy.global_ingress_words!==64'h7ff||flex.global_ingress_words!==64'h7ff||legacy.global_ingress_pairs!==64'h1ff||flex.global_ingress_pairs!==64'h1ff)begin $display("[FAIL] public credit geometry changed");$finish;end
  release legacy.global_ingress_words;
  release flex.global_ingress_words;
  release legacy.global_ingress_pairs;
  release flex.global_ingress_pairs;
  $display("[PASS] actual complete audio_system source elaborates both PREINDEXED0/AW10 and PREINDEXED1/AW9 with official TD FIFO geometry and unchanged credit ports");
  $display("[TB] tb_v3_audio_depth616 done comparisons=10 errors=0");$finish;
 end
endmodule
