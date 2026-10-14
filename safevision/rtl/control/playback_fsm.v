// ============================================================================
// playback_fsm.v — 播放状态机（手册 8.7 表 8-3，对应 B03）
// ----------------------------------------------------------------------------
// C 是这张表的负责人，A / B 只提供事件与执行动作。任何一方要改状态或加事件，
// 必须先改 interface_spec.md 的表 8-3 再改 RTL。
//
// 状态（表 8-3）：
//   BOOT       全局复位释放；BIST / HDMI 初始化、输出静音         -> 基础外设就绪
//   SCAN       SD 挂载成功；扫描目录并构建 media_index           -> 至少四图有效或扫描结束
//   PRELOAD    索引完成；装载四图、计算 CRC、预填音频            -> 四个槽位有效
//   MANUAL     预加载成功且自动模式关闭；显示当前槽，接受 KEY1   -> KEY2 或告警
//   AUTO       KEY2 开启；按配置周期提交下一槽与对应音频         -> KEY2、UART 或告警
//   TRANSITION 切换请求且扩展效果启用；固定帧数双图合成          -> 达到目标槽或故障
//   SAFE       alarm_in 或严重媒体故障；安全画面、报警音、锁存原因
//   RECOVER    可恢复故障解除；只复位媒体链并重新扫描            -> 成功回 MANUAL，失败回 SAFE
//
// 时钟域 : sys_clk（控制域）
// 输出   : state / state_code（UART 日志）、media_rst_active（RECOVER 期间为电平，
//          只复位媒体链，严禁并入安全画面/HDMI 复位）、commit_next（提交下一槽）、
//          slot_index、video_mute、safe_req、auto_mode
// ★ 命名区分：fault_manager 的**请求脉冲**是 `media_rst_req`（本模块的 RECOVER
//   是它的"执行端"之一，见 fault_manager 头注）；本模块对外**执行**的复位是
//   电平 `media_rst_active`。两者语义不同，不可互相顶替接线（见 interface_spec O-13）。
// ★ 每条"等外部回应"路径都有事件出口；SAFE 只由"人工确认且稳定窗口通过"退出。
// ============================================================================

