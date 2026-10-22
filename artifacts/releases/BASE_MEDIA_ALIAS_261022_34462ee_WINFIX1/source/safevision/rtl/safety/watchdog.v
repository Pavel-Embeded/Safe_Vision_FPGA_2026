// ============================================================================
// watchdog.v — 三路独立看门狗（手册 8.4）
// ----------------------------------------------------------------------------
// 监控"被监控对象是否在推进"。喂狗信号必须来自**被监控的真实活动**：
//   frame_heartbeat  : 视频侧每完成一帧一次（A 产生）
//   mem_heartbeat    : SDRAM 控制器每完成一个事务一次（B 产生）
//   progress_token   : 媒体状态机每次状态推进一次（B 产生）
//
// ★ 红线一：绝不用同源自由运行计数器喂狗（= 自己给自己发合格证）；
//           本模块只把上面三根真实活动线当作喂狗源。
// ★ 红线二：三个心跳的阈值**互不相同**（各自独立参数），共用阈值只会
//           "正常操作被误判"或"真卡死判不出来"。
// ★ 红线三：wdt_timeout 一旦锁存，**只能由全局复位或 recover_ack 清除**，
//           绝不允许"下一次心跳自动清掉"——那会把一次真实卡死伪装成从未发生。
//
// timeout 四条件（手册 8.4 原话）：
//   复位：全局复位或该监控域复位时 timer 与 wdt_timeout 一起归零。
//   锁存：心跳未到而 timer 记到 TIMEOUT_N 时置 wdt_timeout=1，并锁存
//         fault_reason 与故障时刻；清除前不得覆盖（首因优先）。
//   清除：只由全局复位或 recover_ack。
//   恢复：清除后只复位媒体链并重新扫描（由 playback_fsm 的 RECOVER 执行），
//         失败则回 SAFE。
//
// 时钟域 : sys_clk（控制域）
// 参数   : 三路阈值默认落在手册要求的 100–500 ms 区间（100 MHz 时钟）：
//          frame 100 ms / mem 200 ms / progress 500 ms（设计目标，待实测）。
//          阈值必须大于正常路径的最大停顿（如一次正常 SDRAM 刷新等待）。
// ============================================================================
`include "fault_code_defs.vh"

module watchdog #(
    parameter integer CLK_HZ       = 100000000,   // 本监控域时钟频率
    parameter integer TO_FRAME_CYC = 10000000,    // 100 ms @100 MHz
    parameter integer TO_MEM_CYC   = 20000000,    // 200 ms @100 MHz
    parameter integer TO_PROG_CYC  = 50000000,    // 500 ms @100 MHz
    parameter [7:0]   CODE_FRAME   = `ERR_MEDIA_INVALID,   // 视频不推进
    parameter [7:0]   CODE_MEM     = `ERR_SD_IO,           // 存储/内存事务不推进
    parameter [7:0]   CODE_PROG    = `ERR_MEDIA_INVALID    // 媒体状态机不推进
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        recover_ack,        // 唯一显式清除入口

    // ---- 被监控的真实活动（喂狗源）----
    input  wire        frame_heartbeat,
    input  wire        mem_heartbeat,
    input  wire        progress_token,

    // ---- 结果 ----
    output reg         wdt_timeout,
    output reg  [1:0]  wdt_channel,        // 0=frame 1=mem 2=progress（首因）
    output reg  [7:0]  wdt_reason,         // 锁存的对外主码
    output reg  [31:0] wdt_ts              // 故障时刻（ms）
);

    function integer counter_width;
        input integer n;
        integer v;
        begin
            counter_width = 1;
            for (v = n-1; v > 1; v = v >> 1) counter_width = counter_width + 1;
        end
    endfunction
    localparam integer MS_DIV = (CLK_HZ >= 1000) ? (CLK_HZ/1000) : 1;

    localparam integer TW_F = counter_width(TO_FRAME_CYC);
    localparam integer TW_M = counter_width(TO_MEM_CYC);
    localparam integer TW_P = counter_width(TO_PROG_CYC);

    reg [31:0]      ms_cnt;
    reg [31:0]      ts_now;                 // 毫秒时基
    reg [TW_F-1:0]  t_frame;
    reg [TW_M-1:0]  t_mem;
    reg [TW_P-1:0]  t_prog;
    reg             f_frame, f_mem, f_prog;

    // ---- 毫秒时基 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_cnt <= 32'd0; ts_now <= 32'd0; end
        else if (ms_cnt == MS_DIV-1) begin ms_cnt <= 32'd0; ts_now <= ts_now + 32'd1; end
        else ms_cnt <= ms_cnt + 32'd1;
    end

    // ---- 三路独立计数器（各自阈值；心跳喂狗；锁存后冻结）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_frame <= 0; f_frame <= 1'b0;
        end else if (recover_ack) begin
            t_frame <= 0; f_frame <= 1'b0;
        end else if (frame_heartbeat) begin
            t_frame <= 0;                        // 真实活动才喂狗
        end else if (f_frame) begin
            t_frame <= t_frame;                  // 已锁存：不再计数
        end else if (t_frame == TO_FRAME_CYC-1) begin
            f_frame <= 1'b1;                     // 锁存
        end else t_frame <= t_frame + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_mem <= 0; f_mem <= 1'b0;
        end else if (recover_ack) begin
            t_mem <= 0; f_mem <= 1'b0;
        end else if (mem_heartbeat) begin
            t_mem <= 0;
        end else if (f_mem) begin
            t_mem <= t_mem;
        end else if (t_mem == TO_MEM_CYC-1) begin
            f_mem <= 1'b1;
        end else t_mem <= t_mem + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_prog <= 0; f_prog <= 1'b0;
        end else if (recover_ack) begin
            t_prog <= 0; f_prog <= 1'b0;
        end else if (progress_token) begin
            t_prog <= 0;
        end else if (f_prog) begin
            t_prog <= t_prog;
        end else if (t_prog == TO_PROG_CYC-1) begin
            f_prog <= 1'b1;
        end else t_prog <= t_prog + 1'b1;
    end

    wire any_to = f_frame | f_mem | f_prog;

    // ---- 结果锁存（首因优先；只由全局复位或 recover_ack 清除）----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdt_timeout <= 1'b0; wdt_channel <= 2'd0; wdt_reason <= 8'h00; wdt_ts <= 32'd0;
        end else if (recover_ack) begin
            wdt_timeout <= 1'b0; wdt_channel <= 2'd0; wdt_reason <= 8'h00; wdt_ts <= 32'd0;
        end else if (any_to && !wdt_timeout) begin
            wdt_timeout <= 1'b1;
            if (f_frame)      begin wdt_channel <= 2'd0; wdt_reason <= CODE_FRAME; end
            else if (f_mem)   begin wdt_channel <= 2'd1; wdt_reason <= CODE_MEM;   end
            else              begin wdt_channel <= 2'd2; wdt_reason <= CODE_PROG;  end
            wdt_ts <= ts_now;
        end
    end

    // synthesis translate_off
    initial if (TO_FRAME_CYC < 1 || TO_MEM_CYC < 1 || TO_PROG_CYC < 1 ||
                TO_FRAME_CYC == TO_MEM_CYC || TO_MEM_CYC == TO_PROG_CYC ||
                TO_FRAME_CYC == TO_PROG_CYC)
        $fatal(1, "watchdog invalid thresholds (must be >=1 and mutually distinct)");
    // synthesis translate_on

endmodule
