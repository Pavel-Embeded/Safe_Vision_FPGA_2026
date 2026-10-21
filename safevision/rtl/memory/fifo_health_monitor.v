// ============================================================================
// fifo_health_monitor.v — FIFO 健康度统计（最低水位 / underflow / overflow）
// ----------------------------------------------------------------------------
// 文件职责：
//   挂在任意一个 FIFO 的水位与握手信号上，输出三样东西：
//     1) min_level      —— 统计窗口内的【历史最低水位】
//     2) underflow_cnt  —— 读侧在空时还想读的次数
//     3) overflow_cnt   —— 写侧在满时还想写的次数
//
// 依据：
//   手册 7.12 阶段 12「带宽预算」原话：
//     「报告里只接受一种结论形式：用计数器统计一段时间内实际完成搬运的数据量，
//      除以时间得到控制器持续带宽，并同时给出该时段的 FIFO 最低水位。」
//   手册 7.13 学习卡片：水位驱动仲裁需要 video_fifo_level / wr_fifo_level；
//   手册 7.16.2 错误处理：每类异常都要有 16bit 计数器。
//   手册 7.8 过关自测：「让读侧停 100 拍，写入不丢数据且 overflow 为 0」。
//
// 关键设计决策：
//   1) min_level 的"清零"是【重新开始统计】的意思，不是把值写成 0。
//      实现上复位 / clr 后置一个"尚未采样"标志，第一个采样周期直接把
//      min_level 拉成当时的 cur_level，之后只做 min 更新。若真的把初值写成 0，
//      只要该 FIFO 不再见底，min_level 会永远是 0，这个统计就废了。
//   2) clr 只重启 min_level 统计；underflow_cnt / overflow_cnt 是累积故障计数，
//      只由 rst_n 清零——静默把故障计数抹掉是可靠性链上的大忌。
//   3) underflow 判定 = rd_en & empty；overflow 判定 = wr_en & full。
//      这两个判定都用"想读/想写"的原始请求，而不是内部已门控的 fire，
//      否则永远数不到事故。
// ============================================================================

module fifo_health_monitor (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        clr,          // 单拍：重启最低水位统计（不清故障计数）
    input  wire [15:0] data_count,   // 来自被观测 FIFO 的水位
    input  wire        empty,
    input  wire        full,
    input  wire        rd_en,        // 读侧"想读"请求
    input  wire        wr_en,        // 写侧"想写"请求

    output reg  [15:0] min_level,
    output reg  [15:0] underflow_cnt,
    output reg  [15:0] overflow_cnt,
    output wire [15:0] cur_level
);

    // 复位 / clr 之后的第一拍还没有采过样，用一个标志让首拍直接装入水位
    reg min_started;

    assign cur_level = data_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_level     <= 16'hFFFF;
            min_started   <= 1'b0;
            underflow_cnt <= 16'd0;
            overflow_cnt  <= 16'd0;
        end else if (clr) begin
            min_level   <= 16'hFFFF;
            min_started <= 1'b0;
        end else begin
            // ---- 历史最低水位 ----
            if (!min_started) begin
                min_level   <= data_count;
                min_started <= 1'b1;
            end else if (data_count < min_level) begin
                min_level <= data_count;
            end

            // ---- 读空还想读 ----
            if (rd_en && empty) begin
                underflow_cnt <= underflow_cnt + 16'd1;
            end

            // ---- 写满还想写 ----
            if (wr_en && full) begin
                overflow_cnt <= overflow_cnt + 16'd1;
            end
        end
    end

endmodule