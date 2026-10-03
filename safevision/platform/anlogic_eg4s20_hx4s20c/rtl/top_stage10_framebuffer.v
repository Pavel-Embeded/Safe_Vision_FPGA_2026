// ============================================================================
// top_stage10_framebuffer.v — 阶段 10 帧缓存回环【板级 bring-up 顶层】
// ----------------------------------------------------------------------------
// 依据：手册 7.10「Frame Buffer 帧缓存」、7.9「SDRAM 先跑官方 Demo」（前置）
//       落点依据：docs/PROJECT_STRUCTURE.md（板级相关一切归 platform/…/）
//
// 定位：**接引脚、不属产品链**的 bring-up 顶层，不是 A 的产品顶层 safevision_top.v。
//       它把一个 640x480 RGB565 帧写进 SDRAM 的 0 号槽，再整帧读回逐像素比对，
//       经 UART 发纯 ASCII 报告。逻辑全在 mem 域（125 MHz），核心逻辑是
//       `framebuffer_loopback_core`（可仿真的那块），本文件只加"板级要素"：
//         · sv_system_pll：50 MHz -> 125M（mem）+ 125M@180（SDRAM Clk_sft）
//         · reset_sync：两级复位（50M 域 + 125M 域）
//         · sdram_app_adapter + 厂商 `sdram`：通用事务口 <-> 安路应用口
//         · uart_tx：把报告发出去
//
// ★★ 为什么这个顶层【进不了 ModelSim 回归】：它例化厂商 `sdram`（安路 RSA 加密
//   IP，只能 TD 解密）。**核心逻辑另有一份可仿真验证**：verification/unit/
//   tb_framebuffer_loopback_core.sv 用 frame_memory_model 顶替后端。所以本顶层
//   上板前，核心部分已经在仿真里绿过。
//
// ★ SDRAM 是封装内硬核（EG_PHY_SDRAM_2M_32），信号不出引脚 ⇒ 本顶层**没有 sd_*
//   端口**，`constraints/pin.adc` 的 [SD-ONLY] 四条必须保持注释（与 stage9 顶层同）。
//
// ★ 时钟：板载 50 MHz（R7）→ sv_system_pll：C1=125M 给 SDRAM/逻辑、C2=125M@180
//   给 SDRAM 采样相位（同源 PLL 相移，不能用反相器）。C0 留空。
// ============================================================================

