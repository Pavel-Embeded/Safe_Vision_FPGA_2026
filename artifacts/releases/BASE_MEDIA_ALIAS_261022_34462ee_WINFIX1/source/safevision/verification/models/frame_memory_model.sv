// ============================================================================
// frame_memory_model.sv — SDRAM 行为级仿真模型（★ 仅仿真，不综合）
// ----------------------------------------------------------------------------
// 依据：手册 7.9「阶段 9：SDRAM 原理」、7.10「Frame Buffer 帧缓存」
//       docs/interface_spec.md §3.4（mem_ctrl 接口）与 §一（只传逻辑字节地址）
//
// 容量：8 MiB = 2M × 32bit（手册 7.12 表 7-3：片内 SDRAM 总量 8,388,608 Byte）
//      地址口径：本模型按【32bit word 地址】索引，1 word = 4 Byte。
//      业务侧给的是逻辑【字节地址】，由 mem_ctrl 做 addr>>2 后送到这里。
//
// ----------------------------------------------------------------------------
// ★ 手册要求背下来的四条命令与四个时序参数（7.9 原文口径）
//   四条命令：
//     ACTIVATE -- 激活某行到灵敏放大器；必须等 tRCD 之后才可读写。
//     READ/WRITE -- 在已激活行内按列读或写；READ 数据在 CL 拍之后才输出。
//     PRECHARGE -- 关行回写；必须等 tRP 之后才可再次 ACTIVATE。
//     REFRESH   -- 定期刷新防漏电；每次刷新占用 tRFC 时间。
//   四个时序参数：
//     tRCD -- ACTIVATE 到 READ/WRITE 之间的最小间隔（行激活延迟）
//     CL   -- CAS 延迟，READ 命令发出到数据出现在总线上所需拍数
//     tRP  -- PRECHARGE 到下一次 ACTIVATE 之间的最小间隔（预充电延迟）
//     tRFC -- 一次 REFRESH 占用总线的时间（刷新周期时间）
//   行命中可连续读写；跨行必须先 PRECHARGE 再 ACTIVATE（手册 7.9）。
//
// ★ 本模型是【行为级简化】：只保留"请求 -> 若干拍后给数据"的确定性行为，
//   不模拟 tRCD / CL / tRP / tRFC 的精确拍数，也不模拟行/列/Bank 三维组织与
//   刷新开销。**真实时序由安路官方 SDRAM IP 负责**（手册 7.9：第一版不要
//   手写完整 SDRAM PHY，最终使用官方 IP wrapper）。
//   这样做的目的：让 frame_writer / mem_ctrl 的接口与地址映射能被独立验证，
//   而不把仿真时间耗在 PHY 时序细节上。
//
// ★ 实测/文档踩过的坑（手册 7.9 易错点）：
//   1) 把 SDRAM 当 SRAM 用：SDRAM 有激活/预充电/刷新，地址未按 32bit 对齐会
//      直接错位——本模型强制按 word 索引，字节地址的低 2 位在 mem_ctrl 里丢弃。
//   2) 忽略刷新导致长跑后偶发错误——本模型不建模刷新，**不能用来评估长稳性**，
//      真实刷新由官方 IP 承担。
// ============================================================================

module frame_memory_model #(
    parameter integer ADDR_BITS   = 21,   // 字地址位宽 -> 2^21 = 2M words = 8 MiB
    parameter integer INIT_CYCLES = 200,  // 上电到 init_done 的固定拍数（可参数化）
    parameter integer RD_LATENCY  = 2     // 读命令到 rdata_valid 的拍数（简化，非真实 CL）
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 请求/响应 ----
    input  wire        req,           // 访问请求
    input  wire        wr,            // 1=写 0=读
    input  wire [31:0] addr,          // ★ 字地址（word 索引），不是字节地址
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,         // 字节选通
    output reg  [31:0] rdata,
    output reg         rdata_valid,   // 单拍
    output wire        ready,         // 可接受新请求
    output reg         init_done      // 上电初始化完成
);

    // ------------------------------------------------------------------------
    // 存储体：2M × 32bit
    // ------------------------------------------------------------------------
    localparam integer DEPTH = (1 << ADDR_BITS);
    reg [31:0] mem [0:DEPTH-1];

    // ------------------------------------------------------------------------
    // 状态机（行为级：INIT -> IDLE -> (WR 占 1 拍 | RD 等 RD_LATENCY 拍)）
    // ------------------------------------------------------------------------
    localparam [1:0] S_INIT = 2'd0,
                     S_IDLE = 2'd1,
                     S_WR   = 2'd2,
                     S_RD   = 2'd3;

    reg [1:0] state;
    reg [7:0] init_cnt;
    reg [7:0] rd_cnt;
    reg [ADDR_BITS-1:0] rd_addr_q;

    // ready：只在初始化完成且空闲时可接受请求（等效于"总线上不忙"）
    assign ready = init_done && (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_INIT;
            init_cnt    <= 8'd0;
            rd_cnt      <= 8'd0;
            rd_addr_q   <= {ADDR_BITS{1'b0}};
            rdata       <= 32'd0;
            rdata_valid <= 1'b0;
            init_done   <= 1'b0;
        end else begin
            // 默认清零：rdata_valid 只做单拍脉冲
            rdata_valid <= 1'b0;

            case (state)
                // ---- 上电固定拍数后拉高 init_done ----
                S_INIT: begin
                    if (init_cnt >= (INIT_CYCLES - 1)) begin
                        init_done <= 1'b1;
                        state     <= S_IDLE;
                    end else begin
                        init_cnt <= init_cnt + 8'd1;
                    end
                end

                // ---- 空闲：接受请求 ----
                S_IDLE: begin
                    if (req) begin
                        if (wr) begin
                            // 写：带字节选通
                            if (wstrb[0]) mem[addr[ADDR_BITS-1:0]][7:0]   <= wdata[7:0];
                            if (wstrb[1]) mem[addr[ADDR_BITS-1:0]][15:8]  <= wdata[15:8];
                            if (wstrb[2]) mem[addr[ADDR_BITS-1:0]][23:16] <= wdata[23:16];
                            if (wstrb[3]) mem[addr[ADDR_BITS-1:0]][31:24] <= wdata[31:24];
                            state <= S_WR;
                        end else begin
                            rd_addr_q <= addr[ADDR_BITS-1:0];
                            rd_cnt    <= RD_LATENCY;
                            state     <= S_RD;
                        end
                    end
                end

                // ---- 写占用 1 拍 ----
                S_WR: begin
                    state <= S_IDLE;
                end

                // ---- 读：等 RD_LATENCY 拍后出数据 ----
                S_RD: begin
                    if (rd_cnt <= 8'd1) begin
                        rdata       <= mem[rd_addr_q];
                        rdata_valid <= 1'b1;
                        state       <= S_IDLE;
                    end else begin
                        rd_cnt <= rd_cnt - 8'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Backdoor 读：供 testbench 校验"写进去的数据在正确的 word 地址上"
    //   用法： frame_memory_model u_sdram(...);  u_sdram.peek_word(word_addr, value);
    //   word_addr 为字地址（与端口 addr 同口径）
    // ------------------------------------------------------------------------
    task peek_word;
        input  [31:0] a;
        output [31:0] d;
        begin
            d = mem[a[ADDR_BITS-1:0]];
        end
    endtask

endmodule