// ============================================================================
// video_read_dma.v — 视频显示读 DMA（SafeVision 阶段 11/12 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.11「阶段 11：Burst 突发传输」
//         · "绝不能请求一个像素 → 等 → 再请求一个像素"，SDRAM 的 ACT/PRE 开销会把
//           带宽吃光；正确做法是一次 Burst 读一长串塞进 FIFO
//         · 单次目标长度 64 word / 256 Byte（实际值由带宽与水位标定）
//       手册 7.12 带宽预算：单图显示读 ≈ 36.864 MB/s，必须靠水位驱动预取维持
//       docs/interface_spec.md §3.4 / §4.1（像素 FIFO，D-2 FWFT）
//
// 职责：按【前帧基地址 frame_base】把一个 640×480 RGB565 帧（614400 Byte）
//       用突发读的方式搬进像素 FIFO。核心是【水位驱动预取】：
//          pix_fifo_level < LOW_WATER 就发起一次 BURST_WORDS word 的突发读，
//          整突发先落进内部 landing buffer，再逐个像素推入 FIFO。
//
// ★ 为什么要有内部 landing buffer（这是本模块的关键设计决策）
//   仲裁器读通道没有反压（mem_arbiter 只按 mem_ready 连续搬），一次突发会
//   1 word/cycle 地灌过来；而本模块按任务要求对外是 16bit/像素 的 fifo_wr 口，
//   1 word = 2 像素，若边收边拆会供不上速率。于是先把整突发收进
//   BURST_WORDS 深的 32bit 缓冲，再从缓冲慢慢拆成 16bit 像素喂 FIFO——
//   记忆法是"先囤一整段，再慢慢拆"。
//
// ★ FIFO 余量：只在 level < LOW_WATER 且 level + BURST_WORDS*2 <= DEPTH 时才发突发，
//   保证整突发塞进去不会溢出（预取策略把"溢出"在结构上排除）。
//
// ★ 实测踩过的坑：landing buffer 一开始起名 `buf`，ModelSim 直接报
//   "syntax error, unexpected buf"——因为 buf 是 Verilog 内建门原语名。
//   已改名 rd_buf。RTL 里取名字别撞内建原语（buf/not/and/or/...）。
// ============================================================================
`include "safevision_defs.vh"

module video_read_dma #(
    parameter integer BURST_WORDS = 16,     // 单次突发 word 数（O-3 建议 16，待实测）
    parameter integer PIX_DEPTH   = 512,    // 像素 FIFO 深度（16bit 项）
    parameter integer LOW_WATER   = 64      // 低水位：低于它就预取
)(
    input  wire        clk,                 // mem_clk 125MHz
    input  wire        rst_n,

    // ---- 控制 ----
    input  wire        start,               // 单拍：开始读一帧
    input  wire [31:0] frame_base,          // 当前显示帧基地址（逻辑字节地址）
    input  wire [15:0] pix_fifo_level,      // 像素 FIFO 当前水位

    // ---- mem 事务口（接 memory_arbiter 读通道）----
    output reg         rd_req,
    output reg  [31:0] rd_addr,
    output reg  [15:0] rd_len,
    input  wire        rd_ack,              // 单拍：突发被受理
    input  wire        rd_busy,
    input  wire [31:0] rd_data,
    input  wire        rd_data_valid,

    // ---- 像素 FIFO 写口（16bit / 像素）----
    output reg  [15:0] fifo_wr_data,
    output reg         fifo_wr_en,

    // ---- 状态 ----
    output reg  [31:0] rd_bytes_cnt,        // 本帧已读字节数
    output reg         active,              // 高：一帧正在搬运
    output reg         done                 // 单拍：一帧搬运完成
);

    // ------------------------------------------------------------------------
    // 常量（640×480 RGB565，2 Byte/pixel）
    // ------------------------------------------------------------------------
    localparam integer FRAME_W     = 640;
    localparam integer FRAME_H     = 480;
    localparam [31:0]  FRAME_BYTES = FRAME_W * FRAME_H * 2;        // 614400
    localparam [31:0]  BURST_BYTES = BURST_WORDS * 4;             // 突发字节数
    localparam [15:0]  HIGH_WATER  = PIX_DEPTH - BURST_WORDS * 2; // 预留整突发像素的空间

    localparam [2:0] V_IDLE    = 3'd0,
                     V_CHECK   = 3'd1,
                     V_WAITACK = 3'd2,
                     V_COLLECT = 3'd3,
                     V_DRAIN   = 3'd4;

    reg  [2:0]  state;
    reg  [31:0] base;                       // 本帧基地址锁存
    reg  [31:0] rd_buf [0:BURST_WORDS-1];   // 突发 landing buffer（避开保留字 buf）
    reg  [4:0]  collect_cnt;                // 已收 word 数
    reg  [4:0]  drain_word;                 // 正在拆的 word
    reg         drain_half;                 // 0=低 16bit（左像素）1=高 16bit

    // ------------------------------------------------------------------------
    // 主逻辑
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= V_IDLE;
            base         <= 32'd0;
            collect_cnt  <= 5'd0;
            drain_word   <= 5'd0;
            drain_half   <= 1'b0;
            rd_req       <= 1'b0;
            rd_addr      <= 32'd0;
            rd_len       <= 16'd0;
            fifo_wr_data <= 16'd0;
            fifo_wr_en   <= 1'b0;
            rd_bytes_cnt <= 32'd0;
            active       <= 1'b0;
            done         <= 1'b0;
        end else begin
            // 默认值：单拍脉冲清零 / FIFO 写使能默认拉低
            done       <= 1'b0;
            fifo_wr_en <= 1'b0;

            case (state)
            // ------------------------------------------------------------------
            V_IDLE: begin
                if (start) begin
                    base         <= frame_base;
                    rd_bytes_cnt <= 32'd0;
                    active       <= 1'b1;
                    rd_req       <= 1'b0;
                    state        <= V_CHECK;
                end
            end
            // ---- 水位驱动预取：低于低水位且 FIFO 有余量就发起一次突发 ----------
            V_CHECK: begin
                if (rd_bytes_cnt >= FRAME_BYTES) begin
                    active <= 1'b0;
                    done   <= 1'b1;             // 一帧搬完
                    state  <= V_IDLE;
                end else if ((pix_fifo_level < LOW_WATER) &&
                             (pix_fifo_level <= HIGH_WATER)) begin
                    rd_addr <= base + rd_bytes_cnt;
                    rd_len  <= BURST_WORDS[15:0];
                    rd_req  <= 1'b1;
                    state   <= V_WAITACK;
                end
            end
            // ---- 等仲裁受理 --------------------------------------------------
            V_WAITACK: begin
                if (rd_ack) begin
                    rd_req      <= 1'b0;
                    collect_cnt <= 5'd0;
                    state       <= V_COLLECT;
                end
            end
            // ---- 整突发收进 landing buffer（1 word/cycle）---------------------
            V_COLLECT: begin
                if (rd_data_valid) begin
                    rd_buf[collect_cnt] <= rd_data;
                    if (collect_cnt == (BURST_WORDS-1)) begin
                        rd_bytes_cnt <= rd_bytes_cnt + BURST_BYTES;
                        drain_word   <= 5'd0;
                        drain_half   <= 1'b0;
                        state        <= V_DRAIN;
                    end else begin
                        collect_cnt <= collect_cnt + 5'd1;
                    end
                end
            end
            // ---- 拆成 16bit 像素推入 FIFO ------------------------------------
            V_DRAIN: begin
                fifo_wr_en   <= 1'b1;
                fifo_wr_data <= drain_half ? rd_buf[drain_word][31:16]
                                           : rd_buf[drain_word][15:0];
                if (drain_half) begin
                    if (drain_word == (BURST_WORDS-1)) begin
                        state <= V_CHECK;       // 本突发拆完，回去看水位
                    end else begin
                        drain_word <= drain_word + 5'd1;
                        drain_half <= 1'b0;
                    end
                end else begin
                    drain_half <= 1'b1;         // 先出低 16bit，再出高 16bit
                end
            end
            default: state <= V_IDLE;
            endcase
        end
    end

endmodule