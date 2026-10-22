// ============================================================================
// audio_priority_arbiter.v — 报警音优先 + 5 ms 音量斜坡（手册 8.6）
// ----------------------------------------------------------------------------
// 依据：手册 8.6「应急告警音存放在片上 ROM，优先级高于普通 WAV，抢占时做
//       5 ms 音量斜坡以降低爆音」；表 8-2「报警音可抢占并按策略恢复」。
//
// 职责：在 WAV 样本与片上 ROM 报警音之间做**交叉淡入淡出**。
//   gain = 0   -> 全 WAV（正常播放）
//   gain = 256 -> 全报警音（抢占完成）
//   alarm_req 拉高：每个样本节拍 gain 上台阶 -> 平滑抬起报警音；
//   alarm_req 撤除：每个样本节拍 gain 下台阶 -> 平滑恢复 WAV。
//   分数余数累加每拍分配 1 或 2 级，RAMP_N=240 时恰好 240 样本到端点。
//   48 kHz 下斜坡为 5 ms。
//
// 定点混合（避免削顶与截断误差）：
//   out = (wav x (256-gain) + tone x gain) >> 8
//   用 signed [33:0] 累加：|wav|<=2^23，系数<=256 -> 乘积 <= 2^31；
//   两项之和的幅度仍 <= max(|wav|,|tone|) x 256 <= 2^31，故 sum[31] 即符号位，
//   取 sum[31:8] 就是正确的 24 bit 有符号结果（等价 >>8）。
//
// 时钟域 : audio_clk（与 audio_scheduler / alarm_tone_gen 同域、同 48 kHz 节拍）
// 节拍   : sample_valid 每个样本节拍一拍（接 audio_scheduler.audio_valid），
//          斜坡只在真实样本节拍推进，与样本严格对齐。
// ============================================================================

module audio_priority_arbiter_reference #(
    parameter integer RAMP_N     = 240,     // 5 ms @48 kHz
    parameter integer FULL_SCALE = 256      // gain 满量程（2^8）
)(
    input  wire        audio_clk,
    input  wire        rst_n,
    input  wire        sample_valid,        // 样本节拍有效（audio_scheduler.audio_valid）
    input  wire        alarm_req,           // 报警音请求（emergency_fsm.alarm_enable）
    input  wire [23:0] wav_l,               // 普通 WAV 左声道（24 bit 有符号）
    input  wire [23:0] wav_r,
    input  wire [23:0] tone_l,              // 报警音左声道（24 bit 有符号）
    input  wire [23:0] tone_r,
    output reg  [23:0] audio_l,             // 交 C->A Audio Sample Interface
    output reg  [23:0] audio_r,
    output reg         audio_valid,
    output reg  [8:0]  gain                 // 观测：0=全 WAV，256=全报警音
);

    // 下一个 gain（按节拍台阶）
    reg [31:0] ramp_error;
    wire [32:0] ramp_sum={1'b0,ramp_error}+FULL_SCALE;
    wire [8:0] ramp_step=ramp_sum/RAMP_N;
    wire [8:0] gain_up = (gain + ramp_step > 9'd256) ? 9'd256 : (gain + ramp_step);
    wire [8:0] gain_dn = (gain > ramp_step) ? (gain - ramp_step) : 9'd0;
    wire [8:0] n_gain  = alarm_req ? gain_up : gain_dn;
    wire [8:0] w_coef  = 9'd256 - n_gain;       // WAV 权重

    wire signed [23:0] wl_s = wav_l;
    wire signed [23:0] wr_s = wav_r;
    wire signed [23:0] tl_s = tone_l;
    wire signed [23:0] tr_s = tone_r;

    wire signed [33:0] mix_l = wl_s * $signed({1'b0, w_coef}) + tl_s * $signed({1'b0, n_gain});
    wire signed [33:0] mix_r = wr_s * $signed({1'b0, w_coef}) + tr_s * $signed({1'b0, n_gain});

    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            gain        <= 9'd0; ramp_error<=0;
            audio_l     <= 24'sd0;
            audio_r     <= 24'sd0;
            audio_valid <= 1'b0;
        end else if (sample_valid) begin
            gain        <= n_gain; ramp_error<=ramp_sum%RAMP_N;
            audio_l     <= mix_l[31:8];     // 算术意义上等价 >>8
            audio_r     <= mix_r[31:8];
            audio_valid <= 1'b1;
        end else begin
            audio_valid <= 1'b0;
        end
    end

    // synthesis translate_off
    initial if (FULL_SCALE != 256 || RAMP_N<1)
        $fatal(1, "audio_priority_arbiter invalid FULL_SCALE (must be 256, RAMP_N >= 1)");
    // synthesis translate_on

endmodule
