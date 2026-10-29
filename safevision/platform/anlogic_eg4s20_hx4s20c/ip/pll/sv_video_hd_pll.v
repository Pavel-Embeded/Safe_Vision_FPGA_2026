/************************************************************\
 **  Copyright (c) 2012-2025 Anlogic Inc.
 **  All Right Reserved.\
\************************************************************/


`timescale 1 ns / 100 fs

module sv_video_hd_pll (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out,
  clk2_out
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;
  output clk2_out;

  wire clk0_buf;


  assign clk0_out = clk0_buf;

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(0),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(2),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(4),
    .FBCLK_DIV(1),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(89),
    .CLKC0_CPHASE(88),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(15),
    .CLKC1_CPHASE(14),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(3),
    .CLKC2_CPHASE(2),
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
    .psdone(sv_video_hd_pll_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({sv_video_hd_pll_open8, sv_video_hd_pll_open7, sv_video_hd_pll_open6, sv_video_hd_pll_open5, sv_video_hd_pll_open4, sv_video_hd_pll_open3, sv_video_hd_pll_open2, sv_video_hd_pll_open1}),
    .fbclk(clk0_out),
    .clkc({sv_video_hd_pll_open10, sv_video_hd_pll_open9, clk2_out, clk1_out, clk0_buf})
  );

endmodule

