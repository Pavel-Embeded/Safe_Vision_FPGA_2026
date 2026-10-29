`timescale 1ns/1ps
module progress_clear_case #(parameter L=1,D=1)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg clk=0,rst=0,active=0,hb=0,mr=0;always #5 clk=~clk;
 integer expected=0,k;reg[31:0] rng=32'h734981+L;
 v3_supervisor #(.CLK_HZ(1000*D),.PROGRESS_CYCLES(L*D)) dut(.clk(clk),.rst_n(rst),.media_active(active),.progress_heartbeat(hb));
 initial force dut.media_reset=mr;
 always@(posedge clk or negedge rst)begin
  if(!rst)expected<=0;
  else if(!active||hb||mr)expected<=0;
  else if(dut.watch_tick&&expected<L)expected<=expected+1;
  #1;comparisons = comparisons + 1;
  if(dut.progress_timer!==expected)begin errors = errors + 1;if(errors<6)$display("[FAIL] published progress L=%0d D=%0d got=%0d want=%0d",L,D,dut.progress_timer,expected);end
 end
 initial begin
  #23;rst=1;active=1;
  repeat(L*D+4*D)@(negedge clk);
  if(dut.progress_timer!=L)begin errors = errors + 1;$display("[FAIL] progress saturation L=%0d D=%0d",L,D);end
  for(k=0;k<20000;k = k + 1)begin
   rng=rng*1664525+1013904223;
   active=(k%1997>7);hb=(k%257==0)||rng[9:0]==0;mr=k%2039==0;
   if(k%3001==0)begin #2;rst=0;#3;rst=1;end
   @(negedge clk);
  end
  done=1;
 end
endmodule
module tb_v3_hd_progress_clear;
 wire[6:0]done;wire[31:0] e[0:6],c[0:6];integer errors,comparisons,i;
 progress_clear_case #(1,2) a(done[0],e[0],c[0]);progress_clear_case #(2,2) b(done[1],e[1],c[1]);
 progress_clear_case #(3,10) d(done[2],e[2],c[2]);progress_clear_case #(7,1) f(done[3],e[3],c[3]);
 progress_clear_case #(255,2) g(done[4],e[4],c[4]);progress_clear_case #(256,1) h(done[5],e[5],c[5]);progress_clear_case #(500,10) j(done[6],e[6],c[6]);
 initial begin
  wait(&done);#2;errors=0;comparisons=0;for(i=0;i<7;i = i + 1)begin errors = errors + (e[i]);comparisons = comparisons + (c[i]);end
  if(errors==0)$display("[PASS] exact published progress over7 limits/dividers,saturation,heartbeat,media reset,async reset;no public latency change");
  $display("[TB] tb_v3_hd_progress_clear done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #400000;$display("[FAIL] progress watchdog");$display("[TB] tb_v3_hd_progress_clear done errors=1");$finish;end
endmodule
