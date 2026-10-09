// ============================================================================
// vendor_ip_stub.sv — 厂商加密 IP 的**仿真桩**（只用于把板级顶层拉进回归）
// ----------------------------------------------------------------------------
// ★★★ 这个文件**不是**厂商行为模型，它**不能证明**任何 SDRAM 协议层面的东西。
//    它存在的唯一目的：`top_sdram_loopback.v` 例化的是两个 ModelSim **编译不了**的单元 ——
//      · `sdram`            → 真正实现在三个**安路 RSA 加密**的 `sdr_*.enc.v` 里（只能 TD 解密）
//      · `sv_system_pll`    → 内部是 TD 的 `EG_PHY_PLL` 宏（仿真库里没有）
//    于是这个顶层一直**进不了回归**，只能靠烧板。但"顶层的状态机 / 报告装配 / 地址生成 /
//    图案生成"这些**都是我们自己的逻辑**，完全可以仿真 —— 用桩顶掉那两个黑盒就能测。
//
// ★ 它能证明什么（`tb_top_sdram_loopback.sv` 用到）：
//     · 上电 → 等初始化 → 写 → 等落地 → 读 → 等收齐 → 发报告 这条**序列真的会跑完**
//     · 报告是**定长 136 Byte** 且**逐字节正确**（含 `CFG` / `BAD0` 行）
//     · `led[3:0]` 最终 = 8（成功态）
//     · 地址步长 / 图案 / `cap_cnt` 对齐这些我们自己的算式
//
// ★ 它**不能**证明什么（别把这里过了当成板子过了）：
//     · SDRAM 的**协议/时序**：桩是"理想存储器"，不模拟初始化、刷新、CAS 延迟、
//       突发窗口、`App_*_addr` 必须每拍自增等任何约束 —— 它**永远不会**报协议错
//     · 数据完整性：桩是**理想存储**（写进去立刻就能读出来、位级无损），
//       所以 `BAD=0000` 在这里是**构造保证**的，不是"真芯片上写读对了"
//     · PLL 的真实频率/相位：桩直接给一个 125 MHz 方波（C2 的 180° 不建模）
//     ⇒ **协议与数据完整性仍然只能靠 M-11 / 阶段 10 的上板实测**（`evidence/board/`）。
//
// ★ 2026-10-04 改动：桩从"按地址算图案"改成**真存真取**（2M×32 bit 理想存储器）——
//   因为顶层现在有 6 种图案模式（见 `sdr_pat_gen.v`），桩不可能去猜它当前用哪种。
//   同时加了**故障注入**钩子（`STUB_ERR_ADDR` / `STUB_ERR_XOR`，默认关闭），
//   供 TB 验证顶层的"出错立即停 + BAD0 定位"这条诊断路径。
//
// ★ 模块名刻意就叫 `sdram` / `sv_system_pll`（否则绑定不上）。因此
//    **不要把真正的 `ip/pll/sv_system_pll.v` 加进 `run_sim.ps1`**，否则会重名。
// ============================================================================
`timescale 1ns / 1ps

// ----------------------------------------------------------------------------
// PLL 桩：产生 125 MHz（周期 8 ns）给 SDRAM 侧逻辑；extlock 立刻给 1
//   ★ 真实 PLL 的相位关系（C2 相对 C1 移相 180°）**没有建模**，也不需要 ——
//     这里只为了让 uart_tx 的分频（按 125 MHz 算）和逻辑跑在正确的节拍上。
// ----------------------------------------------------------------------------
module sv_system_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg clkc = 1'b0;
    always #4 clkc = ~clkc;          // 8 ns 周期 = 125 MHz

    assign extlock  = 1'b1;
    assign clk0_out = clkc;          // C0（100 MHz）本顶层不用，给个占位
    assign clk1_out = clkc;          // C1 → SDRAM 侧 Clk
    assign clk2_out = clkc;          // C2 → Clk_sft（真实是 180°，桩不建模）
endmodule

// ----------------------------------------------------------------------------
// SDRAM 控制器桩：理想存储器
//   · `Sdr_init_done` 上电后很快给 1
//   · 写：`App_wr_en` 有效时按 word 地址真实写入 2M×32 bit 仿真数组
//   · 读：`App_rd_en` 延迟 `RD_LAT` 拍后按 **1:1** 回一个 `Sdr_rd_en` + `mem[addr]`
//     （用来验证顶层地址、轮次/图案切换、响应顺序与比较流水）
// ----------------------------------------------------------------------------
module sdram (
    input  wire        Clk,
    input  wire        Clk_sft,
    input  wire        Rst,
    output wire        Sdr_init_done,
    output wire        Sdr_init_ref_vld,
    output wire        Sdr_busy,
    input  wire        App_wr_en,
    input  wire [20:0] App_wr_addr,
    input  wire [3:0]  App_wr_dm,
    input  wire [31:0] App_wr_din,
    input  wire        App_rd_en,
    input  wire [20:0] App_rd_addr,
    output wire        Sdr_rd_en,
    output wire [31:0] Sdr_rd_dout
);
    localparam integer RD_LAT = 4;

    reg [7:0] init_cnt = 8'd0;
    assign Sdr_init_done    = (init_cnt == 8'hFF);
    assign Sdr_init_ref_vld = 1'b0;
    assign Sdr_busy         = 1'b0;

    always @(posedge Clk) if (init_cnt != 8'hFF) init_cnt <= init_cnt + 8'd1;

    // ---- 理想存储器：2M × 32 bit = 8 MB（**真存真取**）----
    //   ★ 2026-10-04 改成真存储器（原来是"按地址算图案"）：顶层现在有 6 种图案模式，
    //     桩不可能去猜它当前用哪种；真存真取对任何图案都成立。
    reg [31:0] mem [0:2_097_151];

    // ---- 故障注入（默认关闭；TB 用层次引用改这两个寄存器）----
    //   命中 ERR_ADDR 的读回值会被异或上 ERR_XOR ⇒ 用来验证"fail fast + BAD0 定位"。
    //   默认值取合法地址里的最大值，正常情况下不会命中。
    reg  [20:0] STUB_ERR_ADDR = 21'h1FFFFF;
    reg  [31:0] STUB_ERR_XOR  = 32'd0;

    // 写：逐拍真写（顶层写突发期间 `App_wr_en` 连发、地址每拍 +1）
    always @(posedge Clk) if (App_wr_en) mem[App_wr_addr] <= App_wr_din;

    // 读命令延迟线（模拟厂商"延迟应答式"：延迟 RD_LAT 拍后按 1:1 回一个 Sdr_rd_en）
    reg [20:0] addr_d [0:RD_LAT-1];
    reg        rd_d   [0:RD_LAT-1];
    integer i;
    always @(posedge Clk) begin
        addr_d[0] <= App_rd_addr;
        rd_d[0]   <= App_rd_en;
        for (i = 1; i < RD_LAT; i = i + 1) begin
            addr_d[i] <= addr_d[i-1];
            rd_d[i]   <= rd_d[i-1];
        end
    end

    assign Sdr_rd_en = rd_d[RD_LAT-1];

    wire [20:0] rd_a = addr_d[RD_LAT-1];
    assign Sdr_rd_dout = mem[rd_a] ^ ((rd_a == STUB_ERR_ADDR) ? STUB_ERR_XOR : 32'd0);

    // Clk_sft / Rst / App_wr_dm 不参与行为建模
    wire unused = |{ App_wr_dm, Clk_sft, Rst };

endmodule

module sv_board_memory_pll(input wire refclk,reset,output wire extlock,
 output wire clk0_out,clk1_out,clk2_out);
 reg sys=0;always #5 sys=~sys;
 reg mem=0;always #12.5 mem=~mem;
 assign clk0_out=sys;assign clk1_out=mem;assign #10 clk2_out=mem;assign extlock=1;
endmodule
