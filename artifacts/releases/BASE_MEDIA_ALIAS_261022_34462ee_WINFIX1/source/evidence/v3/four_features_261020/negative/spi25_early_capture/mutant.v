// ============================================================================
// spi_master.v — SPI 主机（SafeVision B 链 · 学习阶段 2）
// ----------------------------------------------------------------------------
// 依据：手册 7.2「SPI 主机」「FSM + bit 计数器最稳」
//
// 定位：本项目 FPGA 永远是 Master、SD 卡永远是 Slave，SCLK 由 FPGA 分频产生。
//       本模块只做「字节级全双工收发」，不含任何 SD 协议语义。
//       SD 命令序列由 sd_initializer / sd_sector_reader 负责，本模块被它们复用。
//
// 参数约定：
//   SCLK 半周期 = (clk_div + 1) 个 clk
//   SCLK 频率   = clk / (2 * (clk_div + 1))
//   初始化段 400kHz  -> clk_div = 124 （@100MHz）
//   数据段    25MHz  -> clk_div = 1
//
// 时序：SPI mode0（CPOL=0 / CPHA=0）
//   - SCLK 空闲为低
//   - MOSI 在 SCLK 下降沿更新（本模块移位实现）
//   - MISO 在 SCLK 上升沿采样（本模块采样实现）
//
// ★ cs_n 是【输入】，由上层控制器在全事务期间拉低。
//   SD 要求 CS 变化时 SCLK 必须为低，本模块在 IDLE/DONE 恒把 SCLK 拉低。
// ============================================================================
`include "safevision_defs.vh"

module spi_master #(
    parameter integer CLK_FREQ = 100_000_000,
    // Opt-in board profile: allow divider zero; sample MISO on falling REF
    // 10ns after forwarded SCLK rises, 30ns after its previous falling edge.
    // Default keeps the historical clamped divider and rising-REF sampling.
    parameter integer MID_REF_SAMPLE = 0
)(
    input  wire        clk,
    input  wire        rst_n,           // 同步复位，低有效

    // ---- 配置 ----
    input  wire [15:0] clk_div,         // SCLK 半周期分频，见上方公式

    // ---- 片选（由上层控制）----
    input  wire        cs_n,            // 低有效；上层在全事务期间保持

    // ---- 字节级收发 ----
    input  wire        tx_valid,        // 请求发送一个字节
    input  wire [7:0]  tx_data,         // 待发送字节（全双工：发送同时收 1 字节）
    output wire        tx_ready,        // 可接受新字节
    output reg  [7:0]  rx_data,         // 收到的字节
    output reg         rx_valid,        // 单拍脉冲，与 rx_data 同拍
    output wire        busy,            // 传输中

    // ---- 板级三线 ----
    output wire        sclk,
    output wire        mosi,
    input  wire        miso
);

    // ------------------------------------------------------------------------
    // 状态定义
    // ------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,     // 等 start
                     S_XFER = 2'd1,     // 移位 8 位
                     S_DONE = 2'd2;     // 给 done 与 rx_data

    reg  [1:0]  state;
    reg  [7:0]  div_r;      // 本次传输锁存的分频值（传输中改 clk_div 不影响本字节）
    reg  [7:0]  div_cnt;
    reg  [3:0]  half_cnt;   // 0..15，共 16 个半周期 = 8 位
    reg  [7:0]  tx_sr;      // 发送移位寄存器
    reg  [7:0]  rx_sr;      // 接收移位寄存器
    reg         sclk_r;

    // ------------------------------------------------------------------------
    // 输出
    // ------------------------------------------------------------------------
    assign sclk     = sclk_r;
    assign mosi     = tx_sr[7];           // MSB first：最高位先出
    assign busy     = (state == S_XFER);
    assign tx_ready = (state == S_IDLE);

    wire sample_now = (state == S_XFER) && (div_cnt == div_r) && !sclk_r;
    reg sample_pending;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) sample_pending <= 1'b0;
        else sample_pending <= sample_now;
    generate if (MID_REF_SAMPLE) begin: delayed_miso
        always @(posedge clk or negedge rst_n)
            if (!rst_n) rx_sr <= 8'h00;
            else if (sample_now) rx_sr <= {rx_sr[6:0], miso};
    end else begin: legacy_miso
        always @(posedge clk or negedge rst_n)
            if (!rst_n) rx_sr <= 8'h00;
            else if (sample_now) rx_sr <= {rx_sr[6:0], miso};
    end endgenerate

    // ------------------------------------------------------------------------
    // 主状态机
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            sclk_r   <= 1'b0;
            div_r    <= 8'd1;
            div_cnt  <= 8'd0;
            half_cnt <= 4'd0;
            tx_sr    <= 8'hFF;            // 空闲时 MOSI 保持高（SD 要求空闲为 1）

            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            // rx_valid 只在进入 S_DONE 的下一拍拉高 1 拍
            rx_valid <= (state == S_DONE);

            case (state)
                // ------------------------------------------------------------
                S_IDLE: begin
                    sclk_r   <= 1'b0;
                    div_cnt  <= 8'd0;
                    half_cnt <= 4'd0;
                    if (tx_valid) begin
                        tx_sr <= tx_data;         // LOAD
                        div_r <= (!MID_REF_SAMPLE && clk_div[7:0] == 8'd0) ? 8'd1 : clk_div[7:0];
                        state <= S_XFER;
                    end
                end
                // ------------------------------------------------------------
                S_XFER: begin
                    if (div_cnt == div_r) begin
                        div_cnt <= 8'd0;
                        if (!sclk_r) begin
                            // ---- SCLK 上升沿：采样 MISO ----
                            sclk_r <= 1'b1;

                        end else begin
                            // ---- SCLK 下降沿：移出下一位 ----
                            sclk_r <= 1'b0;
                            tx_sr  <= {tx_sr[6:0], 1'b1};   // 补 1：空闲电平保持高
                            // half_cnt 只在下降沿递增 => 一个完整 SCLK 周期 +1，
                            // 8 位需要 8 个周期（8 个上升沿采样 + 8 个下降沿移出）
                            if (half_cnt == 4'd7) begin
                                state <= S_DONE;
                            end else begin
                                half_cnt <= half_cnt + 4'd1;
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 8'd1;
                    end
                end
                // ------------------------------------------------------------
                S_DONE: begin
                    sclk_r  <= 1'b0;
                    rx_data <= rx_sr;      // 与 rx_valid 同拍输出
                    state   <= S_IDLE;
                end
                // ------------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule