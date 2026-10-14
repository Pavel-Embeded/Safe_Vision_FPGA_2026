// ============================================================================
// emergency_fsm.v — 应急状态机（手册 8.2 / 表 8-1，C 的核心状态机）
// ----------------------------------------------------------------------------
// 回答一个问题："此刻屏幕该听谁的。"
//   五态：NORMAL / WARNING / EMERGENCY / EVACUATION / FAIL_SAFE
//
// 对外控制载荷（给 A 的 emergency_command_adapter）：
//   {emergency_active, direction[1:0], warning_level[1:0]} + 单比特 commit_toggle
//   附加：alarm_enable（给音频链）、fault_reason[7:0]（供 OSD / UART 读取）
//
// ★★ 红线：warning_level / direction 等多位控制信号**绝不逐位打两拍跨域**。
//    本模块把 {emergency_active, warning_level, direction, alarm_enable,
//    fault_reason[7:0]} 作为**一整组 payload 写入寄存器并保持稳定**，
//    只有在前一次提交被 A 用 commit_ack_toggle 确认（acked=1）之后，
//    才更新整组 payload 并翻转 commit_toggle。payload 在 ack 返回之前不得修改。
//    A 侧 emergency_control_bridge 完成 SYS -> PIXEL 的原子跨域。
//
// ★ 锁存 / 清除 / 恢复三条口径：
//   锁存：evt_fire 与 fault_reason 由事件置位后保持不变，绝不"事件撤销即自动清零"
//         （否则一次 100 us 的告警电平会在人工看到之前消失）。
//   清除：只由人工确认（confirm 且稳定窗口通过）或显式 recover_ack 触发，
//         且必须与恢复条件成对出现。
//   恢复：清除后只复位媒体链并重新扫描（由 playback_fsm 的 RECOVER 执行），
//         失败则回 SAFE。
//
// ★ warning_level 语义与 A 的应急图形一致（emergency_graphics.v 的实际译码）：
//    0 = 绿（无应急覆盖） / 1 = 黄（一般告警 WARNING） / 2 = 红（火情疏散 与 兜底）
//    FAIL_SAFE 取 direction=1（右箭头，对应图 8-2 的 "SAFE MODE EXIT ->"）。
//
// 时钟域 : sys_clk（控制域）
// ============================================================================
`include "fault_code_defs.vh"

module emergency_fsm (
    clk, rst_n,
    fire_in, alarm_in, media_fault, media_ok, fault_code_in, fatal,
    confirm, confirm_stable, recover_ack, media_selftest_ok,
    direction_in, direction_valid, warn_window_done, info_only,
    commit_ack_toggle,
    emergency_active, warning_level, direction, alarm_enable, fault_reason,
    commit_toggle, state, bram_req
);
    input  wire       clk;
    input  wire       rst_n;

    // ---- 事件输入 ----
    input  wire       fire_in;            // 火情（同步去抖后）
    input  wire       alarm_in;           // 外部告警（同步去抖后）
    input  wire       media_fault;        // 媒体链故障
    input  wire       media_ok;           // 媒体链仍可用（四图仍可播）
    input  wire [7:0] fault_code_in;      // 故障主码（来自 fault_manager）
    input  wire       fatal;              // 视频 PLL / HDMI PHY 失效（只能标 FATAL）
    input  wire       confirm;            // 人工确认
    input  wire       confirm_stable;     // 人工确认且连续稳定窗口通过
    input  wire       recover_ack;        // 显式恢复条件
    input  wire       media_selftest_ok;  // 媒体链自检通过
    input  wire [1:0] direction_in;       // 方向输入：0 左 1 右 2 双向
    input  wire       direction_valid;    // 方向输入有效
    input  wire       warn_window_done;   // 告警窗口计满
    input  wire       info_only;          // 可选资源缺失（INFO 等级）
    input  wire       commit_ack_toggle;  // A 对上一次提交的确认

    // ---- 对外载荷（整组锁存，ack 前不得修改）----
    output reg        emergency_active;
    output reg  [1:0] warning_level;
    output reg  [1:0] direction;
    output reg        alarm_enable;
    output reg  [7:0] fault_reason;
    output reg        commit_toggle;

    // ---- 状态观测 ----
    output reg  [2:0] state;
    output wire       bram_req;           // 请求 A 的 final_mux 强制选片上 BRAM 应急源

    localparam [2:0] S_NORMAL     = 3'd0;
    localparam [2:0] S_WARNING    = 3'd1;
    localparam [2:0] S_EMERGENCY  = 3'd2;
    localparam [2:0] S_EVACUATION = 3'd3;
    localparam [2:0] S_FAIL_SAFE  = 3'd4;

    reg        evt_fire;        // 火情锁存（由事件置位，只由 confirm/recover_ack 清除）
    reg [7:0]  reason_latch;    // fault_reason 锁存
    reg [1:0]  dir_hold;        // 当前方向（0 左 1 右 2 双向）

    wire       fire_evt = fire_in | alarm_in;
    wire [1:0] dir_in_c = (direction_in == 2'd3) ? 2'd2 : direction_in;   // 3 保留 -> 双向
    wire       dir_chg  = direction_valid & (dir_in_c != dir_hold);

    assign bram_req = (state == S_FAIL_SAFE);

    // ---- 状态 + 锁存位 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_NORMAL;
            evt_fire     <= 1'b0;
            reason_latch <= `ERR_NONE;
            dir_hold     <= 2'd0;
        end else begin
            // 故障原因锁存：第一条媒体故障的主码锁住，先到先得
            if (media_fault && reason_latch == `ERR_NONE)
                reason_latch <= fault_code_in;

            case (state)
                S_NORMAL: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;                 // FATAL 不做"可恢复"承诺
                    end else if (fire_evt) begin
                        evt_fire <= 1'b1;                     // 锁存
                        dir_hold <= direction_valid ? dir_in_c : 2'd0;
                        state    <= S_EMERGENCY;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;                 // 媒体链不可用 -> 兜底
                    end else if (media_fault && media_ok) begin
                        state <= S_WARNING;                   // 四图仍可播 -> 一般告警
                    end
                end

                S_WARNING: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (fire_evt) begin
                        evt_fire <= 1'b1;                     // 高优先级覆盖告警
                        dir_hold <= direction_valid ? dir_in_c : 2'd0;
                        state    <= S_EMERGENCY;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;                 // 告警窗口内完全失效
                    end else if (!media_fault && warn_window_done) begin
                        reason_latch <= `ERR_NONE;          // 清可选告警锁存
                        state <= S_NORMAL;                  // 告警条件消失且窗口计满
                    end
                end

                S_EMERGENCY: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (evt_fire && direction_valid) begin
                        dir_hold <= dir_in_c;
                        state    <= S_EVACUATION;             // fire 持续 + 方向有效
                    end else if (dir_chg) begin
                        dir_hold <= dir_in_c;                 // 更新方向并重新锁存整组载荷
                    end
                    // fire_in 撤销：保持报警与疏散画面，等人工确认，不自动清零
                end

                S_EVACUATION: begin
                    if (fatal) begin
                        state <= S_FAIL_SAFE;
                    end else if (media_fault && !media_ok) begin
                        state <= S_FAIL_SAFE;                 // 保持报警，请求 BRAM
                    end else if (dir_chg) begin
                        dir_hold <= dir_in_c;
                    end else if (confirm && confirm_stable) begin
                        evt_fire     <= 1'b0;                 // 清 evt_fire 锁存
                        reason_latch <= `ERR_NONE;            // 清原因锁存
                        dir_hold     <= 2'd0;                 // 方向归零
                        state        <= S_NORMAL;
                    end
                end

                S_FAIL_SAFE: begin
                    if (recover_ack && media_selftest_ok) begin
                        reason_latch <= `ERR_NONE;            // 清 fault_reason 锁存
                        evt_fire     <= 1'b0;
                        dir_hold     <= 2'd0;
                        state        <= S_NORMAL;             // 只复位媒体链并重新扫描
                    end
                    // 人工确认但媒体链未恢复：维持应急画面与报警，不自动退出
                end

                default: state <= S_NORMAL;
            endcase
        end
    end

    // ---- 期望载荷（组合）----
    reg       n_active;
    reg [1:0] n_level;
    reg [1:0] n_dir;
    reg       n_alarm;
    reg [7:0] n_reason;
    always @* begin
        n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0; n_alarm = 1'b0;
        n_reason = reason_latch;
        case (state)
            S_NORMAL: begin
                n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0;
                n_alarm  = info_only;                     // INFO：提示音，不改主画面
            end
            S_WARNING: begin
                n_active = 1'b1; n_level = 2'd1; n_dir = 2'd0; n_alarm = 1'b1;
            end
            S_EMERGENCY: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = dir_hold; n_alarm = evt_fire;
            end
            S_EVACUATION: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = dir_hold; n_alarm = evt_fire;
            end
            S_FAIL_SAFE: begin
                n_active = 1'b1; n_level = 2'd2; n_dir = 2'd1; n_alarm = 1'b1;
                n_reason = (reason_latch == `ERR_NONE) ? `ERR_MEDIA_INVALID : reason_latch;
            end
            default: begin
                n_active = 1'b0; n_level = 2'd0; n_dir = 2'd0; n_alarm = 1'b0;
            end
        endcase
    end

    // ---- payload mailbox：整组锁存 + commit/ack toggle ----
    wire        acked = (commit_ack_toggle == commit_toggle);
    wire [13:0] n_pay = {n_active, n_level, n_dir, n_alarm, n_reason};
    wire [13:0] c_pay = {emergency_active, warning_level, direction, alarm_enable, fault_reason};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            emergency_active <= 1'b0;
            warning_level    <= 2'd0;
            direction        <= 2'd0;
            alarm_enable     <= 1'b0;
            fault_reason     <= `ERR_NONE;
            commit_toggle    <= 1'b0;
        end else if (acked && (n_pay != c_pay)) begin
            emergency_active <= n_active;
            warning_level    <= n_level;
            direction        <= n_dir;
            alarm_enable     <= n_alarm;
            fault_reason     <= n_reason;
            commit_toggle    <= ~commit_toggle;
        end
    end

endmodule
