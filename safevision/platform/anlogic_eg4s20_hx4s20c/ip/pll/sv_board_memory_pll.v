// Board memory timing profile derived from the TD-generated system PLL.
// Same 50MHz reference, 1GHz VCO and 100MHz SYS; MEM=40MHz, SDRAM=40MHz
// with its rising edge 10ns after MEM (144 degrees). CPHASE=9 is verified
// by TD derive_clocks, not inferred from the IP GUI label. All SDRAM setup/
// hold paths remain timed. The original 125MHz PLL is retained for lab tops.
`timescale 1 ns / 100 fs

module sv_board_memory_pll (
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
  wire clk2_buf;

  // Forward the phase-shifted SDRAM clock on a dedicated clock network.
  EG_LOGIC_BUFG bufg_memory (.i(clk2_buf), .o(clk2_out));

  // TD 6.2.168116 workaround: keep NORMAL / CLKC0_EXT compensation.
  // A split explicit feedback BUFG is physically merged by the router but
  // check_timing misclassifies its input segment. A single C0 feedback net
  // is auto-routed through the same global clock mesh to PLL fbclk.
  // Verify final global routing and clock coverage after IP regeneration.
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
    .CLKC1_DIV(25),
    .CLKC1_CPHASE(24),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(25),
    .CLKC2_CPHASE(9),
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
    .psdone(sv_board_memory_pll_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({sv_board_memory_pll_open8, sv_board_memory_pll_open7, sv_board_memory_pll_open6, sv_board_memory_pll_open5, sv_board_memory_pll_open4, sv_board_memory_pll_open3, sv_board_memory_pll_open2, sv_board_memory_pll_open1}),
    .fbclk(clk0_out),
    .clkc({sv_board_memory_pll_open11, sv_board_memory_pll_open10, clk2_buf, clk1_out, clk0_buf})
  );

endmodule
