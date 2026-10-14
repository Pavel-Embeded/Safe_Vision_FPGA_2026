// ============================================================================
// input_sync.v — C 链第一级：异步输入 → 两级同步 → 去抖 → 边沿检测 → 单拍事件
// ----------------------------------------------------------------------------
// 依据：手册 8.1（前级链固定四级，顺序颠倒会表现为"按键误触发"）
//   async_in → 两级同步器 → 去抖（DEB_N 拍稳定窗口）→ 边沿检测 → press
//   另加 pending 事件锁存位：press 只有一拍，FSM 当拍没取走就永久丢失，
//   故 evt_pending 由 press 置位、由 evt_clear 清除（"FSM 取走后清"）。
//
// 时钟域 : sys_clk（控制域）
// 参数   : DEB_N 为稳定窗口拍数，手册 20 ms 目标 -> DEB_N = 20 ms x clk。
//          默认按 100 MHz 取 2_000_000（设计目标，待实测回填）。
//          RESET_LEVEL 为输入的空闲逻辑电平。
//
// ★ 红线：press 必须"正好一拍"；去抖计数器在输入回到稳定值时归零；
//   绝不允许把稳定电平本身当事件（必须用边沿）。
// ★ 异步输入绝不直接进 FSM / 去抖 / 边沿检测——先过两级同步器。
// ============================================================================

module input_sync #(
    parameter integer DEB_N       = 2000000,  // 20 ms @100 MHz -> 2_000_000 拍
    parameter         RESET_LEVEL = 1'b0      // 输入空闲电平
)(
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    input  wire evt_clear,     // FSM 取走 pending 事件后拉高
    output reg  press,         // 上升沿，正好一拍
    output reg  level,         // 去抖后的稳定电平（供长按 / 稳定窗口判定）
    output reg  evt_pending    // 事件锁存：置位后保持，直到 evt_clear
);

    function integer counter_width;
        input integer n;
        integer v;
        begin
            counter_width = 1;
            for (v = n-1; v > 1; v = v >> 1) counter_width = counter_width + 1;
        end
    endfunction
    localparam integer CW = counter_width(DEB_N);

    (* ASYNC_REG = "TRUE" *) reg sync_meta;
    (* ASYNC_REG = "TRUE" *) reg sync_sync;   // 两级同步器
    reg level_d;                              // 边沿检测打拍
    reg [CW-1:0] db_cnt;                      // 去抖计数器

    // ---- 两级同步器（绝不让异步信号直接进后面的逻辑）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync_meta <= RESET_LEVEL; sync_sync <= RESET_LEVEL; end
        else begin sync_meta <= async_in; sync_sync <= sync_meta; end
    end

    // ---- 去抖 + 边沿检测 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            level <= RESET_LEVEL; level_d <= RESET_LEVEL; db_cnt <= 0; press <= 1'b0;
        end else begin
            level_d <= level;
            press   <= level & ~level_d;      // 恰好一拍
            if (sync_sync != level) begin     // 输入变化：等稳定窗口走完
                if (db_cnt == DEB_N-1) begin level <= sync_sync; db_cnt <= 0; end
                else db_cnt <= db_cnt + 1'b1;
            end else db_cnt <= 0;             // 回到稳定值即重新计时
        end
    end

    // ---- pending 事件锁存（防窄脉冲在 FSM 当拍没取走时丢失）----
    // 置位优先：同一拍既有新 press 又有 evt_clear 时，新事件不能被吞掉。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) evt_pending <= 1'b0;
        else if (press)     evt_pending <= 1'b1;
        else if (evt_clear) evt_pending <= 1'b0;
    end

    // synthesis translate_off
    initial if (DEB_N < 1) $fatal(1, "input_sync invalid DEB_N (must be >= 1)");
    // synthesis translate_on

endmodule
