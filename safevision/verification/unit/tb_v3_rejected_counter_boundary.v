`timescale 1ns/1ps
module tb_v3_rejected_counter_boundary;
 reg clk=0,rst=0,rv=0;reg[7:0] data=0;always #5 clk=~clk;
 wire cv,rcv,q,rq,pv,rpv;wire[7:0] target,rtarget,code,rcode;wire[95:0] name,rname;
 wire signed[31:0] value,rvalue;wire[31:0] count,rcount;wire[6:0] id,rid;
 v3_command_parser_catalog #(.TIMEOUT(1000),.CATALOG_FILE("v3_command_catalog.mem")) dut(clk,rst,rv,data,cv,target,name,value,q,pv,code,count,id);
 v3_command_catalog_before_counter #(.TIMEOUT(1000),.CATALOG_FILE("v3_command_catalog.mem")) oracle(clk,rst,rv,data,rcv,rtarget,rname,rvalue,rq,rpv,rcode,rcount,rid);
 integer errors=0,comparisons=0,i;reg[31:0] expected;
 task ck(input  ok,input [4095:0] message);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<9)$display("[FAIL] %s",message);end end  end endtask
 always @(posedge clk)begin #1;
  ck({cv,pv,count,id}==={rcv,rpv,rcount,rid},"cycle-exact event and saturating counter equivalence to untouched parser");
  if(cv)ck({target,name,value,q}==={rtarget,rname,rvalue,rq},"valid command payload equivalence");
  if(pv)ck(code===rcode,"same malformed-packet response code");
 end
 task bad_target;begin begin
  @(negedge clk);data=36;rv=1;
  @(negedge clk);data="X";
  @(posedge clk);#2;
  if(expected!=32'hffffffff)expected=expected+1;
  ck(count===expected && rcount===expected,"independent saturated journal at original reject edge");
  @(negedge clk);rv=0;
 end  end endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
  force dut.rejected_base=32'hfffffffd;force dut.rejected_pending=0;
  force oracle.rejected=32'hfffffffd;
  @(negedge clk);release dut.rejected_base;release dut.rejected_pending;release oracle.rejected;
  expected=32'hfffffffd;
  for(i=0;i<12;i = i + 1)bad_target();
  repeat(10)@(negedge clk);ck(count==32'hffffffff,"count never wraps after saturation");
  #2;rst=0;#1;ck(count===0 && rcount===0,"asynchronous reset cancels pending increment");
  repeat(3)@(negedge clk);rst=1;expected=0;
  for(i=0;i<500;i = i + 1)bad_target();
  repeat(6)@(negedge clk);ck(count==500,"consecutive malformed frames keep every event");
  if(errors==0)$display("[PASS] original-edge parity, independent500-event journal, saturation and reset");
  $display("[TB] tb_v3_rejected_counter_boundary done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #100000;$display("[FAIL] counter boundary watchdog errors=1");$finish;end
endmodule
