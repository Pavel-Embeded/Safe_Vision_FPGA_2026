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
  // ★ 2026-10-11：`Clk_sft` 必须是 **半周期（180°）**，不能是别的相位。
  //
  //   证据（三份配置并排）：
  //     · 厂商例程 lab_ex4_tf 的 sys_pll：CLKC1_DIV=8/CPHASE=7、CLKC2_DIV=8/CPHASE=3
  //       ⇒ Clk=125MHz 0°、Clk_sft=125MHz **+4ns = 恰好 180°**
  //     · 我们仓库里**上板跑通过**的 SDRAM 回环自检 top_sdram_loopback 用同一个
  //       sv_system_pll，文件头明写："C1=125M = SDRAM 侧 Clk、C2=125M **180° 相移** = Clk_sft"
  //     · 本文件原来：CLKC1_DIV=25/CPHASE=24、CLKC2_DIV=25/CPHASE=9
  //       ⇒ 40MHz 0° / **+10ns = 144°** ✗
  //
  //   相位公式（VCO=1GHz ⇒ 步进恰好 1ns，已用实测反验过）：
  //       phase_ns = ((CPHASE - (DIV-1)) mod DIV) × 1ns
  //     验算：DIV=8 /CPHASE=3 → ((3-7) mod 8)=4 → 4ns = 8ns 的一半 ✓ 180°
  //           DIV=25/CPHASE=9 → ((9-24) mod 25)=10 → 10ns / 25ns = 144% ✗
  //
  //   为什么致命：`Clk_sft` **就是驱动封装内 SDRAM 时钟的那一路**
  //     （路由报告：system_pll/pll_inst.clkc[2] → bufg_memory → memory_ip/sdram.clk），
  //     IP 内部按"Clk + Clk_sft 两相"工作；相位不是 180° 时它的内部时序整体错位
  //     ⇒ 写命令/写数据/读回全部错 ⇒ 现象正是"写不进去、读回处处全 1、
  //     却不报任何故障（Sdr_init_done=1、无 protocol_fault、无 mem_timeout）"。
  //
  //   注意 40MHz 下 180° = 12.5ns，1ns 步进**做不出来** ⇒ 改用 **50MHz（周期 20ns，
  //   180° = 10ns 正好整数）**。50MHz 下 MEM 域最差路径 14.963ns < 20ns，余量 5ns ✓。
  //   `-define SAFEVISION_DIAG_MEM62` 可切到 62.5MHz（16ns，180°=8ns，余量仅 1ns，备用）。
  // ==========================================================================
`ifdef SAFEVISION_DIAG_MEM100P0
  // 100MHz + **0ns**：相移最小的一端
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=9;
`elsif SAFEVISION_DIAG_MEM100P1
  // 100MHz + **1ns**
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=0;
`elsif SAFEVISION_DIAG_MEM100P2
  // 100MHz + **2ns**（72°）：把 DQ 提前到 clk1 沿之前
  //   DQ 有效 ≈ 2+5.4 = 7.4ns，clk1 沿在 10ns ⇒ 建立 2.6ns ✓；保持到 17.4ns ⇒ 保持 7.4ns ✓
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=1;
`elsif SAFEVISION_DIAG_MEM100P8
  // 100MHz + **8ns**（288°）：反方向 —— 让 DQ 落在下一个 clk1 沿之前
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=7;
`elsif SAFEVISION_DIAG_D40R
  // ★ 40MHz，`Clk_sft` = +10ns —— 与队友上板验证过的档**逐字相同**
  //   （DIV=25/CPHASE=24 → 0°；DIV=25/CPHASE=9 → (9-24) mod 25 = 10ns）。
  localparam integer MEM_DIV=25, MEM_CPH=24, SFT_CPH=9;
`elsif SAFEVISION_DIAG_D4KR
  // 与 D100/D10R 同一时钟档（100MHz + 精确 180°）；差别只在刷新行数与报头/ID。
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=4;
`elsif SAFEVISION_DIAG_D10R
  // 与 D100 完全同一时钟档（100MHz + 精确 180°）；单独宏只为报头/ID 可辨。
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=4;
`elsif SAFEVISION_DIAG_D100
  // ★ 100MHz + 精确 180°（5ns），与 `SAFEVISION_DIAG_MEM100` 同一时钟档；
  //   单独的宏只为让报头/ID 可辨（这一版带 DQM 修复）。phase = ((4-9) mod 10)=5 → 5ns ✓
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=4;
`elsif SAFEVISION_DIAG_MEM100
  // ★★ 100MHz + **精确 180°（5ns）**：MEM 域最差路径 8.796ns（去 guard 后 Fmax 113.7MHz）
  //   ⇒ 10ns 周期余量 +1.2ns ✓；相位 ((4-9) mod 10)=5 → 5ns = 10ns 的一半 ✓
  localparam integer MEM_DIV=10, MEM_CPH=9, SFT_CPH=4;
`elsif SAFEVISION_DIAG_MEM111
  // 111.1MHz + 4ns（160°）：MEM 域余量仅 +0.2ns，备用
  localparam integer MEM_DIV=9, MEM_CPH=8, SFT_CPH=3;
