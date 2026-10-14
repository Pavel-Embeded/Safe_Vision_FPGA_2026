// ============================================================================
// tb_c_playback_fsm.sv — 播放状态机单元验证（手册 8.7 表 8-3，对应 B03）
// ----------------------------------------------------------------------------
// 过关标准：表 8-3 的每个状态进入 / 退出条件各跑一遍，含兜底与恢复两条路径。
//   P1  复位 -> BOOT，输出静音（video_mute=1）
//   P2  boot_ready -> SCAN，解除静音
//   P3  scan_done -> PRELOAD
//   P4  preload_ok 且自动关闭 -> MANUAL
//   P5  MANUAL + KEY1(!trans_en) -> commit_next 单拍 + slot 递增
//   P6  MANUAL auto_en -> AUTO
//   P7  AUTO auto_tick -> commit_next + slot 递增
//   P8  AUTO 关闭自动 / uart_stop -> MANUAL
//   P13 KEY1+trans_en -> TRANSITION；trans_done -> commit+slot++ -> MANUAL
//   P9  MANUAL alarm_in -> SAFE（safe_req=1）；SAFE 期间 media_rst_active 必须为 0
//   P10 SAFE confirm_stable -> RECOVER
//   P14 RECOVER 期间 media_rst_active=1（只复位媒体链，不牵连安全画面）
//   P12 RECOVER 未完成 -> 回 SAFE
//   P11 RECOVER 完成 -> MANUAL
//   P15 PRELOAD 未备齐四图（scan_done 且 !preload_ok）-> SAFE（兜底）
//   P16 TRANSITION 故障 -> SAFE
// ============================================================================
`timescale 1ns / 1ps

module tb_c_playback_fsm;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n;
    reg [15:0] stim;

    // 事件位映射
    wire boot_ready        = stim[0];
    wire sd_mount_ok       = stim[1];
    wire scan_done         = stim[2];
    wire four_img_ok       = stim[3];
    wire preload_ok        = stim[4];
    wire auto_en           = stim[5];
    wire key_next          = stim[6];
    wire uart_stop         = stim[7];
    wire trans_en          = stim[8];
    wire auto_tick         = stim[9];
    wire trans_done        = stim[10];
    wire trans_fault       = stim[11];
    wire alarm_in          = stim[12];
    wire media_fault_severe= stim[13];
    wire confirm_stable    = stim[14];
    wire recover_done      = stim[15];

    wire [2:0] state;
    wire [2:0] state_code;
    wire       media_rst_active, commit_next;
    wire [1:0] slot_index;
    wire       video_mute, safe_req, auto_mode;

    playback_fsm #(.SLOTS(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .boot_ready(boot_ready), .sd_mount_ok(sd_mount_ok), .scan_done(scan_done),
        .four_img_ok(four_img_ok), .preload_ok(preload_ok), .auto_en(auto_en),
        .key_next(key_next), .uart_stop(uart_stop), .trans_en(trans_en),
        .auto_tick(auto_tick), .trans_done(trans_done), .trans_fault(trans_fault),
        .alarm_in(alarm_in), .media_fault_severe(media_fault_severe),
        .confirm_stable(confirm_stable), .recover_done(recover_done),
        .state(state), .state_code(state_code), .media_rst_active(media_rst_active),
        .commit_next(commit_next), .slot_index(slot_index), .video_mute(video_mute),
        .safe_req(safe_req), .auto_mode(auto_mode)
    );

    localparam [2:0] S_BOOT = 3'd0, S_SCAN = 3'd1, S_PRELOAD = 3'd2,
                     S_MANUAL = 3'd3, S_AUTO = 3'd4, S_TRANSITION = 3'd5,
                     S_SAFE = 3'd6, S_RECOVER = 3'd7;

    integer errors = 0, ps;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // 单拍脉冲：位 b 在 posedge 有效一拍，之后清 0
    task one;
        input integer b;
        begin @(negedge clk); stim = 16'd1 << b; @(posedge clk); #1; stim = 16'd0; end
    endtask

    // 保持：位向量在 posedge 有效并保持
    task hold;
        input [15:0] v;
        begin @(negedge clk); stim = v; @(posedge clk); #1; end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0; stim = 16'd0;
            repeat (3) @(posedge clk); #1;
            rst_n = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 1'b0; stim = 16'd0;
        do_reset();
        check(state === S_BOOT && video_mute === 1'b1,
              "P1 复位 -> BOOT，输出静音");

        one(0);
        check(state === S_SCAN, "P2 boot_ready -> SCAN");
        @(posedge clk); #1;          // video_mute 是寄存器输出，进入 SCAN 后一拍才落地
        check(video_mute === 1'b0, "P2b SCAN 解除静音");

        one(2);
        check(state === S_PRELOAD, "P3 scan_done -> PRELOAD");

        hold(16'd1 << 4);
        check(state === S_MANUAL && auto_mode === 1'b0, "P4 preload_ok(auto off) -> MANUAL");

        ps = slot_index;
        one(6);
        check(commit_next === 1'b1 && state === S_MANUAL,
              "P5 MANUAL KEY1(!trans_en) -> commit_next 单拍");
        check(slot_index === ps + 1'b1, "P5b slot_index 递增");

        hold(16'd1 << 5);
        check(state === S_AUTO && auto_mode === 1'b1, "P6 MANUAL auto_en -> AUTO");

        ps = slot_index;
        hold((16'd1 << 5) | (16'd1 << 9));
        check(commit_next === 1'b1 && slot_index === ps + 1'b1 && state === S_AUTO,
              "P7 AUTO auto_tick -> commit_next + slot++");

        hold(16'd0);
        check(state === S_MANUAL && auto_mode === 1'b0, "P8 AUTO 关闭自动 -> MANUAL");

        hold(16'd1 << 5);
        check(state === S_AUTO, "P8b 再次 auto_en -> AUTO");
        hold((16'd1 << 5) | (16'd1 << 7));
        check(state === S_MANUAL, "P8c AUTO uart_stop -> MANUAL");
        stim = 16'd0;

        hold((16'd1 << 6) | (16'd1 << 8));
        check(state === S_TRANSITION, "P13 MANUAL KEY1+trans_en -> TRANSITION");
        ps = slot_index;
        one(10);
        check(commit_next === 1'b1 && slot_index === ps + 1'b1 && state === S_MANUAL,
              "P13b trans_done -> commit+slot++ -> MANUAL");

        hold(16'd1 << 12);
        check(state === S_SAFE && safe_req === 1'b1, "P9 MANUAL alarm_in -> SAFE (safe_req=1)");
        check(media_rst_active === 1'b0,
              "P9b SAFE 期间 media_rst_active=0（媒体复位只在 RECOVER 有效）");

        hold((16'd1 << 12) | (16'd1 << 14));
        check(state === S_RECOVER, "P10 SAFE confirm_stable -> RECOVER");
        check(media_rst_active === 1'b1,
              "P14 RECOVER 期间 media_rst_active=1（只复位媒体链）");

        hold(16'd1 << 12);
        check(state === S_SAFE, "P12 RECOVER 未完成(recover_done=0) -> 回 SAFE");

        hold((16'd1 << 12) | (16'd1 << 14));
        check(state === S_RECOVER, "P11 SAFE -> RECOVER");
        hold(16'd1 << 15);
        check(state === S_MANUAL, "P11b recover_done -> MANUAL");
        check(media_rst_active === 1'b0, "P14b 离开 RECOVER 后 media_rst_active=0");
        stim = 16'd0;

        // P16 TRANSITION 中故障 -> SAFE
        hold((16'd1 << 6) | (16'd1 << 8));
        check(state === S_TRANSITION, "P16 前置：进入 TRANSITION");
        hold((16'd1 << 6) | (16'd1 << 8) | (16'd1 << 11));
        check(state === S_SAFE && safe_req === 1'b1, "P16 TRANSITION trans_fault -> SAFE");
        stim = 16'd0;

        // P15 PRELOAD 未备齐四图 -> SAFE（兜底）
        do_reset();
        one(0);
        one(2);
        check(state === S_PRELOAD, "P15 前置：到达 PRELOAD");
        one(2);
        check(state === S_SAFE && safe_req === 1'b1,
              "P15 PRELOAD 未备齐四图 -> SAFE（兜底不黑屏）");

        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_playback_fsm done, errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] tb_c_playback_fsm 看门狗超时");
        $finish;
    end

endmodule