module top_stage10_framebuffer #(
    parameter integer CLK_FREQ     = 50_000_000,
    parameter integer MEM_CLK_FREQ = 125_000_000,   // sv_system_pll C1
    parameter integer BAUD         = 115200
)(
    // ---- 板级引脚（引脚号见同目录 ../constraints/pin.adc）----
    input  wire        clk,        // R7   FPGA_GCLK  50 MHz
    input  wire        rst_n,      // A2   KEY_1       低有效按键
    output wire        uart_txd,   // D12  USB-UART 发送（板载 CH340G，115200 8N1）
    output wire [3:0]  led         // A4/A3/C10/B12 = LED0..LED3，高电平点亮
);

    // ---- 复位链：参考域 -> PLL 锁定 -> mem 域 ----
    wire rst_ref_n;
    wire pll_locked;
    wire ext_mem_clk;         // 125 MHz
    wire ext_mem_clk_sft;     // 125 MHz @180°
    wire rst_mem_n;
    wire rst_mem;             // SDRAM IP 要【高有效】Rst

    reset_sync u_rst_ref (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_ref_n)
    );

    sv_system_pll u_sys_pll (
        .refclk   (clk),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (),
        .clk1_out (ext_mem_clk),
        .clk2_out (ext_mem_clk_sft)
    );

    reset_sync u_rst_mem (
        .clk        (ext_mem_clk),
        .async_rst_n(rst_ref_n & pll_locked),
        .rst_n      (rst_mem_n)
    );

    assign rst_mem = ~rst_mem_n;

    // ---- 核心 <-> 适配器的通用事务口 ----
    wire        c_req, c_wr;
    wire [31:0] c_addr, c_wdata;
    wire [3:0]  c_wstrb;
    wire [31:0] c_rdata;
    wire        c_rvalid, c_ready, c_initdone;

    // ---- 核心 <-> 适配器的厂商应用口 ----
    wire        sdr_init_done;
    wire        sdr_init_ref_vld;
    wire        sdr_busy;
    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    wire        sdr_rd_en;
    wire [31:0] sdr_rd_dout;

    // ---- 报告 / 状态 ----
    wire        rep_valid;
    wire        rep_ready;
    wire [7:0]  rep_data;
    wire        fb_ok;
    wire [7:0]  err_code;
    wire [18:0] wr_px, rd_px, bad_px;
    wire        crc_ok, slot_valid;

    framebuffer_loopback_core u_core (
        .clk               (ext_mem_clk),
        .rst_n             (rst_mem_n),
        .sdram_req         (c_req),
        .sdram_wr          (c_wr),
        .sdram_addr        (c_addr),
        .sdram_wdata       (c_wdata),
        .sdram_wstrb       (c_wstrb),
        .sdram_rdata       (c_rdata),
        .sdram_rdata_valid (c_rvalid),
        .sdram_ready       (c_ready),
        .sdram_init_done   (c_initdone),
        .rep_valid         (rep_valid),
        .rep_data          (rep_data),
        .rep_ready         (rep_ready),
        .ok                (fb_ok),
        .err_code          (err_code),
        .wr_px             (wr_px),
        .rd_px             (rd_px),
        .bad_px            (bad_px),
        .crc_ok            (crc_ok),
        .slot_valid        (slot_valid)
    );

    sdram_app_adapter u_adapter (
        .clk               (ext_mem_clk),
        .rst_n             (rst_mem_n),
        .req               (c_req),
        .wr                (c_wr),
        .addr              (c_addr),
        .wdata             (c_wdata),
        .wstrb             (c_wstrb),
        .rdata             (c_rdata),
        .rdata_valid       (c_rvalid),
        .ready             (c_ready),
        .init_done         (c_initdone),
        .Sdr_init_done     (sdr_init_done),
        .Sdr_init_ref_vld  (sdr_init_ref_vld),
        .Sdr_busy          (sdr_busy),
        .App_wr_en         (app_wr_en),
        .App_wr_addr       (app_wr_addr),
        .App_wr_dm         (app_wr_dm),
        .App_wr_din        (app_wr_din),
        .App_rd_en         (app_rd_en),
        .App_rd_addr       (app_rd_addr),
        .Sdr_rd_en         (sdr_rd_en),
        .Sdr_rd_dout       (sdr_rd_dout)
    );

    // ---- 厂商 SDRAM 控制器（RSA 加密，见 ../ip/sdram/）----
    sdram u_sdram (
        .Clk               (ext_mem_clk),
        .Clk_sft           (ext_mem_clk_sft),
        .Rst               (rst_mem),
        .Sdr_init_done     (sdr_init_done),
        .Sdr_init_ref_vld  (sdr_init_ref_vld),
        .Sdr_busy          (sdr_busy),
        .App_wr_en         (app_wr_en),
        .App_wr_addr       (app_wr_addr),
        .App_wr_dm         (app_wr_dm),
        .App_wr_din        (app_wr_din),
        .App_rd_en         (app_rd_en),
        .App_rd_addr       (app_rd_addr),
        .Sdr_rd_en         (sdr_rd_en),
        .Sdr_rd_dout       (sdr_rd_dout)
    );

    // ---- UART（125 MHz 域，115200 8N1）----
    uart_tx #(
        .CLK_FREQ (MEM_CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (ext_mem_clk),
        .rst_n     (rst_mem_n),
        .tx_valid  (rep_valid),
        .tx_data   (rep_data),
        .tx_ready  (rep_ready),
        .txd       (uart_txd)
    );

    // ---- LED：成功 = 8；否则 1（运行中）或错误主码低 4 位 ----
    wire [3:0] led_code = fb_ok ? 4'h8 : ((err_code != 8'h00) ? err_code[3:0] : 4'h1);
    assign led = led_code;

endmodule
