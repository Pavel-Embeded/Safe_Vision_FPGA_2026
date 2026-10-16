// ============================================================================
// error_report.v — 全链错误汇总（Control Event Interface）
// ----------------------------------------------------------------------------
// 文件职责：
//   汇总全链错误码，按 docs/interface_spec.md §3.5 的 Control Event Interface
//   输出给 C 的 UART 日志。内部用一个深度 8 的事件 FIFO 排队，保证
//   「错误事件不允许丢弃」——放不下时明确置 evt_full 并计入 drop_cnt，
//   绝不静默吞掉。
//
// 依据：
//   docs/interface_spec.md §3.5「横切模块 / error_report」：
//     时钟域 sys_clk；err_push / err_code[7:0] / err_src[3:0] / err_ts[31:0]；
//     evt_type[3:0] / evt_value[15:0] / evt_valid / evt_full；
//     约定「错误事件不允许丢弃；满时置 evt_full 并计数」。
//   docs/interface_spec.md §一：「错误上报统一走 error_report → Control Event
//     Interface……溢出计数在 C 侧」。
//   手册 7.16.2 错误处理学习卡片：「错误标志无法清除 / 重试无上限卡死」是易错点，
//     故本模块配 16bit 的 drop_cnt 观测口（对应 §7.16.2 的 *_cnt[15:0]）。
//
// 关键设计决策：
//   1) 事件队列深度 8：足够容纳"一次上电 + 一次拔卡 + 若干坏图"的连锁错误，
//      又不会在 sys_clk 上占掉明显面积。
//   2) 队列元素 44bit = {err_ts[31:0], err_code[7:0], err_src[3:0]}：
//      时间戳一起入队——只存码不存时间会让日志无法定位"是启动期还是运行期"，
//      等于部分丢事件。V3 将时间戳通过 evt_ts 与码和来源一起原子输出。
//   3) 编码（按本任务冻结口径）：
//        evt_type[3:0]  = err_src    —— 用来源模块编号编码来源
//        evt_value[15:0]= {8'h00, err_code} —— 用错误码
//      evt_valid 直接取队列 !empty（与全链 FWFT 语义一致，见 §7 决策 D-2/D-6）。
//   4) evt_full 是电平：队列真的满了就拉高，C 侧一眼能看出"还有事件没读走"；
//      drop_cnt 则记录"满的时候又压进来几条"，是永久留证的故障计数。
//
// V3 消费契约：evt_valid && evt_ready 才弹出，反压期间码、来源、时间戳保持。
// 兼容旧具名实例：未连接 evt_ready 时不弹出。满时保留旧事件并饱和计数。
// ============================================================================

module error_report (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 错误压入 ----
    input  wire        err_push,
    input  wire [7:0]  err_code,
    input  wire [3:0]  err_src,
    input  wire [31:0] err_ts,

    // ---- Control Event Interface（交 C）----
    output wire [3:0]  evt_type,
    output wire [15:0] evt_value,
    output wire        evt_valid,
    output wire        evt_full,
    input  wire        evt_ready,
    output wire [31:0] evt_ts,

    // ---- 观测（不在 §3.5 冻结表内，仅作留证计数口）----
    output reg  [15:0] drop_cnt
);

    localparam integer EVT_W        = 44;   // {err_ts, err_code, err_src}
    localparam integer EVT_DEPTH    = 8;
    localparam integer EVT_AFULL_TH = 6;    // 提前反压阈值（almost_full 才是反压手段）
    localparam integer EVT_AEMPTY_TH= 1;

    wire [EVT_W-1:0] evt_head;
    wire             evt_empty;
    wire             evt_almost_full;

    // 队列元素布局（低位在前）：[3:0]=err_src, [11:4]=err_code, [43:12]=err_ts
    wire [43:0] push_data = {err_ts, err_code, err_src};

    // 满时不再写入，由 drop_cnt 与 evt_full 留证；绝不用新事件覆盖旧事件
    wire evt_wr = err_push & ~evt_full;

    sync_fifo #(
        .W               (EVT_W),
        .DEPTH           (EVT_DEPTH),
        .ALMOST_FULL_TH  (EVT_AFULL_TH),
        .ALMOST_EMPTY_TH (EVT_AEMPTY_TH)
    ) u_evt_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (evt_wr),
        .din          (push_data),
        .full         (evt_full),
        .almost_full  (evt_almost_full),
        .rd_en        (evt_valid && (evt_ready === 1'b1)),
        .dout         (evt_head),
        .empty        (evt_empty),
        .almost_empty (),
        .data_count   ()
    );

    // FWFT：非空即有效，队首就在 evt_head 上
    assign evt_valid = ~evt_empty;
    assign evt_type  = evt_head[3:0];
    assign evt_value = {8'h00, evt_head[11:4]};
    assign evt_ts    = evt_head[43:12];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_cnt <= 16'd0;
        end else if (err_push && evt_full) begin
            if (drop_cnt != 16'hffff) drop_cnt <= drop_cnt + 16'd1;
        end
    end

endmodule
