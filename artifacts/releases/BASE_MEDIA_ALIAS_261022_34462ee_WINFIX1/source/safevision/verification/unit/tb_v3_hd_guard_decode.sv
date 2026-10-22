`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_v3_hd_guard_decode;
 reg[31:0]addr=0,rng=32'h5b691273;integer errors=0,comparisons=0,k,slot,off,idx;reg valid;
 v3_row_integrity dut(.clk(1'b0),.rst_n(1'b0),.lookup_addr(addr));
 task check;begin #1;
  slot=addr>=32'h1e0000 ? 3 : addr>=32'h140000 ? 2 : addr>=32'ha0000 ? 1 : 0;
  off=addr-slot*655360;valid=$unsigned(off)<614400&&$unsigned(off)%1280==0;
  idx=valid?slot*512+$unsigned(off)/1280:0;comparisons++;
  if(dut.query_ok!==valid||dut.query_index!==idx[10:0])begin errors++;if(errors<6)$display("[FAIL] exact lookup addr=%h q=%d idx=%d expected=%d",addr,dut.query_ok,dut.query_index,idx);end
 end endtask
 initial begin
  for(k=0;k<2621440;k++)begin addr=k;check();end
  for(k=0;k<100000;k++)begin rng=rng*1664525+1013904223;addr=rng;check();end
  if(errors==0)$display("[PASS] all four allocated slot byte addresses plus100k32-bit addresses; full validity and exact index with unchanged latency");
  $display("[TB] tb_v3_hd_guard_decode done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #4000000;$display("[FAIL] decode watchdog");$display("[TB] tb_v3_hd_guard_decode done errors=1");$finish;end
endmodule
