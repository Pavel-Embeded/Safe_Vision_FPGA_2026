// ============================================================================
// fault_manager.v — 故障首因粘滞 / 等级判定 / 媒体复位隔离（手册 8.7 表 8-4）
// ----------------------------------------------------------------------------
// 职责：
//   1) **首因粘滞**：第一条真故障的主码和时刻锁存后保持不变；当前等级
//      可随后续更严重故障升级。早先 WARNING 绝不能屏蔽后来的 SAFE/FATAL。
//   2) **等级判定**：表 8-4 的五级 INFO / WARNING / DEGRADED / SAFE / FATAL。
//   3) **媒体复位隔离**：media_rst_req 只请求复位"媒体链"，绝不允许并进
//      视频时序 / 安全画面 / HDMI PHY 的复位（TC-C-SAFE：媒体复位不影响安全画面）。
//
// 清除规则（与手册 8.7 一致）：
//   可恢复故障的原因锁存只由 recover_ack 清除，且必须与"恢复条件成对出现"——
//   本模块在清除的同一拍给出 media_rst_req，由 playback_fsm 的 RECOVER 执行
//   "只复位媒体链并重新扫描"。
//   FATAL（视频 PLL / HDMI PHY 失效）**只由全局复位清除**，不参与可恢复承诺：
//   片上逻辑在这些部件失效时根本没有输出能力，任何设计都无法保证画面。
//
// 时钟域 : sys_clk（控制域）
// ============================================================================
`include "fault_code_defs.vh"

module fault_manager #(
    parameter integer CLK_HZ = 100000000
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 故障源 ----
    input  wire        err_push,        // 一条新故障（可能来自 error_report / B 链）
    input  wire [7:0]  err_code,        // 对外主码 ERR_*
    input  wire [2:0]  err_level,       // 该故障的等级（见表 8-4）
    input  wire        wdt_timeout,     // 看门狗锁存
    input  wire [7:0]  wdt_reason,      // 看门狗锁存的原因码
    input  wire        media_fatal,     // 视频 PLL / HDMI PHY 失效（只能标 FATAL）

    // ---- 清除 ----
    input  wire        recover_ack,     // 显式恢复条件（与恢复动作成对）

    // ---- 输出 ----
    output reg  [7:0]  fault_code,      // 首因对外主码
    output reg  [2:0]  fault_level,     // 当前最高等级；主码和时刻仍保留首因
    output reg         fault_valid,     // 首因已锁存
    output reg         fatal,           // FATAL 锁存（只由全局复位清除）
    output reg  [31:0] fault_ts,        // 首因时刻（ms）
    output reg         media_rst_req    // 只复位媒体链（单拍）
);
    localparam integer MS_DIV = (CLK_HZ >= 1000) ? (CLK_HZ/1000) : 1;

    // 表 8-4 的五个等级
    localparam [2:0] LV_INFO     = 3'd0;   // 可选 WAV 缺失等
    localparam [2:0] LV_WARNING  = 3'd1;   // 一个 BMP 非法但仍有四图
    localparam [2:0] LV_DEGRADED = 3'd2;   // 拔卡但四图已缓存
    localparam [2:0] LV_SAFE     = 3'd3;   // SDRAM BIST 失败 / 连续欠载 / 外部告警
    localparam [2:0] LV_FATAL    = 3'd4;   // 视频 PLL / HDMI PHY 失效

    reg [31:0] ms_cnt;
    reg [31:0] ts_now;
    // The watchdog timeout is sticky and clears on THIS same recover_ack edge.
    // Requiring its old value to be zero would deadlock the paired clear.
    wire can_clear = recover_ack & ~fatal & ~media_fatal & ~err_push;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_cnt <= 32'd0; ts_now <= 32'd0; end
        else if (ms_cnt == MS_DIV-1) begin ms_cnt <= 32'd0; ts_now <= ts_now + 32'd1; end
        else ms_cnt <= ms_cnt + 32'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_code <= 8'h00; fault_level <= LV_INFO; fault_valid <= 1'b0;
            fatal <= 1'b0; fault_ts <= 32'd0; media_rst_req <= 1'b0;
        end else begin
            media_rst_req <= 1'b0;
            if (media_fatal) fatal <= 1'b1;   // FATAL 只由全局复位清除
            if (err_push && err_level==LV_FATAL) fatal <= 1'b1;

            if (can_clear) begin
                // 恢复条件成对：清首因锁存 + 请求只复位媒体链
                fault_code <= 8'h00; fault_level <= LV_INFO; fault_valid <= 1'b0;
                fault_ts <= 32'd0; media_rst_req <= 1'b1;
            end else if (!fault_valid) begin
                // 首因锁存：第一条真故障胜出，之后不再被覆盖
                if (err_push) begin
                    fault_code <= err_code; fault_level <= err_level;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end else if (wdt_timeout) begin
                    fault_code <= wdt_reason; fault_level <= LV_SAFE;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end else if (media_fatal) begin
                    fault_code <= 8'h00; fault_level <= LV_FATAL;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end
            end else if (media_fatal) begin
                fault_level <= LV_FATAL;      // 已锁存原因升级为 FATAL，码不覆盖
            end else if (wdt_timeout && fault_level<LV_SAFE) begin
                fault_level<=LV_SAFE;
            end else if (err_push && err_level>fault_level) begin
                fault_level<=err_level;
            end
        end
    end

endmodule
