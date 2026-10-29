`timescale 1ns/1ps
module tb_v3_pixel_response_tracker;
 reg clk=0,rst=0,req=0,cancel=0,valid=0,busy=0,direct=0,is_next=0,initialized=0;always #5 clk=~clk;
 reg[7:0]target=0,current=0,alpha=0;wire evt,toggle;
 v3_pixel_response_tracker d(clk,rst,req,cancel,valid,busy,direct,is_next,initialized,target,current,alpha,evt,toggle);
 integer errors=0,comparisons=0,k,events=0,old_events;reg expect_toggle=0;
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<10)$display("[FAIL] %s",msg);end end  end endtask
 task cycle(input  want_event);begin begin
  want_event = (want_event === 1'b1); #1;ck(evt===want_event,"only the intended request target can respond");
  @(posedge clk);#1;if(want_event)begin expect_toggle=!expect_toggle;events = events + 1;end
  ck(toggle===expect_toggle,"exactly one matching response toggle");@(negedge clk);
 end  end endtask
 task request;begin begin req=1;cycle(0);req=0;end  end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;

  request();target=1;busy=1;direct=1;valid=1;cycle(0);
  busy=0;current=1;initialized=1;cycle(0);
  target=2;busy=1;direct=0;is_next=1;alpha=0;cycle(0);
  alpha=8;valid=0;cycle(0);valid=1;cycle(1);cycle(0);
  busy=0;current=2;alpha=0;cycle(0);

  request();cycle(0);target=3;busy=1;direct=1;cycle(0);
  busy=0;current=3;cycle(1);cycle(0);

  request();target=4;busy=1;direct=0;alpha=8;valid=0;cycle(0);
  cancel=1;valid=1;cycle(0);cancel=0;busy=0;is_next=0;cycle(0);
  request();cycle(0);target=5;busy=1;direct=0;is_next=1;alpha=8;cycle(1);cycle(0);


  for(k=0;k<1024;k = k + 1)begin
   busy=0;current=target;request();cycle(0);
   target=target+1'b1;busy=1;direct=0;is_next=1;alpha=0;cycle(0);
   if(k%3==0)begin cancel=1;cycle(0);cancel=0;busy=0;is_next=0;cycle(0);end
   else begin alpha=8;valid=1;cycle(1);cycle(0);end
  end


  busy=0;current=target;is_next=1;request();cycle(0);request();cycle(0);
  target=target+1'b1;busy=1;direct=0;alpha=8;cycle(1);cycle(0);
  busy=0;current=target;request();target=target+1'b1;busy=1;alpha=8;
  request();cycle(0);target=target+1'b1;cycle(1);cycle(0);
  if(errors==0)$display("[PASS] startup queue, previous-target rejection, direct/fade, invalid pixels, cancellation, latest request and1024 wrapped allocations");
  $display("[TB] tb_v3_pixel_response_tracker done errors=%0d comparisons=%0d events=%0d",errors,comparisons,events);$finish;
 end
endmodule
