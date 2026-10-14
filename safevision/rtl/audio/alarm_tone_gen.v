// ============================================================================
// alarm_tone_gen.v — 应急告警音发生器（片上 ROM，手册 8.6）
// ----------------------------------------------------------------------------
// 依据：手册 8.6「应急告警音存放在片上 ROM，优先级高于普通 WAV，抢占时做
//       5 ms 音量斜坡以降低爆音」；表 8-2「1 kHz 测试音频率误差不超过 1%」。
//
// 方案：相位累加器 + 32 项四分之一正弦 ROM（用 function + case 描述，综合为
//       片上分布式 ROM）+ 象限对称。
//   相位 16 bit；每样本 phase += PHASE_INC。
//   quad = phase[15:14]（4 个象限）；qidx = phase[13:9]（象限内 32 点）。
//   频率 = PHASE_INC x Fs / 2^16。取 PHASE_INC = 1365：
//         f = 1365 x 48000 / 65536 = 999.76 Hz，误差 0.024% << 1%（表 8-2）。
//   幅度 AMP = 2000000（满量程 2^23），峰值约 24% FS，留足余量不削顶。
//
// 象限对称（qidx 从象限起点递增）：
//   quad0(0..90)   : +sin[qidx]
//   quad1(90..180) : +sin[31-qidx]   （sin(90+θ)=sin(90-θ)）
//   quad2(180..270): -sin[qidx]
//   quad3(270..360): -sin[31-qidx]
//   统一写法：base = quad[0] ? sin[31-qidx] : sin[qidx];
//             val  = quad[1] ? -base : base;
//
// 时钟域 : audio_clk（与 audio_scheduler 同一 48 kHz 节拍）
// 节拍   : 复用外部 tick（audio_scheduler.sample_tick），保证报警音与 WAV
//          样本严格同相，避免两套分频器漂移。
//   enable=0 时相位归零，使下次使能从零相位起振（配合仲裁器 5 ms 斜坡进一步
//   降低爆音）。tone 为对已寄存 phase 的组合译码，与 audio_scheduler 的
//   寄存输出在相同样本节拍对齐。
//
// ROM 表值：sin_q[i] = round(AMP x sin(i x pi / 64))，i = 0..31（精确浮点生成
//   后钉死；TB 反查已知值，防止公式被误改）。
// ============================================================================

module alarm_tone_gen #(
    parameter integer PHASE_INC = 1365,     // f = PHASE_INC x Fs / 2^16 ~ 1 kHz
    parameter integer AMP       = 2000000   // 峰值（满量程 2^23）
)(
    input  wire        audio_clk,
    input  wire        rst_n,
    input  wire        tick,               // 48 kHz 样本节拍（与 audio_scheduler 同源）
    input  wire        enable,             // 报警音使能
    output wire [23:0] tone_l,             // 24 bit 有符号
    output wire [23:0] tone_r
);

    reg [15:0] phase;
    wire [1:0] quad = phase[15:14];
    wire [4:0] qidx = phase[13:9];

    // 四分之一正弦 ROM（32 项，有符号 24 bit）
    function signed [23:0] sin_q;
        input [4:0] i;
        begin
            case (i)
                5'd0:  sin_q = 24'sd0;
                5'd1:  sin_q = 24'sd98135;
                5'd2:  sin_q = 24'sd196034;
                5'd3:  sin_q = 24'sd293461;
                5'd4:  sin_q = 24'sd390181;
                5'd5:  sin_q = 24'sd485960;
                5'd6:  sin_q = 24'sd580569;
                5'd7:  sin_q = 24'sd673780;
                5'd8:  sin_q = 24'sd765367;
                5'd9:  sin_q = 24'sd855110;
                5'd10: sin_q = 24'sd942793;
                5'd11: sin_q = 24'sd1028205;
                5'd12: sin_q = 24'sd1111140;
                5'd13: sin_q = 24'sd1191399;
                5'd14: sin_q = 24'sd1268787;
                5'd15: sin_q = 24'sd1343118;
                5'd16: sin_q = 24'sd1414214;
                5'd17: sin_q = 24'sd1481902;
                5'd18: sin_q = 24'sd1546021;
                5'd19: sin_q = 24'sd1606415;
                5'd20: sin_q = 24'sd1662939;
                5'd21: sin_q = 24'sd1715457;
                5'd22: sin_q = 24'sd1763843;
                5'd23: sin_q = 24'sd1807979;
                5'd24: sin_q = 24'sd1847759;
                5'd25: sin_q = 24'sd1883088;
                5'd26: sin_q = 24'sd1913881;
                5'd27: sin_q = 24'sd1940063;
                5'd28: sin_q = 24'sd1961571;
                5'd29: sin_q = 24'sd1978353;
                5'd30: sin_q = 24'sd1990369;
                default: sin_q = 24'sd1997591;
            endcase
        end
    endfunction

    wire signed [23:0] idx_fwd = sin_q(qidx);
    wire signed [23:0] idx_rev = sin_q(5'd31 - qidx);
    wire signed [23:0] base = quad[0] ? idx_rev : idx_fwd;
    wire signed [23:0] val  = quad[1] ? -base : base;

    assign tone_l = val;
    assign tone_r = val;

    // ---- 相位累加：仅在前沿样本节拍推进；enable=0 时归零起振 ----
    always @(posedge audio_clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= 16'd0;
        end else if (!enable) begin
            phase <= 16'd0;                    // 归零，下次从零相位起振
        end else if (tick) begin
            phase <= phase + PHASE_INC[15:0];
        end
    end

    // synthesis translate_off
    initial if (PHASE_INC < 1) $fatal(1, "alarm_tone_gen invalid PHASE_INC (must be >= 1)");
    // synthesis translate_on

endmodule
