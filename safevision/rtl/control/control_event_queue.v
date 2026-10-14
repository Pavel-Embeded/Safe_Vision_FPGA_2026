// ============================================================================
// control_event_queue.v — C 侧事件顺序队列（UART 日志 / 事件顺序证据）
// ----------------------------------------------------------------------------
// 依据：interface_spec §一「错误上报统一走 error_report → Control Event
//       Interface（evt_type / evt_value / evt_valid / evt_full），**溢出计数在 C 侧**」；
//       手册 8.7「每个事件有锁存……状态机与转移表以 UART 日志为证据」。
//
// 作用：把 C 链内部事件（按键、模式转移、故障、看门狗、恢复）+ 由 error_report
//       转来的错误事件，按**到达顺序**排队，供 UART 日志模块逐条读出；
//       放不下时**不覆盖旧事件**，明确计入 ovf_cnt（永久留证的故障计数）。
//
// 元素 52 bit = {evt_ts[31:0], evt_value[15:0], evt_type[3:0]}
//    evt_type 取 event_code_defs.vh 的 SV_EVT_SRC_*（谁报的）
//    evt_value 取 fault_code_defs.vh 的 ERR_*/DET_* 或事件取值
//
// ★★ 已知接口缺口（诚实登记，不是本模块缺陷）：B 的 error_report 内部队列
//    只有 wr_en、rd_en 恒 0（见 error_report.v 文件头"已知取舍"），
//    即冻结的 Control Event Interface **没有读出/确认信号**。
//    因此 C 侧真正联调"读走 B 的事件"需要 error_report 增加 evt_ack（属 B 的改动，
//    须先改 interface_spec.md 并通知 B）。本模块先作为 C 自己的可读事件队列落地，
//    并已把该缺口登记为 interface_spec 待确认项 O-12。
// ============================================================================

module control_event_queue #(
    parameter integer DEPTH    = 16,
    parameter integer AFULL_TH = 12
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 压入侧（C 侧各模块）----
    input  wire        push,
    input  wire [3:0]  push_type,     // SV_EVT_SRC_*
    input  wire [15:0] push_value,    // ERR_*/DET_* 或事件取值
    input  wire [31:0] push_ts,       // 时间戳（ms）

    // ---- 读出侧（UART 日志）----
    input  wire        pop,
    output wire [3:0]  out_type,
    output wire [15:0] out_value,
    output wire [31:0] out_ts,
    output wire        out_valid,     // FWFT：非空即有效，队首在 out_* 上
    output wire        empty,
    output wire        full,

    // ---- 计数（永久留证）----
    output reg  [15:0] ovf_cnt        // 满时又压入的条数（"错误事件不允许丢弃"）
);
    localparam integer EVT_W = 52;

    wire [EVT_W-1:0] head;
    wire [EVT_W-1:0] din = {push_ts, push_value, push_type};

    // 满时不再写入（绝不覆盖旧事件），由 ovf_cnt 留证
    wire evt_wr = push & ~full;
    wire evt_rd = pop  & ~empty;     // 空时不推进指针

    sync_fifo #(
        .W               (EVT_W),
        .DEPTH           (DEPTH),
        .ALMOST_FULL_TH  (AFULL_TH),
        .ALMOST_EMPTY_TH (1)
    ) u_evt_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (evt_wr),
        .din          (din),
        .full         (full),
        .almost_full  (),
        .rd_en        (evt_rd),
        .dout         (head),
        .empty        (empty),
        .almost_empty (),
        .data_count   ()
    );

    assign out_valid = ~empty;
    assign out_type  = head[3:0];
    assign out_value = head[19:4];
    assign out_ts    = head[51:20];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ovf_cnt <= 16'd0;
        else if (push && full) ovf_cnt <= ovf_cnt + 16'd1;
    end

endmodule
