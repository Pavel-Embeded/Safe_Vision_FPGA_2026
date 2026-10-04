// ============================================================================
// frame_swap_ctrl.v — 帧交换握手状态机（SafeVision 阶段 15 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.15「阶段 15：帧交换握手（A/B 第一次真正协同）」
//         · 表 7-5 帧交换握手信号
//         · 表 7-6 帧交换握手状态转移：IDLE → WAIT_VBLANK → COMMIT → WAIT_ACK → IDLE
//         · 「技术纠错：帧交换的两类跨域错误」：
//             ✗ 老版把 frame_ready 当单拍脉冲直接打两拍跨域 → 目标时钟可能采样不到
//               而整体丢失；正确做法是 toggle 电平翻转
//             ✗ slot_id/generation/crc_ok/frame_index 多位载荷逐位各打两拍 → 取到
//               "半新半旧"（槽号已新、代次还旧）；正确做法是 mailbox 锁存
//             · 源域在收到 ack 之前不得修改这组寄存器
//       docs/interface_spec.md §3.4 swap_ctrl（端口冻结）+ §7 决策 D-3
//
// ★ 域归属（重要取舍，见交付说明）：本状态机实现在【B 侧（sys_clk）】，
//   严格按 interface_spec §3.4 的端口方向：
//       输出 frame_index / slot_id / generation / crc_ok / swap_req / swap_error
//       输入 frame_ready / frame_start / swap_ack
//   表 7-6 里"拉高 / 释放 swap_ack"对应 B 侧"保持 / 释放 swap_req 的请求有效窗口"，
//   因为 swap_ack 是 A→B 的回执（spec 端口方向），本模块只能读不能写。
//   frame_start（A→B 单拍）与 swap_ack（A→B toggle）都必须先经 frame_swap_cdc
//   同步/边沿检测，本模块收到的已是【本域单拍事件】。
//
// ★ 主序列保持不变；额外插入一个 S_REQ 过渡拍，对应图 7-2"payload 锁存进 mailbox"
//   之后才"swap_req 翻转"：保证 req 翻转前 payload 已稳定（手册 7.15 纠错要求）。
// ============================================================================
`include "safevision_defs.vh"

module frame_swap_ctrl #(
    // Default covers a full 60 Hz frame plus CDC/ack margin at 100/125 MHz.
    // 5M cycles = 50/40 ms; other frame rates/clocks must override it (O-5).
    parameter [31:0] TIMEOUT_N = 32'd5_000_000
)(
    input  wire       clk,                // sys_clk
    input  wire       rst_n,

    // ---- 写侧提交（来自 slot_writer / frame_buffer_manager）----
    input  wire       frame_ready,        // 新帧已完整写入
    input  wire       wr_frame_index,
    input  wire [1:0] wr_slot_id,
    input  wire [7:0] wr_generation,
    input  wire       wr_crc_ok,

    // ---- A 侧（均已经 frame_swap_cdc 同步成本域单拍事件）----
    input  wire       frame_start,        // 垂直消隐入口，每帧 1 拍
    input  wire       swap_ack,           // A 已完成切换（toggle 的边沿事件）

    // ---- 输出给 A（B→A，经 frame_swap_cdc）----
    output reg        swap_req,           // toggle 电平翻转（不是单拍脉冲）
    output reg        frame_index,        // mailbox payload
    output reg [1:0]  slot_id,
    output reg [7:0]  generation,
    output reg        crc_ok,
    output reg        swap_error,         // 握手超时 → C 的可靠性链

    // ---- 提交给 frame_buffer_manager（原子更新 active_slot/slot_base/generation）----
    output reg        active_commit,      // 单拍
    output reg [1:0]  active_next,
    output reg [7:0]  generation_next,
    output reg        frame_index_next,

    // ---- 观测 ----
    output reg [2:0]  state_o
);

    localparam [2:0] S_IDLE        = 3'd0,
                     S_REQ         = 3'd1,   // 锁存后一拍：翻转 swap_req
                     S_WAIT_VBLANK = 3'd2,
                     S_COMMIT      = 3'd3,
                     S_WAIT_ACK    = 3'd4,
                     S_SAFE        = 3'd5;

    reg [2:0]  state;
    reg [31:0] to_cnt;
    reg        ack_seen;     // retain an ack received before/on the commit edge
    reg        fr_d;          // frame_ready 上一拍值，用于 S_SAFE 只在"新的"有效帧上重试

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            to_cnt           <= 32'd0;
            fr_d             <= 1'b0;
            ack_seen         <= 1'b0;
            swap_req         <= 1'b0;
            frame_index      <= 1'b0;
            slot_id          <= 2'd0;
            generation       <= 8'd0;
            crc_ok           <= 1'b0;
            swap_error       <= 1'b0;
            active_commit    <= 1'b0;
            active_next      <= 2'd0;
            generation_next  <= 8'd0;
            frame_index_next <= 1'b0;
            state_o          <= S_IDLE;
        end else begin
            // 默认：单拍脉冲清零
            active_commit <= 1'b0;
            state_o       <= state;
            fr_d          <= frame_ready;
            if ((state == S_WAIT_VBLANK || state == S_COMMIT || state == S_WAIT_ACK) && swap_ack)
                ack_seen <= 1'b1;

            case (state)
            // ------------------------------------------------------------------
            S_IDLE: begin
                // frame_ready 有效且 crc_ok -> 锁存 payload 到 mailbox
                if (frame_ready && wr_crc_ok) begin
                    ack_seen         <= 1'b0;
                    frame_index      <= wr_frame_index;
                    slot_id          <= wr_slot_id;
                    generation_next  <= wr_generation;
                    frame_index_next <= wr_frame_index;
                    crc_ok           <= wr_crc_ok;
                    generation       <= wr_generation;
                    to_cnt           <= 32'd0;
                    state            <= S_REQ;
                end
            end
            // ---- 锁存完成，翻转 swap_req（toggle），请求 A 在消隐期切换 ----------
            S_REQ: begin
                swap_req <= ~swap_req;
                to_cnt   <= 32'd0;
                state    <= S_WAIT_VBLANK;
            end
            // ---- 等垂直消隐入口 ------------------------------------------------
            S_WAIT_VBLANK: begin
                if (frame_start) begin
                    // ★ 原子提交：active_slot / slot_base / generation 同一拍一起更新
                    active_next   <= slot_id;
                    active_commit <= 1'b1;
                    to_cnt        <= 32'd0;
                    state         <= S_COMMIT;
                end else if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;           // 超时：保持当前显示块，交 C
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                end
            end
            // ---- active_slot 已翻转，保持 swap_req 在有效窗口内 -----------------
            S_COMMIT: begin
                if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                    state  <= S_WAIT_ACK;
                end
            end
            // ---- 等 A 的回执（swap_ack toggle 的边沿事件）----------------------
            S_WAIT_ACK: begin
                if (swap_ack || ack_seen) begin
                    ack_seen <= 1'b0;
                    // A 已切换完成，允许 B 写另一块；swap_req 保持电平，等下次翻转
                    state <= S_IDLE;
                end else if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                end
            end
            // ---- SAFE：保持当前显示块；收到【新的】合法 frame_ready 再试一次 -----
            S_SAFE: begin
                if (frame_ready && wr_crc_ok && !fr_d) begin
                    ack_seen         <= 1'b0;
                    swap_error       <= 1'b0;
                    frame_index      <= wr_frame_index;
                    slot_id          <= wr_slot_id;
                    generation_next  <= wr_generation;
                    frame_index_next <= wr_frame_index;
                    crc_ok           <= wr_crc_ok;
                    generation       <= wr_generation;
                    to_cnt           <= 32'd0;
                    state            <= S_REQ;      // 重新尝试一次握手
                end
            end
            default: state <= S_IDLE;
            endcase
        end
    end

endmodule