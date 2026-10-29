`timescale 1ns/1ps
module tb_v3_fifo_phase50;
 reg wc=0,rc=0,rst=1,wen=1,ren=1,stop_write=0,draining=0,wv=0,ready=0;always #5 if(wen)wc=~wc;always #7 if(ren)rc=~rc;
 reg[15:0]data=0;reg[31:0] rngw=32'h194326,rngr=32'h883765;
 wire[15:0]ad,bd;wire av,bv,af,bf,ae,be,aaf,baf,aae,bae,donea,doneb;wire[3:0]aw,bw,ar,br;
 wire wa=wv&&donea&&!af,wb=wv&&doneb&&!bf,ra=ready&&av&&!ae,rb=ready&&bv&&!be;
 sv_fifo_phase_ip #(.DATA_WIDTH_W(16),.DATA_WIDTH_R(16),.ADDR_WIDTH_W(4),.ADDR_WIDTH_R(4),.AL_FULL_NUM(12),.AL_EMPTY_NUM(4)) dut(.rst(rst),.clkw(wc),.clkr(rc),.we(wa),.di(data),.re(ra),.dout(ad),.valid(av),.full_flag(af),.empty_flag(ae),.afull(aaf),.aempty(aae),.wrusedw(aw),.rdusedw(ar),.wr_rst_done(donea));
 a_pixel_fifo_phase49_reference #(.DATA_WIDTH_W(16),.DATA_WIDTH_R(16),.ADDR_WIDTH_W(4),.ADDR_WIDTH_R(4),.AL_FULL_NUM(12),.AL_EMPTY_NUM(4)) reference(.rst(rst),.clkw(wc),.clkr(rc),.we(wb),.di(data),.re(rb),.dout(bd),.valid(bv),.full_flag(bf),.empty_flag(be),.afull(baf),.aempty(bae),.wrusedw(bw),.rdusedw(br),.wr_rst_done(doneb));
 integer errors=0,comparisons=0,written=0,readn=0,total_wr=0,total_rd=0,k;reg[15:0]score[0:100000];
 task check(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;if(errors<10)$display("[FAIL] %s written=%0d read=%0d",message,written,readn);end end endtask
 always@(negedge wc)begin rngw=rngw*1664525+1013904223;wv<=!stop_write&&rngw[1:0]!=0;end
 always@(negedge rc)begin rngr=rngr*1664525+1013904223;ready<=draining||rngr[1:0]!=0;end


 always@(posedge wc or posedge rst)begin
  if(rst)begin written=0;data<=0;end
  else begin
   check({wa,af,aaf,aw}==={wb,bf,baf,bw},"write sampling edge,ready/full/credit");
   if(wa)begin score[written]=data;written++;total_wr++;data<=data+16'h0107;end
  end
 end
 always@(posedge rc or posedge rst)begin
  if(rst)readn=0;
  else begin
   check({ra,av,ae,aae,ar}==={rb,bv,be,bae,br},"read sampling edge,valid/empty/credit");
   if(ra)begin check(ad===bd,"frozen vendor output payload");check(readn<written&&ad===score[readn],"independent accepted-word order");readn++;total_rd++;end
  end
 end
 initial begin
  #1;rst=0;#2;rst=1;#21;rst=0;
  for(k=0;k<6;k++)begin
   repeat(4000)@(negedge wc);
   #2;rst=1;#1;check(!donea&&!doneb,"asynchronous assertion");#11;rst=0;
  end
  @(negedge rc);ren=0;#2;rst=1;#11;rst=0;#100;check(dut.rd_rst===1'b1,"stopped read clock cannot release");ren=1;
  repeat(6000)@(negedge wc);stop_write=1;draining=1;repeat(1000)@(negedge rc);
  check(readn==written&&total_rd>5000,"all final words drained with meaningful accepted coverage");
  if(errors==0)$display("[PASS] FIFO phase,async stopped-clock reset,accepted-edge equivalence,full/backpressure/Gray order and independent scoreboard");
  $display("[TB] tb_v3_fifo_phase50 done errors=%0d comparisons=%0d writes=%0d reads=%0d",errors,comparisons,total_wr,total_rd);$finish;
 end
 initial begin #2000000;$display("[FAIL] FIFO phase watchdog");$display("[TB] tb_v3_fifo_phase50 done errors=1");$finish;end
endmodule
