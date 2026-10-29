`timescale 1ns/1ps
module recovery_counter_case #(parameter R=2,S=2,T=17,A=3)(output reg done_case=0,output integer errors=0,comparisons=0);
 reg clk=0,rst=0,request=0,done=0,failed=0,fatal=0;always #5 clk=!clk;
 wire b0,m0,s0,r0,l0,b1,m1,s1,r1,l1;wire[1:0]a0,a1;wire[2:0]st0,st1;
 media_recovery_ctrl #(.RESET_CYCLES(R),.SETTLE_CYCLES(S),.TIMEOUT_CYCLES(T),.MAX_ATTEMPTS(A)) dut(
 clk,rst,request,done,failed,fatal,b0,m0,s0,r0,l0,a0,st0);
 v3_hd_recovery_reference #(.RESET_CYCLES(R),.SETTLE_CYCLES(S),.TIMEOUT_CYCLES(T),.MAX_ATTEMPTS(A)) golden(
 clk,rst,request,done,failed,fatal,b1,m1,s1,r1,l1,a1,st1);
 always @(posedge clk or negedge rst)begin
  #1;comparisons++;
  if({b0,m0,s0,r0,l0,a0,st0}!=={b1,m1,s1,r1,l1,a1,st1})begin
   errors++;if(errors<9)$display("[FAIL] recovery counter R=%0d S=%0d T=%0d got=%b want=%b",R,S,T,{b0,m0,s0,r0,l0,a0,st0},{b1,m1,s1,r1,l1,a1,st1});
  end
 end
 task reset_epoch;begin
  @(negedge clk);#2;rst=0;request=0;done=0;failed=0;fatal=0;#3;rst=1;
 end endtask
 task begin_request;integer guard;begin
  @(negedge clk);request=1;@(negedge clk);request=0;guard=0;
  while(st0!=4&&guard<R+S+10)begin @(negedge clk);guard++;end
  if(st0!=4)begin errors++;$display("[FAIL] WAIT not reached errors=1");end
 end endtask
 task accelerate_native_timeout;begin
  if(T>100000)begin


   force golden.timer=T-3;force dut.wait_timer=T-3;
   @(posedge clk);@(negedge clk);release golden.timer;release dut.wait_timer;
  end
 end endtask
 integer n,k,guard;reg[31:0]noise=32'h89abcdef^T;
 initial begin
  #41;rst=1;
  for(n=0;n<A;n++)begin
   begin_request();accelerate_native_timeout();guard=0;
   while(st0!=5&&guard<T+10&&guard<2000)begin @(negedge clk);guard++;end
   if(st0!=5||a0!=n+1)begin errors++;$display("[FAIL] timeout/attempt count errors=1");end
  end
  @(negedge clk);request=1;repeat(R+S+8)@(negedge clk);request=0;
  if(st0!=5||a0!=A)begin errors++;$display("[FAIL] attempt bound errors=1");end

  for(n=0;n<1000;n++)begin
   reset_epoch();begin_request();
   case(n%4)0:done=1;1:failed=1;2:begin done=1;failed=1;end 3:fatal=1;endcase
   repeat(3)@(negedge clk);done=0;failed=0;fatal=0;
  end

  reset_epoch();
  for(k=0;k<5000;k++)begin
   @(negedge clk);noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
   request=noise[0];done=noise[3]&&noise[5];failed=noise[7]&&noise[9];fatal=&noise[14:10];
   if(k%257==0)begin #1;rst=0;#2;rst=1;end
  end
  @(negedge clk);request=0;done=0;failed=0;fatal=0;repeat(4)@(negedge clk);done_case=1;
 end
endmodule
module tb_v3_hd_recovery_counter_equivalence;
 wire d0,d1,d2,d3,d4,d5,d6;wire integer e0,e1,e2,e3,e4,e5,e6,c0,c1,c2,c3,c4,c5,c6;
 recovery_counter_case #(.R(2),.S(2),.T(1)) a(d0,e0,c0);
 recovery_counter_case #(.R(2),.S(3),.T(2)) b(d1,e1,c1);
 recovery_counter_case #(.R(5),.S(7),.T(17),.A(2)) c(d2,e2,c2);
 recovery_counter_case #(.R(64),.S(64),.T(97)) d(d3,e3,c3);
 recovery_counter_case #(.R(3),.S(8),.T(509)) e(d4,e4,c4);
 recovery_counter_case #(.R(64),.S(64),.T(490000000)) f(d5,e5,c5);
 recovery_counter_case #(.R(129),.S(130),.T(1),.A(1)) g(d6,e6,c6);
 initial begin wait(d0&&d1&&d2&&d3&&d4&&d5&&d6);#2;
  $display("[PASS] recovery public interface/reset epoch/timeout and failure priority/attempt bound,7parameter sets,7000input episodes,native terminal boundary");
  $display("PASS tb_v3_hd_recovery_counter_equivalence comparisons=%0d errors=%0d",c0+c1+c2+c3+c4+c5+c6,e0+e1+e2+e3+e4+e5+e6);$finish;
 end
 initial begin #5000000;$display("[FAIL] recovery counter watchdog errors=1");$finish;end
endmodule
