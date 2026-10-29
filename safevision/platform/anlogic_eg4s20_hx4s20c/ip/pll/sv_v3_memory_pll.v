


`timescale 1ns/100fs
module sv_v3_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 wire clk0_buf,clk2_buf;
 wire sv_v3_memory_pll_open0,sv_v3_memory_pll_open1,sv_v3_memory_pll_open2,
 sv_v3_memory_pll_open3,sv_v3_memory_pll_open4,sv_v3_memory_pll_open5,
 sv_v3_memory_pll_open6,sv_v3_memory_pll_open7,sv_v3_memory_pll_open8,
 sv_v3_memory_pll_open10,sv_v3_memory_pll_open11;
 assign clk0_out=clk0_buf;
 EG_LOGIC_BUFG bufg_memory(.i(clk2_buf),.o(clk2_out));
  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(4),
    .ICP_CURRENT(13),
    .KVCO(4),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(4),
    .REFCLK_DIV(1),
    .FBCLK_DIV(2),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(10),
    .CLKC0_CPHASE(9),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(20),
    .CLKC1_CPHASE(19),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(20),
    .CLKC2_CPHASE(7),
    .CLKC2_FPHASE(0)
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(sv_v3_memory_pll_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({sv_v3_memory_pll_open8, sv_v3_memory_pll_open7, sv_v3_memory_pll_open6, sv_v3_memory_pll_open5, sv_v3_memory_pll_open4, sv_v3_memory_pll_open3, sv_v3_memory_pll_open2, sv_v3_memory_pll_open1}),
    .fbclk(clk0_out),
    .clkc({sv_v3_memory_pll_open11, sv_v3_memory_pll_open10, clk2_buf, clk1_out, clk0_buf})
  );

endmodule
