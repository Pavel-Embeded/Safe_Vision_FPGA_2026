`timescale 1ns/1ps
module mailbox_case228 #(parameter W=103,SC=5,DC=7)(output reg done=0,output integer errors=0,comparisons=0);
 reg s=0,d=0,rst=0,running=1;always #(SC) s=~s;always #(DC) d=~d;
 reg[W-1:0] data=0;reg valid=0,ready=0;wire sr,sv,rr,rv;wire[W-1:0] sd,rd;
 video_cdc_mailbox #(.WIDTH(W)) dut(s,rst,data,valid,sr,d,rst,sd,sv,ready);
 video_cdc_mailbox220_reference #(.WIDTH(W)) oracle(s,rst,data,valid,rr,d,rst,rd,rv,ready);
 reg[W-1:0] queue[0:100000];integer head=0,tail=0,scount=0,dcount=0,epoch,cycle;
 reg[31:0] random_s=32'h5a341cd7,random_d=32'h8dc21345;
 function[31:0] next_random(input[31:0] x);reg[31:0] y;begin y=x^(x<<13);y=y^(y>>17);next_random=y^(y<<5);end endfunction
 always@(negedge s)begin
  random_s=next_random(random_s);scount++;
  if(!rst||!running)begin valid=0;data=0;end
  else if(!valid||sr)begin valid=random_s[2:0]!=0;data={random_s,next_random(random_s),next_random(random_s^32'h12345678),random_s};end
 end
 always@(negedge d)begin random_d=next_random(random_d);dcount++;ready=(dcount%511<180)?0:random_d[0];end
 always@(posedge s or negedge rst)begin
  if(!rst)tail=0;else if(valid&&sr)begin queue[tail]=data;tail++;end
 end
 always@(posedge d or negedge rst)begin
  if(!rst)head=0;else if(sv&&ready)begin
   comparisons++;if(head>=tail||sd!==queue[head])begin errors++;if(errors<8)$display("[FAIL] missing/duplicate/corrupt mailbox epoch payload W=%0d",W);end
   head++;
  end
 end
 always@(posedge s)begin #0.2;comparisons++;if(sr!==rr)begin errors++;if(errors<8)$display("[FAIL] source ready edge differs");end end
 always@(posedge d)begin #0.2;comparisons++;if({sv,sd}!=={rv,rd})begin errors++;if(errors<8)$display("[FAIL] destination public edge differs W=%0d",W);end end
 initial begin
  #100;rst=1;
  // Reset during idle, request crossing, settling, valid backpressure and
  // acknowledgment phases. Private payload may be X, public outputs cannot.
  for(epoch=0;epoch<12;epoch++)begin
   for(cycle=0;cycle<3000+epoch*19;cycle++)@(negedge s);
   #1.3;rst=0;#0.3;comparisons++;if(sd!==0||sv!==0||sr!==0)begin errors++;$display("[FAIL] public asynchronous reset lost");end
   #(83+epoch);rst=1;
  end
  repeat(20000)@(negedge s);running=0;repeat(1500)@(negedge d);
  comparisons++;if(head!=tail||sv)begin errors++;$display("[FAIL] mailbox did not fully drain");end
  if(!errors)$display("[PASS] private reset elision preserves every public edge, independent queue and12 reset epochs W=%0d",W);
  done=1;
 end
endmodule
module tb_v3_mailbox_miter228;
 wire a,b;wire integer ea,eb,ca,cb;
 mailbox_case228 #(.W(103),.SC(5),.DC(7)) x(a,ea,ca);
 mailbox_case228 #(.W(71),.SC(10),.DC(5)) y(b,eb,cb);
 initial begin wait(a&&b);$display("[TB] tb_v3_mailbox_miter228 done errors=%0d comparisons=%0d",ea+eb,ca+cb);$finish;end
 initial begin #2000000;$display("[FAIL] mailbox watchdog");$display("[TB] tb_v3_mailbox_miter228 done errors=1 comparisons=0");$finish;end
endmodule
