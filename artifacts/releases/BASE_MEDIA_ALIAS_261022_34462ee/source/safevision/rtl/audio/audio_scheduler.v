// ============================================================================
// audio_scheduler.v — 48 kHz 样本调度（手册 8.6 / interface_spec §3.6）
// ----------------------------------------------------------------------------
// 依据：手册 8.6「C 的 audio_scheduler 以 48 kHz 节拍取左右样本、符号扩展到
//       24 bit 并产生 audio_valid」；interface_spec §3.6「C 的 audio_scheduler
//       按 48 kHz 节拍拉 pcm_rd；pcm_empty 为 1 时 C 必须输出零样本并计入
//       audio_underflow，★ 绝不输出随机数据」。
//
// 时钟域 : audio_clk（= audio_mclk 12.288 MHz = 256 x Fs，由 A 平台 PLL 提供）
// 节拍   : TICK_N 分频。12.288 MHz / 256 = 48 kHz，故 TICK_N = 255
//          （计到 255 归零 -> 周期 256 拍，恰好 48 kHz）。
//
// 职责边界（手册 8.6）：C 负责「按 48 kHz 节拍稳定产出样本与 audio_valid，
//   并维护欠载计数」；不做 PHY，也不解析 WAV 容器（容器解析属 B）。
//
// ★ 欠载语义：pcm_empty=1 -> audio_l/r 输出 24'sd0 且 audio_underflow+1，
//   绝不输出旧样本或随机数据（手册 8.6 易错点：「欠载时输出旧样本」）。
// ★ 位宽：B 侧为 16 bit 有符号 PCM；C 符号扩展为 24 bit
//   （{{8{pcm_l[15]}}, pcm_l}），交 C->A 的 Audio Sample Interface。
// ★ 音画同步：track_id 在 B->C 边界已随 generation 生效（interface_spec
//   §一：sys_clk -> audio_clk 走 toggle+mailbox），C 在本域按样本节拍透传。
//
// 端口与 §3.6 的 PCM Sample Interface（B->C）一致；C->A 侧登记在
// §3.6「Audio Sample Interface」。
// ============================================================================

module audio_scheduler #(
    parameter integer TICK_N = 255          // 48 kHz：12.288 MHz/256 - 1
)(
    input  wire        audio_clk,
    input  wire        rst_n,

    // ---- B->C：PCM Sample Interface（audio_clk 域）----
    input  wire [15:0] pcm_l,              // 左声道，有符号
    input  wire [15:0] pcm_r,              // 右声道，有符号
    input  wire        pcm_valid,          // FWFT：等效 !pcm_empty
    input  wire        pcm_empty,          // 空标志（权威欠载判据）
    output reg         pcm_rd,             // 取走一对样本，推进指针（单拍）
    input  wire        audio_fallback,     // 1 = 当前为提示音回退（透传观测）
    input  wire [7:0]  track_id_in,        // 当前音轨编号，随 generation 生效
    input  wire        track_change,       // 音轨切换事件（toggle，观测）

    // ---- C->A：Audio Sample Interface ----
    output reg  [23:0] audio_l,            // 24 bit 有符号（16->24 符号扩展）
    output reg  [23:0] audio_r,
    output reg         audio_valid,        // 与 audio_l / audio_r 同拍
    output reg  [7:0]  track_id,           // 透传，供 Audio InfoFrame / 日志
    output reg  [31:0] audio_underflow,    // 欠载计数器（手册 8.6：C 侧维护）

    // ---- 观测 ----
    output reg         sample_tick         // 48 kHz 节拍（调试 / 波形用）
);

    reg [15:0] tcnt;

    // ---- 48 kHz 节拍：TICK_N 分频得到 sample_tick（手册 8.6 原话）----
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            tcnt        <= 16'd0;
            sample_tick <= 1'b0;
        end else if (tcnt == TICK_N[15:0]) begin
            tcnt        <= 16'd0;
            sample_tick <= 1'b1;
        end else begin
            tcnt        <= tcnt + 16'd1;
            sample_tick <= 1'b0;
        end
    end

    // ---- 样本调度：空则输出零样本并计数，否则取样本并符号扩展 ----
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            audio_l         <= 24'sd0;
            audio_r         <= 24'sd0;
            audio_valid     <= 1'b0;
            pcm_rd          <= 1'b0;
            track_id        <= 8'h00;
            audio_underflow <= 32'd0;
        end else begin
            pcm_rd      <= 1'b0;      // 单拍脉冲：仅在取样本那拍拉高
            audio_valid <= 1'b0;
            if (sample_tick) begin
                track_id <= track_id_in;
                if (pcm_empty) begin
                    // ★ 绝不输出随机 / 旧样本：明确输出零并计欠载
                    audio_l         <= 24'sd0;
                    audio_r         <= 24'sd0;
                    audio_underflow <= audio_underflow + 32'd1;
                end else begin
                    // 16 bit 有符号 -> 24 bit 符号扩展
                    audio_l <= {{8{pcm_l[15]}}, pcm_l};
                    audio_r <= {{8{pcm_r[15]}}, pcm_r};
                    pcm_rd  <= 1'b1;    // B 侧 FIFO 推进指针
                end
                audio_valid <= 1'b1;
            end
        end
    end

    // synthesis translate_off
    initial if (TICK_N < 1) $fatal(1, "audio_scheduler invalid TICK_N (must be >= 1)");
    // synthesis translate_on

endmodule
