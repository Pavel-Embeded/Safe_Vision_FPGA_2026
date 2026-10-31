`timescale 1ns/1ps
module tb_v3_audio_ingress;
 reg wc=0,rc=0,rst=1,read_clock=0,valid=0,re=0;
 always #5 wc=~wc;always #6.7 if(read_clock)rc=~rc;
 reg[31:0] data=0;wire ready,room,rv;wire[8:0] pairs;wire[31:0] out;
 v3_pcm_ingress_fifo dut(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(data),.wr_valid(valid),
 .wr_ready(ready),.wr_pairs(pairs),.sector_room(room),.rd_data(out),.rd_valid(rv),.rd_ready(re));
 reg[31:0] expected[0:2047];integer head=0,tail=0,checks=0;reg stalled=0;reg[31:0] last_value;
 always @(posedge wc)if(!rst&&valid&&ready)begin expected[tail]=data;tail=tail+1;end
 always @(posedge rc)if(!rst)begin
  if(stalled&&(!rv||out!==last_value))begin $display("[FAIL] ingress pair changed under backpressure"); $finish; end
  stalled=rv&&!re;last_value=out;
  if(rv&&re)begin
   if(head>=tail||out!==expected[head])begin $display("[FAIL] ingress stereo framing/order idx=%0d got=%h expected=%h",head,out,expected[head]); $finish; end
   head=head+1;checks=checks+1;
  end
 end
 task send(input integer n);
  begin  @(negedge wc);data=32'ha5c30000+n;valid=1;@(posedge wc);while(!ready)@(posedge wc);@(negedge wc);valid=0;
  end endtask
 task reset_epoch;
  begin  rst=1;valid=0;read_clock=1;re=0;#100;head=0;tail=0;stalled=0;rst=0;repeat(10)@(negedge wc);
  end endtask
 initial begin
  reset_epoch();@(negedge rc);read_clock=0;
  begin : v_loop_1 integer k; for( k=0;k<126;k=k+1)send(k); end
  wait(!dut.holding);repeat(5)@(negedge wc);
  if(!room||dut.words!=252)begin $display("[FAIL] precondition full-sector reservation words=%0d room=%b",dut.words,room); $finish; end

  begin : v_loop_2 integer k; for( k=126;k<254;k=k+1)send(k); end
  wait(!dut.holding);repeat(5)@(negedge wc);
  if(dut.words!=508||room||pairs!=254)begin $display("[FAIL] 128pair sector capacity was reduced words=%0d pairs=%0d",dut.words,pairs); $finish; end
  read_clock=1;re=1;wait(head>=100);re=0;repeat(20)@(negedge rc);re=1;wait(head==tail);

  fork : v_race_1  begin : v_branch_1 begin send(300);end disable v_race_1; end  begin : v_branch_2 begin wait(dut.holding&&dut.write_part);rst=1;end disable v_race_1; end  join
  reset_epoch();re=1;
  begin : v_loop_3 integer k; for( k=0;k<200;k=k+1)send(k+400); end
  wait(head==tail);repeat(10)@(negedge rc);
  $display("[PASS] one TD16x512 FIFO reserves128stereo pairs at252words, lossless order/backpressure/halfpacket epoch");
  $display("PASS tb_v3_audio_ingress errors=0 comparisons=%0d",checks);$finish;
 end
 initial begin #1000000;begin $display("[FAIL] ingress watchdog head=%0d tail=%0d words=%0d holding=%b",head,tail,dut.words,dut.holding); $finish; end end
endmodule

