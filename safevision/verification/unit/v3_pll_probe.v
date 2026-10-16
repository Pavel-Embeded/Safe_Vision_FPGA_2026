// Preserve one observable consumer for each PLL output in native derivation.
module v3_pll_probe(input wire clk,rst_n,output wire[2:0] activity);
 wire sys,mem,shift,lock;
 sv_v3_memory_pll clocks(.refclk(clk),.reset(1'b0),.extlock(lock),.clk0_out(sys),.clk1_out(mem),.clk2_out(shift));
 reg[3:0] s,m,h;reg phase_capture;
 always @(posedge sys or negedge rst_n)if(!rst_n)s<=0;else s<=s+1'b1;
 always @(posedge mem or negedge rst_n)if(!rst_n)m<=0;else m<=m+1'b1;
 always @(posedge shift or negedge rst_n)if(!rst_n)h<=0;else h<=h+1'b1;
 always @(posedge shift or negedge rst_n)if(!rst_n)phase_capture<=0;else phase_capture<=m[0];
 assign activity={s[3],m[3],h[3]^phase_capture} & {3{lock}};
endmodule
