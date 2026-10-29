`timescale 1ns/1ps
module tb_v3_event_fifo;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,w=0,r=0;reg[43:0] din=0;
 wire full,empty,af,ae,f0,e0,af0,ae0;wire[43:0] dout,d0;wire[3:0] count,n0;
 v3_event_fifo dut(clk,rst_n,w,din,full,af,r,dout,empty,ae,count);
 sync_fifo #(.W(44),.DEPTH(8),.ALMOST_FULL_TH(6),.ALMOST_EMPTY_TH(1)) reference(
 .clk(clk),.rst_n(rst_n),.wr_en(w),.din(din),.full(f0),.almost_full(af0),.rd_en(r),.dout(d0),.empty(e0),.almost_empty(ae0),.data_count(n0));
 reg[43:0] model[0:7];integer head=0,tail=0,queued=0,errors=0,comparisons=0,i,phase;
 reg wf,rf;reg[31:0] random_state=32'h8a914f62;
 task ck;input c;input[511:0] msg;begin begin comparisons=comparisons+1;
 if(!c)begin errors=errors+1;if(errors<20)$display("[FAIL] %s cnt=%0d/%0d head=%h/%h ref=%h",msg,count,queued,dout,model[head],d0);end end  end endtask
 always @(posedge clk)begin
  if(!rst_n)begin head=0;tail=0;queued=0;end
  else begin
   ck(full==f0&&empty==e0&&af==af0&&ae==ae0&&count==n0,"cycle-exact legacy flags/count");
   ck(count==queued&&full==(queued==8)&&empty==(queued==0),"independent logical occupancy");
   if(queued>0)ck(dout===model[head]&&dout===d0,"FWFT complete event identity before accepting edge");
   wf=w&&(queued<8);rf=r&&(queued>0);
   if(wf)begin model[tail]=din;tail=(tail+1)%8;end
   if(rf)head=(head+1)%8;
   queued=queued+wf-rf;
  end
 end
 task cycle;input wr,rd;begin begin w=wr;r=rd;din=din+44'h13579bdf01;@(negedge clk);end  end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;

  for(phase=0;phase<80;phase=phase+1)begin
   cycle(1,0);repeat(6)cycle(1,1);repeat(12)cycle(1,0);
   repeat(12)cycle(1,1);repeat(12)cycle(0,1);repeat(2)cycle(0,0);
  end
  for(i=0;i<20000;i=i+1)begin
   random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
   cycle(random_state[0],random_state[4]);
   if(i%173==0)begin rst_n=0;w=0;r=0;repeat(2)@(negedge clk);rst_n=1;end
  end
  repeat(12)cycle(0,1);w=0;r=0;repeat(3)@(negedge clk);
  ck(empty&&count==0,"all retained events drained after wrap/reset pressure");
  if(errors==0)$display("[PASS] physical event FIFO exact legacy FWFT, collisions, stalls, wrap and reset epochs");
  $display("[TB] tb_v3_event_fifo done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #500000;$display("[FAIL] global timeout");$finish;end
endmodule
