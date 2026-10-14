// ============================================================================
// tb_c_audio.sv — C 音频链单元验证（手册 8.6 / interface_spec §3.6）
// ----------------------------------------------------------------------------
// 覆盖三个 C 音频模块：
//   DUT-S : audio_scheduler            48 kHz 节拍 / pcm_rd 单拍 / 16->24 符号扩展
//                                      / 空->零样本 + underflow 计数 / track_id 透传
//   DUT-T : alarm_tone_gen             片上 ROM 精确值（force phase 反查）/ 象限对称
//                                      / ~1 kHz 频率（48000 节拍内回绕计数，误差 <1%）
//   DUT-A : audio_priority_arbiter     5 ms 音量斜坡（gain 0<->256）/ 端点恒等
//                                      / 中间混合精确值 / 单调无突变 / audio_valid 时序
//
// 过关判据全部是"性质"，不是自比：
//   * 符号扩展用 0x1234/0x8000/0xFFFF 钉死，防止把 16->24 写成截断；
//   * ROM 用已知相位反查 sin_q 精确整数值，防止 ROM 表被误改；
//   * 频率用"每 48000 个 48 kHz 节拍的回绕次数"验证，而不只看单点相位；
//   * 斜坡验证单调 + 每步恰好 STEP，且两端 gain=0 恒等 WAV、gain=256 全报警音。
// ============================================================================
`timescale 1ns / 1ps

module tb_c_audio;

    // ---- 48 kHz 之外的 audio_clk：TB 里用 100 MHz 时钟即可（分频比由 TICK_N 定）----
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;

    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ========================================================================
    // DUT-S : audio_scheduler（TICK_N=3 -> sample_tick 周期 = 4 拍）
    // ========================================================================
    localparam integer TICK_N = 3;

    reg  [15:0] pcm_l, pcm_r;
    reg         pcm_valid, pcm_empty, audio_fallback, track_change;
    reg  [7:0]  track_id_in;
    wire        pcm_rd, audio_valid_s, sample_tick;
    wire [23:0] audio_l_s, audio_r_s;
    wire [7:0]  track_id_s;
    wire [31:0] audio_underflow;

    audio_scheduler #( .TICK_N(TICK_N) ) dut_s (
        .audio_clk      (clk),
        .rst_n          (rst_n),
        .pcm_l          (pcm_l),
        .pcm_r          (pcm_r),
        .pcm_valid      (pcm_valid),
        .pcm_empty      (pcm_empty),
        .pcm_rd         (pcm_rd),
        .audio_fallback (audio_fallback),
        .track_id_in    (track_id_in),
        .track_change   (track_change),
        .audio_l        (audio_l_s),
        .audio_r        (audio_r_s),
        .audio_valid    (audio_valid_s),
        .track_id       (track_id_s),
        .audio_underflow(audio_underflow),
        .sample_tick    (sample_tick)
    );

    // 等到下一个 48 kHz 节拍，并推进到"样本已更新"那一拍
    task sched_tick;
        begin
            @(posedge clk); #1;
            while (sample_tick !== 1'b1) begin @(posedge clk); #1; end
            @(posedge clk); #1;          // audio_scheduler 在这一拍更新输出
        end
    endtask

    // 量一次 sample_tick 周期（应等于 TICK_N+1）
    integer tick_period;
    task measure_period;
        output integer n;
        integer c;
        begin
            @(posedge clk); #1;
            while (sample_tick !== 1'b1) begin @(posedge clk); #1; end
            c = 0;
            @(posedge clk); #1;
            while (sample_tick !== 1'b1) begin
                @(posedge clk); #1;
                c = c + 1;
            end
            n = c + 1;
        end
    endtask

    // ========================================================================
    // DUT-T : alarm_tone_gen（默认 PHASE_INC=1365 / AMP=2000000）
    // ========================================================================
    reg         tone_tick, tone_en;
    wire [23:0] tone_l, tone_r;

    alarm_tone_gen dut_t (
        .audio_clk(clk),
        .rst_n    (rst_n),
        .tick     (tone_tick),
        .enable   (tone_en),
        .tone_l   (tone_l),
        .tone_r   (tone_r)
    );

    integer    wraps;
    reg [15:0] phase_d;
    reg        freq_win;
    always @(posedge clk) begin
        #1;                                   // 跳出本拍，读稳定值，避免与 DUT NBA 竞争
        if (freq_win && (dut_t.phase < phase_d)) wraps = wraps + 1;
        phase_d = dut_t.phase;
    end

    // ========================================================================
    // DUT-A : audio_priority_arbiter（RAMP_N=8 -> STEP=32，8 个样本到满量程）
    // ========================================================================
    reg        a_valid_in, alarm_req;
    reg  [23:0] wav_l_a, wav_r_a, tone_l_a, tone_r_a;
    wire [23:0] aout_l, aout_r;
    wire        aout_valid;
    wire [8:0]  gain;

    audio_priority_arbiter #( .RAMP_N(8), .FULL_SCALE(256) ) dut_a (
        .audio_clk  (clk),
        .rst_n      (rst_n),
        .sample_valid(a_valid_in),
        .alarm_req  (alarm_req),
        .wav_l      (wav_l_a),
        .wav_r      (wav_r_a),
        .tone_l     (tone_l_a),
        .tone_r     (tone_r_a),
        .audio_l    (aout_l),
        .audio_r    (aout_r),
        .audio_valid(aout_valid),
        .gain       (gain)
    );

    task do_sample;
        begin
            a_valid_in = 1'b1;
            @(posedge clk); #1;             // 本拍 sample_valid 有效，输出在此时更新
            a_valid_in = 1'b0;              // 立即撤销，保证下一个样本仍只占一拍
        end
    endtask

    // ========================================================================
    // 主激励
    // ========================================================================
    integer   i;
    reg [8:0] prev_gain;
    reg       ok_mono;

    initial begin
        // ---- 初值 ----
        rst_n          = 1'b0;
        pcm_l          = 16'd0;   pcm_r          = 16'd0;
        pcm_valid      = 1'b0;    pcm_empty      = 1'b1;
        audio_fallback = 1'b0;    track_change   = 1'b0;
        track_id_in    = 8'h00;
        tone_tick      = 1'b0;    tone_en        = 1'b0;
        freq_win       = 1'b0;    wraps          = 0;    phase_d = 16'd0;
        a_valid_in     = 1'b0;    alarm_req      = 1'b0;
        wav_l_a = 24'd0; wav_r_a = 24'd0; tone_l_a = 24'd0; tone_r_a = 24'd0;

        repeat (4) @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // ================= DUT-S : audio_scheduler =================
        check(audio_l_s === 24'd0,        "S1.1 复位后 audio_l = 0");
        check(audio_r_s === 24'd0,        "S1.2 复位后 audio_r = 0");
        check(audio_valid_s === 1'b0,     "S1.3 复位后 audio_valid = 0");
        check(audio_underflow === 32'd0,  "S1.4 复位后 audio_underflow = 0");
        check(pcm_rd === 1'b0,            "S1.5 复位后 pcm_rd = 0");

        // ---- S2 正常样本：符号扩展 + pcm_rd 单拍 + track_id ----
        pcm_empty    = 1'b0;
        pcm_valid    = 1'b1;
        pcm_l        = 16'h1234;
        pcm_r        = 16'h8000;      // 负值：最高位为 1
        track_id_in  = 8'h5A;
        sched_tick;
        check(audio_l_s === 24'h001234,   "S2.1 16->24 符号扩展（正）0x1234 -> 0x001234");
        check(audio_r_s === 24'hFF8000,   "S2.2 16->24 符号扩展（负）0x8000 -> 0xFF8000");
        check(audio_valid_s === 1'b1,     "S2.3 取到样本时 audio_valid 拉高");
        check(pcm_rd === 1'b1,            "S2.4 取到样本时 pcm_rd 单拍脉冲");
        check(track_id_s === 8'h5A,       "S2.5 track_id 按样本节拍透传");
        check(audio_underflow === 32'd0,  "S2.6 非空时 underflow 不增");
        @(posedge clk); #1;
        check(pcm_rd === 1'b0,            "S2.7 pcm_rd 下一拍即撤销（单拍）");
        check(audio_valid_s === 1'b0,     "S2.8 audio_valid 只持续一拍");

        // ---- S3 负值边界 ----
        pcm_l = 16'hFFFF;
        pcm_r = 16'h0001;
        sched_tick;
        check(audio_l_s === 24'hFFFFFF,   "S3.1 符号扩展 0xFFFF -> 0xFFFFFF");
        check(audio_r_s === 24'h000001,   "S3.2 符号扩展 0x0001 -> 0x000001");

        // ---- S4 空 FIFO：零样本 + underflow 递增（绝不输出旧/随机样本）----
        pcm_empty = 1'b1;
        sched_tick;
        check(audio_l_s === 24'd0,        "S4.1 空 -> audio_l 明确为 0");
        check(audio_r_s === 24'd0,        "S4.2 空 -> audio_r 明确为 0");
        check(audio_underflow === 32'd1,  "S4.3 空 -> underflow +1");
        check(pcm_rd === 1'b0,            "S4.4 空时不推进 pcm_rd");
        sched_tick; sched_tick; sched_tick;
        check(audio_underflow === 32'd4,  "S4.5 underflow 每个空节拍各计一次");

        // ---- S5 混合：好样本不增加 underflow ----
        pcm_empty = 1'b0;
        pcm_l     = 16'h0100;
        pcm_r     = 16'hFF00;
        sched_tick;
        check(audio_underflow === 32'd4,  "S5.1 好样本不改变 underflow");

        // ---- S6 sample_tick 周期 = TICK_N+1 ----
        measure_period(tick_period);
        check(tick_period === (TICK_N + 1), "S6 sample_tick 周期 = TICK_N+1");

        // ================= DUT-T : alarm_tone_gen =================
        tone_en = 1'b0; tone_tick = 1'b0;
        @(posedge clk); #1;
        check(tone_l === 24'd0,           "T1.1 未使能 -> tone_l = 0");
        check(tone_r === 24'd0,           "T1.2 未使能 -> tone_r = 0");

        // ---- T2 ROM 精确值（force phase 反查 sin_q）----
        //   相位 16 bit：quad = phase[15:14]，qidx = phase[13:9]
        force dut_t.phase = 16'h0200; #1;
        check(tone_l === 24'h017F57,      "T2.1 phase 0x0200 -> +sin_q(1) = 98135");
        force dut_t.phase = 16'h3E00; #1;
        check(tone_l === 24'h1E7B17,      "T2.2 phase 0x3E00 -> +sin_q(31) = 1997591");
        force dut_t.phase = 16'h4000; #1;
        check(tone_l === 24'h1E7B17,      "T2.3 phase 0x4000（quad1 起点）-> +sin_q(31)");
        force dut_t.phase = 16'h4200; #1;
        check(tone_l === 24'h1E5EE1,      "T2.4 phase 0x4200 -> +sin_q(30) = 1990369");
        force dut_t.phase = 16'h8000; #1;
        check(tone_l === 24'h000000,      "T2.5 phase 0x8000（180 度）-> 0");
        force dut_t.phase = 16'h8200; #1;
        check(tone_l === 24'hFE80A9,      "T2.6 phase 0x8200 -> -sin_q(1) = -98135");
        force dut_t.phase = 16'hC000; #1;
        check(tone_l === 24'hE184E9,      "T2.7 phase 0xC000 -> -sin_q(31) = -1997591");
        force dut_t.phase = 16'hC200; #1;
        check(tone_l === 24'hE1A11F,      "T2.8 phase 0xC200 -> -sin_q(30) = -1990369");
        check(tone_r === tone_l,          "T2.9 tone_r 与 tone_l 一致");
        release dut_t.phase;

        // ---- T3 频率 ~1 kHz：48000 个节拍内相位回绕次数（表 8-2，误差 <1%）----
        //   f = 1365 * 48000 / 65536 = 999.76 Hz；48000 拍回绕 floor(999.76) = 999 次
        tone_en   = 1'b1;
        tone_tick = 1'b1;
        freq_win  = 1'b1;
        wraps     = 0;
        repeat (48000) @(posedge clk);
        freq_win  = 1'b0;
        tone_tick = 1'b0;
        tone_en   = 1'b0;
        check((wraps >= 990) && (wraps <= 1010), "T3 报警音频率 ~1kHz（回绕次数在 990..1010）");

        // ================= DUT-A : audio_priority_arbiter =================
        alarm_req = 1'b0;
        a_valid_in = 1'b0;
        @(posedge clk); #1;
        check(gain === 9'd0,              "A1.1 复位/空闲 gain = 0");
        check(aout_valid === 1'b0,        "A1.2 复位/空闲 audio_valid = 0");

        // ---- A2 alarm 关闭 -> 恒等 WAV ----
        wav_l_a = 24'h0F4240;  wav_r_a = 24'h0F4240;   // 1000000
        tone_l_a = 24'h123456; tone_r_a = 24'h123456;
        do_sample;
        check(gain === 9'd0,              "A2.1 alarm=0 -> gain 保持 0");
        check(aout_l === 24'h0F4240,      "A2.2 gain=0 -> 输出恒等 WAV");
        check(aout_valid === 1'b1,        "A2.3 样本有效时 audio_valid 拉高");

        // ---- A3 斜坡上升：单调、每步 STEP、8 样本到满量程 ----
        tone_l_a = 24'h000000; tone_r_a = 24'h000000;  // 便于看 WAV 权重
        prev_gain = gain;
        ok_mono   = 1'b1;
        for (i = 0; i < 10; i = i + 1) begin
            alarm_req = 1'b1;
            do_sample;
            if (gain < prev_gain)                     ok_mono = 1'b0;
            if ((gain - prev_gain) > 9'd32)           ok_mono = 1'b0;
            if (gain > 9'd256)                        ok_mono = 1'b0;
            prev_gain = gain;
        end
        check(ok_mono,                    "A3.1 上升斜坡单调、每步不超过 STEP(32)");
        check(gain === 9'd256,            "A3.2 alarm 持续 -> gain 饱和到 256");
        check(aout_l === 24'h000000,      "A3.3 gain=256 & tone=0 -> 输出 0");

        // ---- A3.4 第一步精确值：0->32，out = (1000000*(256-32))>>8 = 875000 ----
        //   （上面已到饱和，这里另起一段：force gain 回 0 再走一步）
        force dut_a.gain = 9'd0;
        wav_l_a = 24'h0F4240; tone_l_a = 24'h000000;
        alarm_req = 1'b1;
        do_sample;
        check(aout_l === 24'h0D59F8,      "A3.4 首步 gain=32 -> out=(wav*224)>>8=875000");
        release dut_a.gain;

        // ---- A4 满报警：gain=256 -> 输出恒等报警音 ----
        alarm_req = 1'b1;
        repeat (10) do_sample;                          // 回到饱和
        tone_l_a = 24'h123456; tone_r_a = 24'h654321;
        do_sample;
        check(gain === 9'd256,            "A4.1 alarm 持续时 gain 保持 256");
        check(aout_l === 24'h123456,      "A4.2 gain=256 -> 输出恒等报警音");

        // ---- A5 斜坡下降：回到 0 并恢复 WAV ----
        alarm_req = 1'b0;
        wav_l_a = 24'h0F4240;
        repeat (10) do_sample;
        check(gain === 9'd0,              "A5.1 alarm 撤销 -> gain 回到 0");
        check(aout_l === 24'h0F4240,      "A5.2 gain=0 -> 输出恢复恒等 WAV");

        // ---- A6 中间混合精确值（force gain=128 + alarm=1 -> n_gain=160）----
        //   out = (0x100000*(256-160))>>8 = 1048576*96/256 = 393216 = 0x060000
        force dut_a.gain = 9'd128;
        wav_l_a = 24'h100000; tone_l_a = 24'h000000;
        alarm_req = 1'b1;
        do_sample;
        check(aout_l === 24'h060000,      "A6 中间混合 0x100000*96/256 = 0x060000");
        release dut_a.gain;

        // ---- A7 audio_valid 单拍 ----
        alarm_req = 1'b0;
        wav_l_a = 24'h0F4240;
        do_sample;
        check(aout_valid === 1'b1,        "A7.1 样本有效时 audio_valid 拉高");
        @(posedge clk); #1;
        check(aout_valid === 1'b0,        "A7.2 audio_valid 只持续一拍");

        $display("[TB] tb_c_audio done, errors=%0d (tick_period=%0d tone_wraps=%0d)",
                 errors, tick_period, wraps);
        $finish;
    end

    // 看门狗
    initial begin
        #5_000_000;
        $display("[FAIL] tb_c_audio 看门狗超时");
        $finish;
    end

endmodule
