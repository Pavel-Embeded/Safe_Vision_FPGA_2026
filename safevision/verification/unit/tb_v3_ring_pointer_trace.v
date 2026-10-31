`timescale 1ns/1ps
module tb_v3_ring_pointer_trace;
 reg clk=0;always #5 clk=~clk;
 wire done;wire[31:0]errors,comparisons;
 ring_pointer_lane #(.PW(4))a(clk,done,errors,comparisons);
 initial begin
  repeat(8)begin #20000;
   $display("INFO pointer trace cycle=%0d done=%b state=%0d levels=%h valid=%h ready=%h busy=%b ack=%b req=%b countdown=%0d slot=%0d n=%0d writes=%0d/%0d/%0d/%0d reads=%0d/%0d/%0d/%0d",a.cycles,done,a.current.state,a.levels[0],a.valid,a.ready[0],a.busy,a.ack,a.req[0],a.countdown,a.slot,a.n,a.writes[0],a.writes[1],a.writes[2],a.writes[3],a.reads[0],a.reads[1],a.reads[2],a.reads[3]);
   $display("INFO target=%h equality=%b cap=%0d",{4{v_cast_u16(a.CAP)}},a.levels[0]==={4{v_cast_u16(a.CAP)}},a.CAP);
  end
  if(!done)$display("[FAIL] trace harness has not completed its small-capacity scenario");
  $display("[PASS] trace observation completed");
  $display("PASS tb_v3_ring_pointer_trace errors=%0d comparisons=%0d data_errors=%0d",errors+(!done),comparisons,errors);$finish;
 end

function [15:0] v_cast_u16; input [15:0] value; begin  v_cast_u16=value;   end endfunction
endmodule
