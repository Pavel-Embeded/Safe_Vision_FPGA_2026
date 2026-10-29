

`timescale 1ns/1ps
module sv_v3_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);

 reg sys=1,mem=0;always #5 sys=~sys;always #10 mem=~mem;
 assign clk0_out=sys;assign clk1_out=mem;assign #8 clk2_out=mem;
 assign extlock=1'b1;
endmodule
