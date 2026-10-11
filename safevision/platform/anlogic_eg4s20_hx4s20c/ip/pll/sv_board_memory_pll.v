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

  // ==========================================================================
  // Memory clock profile - FINAL, board-verified configuration.
  //
  //   MEM   (clk1) = 40 MHz,   0 deg
  //   SDRAM (clk2) = 40 MHz, +10 ns      <- Clk_sft, drives the in-package SDRAM
  //                                         clock (route report:
  //                                         system_pll/pll_inst.clkc[2] -> bufg_memory
  //                                         -> memory_ip/sdram.clk), so this phase
  //                                         is the SDRAM interface timing reference.
  //
  //   Phase formula (VCO = 1 GHz, so the step is exactly 1 ns):
  //       phase_ns = ((CPHASE - (DIV-1)) mod DIV) * 1 ns
  //       DIV=25 / CPHASE=24 -> ((24-24) mod 25) = 0   ->  0 ns
  //       DIV=25 / CPHASE=9  -> (( 9-24) mod 25) = 10  -> 10 ns
  //
  //   At this profile the whole design closes with 0 negative paths
  //   (SWNS +1.517 ns, no experimental exception needed) and the board shows the
  //   SD image - see docs/B链-构建与复现.md for the full fingerprint.
  //
  //   NOT kept here on purpose (they were tried on hardware and are superseded):
  //   the clock-phase sweep (100/111/125 MHz with phases 0..13 ns) and the
  //   vendor-example profile (125 MHz / 180 deg). Recover them from git history
  //   (tag archive/*) if ever needed.
  // ==========================================================================
  localparam integer MEM_DIV=25, MEM_CPH=24, SFT_CPH=9;

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
    .CLKC1_DIV(MEM_DIV),
    .CLKC1_CPHASE(MEM_CPH),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"),
    .CLKC2_DIV(MEM_DIV),
    .CLKC2_CPHASE(SFT_CPH),
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