`elsif SAFEVISION_DIAG_MEM125
  // ★★ 125MHz + 180°：**逐字照抄厂商例程与仓库里跑通的回环自检**
  //   （lab_ex4_tf/sys_pll 与 sv_system_pll：CLKC1_DIV=8/CPHASE=7、CLKC2_DIV=8/CPHASE=3）
  //   phase = ((7-7) mod 8)×1ns = 0 ；((3-7) mod 8)×1ns = 4ns = 8ns 的一半 = 180° ✓
  //   前提：把 guard 整块去掉（SAFEVISION_DIAG_NO_GUARD），否则 MEM 域 Fmax 只有 66.8MHz。
  //   ⚠️ 实测：去掉 guard 后 MEM 域仍差 0.796ns（arbiter/cur_addr → adapter/contiguous_refill
  //   8.516ns，含 2 个 ADDER）⇒ 125MHz 过不了门限，改用 100MHz。
  localparam integer MEM_DIV=8, MEM_CPH=7, SFT_CPH=3;
`elsif SAFEVISION_DIAG_MEM62
  localparam integer MEM_DIV=16, MEM_CPH=15, SFT_CPH=7;   // 62.5MHz, +8ns  = 180°
`elsif SAFEVISION_DIAG_MEM180
  localparam integer MEM_DIV=20, MEM_CPH=19, SFT_CPH=9;   // 50MHz,   +10ns = 180°（边界负余量）
`elsif SAFEVISION_DIAG_MEM187
  // 40MHz + 13ns（187.2°）：建立窗口最大 ⇒ 给 SDRAM 边界的 ~10.8ns 路径留 2.2ns 余量
  localparam integer MEM_DIV=25, MEM_CPH=24, SFT_CPH=12;
`else
  // ★ 默认（"只动相位、不动频率"的干净实验）：40MHz，Clk_sft = +12ns
  //   12ns / 25ns = 172.8°，是 40MHz 下最接近 180° 的取值（180° 需要 12.5ns，
  //   1ns 步进做不出来）。**保持 40MHz 是为了不引入 SDRAM 边界负余量**：
  //   50MHz 档 TD 报 SWNS=-0.826ns / 32 条 SDRAM 边界负路径（EXPERIMENTAL_SDRAM_UNCLOSED），
  //   而 40MHz 档是 0 负路径 ⇒ 只有保持 40MHz，才能把"相位"这一个变量单独验出来。
  localparam integer MEM_DIV=25, MEM_CPH=24, SFT_CPH=11;  // 40MHz,   +12ns = 172.8°
`endif

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
