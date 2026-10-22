// ============================================================================
// key_debounce.v — 多路按键/拨码聚合：每路复用 input_sync，再聚合成一个事件
// ----------------------------------------------------------------------------
// 依据：手册 8.1（按键/拨码/外部告警都是异步且可能抖动）与 8.7 表 8-3
//       （KEY1 切下一张、KEY2 启停自动播放）。
//
// 结构：KEYS 路 input_sync（两级同步 + 去抖 + 边沿 + pending），
//       聚合出 press_any（单拍）、锁存的事件键号 evt_key、以及 evt_pending。
//       同一拍多个按键时按"最低编号优先"（纯组合优先编码），锁存后保持不变，
//       直到 FSM 用 evt_clear 取走。
//
// ★ 复用而非重写：两级同步 / 去抖 / 边沿检测算法在 input_sync 里只保留一份，
//   本模块是聚合包装（仓库约定：公共算法只保留一份）。
// ★ 采用非 ANSI 端口写法：evt_key 的位宽 KW 依赖参数 KEYS 计算，
//   必须让 localparam 声明先于端口声明（ANSI 写法无法保证这一点）。
// ============================================================================

module key_debounce (
    clk, rst_n, key_async, evt_clear, tick,
    key_level, press_vec, press_any, evt_key, evt_pending
);
    parameter integer USE_TICK=0;
    parameter integer KEYS        = 4;
    parameter integer DEB_N       = 2000000;  // 20 ms @100 MHz
    parameter         RESET_LEVEL = 1'b0;

    function integer clog2;
        input integer n;
        integer v;
        begin
            clog2 = 1;
            for (v = n-1; v > 1; v = v >> 1) clog2 = clog2 + 1;
        end
    endfunction
    localparam integer KW = clog2(KEYS);

    input wire tick;
    input  wire            clk;
    input  wire            rst_n;
    input  wire [KEYS-1:0] key_async;
    input  wire            evt_clear;     // FSM 取走事件后拉高
    output wire [KEYS-1:0] key_level;     // 各路去抖后稳定电平
    output wire [KEYS-1:0] press_vec;     // 各路上升沿，单拍
    output wire            press_any;     // 任一按键按下，单拍
    output reg  [KW-1:0]   evt_key;       // 锁存的事件键号（随 evt_pending 有效）
    output reg             evt_pending;   // 事件锁存：置位后保持，直到 evt_clear

    genvar g;
    generate
        for (g = 0; g < KEYS; g = g + 1) begin : g_key
            input_sync #(
                .USE_TICK(USE_TICK),.DEB_N       (DEB_N),
                .RESET_LEVEL (RESET_LEVEL)
            ) u_ch (
                .tick(tick),.clk         (clk),
                .rst_n       (rst_n),
                .async_in    (key_async[g]),
                .evt_clear   (evt_clear),
                .press       (press_vec[g]),
                .level       (key_level[g]),
                .evt_pending (/* 单路 pending 由本模块统一聚合，不单独引出 */)
            );
        end
    endgenerate

    // 纯组合优先编码：最低编号的按键优先（循环从高到低，最后一次赋值最低位胜出）
    integer i;
    reg [KW-1:0] key_sel;
    always @* begin
        key_sel = {KW{1'b0}};
        for (i = KEYS-1; i >= 0; i = i - 1)
            if (press_vec[i]) key_sel = i[KW-1:0];
    end

    assign press_any = |press_vec;

    // 事件锁存：新按下置位并锁存键号；evt_clear 清除（置位优先，不丢新事件）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            evt_key <= {KW{1'b0}};
            evt_pending <= 1'b0;
        end else if (press_any) begin
            evt_key <= key_sel;
            evt_pending <= 1'b1;
        end else if (evt_clear) begin
            evt_pending <= 1'b0;
        end
    end

endmodule
