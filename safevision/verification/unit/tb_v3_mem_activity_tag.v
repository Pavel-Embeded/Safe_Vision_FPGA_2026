`timescale 1ns/1ps
module mem_activity_case #(parameter integer PHASE=0)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 reg sys_clk=0,mem_clk=0,rst=0,activity=0;always #5 sys_clk=~sys_clk;
 initial begin #(PHASE);forever #10 mem_clk=~mem_clk;end
 wire[31:0] token,snapshot;wire valid;reg seen=0;
 integer produced=0,observed=0,epoch,i;reg[31:0] random_bits=32'h1d872fa5;
 v3_mem_activity_tag producer(.clk(mem_clk),.rst_n(rst),.activity(activity),.token(token));
 v3_related_status_capture #(.WIDTH(32)) capture(.clk(sys_clk),.rst_n(rst),.source_data(token),.data(snapshot),.valid(valid));

 always @(posedge mem_clk or negedge rst)
  if(!rst)produced=0;else if(activity)produced=produced+1;


 always @(posedge sys_clk or negedge rst)begin
  if(!rst)begin seen<=0;observed<=0;end
  else if(valid)begin
   if(snapshot[0]!=seen)observed<=observed+1;
   seen<=snapshot[0];
   comparisons=comparisons+1;
   if(snapshot[31:1]!==0)begin errors=errors+1;$display("[FAIL] reserved token bits changed");end
  end
 end
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons=comparisons+1;
  if(!ok)begin errors=errors+1;$display("[FAIL] phase=%0d %s produced=%0d observed=%0d",PHASE,msg,produced,observed);end end  end endtask
 initial begin
  #1;rst=1;#1;rst=0;
  for(epoch=0;epoch<4;epoch=epoch+1)begin
   repeat(4)@(negedge sys_clk);rst=1;
   for(i=0;i<1000;i=i+1)begin
    @(negedge mem_clk);random_bits=random_bits*1664525+1013904223;
    activity=(i<128) ? 1:(i<256) ? 0:(random_bits[3:0]<11);
   end
   @(negedge mem_clk);activity=0;
   repeat(8)@(negedge sys_clk);
   ck(produced>600 && observed==produced,"every event preserved across full-rate bursts and gaps");
   #2;rst=0;#1;
   ck(token===0 && snapshot===0 && !valid,"reset cancels previous token epoch");
  end
  repeat(4)@(negedge sys_clk);done=1;
 end
endmodule
module tb_v3_mem_activity_tag;
 wire done;wire[31:0] errors,comparisons;
 mem_activity_case #(.PHASE(0)) test_case(done,errors,comparisons);
 initial begin wait(done);if(errors==0)$display("[PASS] source journal equals delivered events, phase0,4reset epochs");
 $display("[TB] tb_v3_mem_activity_tag done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #100000;$display("[FAIL] activity watchdog errors=1");$finish;end
endmodule
module tb_v3_mem_activity_tag_phase3;
 wire done;wire[31:0] errors,comparisons;
 mem_activity_case #(.PHASE(3)) test_case(done,errors,comparisons);
 initial begin wait(done);if(errors==0)$display("[PASS] source journal equals delivered events, phase3,4reset epochs");
 $display("[TB] tb_v3_mem_activity_tag_phase3 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #100000;$display("[FAIL] activity watchdog errors=1");$finish;end
endmodule
module tb_v3_mem_activity_tag_phase5;
 wire done;wire[31:0] errors,comparisons;
 mem_activity_case #(.PHASE(5)) test_case(done,errors,comparisons);
 initial begin wait(done);if(errors==0)$display("[PASS] source journal equals delivered events, phase5,4reset epochs");
 $display("[TB] tb_v3_mem_activity_tag_phase5 done errors=%0d comparisons=%0d",errors,comparisons);$finish;end
 initial begin #100000;$display("[FAIL] activity watchdog errors=1");$finish;end
endmodule
