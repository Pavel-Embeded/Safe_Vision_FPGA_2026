// Clock contract only. This does not simulate the vendor PLL, jitter or locks.
`timescale 1ns/1ps
module sv_audio_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out);
 reg a=0;always #40.68966 a=!a;
 assign clk0_out=refclk;assign clk1_out=a;assign extlock=1;
endmodule