module playback_fsm (
    clk, rst_n,
    boot_ready, sd_mount_ok, scan_done, four_img_ok, preload_ok,
    auto_en, key_next, uart_stop, trans_en, auto_tick, trans_done, trans_fault,
    alarm_in, media_fault_severe, confirm_stable, recover_done,
    state, state_code, media_rst_active, commit_next, slot_index,
    video_mute, safe_req, auto_mode
);
    parameter integer SLOTS = 4;

    function integer clog2;
        input integer n;
        integer v;
        begin
            clog2 = 1;
            for (v = n-1; v > 1; v = v >> 1) clog2 = clog2 + 1;
        end
    endfunction
    localparam integer SIW = clog2(SLOTS);

    input  wire clk;
    input  wire rst_n;

    // ---- 事件输入 ----
    input  wire boot_ready;        // 基础外设就绪（BIST / HDMI 初始化完成）
    input  wire sd_mount_ok;       // SD 挂载成功
    input  wire scan_done;         // 目录扫描结束
    input  wire four_img_ok;       // 至少四图有效
    input  wire preload_ok;        // 四个槽位有效、CRC 通过、音频预填完成
    input  wire auto_en;           // KEY2 开启自动播放
    input  wire key_next;          // KEY1：切下一张
    input  wire uart_stop;         // UART 命令停自动
    input  wire trans_en;          // 扩展转场效果启用
    input  wire auto_tick;         // AUTO 周期到（提交下一槽）
    input  wire trans_done;        // 转场达到目标槽
    input  wire trans_fault;       // 转场中故障
    input  wire alarm_in;          // 外部告警
    input  wire media_fault_severe;// 严重媒体故障（SDRAM BIST 失败 / 连续欠载 / 拔卡）
    input  wire confirm_stable;    // 人工确认且恢复条件连续稳定窗口通过
    input  wire recover_done;      // RECOVER 重扫成功

    // ---- 状态与动作输出 ----
    output reg  [2:0]     state;
    output wire [2:0]     state_code;
    output wire           media_rst_active; // 只复位媒体链（不含视频时序 / 安全画面）
                                            // RECOVER 期间为电平（状态导出），避免"1 拍脉冲"不可观测
                                            // 与 fault_manager 的请求脉冲 media_rst_req 语义不同，勿混接
    output reg            commit_next;     // 提交下一槽（单拍）
    output reg  [SIW-1:0] slot_index;      // 当前槽号
    output reg            video_mute;      // BOOT：输出静音
    output reg            safe_req;        // SAFE：请求安全画面 + 报警音
    output reg            auto_mode;

    localparam [2:0] S_BOOT       = 3'd0;
    localparam [2:0] S_SCAN       = 3'd1;
    localparam [2:0] S_PRELOAD    = 3'd2;
    localparam [2:0] S_MANUAL     = 3'd3;
    localparam [2:0] S_AUTO       = 3'd4;
    localparam [2:0] S_TRANSITION = 3'd5;
    localparam [2:0] S_SAFE       = 3'd6;
    localparam [2:0] S_RECOVER    = 3'd7;

    assign state_code = state;
    assign media_rst_active = (state == S_RECOVER);   // RECOVER 期间持续请求复位媒体链

    // 高级事件：任何"运行态"下一旦外部告警或严重媒体故障，立刻进 SAFE
    wire to_safe = alarm_in | media_fault_severe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_BOOT;
            commit_next   <= 1'b0;
            slot_index    <= {SIW{1'b0}};
            video_mute    <= 1'b1;
            safe_req      <= 1'b0;
            auto_mode     <= 1'b0;
        end else begin
            // 默认单拍输出归零
            commit_next   <= 1'b0;

            case (state)
                S_BOOT: begin
                    video_mute <= 1'b1;         // 输出静音
                    safe_req   <= 1'b0;
                    if (boot_ready) state <= S_SCAN;
                end

                S_SCAN: begin
                    video_mute <= 1'b0;
                    if (scan_done) state <= S_PRELOAD;
                end

                S_PRELOAD: begin
                    if (preload_ok) begin
                        auto_mode <= auto_en;
                        state <= auto_en ? S_AUTO : S_MANUAL;
                    end else if (scan_done) begin
                        // 扫描结束但四个槽位没备齐 -> 兜底
                        safe_req <= 1'b1;
                        state    <= S_SAFE;
                    end
                end

                S_MANUAL: begin
                    safe_req   <= 1'b0;
                    auto_mode  <= 1'b0;
                    if (to_safe) begin
                        safe_req <= 1'b1;
                        state    <= S_SAFE;
                    end else if (auto_en) begin
                        auto_mode <= 1'b1;
                        state     <= S_AUTO;
                    end else if (key_next) begin
                        if (trans_en) state <= S_TRANSITION;
                        else begin
                            commit_next <= 1'b1;                 // 普通切下一张
                            slot_index  <= slot_index + 1'b1;
                        end
                    end
                end

                S_AUTO: begin
                    safe_req <= 1'b0;
                    if (to_safe) begin
                        safe_req <= 1'b1;
                        state    <= S_SAFE;
                    end else if (!auto_en || uart_stop) begin
                        auto_mode <= 1'b0;
                        state     <= S_MANUAL;
                    end else if (auto_tick) begin
                        commit_next <= 1'b1;                     // 按配置周期提交下一槽
                        slot_index  <= slot_index + 1'b1;
                    end
                end

                S_TRANSITION: begin
                    if (to_safe || trans_fault) begin
                        safe_req <= 1'b1;
                        state    <= S_SAFE;
                    end else if (trans_done) begin
                        commit_next <= 1'b1;
                        slot_index  <= slot_index + 1'b1;
                        state       <= auto_mode ? S_AUTO : S_MANUAL;
                    end
                end

                S_SAFE: begin
                    // 安全画面 + 报警音，锁存原因；只由"人工确认且稳定窗口通过"退出
                    safe_req <= 1'b1;
                    if (confirm_stable) begin
                        state <= S_RECOVER;
                    end
                end

                S_RECOVER: begin
                    safe_req <= 1'b0;
                    // media_rst_active 由 state 导出（见上面的 assign），RECOVER 期间持续有效
                    if (recover_done) state <= auto_mode ? S_AUTO : S_MANUAL;
                    else              state <= S_SAFE;     // 恢复失败回 SAFE
                end

                default: state <= S_BOOT;
            endcase
        end
    end

    // synthesis translate_off
    initial if (SLOTS < 1) $fatal(1, "playback_fsm invalid SLOTS");
    // synthesis translate_on

endmodule
