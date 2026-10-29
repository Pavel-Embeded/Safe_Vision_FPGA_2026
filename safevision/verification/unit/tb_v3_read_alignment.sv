


`timescale 1ns/1ps
module tb_v3_read_alignment #(parameter integer STRICT_BURST=1,RD_LAT=4,FAST_READ=1,PREFETCH_READ=1,READ_DATA_LEADS_VALID=1);
 reg clk=0; always #4 clk=~clk;
 reg rst_n=0,init=0,req=0,wr=1;
 reg [31:0] addr=0,data=0; reg [3:0] strb=15;
 wire ready,idone,rv,aw,ar; wire [31:0] dout,wd;
 wire [20:0] wa,ra; wire [3:0] dm;
 reg base_sr=0; reg sr=0; reg [31:0] sd=0;
 sdram_app_adapter #(.FAST_READ(FAST_READ),.PREFETCH_READ(PREFETCH_READ),.READ_DATA_LEADS_VALID(READ_DATA_LEADS_VALID)) dut(.clk(clk),.rst_n(rst_n),.req(req),.wr(wr),.addr(addr),
 .wdata(data),.wstrb(strb),.ready(ready),.init_done(idone),.rdata(dout),.rdata_valid(rv),
 .Sdr_init_done(init),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_wr_en(aw),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),
 .App_rd_en(ar),.App_rd_addr(ra),.Sdr_rd_en(sr),.Sdr_rd_dout(sd));
 reg [31:0] mem[0:2097151];
 reg [20:0] pending_addr[0:31]; reg [31:0] pending_data[0:31];
 reg [3:0] pending_dm[0:31];
 reg [RD_LAT-1:0] read_valid=0; reg [20:0] read_addr[0:RD_LAT-1];
 reg[1:0] read_group_count=0;reg[20:0] read_group_base=0;reg end_fence=0;
 integer cycles=0,wr_count=0,write_bursts=0,single_bursts=0,overlap=0,gap_bad=0;
 integer last_cmd=-1000,last_read=-1000; reg last_w=0,last_r=0;
 integer i,b,j,mapped_address,errors=0,checks=0;
 reg stream_compare=0;integer stream_received=0,stream_start_cycle=0,stream_cycles=0;
 always @(negedge clk)if(stream_compare&&rv)begin
   if(stream_received>=4096||dout!==32'h9abc0000+stream_received)
     $fatal(1,"stream prefetch order/data mismatch index=%0d got=%08x",stream_received,dout);
   stream_received=stream_received+1;
 end
 task check(input bit ok,input string name);
 begin checks=checks+1;if(!ok)begin errors=errors+1;$display("[FAIL] %s",name);end
 else $display("[PASS] %s",name);end endtask
 always @(posedge clk)begin
  cycles=cycles+1;
  base_sr<=read_valid[RD_LAT-1];sr<=base_sr; if(read_valid[RD_LAT-1]) sd<=mem[read_addr[RD_LAT-1]];
  read_valid<=(read_valid<<1)|ar;
  if(!ar)read_group_count<=0;
  else begin
   if(end_fence&&ra<21'h1fffe0)begin $display("[FAIL] speculative read crossed physical end");errors=errors+1;end
   read_group_count<=read_group_count+1'b1;
   if(!STRICT_BURST||read_group_count==0)begin read_group_base<=ra;read_addr[0]<=ra;end
   else read_addr[0]<={read_group_base[20:2],2'b00}|((read_group_base[1:0]+read_group_count)&3);
  end
  for(i=1;i<RD_LAT;i=i+1)read_addr[i]<=read_addr[i-1];
  if(aw&&ar)overlap=overlap+1;
  if(aw&&!last_w && cycles-last_cmd<17)gap_bad=gap_bad+1;
  if(ar&&!last_r && cycles-last_cmd<17)gap_bad=gap_bad+1;
  if(aw)begin
   if(wr_count>=32)$fatal(1,"model burst overflow");
   pending_addr[wr_count]=wa;pending_data[wr_count]=wd;pending_dm[wr_count]=dm;
   if(wr_count>0&&wa!==pending_addr[wr_count-1]+1)$fatal(1,"nonconsecutive hardware write");
   wr_count=wr_count+1;
  end
  if(last_w&&!aw)begin
   write_bursts=write_bursts+1;if(wr_count<4||wr_count%4!=0)single_bursts=single_bursts+1;
   for(j=0;j<(STRICT_BURST?(wr_count/4)*4:wr_count);j=j+1)begin
    mapped_address=STRICT_BURST?((pending_addr[(j/4)*4]&21'h1ffffc)|((pending_addr[(j/4)*4]+j%4)&3)):pending_addr[j];
    for(b=0;b<4;b=b+1)if(!pending_dm[j][b])
      mem[mapped_address&21'h1fffff][8*b+:8]=pending_data[j][8*b+:8];
   end
   wr_count=0;
  end
  if(aw||ar)last_cmd=cycles;
  last_w=aw;last_r=ar;
 end
 task write_word(input integer a,input [31:0] d,input [3:0] mask);
 integer n;begin
  @(negedge clk);req=1;wr=1;addr=a;data=d;strb=mask;
  n=0;@(posedge clk);while(ready!==1'b1&&n<5000)begin @(posedge clk);n=n+1;end
  if(n==5000)$fatal(1,"write handshake timeout at %h",a);
  @(negedge clk);req=0;
 end endtask
 task read_word(input integer a,output [31:0] d);
 integer n;begin
  @(negedge clk);req=1;wr=0;addr=a;
  n=0;@(posedge clk);while(ready!==1'b1&&n<5000)begin @(posedge clk);n=n+1;end
  if(n==5000)$fatal(1,"read handshake timeout at %h",a);
  @(negedge clk);req=0;n=0;
  while(rv!==1'b1&&n<5000)begin @(negedge clk);n=n+1;end
  if(n==5000)$fatal(1,"read response timeout at %h",a);
  d=dout;@(negedge clk);
 end endtask
 reg [31:0] v,lfsr=32'h1aceb00c,gold[0:63];integer a,t,byte_i;
 integer k,n,offset,mask_case,base_address,mismatch=0;
 initial begin
  for(k=0;k<32768;k=k+1)mem[k]=32'hd00df00d;
  repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  check(ready===0,"no write acceptance before SDRAM initialization");
  init=1;repeat(5)@(negedge clk);
  for(k=0;k<32;k=k+1)begin write_word(1024+k,32'ha5000000+k,15);repeat(500)@(negedge clk);end
  repeat(100)@(negedge clk);
  for(k=0;k<32;k=k+1)begin read_word(1024+k,v);if(v!==32'ha5000000+k)mismatch=mismatch+1;end
  check(mismatch==0,"slow card words (>48 clocks apart) all stored/read correctly");
  write_word(2048,32'h11112222,15);write_word(2049,32'h33334444,15);
  write_word(2200,32'h55556666,15);write_word(2201,32'h77778888,15);
  repeat(150)@(negedge clk);
  read_word(2048,v);check(v===32'h11112222,"first contiguous segment");
  read_word(2200,v);check(v===32'h55556666,"jump starts a new physical write segment");
  read_word(2201,v);check(v===32'h77778888,"jump segment tail");


  for(k=0;k<4096;k=k+1)mem[12000+k]=32'h9abc0000+k;
  repeat(3)@(negedge clk);stream_compare=1;stream_received=0;
  req=1;wr=0;stream_start_cycle=cycles;
  for(k=0;k<4096;k=k+1)begin
   addr=12000+k;n=0;
   @(posedge clk);while(ready!==1'b1&&n<5000)begin @(posedge clk);n=n+1;end
   if(n==5000)$fatal(1,"stream handshake timeout");
   @(negedge clk);
  end
  req=0;stream_cycles=cycles-stream_start_cycle;repeat(3)@(negedge clk);stream_compare=0;
  check(stream_received==4096,"4096 continuous reads match independent address/data scoreboard");
  if(PREFETCH_READ&&RD_LAT<=11)
    check(stream_cycles<=11377,"prefetch sustains at least 14.4M words/s at 40MHz through latency 11");
  $display("[BANDWIDTH] RD_LAT=%0d FAST_READ=%0d PREFETCH_READ=%0d words=4096 cycles=%0d",RD_LAT,FAST_READ,PREFETCH_READ,stream_cycles);
  if(PREFETCH_READ)begin
   for(k=0;k<128;k=k+1)mem[17000+k]=32'h13570000+k;
   j=0;
   while(j<16&&!(dut.state==3&&dut.contiguous_refill))begin
    read_word(17000+j,v);
    check(v===32'h13570000+j,"prefetch cancellation setup data");
    j=j+1;
   end
   check(dut.state==3&&dut.contiguous_refill,"read prefetch is in flight with a partially drained previous bank");
   @(negedge clk);req=1;wr=1;addr=18000;data=32'hdeadbeef;strb=15;
   @(posedge clk);if(ready)$fatal(1,"write unexpectedly accepted during physical read");
   @(negedge clk);req=0;
   mismatch=0;
   for(k=j;k<64;k=k+1)begin
    read_word(17000+k,v);if(v!==32'h13570000+k)mismatch=mismatch+1;
   end
   check(mismatch==0&&mem[18000]===32'hd00df00d,"cancelled write during prefetch preserves read order and never writes memory");
  end
  read_word(1024,v);write_word(1025,32'hcafebabe,15);repeat(100)@(negedge clk);
  read_word(1025,v);check(v===32'hcafebabe,"write invalidates a prefetched read cache");
  write_word(4096,32'h12345678,15);read_word(4096,v);
  check(v===32'h12345678,"read after accepted buffered write waits for physical drain");
  write_word(4096,32'haabbccdd,4'b0101);repeat(100)@(negedge clk);read_word(4096,v);
  check(v===32'h12bb56dd,"byte masks preserved");
  read_word(4097,v);check(v===32'hd00df00d,"masked padding leaves neighbour unchanged");

  for(k=0;k<64;k=k+1)write_word(5000+k,32'h55aa0000+k,15);
  mismatch=0;
  for(k=0;k<64;k=k+1)begin read_word(5000+k,v);if(v!==32'h55aa0000+k)mismatch=mismatch+1;end
  check(mismatch==0,"64 back-to-back words survive burst and read-cache boundaries");
  for(k=0;k<64;k=k+1)gold[k]=32'hd00df00d;
  mismatch=0;
  for(t=0;t<200;t=t+1)begin
    lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};a=lfsr[5:0];
    write_word(6000+a,lfsr,lfsr[3:0]);
    for(byte_i=0;byte_i<4;byte_i=byte_i+1)if(lfsr[byte_i])gold[a][8*byte_i+:8]=lfsr[8*byte_i+:8];
    if(t%7==0)begin read_word(6000+a,v);if(v!==gold[a])mismatch=mismatch+1;end
  end
  for(k=0;k<64;k=k+1)begin read_word(6000+k,v);if(v!==gold[k])mismatch=mismatch+1;end
  check(mismatch==0,"200 reproducible sparse/masked writes and interleaved reads match independent scoreboard");


  @(negedge clk);req=1;wr=1;strb=15;
  for(k=0;k<64;k=k+1)begin
    addr=7000+k;data=32'h34560000+k;n=0;
    @(posedge clk);while(ready!==1'b1&&n<5000)begin @(posedge clk);n=n+1;end
    if(n==5000)$fatal(1,"continuous write timeout");
    @(negedge clk);
  end
  req=0;mismatch=0;
  for(k=0;k<64;k=k+1)begin read_word(7000+k,v);if(v!==32'h34560000+k)mismatch=mismatch+1;end
  check(mismatch==0,"continuous req holds 64 successive accepted word transactions correctly");


  @(negedge clk);req=1;wr=1;addr=7200;data=32'hfeedbeef;strb=15;
  @(posedge clk);@(negedge clk);req=0;repeat(3)@(negedge clk);
  read_word(7200,v);check(v===32'hd00df00d,"cancelled unaccepted write leaves memory unchanged and clears its precheck");


  for(offset=0;offset<4;offset=offset+1)
   for(t=1;t<=16;t=t+1)
    for(mask_case=0;mask_case<16;mask_case=mask_case+1)begin
     base_address=20000+offset*2048+t*64+offset;


     for(k=-3;k<t+3;k=k+1)mem[base_address+k]=32'hd00df00d;
     for(k=0;k<t;k=k+1)begin
      gold[k]=32'hd00df00d;
      lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
      for(byte_i=0;byte_i<4;byte_i=byte_i+1)
       if(mask_case&(1<<byte_i))gold[k][8*byte_i+:8]=lfsr[8*byte_i+:8];
      write_word(base_address+k,lfsr,mask_case);
     end
     repeat(110)@(negedge clk);mismatch=0;
     for(k=0;k<t;k=k+1)if(mem[base_address+k]!==gold[k])mismatch=mismatch+1;
     for(k=1;k<=3;k=k+1)begin
      if(mem[base_address-k]!==32'hd00df00d)mismatch=mismatch+1;
      if(mem[base_address+t+k-1]!==32'hd00df00d)mismatch=mismatch+1;
     end
     check(mismatch==0,"all offsets/lengths/masks preserve target and BOTH neighbour regions");
    end
  write_word(7500,32'hbadc0ffe,15);
  @(negedge clk);rst_n=0;
  check(ready===0,"reset suppresses acceptance even if SDRAM init remains high");
  repeat(4)@(negedge clk);req=0;rst_n=1;repeat(8)@(negedge clk);
  read_word(7500,v);check(v===32'hd00df00d,"reset discards an unflushed buffered write and clears cached state");

  repeat(100)@(negedge clk);
  for(k=0;k<32;k=k+1)mem[21'h1fffe0+k]=32'hb17e0000+k;
  for(offset=0;offset<4;offset=offset+1)begin
   read_word(23000,v);repeat(100)@(negedge clk);end_fence=1;
   read_word(21'h1ffffc+offset,v);
   check(v===32'hb17e001c+offset,"physical end clipping preserves the requested last word");
   repeat(100)@(negedge clk);end_fence=0;
  end
  check(single_bursts==0,"all physical write bursts contain complete groups of4");
  check(overlap==0,"read and write hardware commands never overlap");
  check(gap_bad==0,"all hardware burst boundaries have at least 16 quiet clocks");
  $display("ADAPTER STREAMING strict=%0d RD_LAT=%0d FAST_READ=%0d PREFETCH_READ=%0d checks=%0d errors=%0d bursts=%0d singles=%0d overlap=%0d gap_bad=%0d",STRICT_BURST,RD_LAT,FAST_READ,PREFETCH_READ,checks,errors,write_bursts,single_bursts,overlap,gap_bad);
  $display("[TB] tb_v3_read_alignment done, errors=%0d checks=%0d",errors,checks);
  if(errors==0)$display("[PASS] ADAPTER ALIGNMENT PASS");$finish;
 end
 initial begin #20000000;$fatal(1,"global timeout");end
endmodule
