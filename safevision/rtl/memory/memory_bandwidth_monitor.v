// ============================================================================
// memory_bandwidth_monitor.v — SDRAM 侧带宽实测（按统计窗口）
// ----------------------------------------------------------------------------
// 文件职责：
//   统计一个固定长度窗口内实际完成搬运的读/写字节数，算出该窗口的持续带宽，
//   并累计从复位以来的总搬运量。它是"A 只需要带宽就能读到数据"的量化依据。
//
// 依据：
//   手册 7.12 阶段 12「带宽预算（B 的核心比赛能力）」：
//     「500 MB/s 是理论峰值，不是可以写进报告的性能结论……报告里只接受一种
//      结论形式：用计数器统计一段时间内实际完成搬运的数据量，除以时间得到
//      控制器持续带宽，并同时给出该时段的 FIFO 最低水位。」
//   手册 7.12 表 7-4：各场景验收门槛均以"计数器 + 实际测量"为口径。
//
// ★ 带宽计算公式（写在注释里，便于评审问答直接引用）：
//       MB/s = bytes / cycles * clk_MHz
//   推导：bytes/cycles 是"每拍搬运字节数"；clk_MHz 表示每秒有 clk_MHz 百万拍，
//   两者相乘 = 每微秒搬运的字节数 = MB/s（1 MB = 1e6 Byte）。
//   例：4 Byte/拍 @125 MHz => 4 * 125 = 500 MB/s（对应手册 7.12 的理论峰值）。
//
// 关键设计决策：
//   1) window_cycles 是输入而不是参数，便于按场景选窗口（如 1 ms / 10 ms /
//      1 s 对应 125_000 / 1_250_000 / 125_000_000 拍），也便于 TB 用小窗口加速。
//   2) 带宽在窗口结束的同一拍算出并锁存，window_done 只脉冲一拍；
//      下游（UART 日志 / C 侧）看到 window_done 时读到的带宽就是本窗口结果。
//   3) 乘法与除法用 64bit 中间量：win_bytes(最大约 5e8) * clk_MHz(125) 会溢出
//      32bit，直接用 32bit 相乘会让高带宽场景算出错误结果。
//      该乘除法只在窗口结束时使用，属于"低频统计逻辑"，不进关键路径；
//      若综合资源紧张，可改成只输出 bytes+cycles 由软核除。
//   4) 窗口长度非法（0）时不做任何统计，避免除零得到 X 把日志污染成未知态。
// ============================================================================

module memory_bandwidth_monitor #(
    parameter integer CLK_MHZ = 125
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 每拍搬运量 ----
    input  wire [31:0] wr_bytes,     // 本拍写入字节数
    input  wire        wr_valid,
    input  wire [31:0] rd_bytes,     // 本拍读出字节数
    input  wire        rd_valid,

    // ---- 统计窗口（拍）----
    input  wire [31:0] window_cycles,

    // ---- 结果 ----
    output reg  [31:0] rd_bytes_total,
    output reg  [31:0] wr_bytes_total,
    output reg  [31:0] rd_bw_mbps,
    output reg  [31:0] wr_bw_mbps,
    output reg         window_done    // 单拍脉冲：一个窗口结束
);

    localparam [63:0] CLK_MHZ_W = CLK_MHZ;   // 零扩展到 64bit，避免乘法溢出

    reg [31:0] cyc;        // 窗口内已过的拍数，0 .. window_cycles-1
    reg [31:0] win_rd;     // 本窗口累计读字节
    reg [31:0] win_wr;     // 本窗口累计写字节

    // 含本拍的累计值（窗口最后一拍要用它算结果）
    wire [31:0] rd_acc_next = win_rd + (rd_valid ? rd_bytes : 32'd0);
    wire [31:0] wr_acc_next = win_wr + (wr_valid ? wr_bytes : 32'd0);

    // MB/s = bytes / cycles * clk_MHz，用 64bit 中间量防溢出
    wire [63:0] rd_bw_calc = (window_cycles == 32'd0) ? 64'd0
                           : ({{32{1'b0}}, rd_acc_next} * CLK_MHZ_W)
                             / {{32{1'b0}}, window_cycles};
    wire [63:0] wr_bw_calc = (window_cycles == 32'd0) ? 64'd0
                           : ({{32{1'b0}}, wr_acc_next} * CLK_MHZ_W)
                             / {{32{1'b0}}, window_cycles};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cyc            <= 32'd0;
            win_rd         <= 32'd0;
            win_wr         <= 32'd0;
            rd_bytes_total <= 32'd0;
            wr_bytes_total <= 32'd0;
            rd_bw_mbps     <= 32'd0;
            wr_bw_mbps     <= 32'd0;
            window_done    <= 1'b0;
        end else begin
            window_done <= 1'b0;               // 默认单拍脉冲

            if (window_cycles == 32'd0) begin
                // 非法窗口：不统计，保持上次结果
                cyc <= 32'd0;
            end else if (cyc == window_cycles - 32'd1) begin
                // ---- 本拍是窗口最后一拍：结算 ----
                cyc            <= 32'd0;
                win_rd         <= 32'd0;
                win_wr         <= 32'd0;
                rd_bytes_total <= rd_bytes_total + rd_acc_next;
                wr_bytes_total <= wr_bytes_total + wr_acc_next;
                rd_bw_mbps     <= rd_bw_calc[31:0];
                wr_bw_mbps     <= wr_bw_calc[31:0];
                window_done    <= 1'b1;
            end else begin
                cyc    <= cyc + 32'd1;
                win_rd <= rd_acc_next;
                win_wr <= wr_acc_next;
            end
        end
    end

endmodule