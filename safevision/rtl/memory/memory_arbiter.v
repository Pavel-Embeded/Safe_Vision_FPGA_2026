// ============================================================================
// memory_arbiter.v — SDRAM 访问仲裁器（SafeVision 阶段 13 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.13「阶段 13：Arbiter 仲裁器」
//         · 第一版固定优先级 Video Read > Frame Write > SD
//         · 无论哪种策略都要加两条硬约束：
//           ① 单次占用不超过 N 个突发；
//           ② 每个主设备有"最长等待时间"计数器，超限即临时提升优先级（防饥饿）
//         · 水位驱动动态优先级（LOW_WM / HIGH_WM）—— 阈值是设计目标，待实测
//       手册 7.11「绝不能请求一个像素等一次」→ 仲裁以【突发】为粒度，只在突发边界切换
//       docs/interface_spec.md §3.4 mem_arbiter（端口冻结）+ §一 CDC/握手约定
//
// 职责：三个主设备（Video Read / Frame Write / SD 调试）分时复用同一个 SDRAM
//       端口，对外用 req/ack/busy 握手，对下用 mem_req/mem_ready 事务口接 mem_ctrl。
//
// ★ 设计要点
//   1) 传输模型：一次 req = 一个突发（rd_len / wr_len 个 32bit word）。
//      仲裁只在【突发边界】发生；一个突发一旦开始就让 mem_ctrl 连续搬完，
//      绝不中途切换（手册 7.13 易错点：切换粒度过细反复打断长突发）。
//   2) 单次 grant 连续突发上限 N = MAX_BURSTS：达到上限后若还有别的主设备在等，
//      就屏蔽当前这一路，强制让出一次（防独占）。
//   3) 最长等待时间 STARVE_LIMIT：任一路等待超过它就置 urgent，下一轮仲裁优先服务。
//   4) 饥饿计数 wr_starve_cnt / rd_starve_cnt：统计"某一路已超时，但仲裁仍把
//      授权给了别人"这种【真正的饥饿事件】。防饥饿机制正常工作时它为 0。
//      （需求里的"最长等待时间计数器"是内部 rd/wr/sd_wait_cnt，不对外。）
//
// ★ LOW_WM=16 / HIGH_WM=48 是【设计目标，待实测】：水位高于 HIGH_WM 说明像素读
//   FIFO 缓冲充足，视频读可以让一次路给写侧；低于 LOW_WM 说明快空了，视频读最高
//   优先级。实测标定后回填 docs/interface_spec.md 的 O-3 / 表 7-4。
//   ★★ 突发长度（2026-10-05 订正口径）：手册 7.13 要求"突发长度固定写死"，
//     **整机集成的取值 = 64 word** —— A 的 `a_video_display_core` 参数 `BURST_WORDS`
//     默认 64，interface_spec v1.34 补充契约原文："`rd_len` 按 32bit word，**默认 64**"。
//     ★ 本模块对长度**不设上限、也不写死**：`word_left` 是 16 位（64 远在范围内），
//       长度完全由调用方给出（Video Read 由 A 的 `a_frame_fetch_bridge` 驱动）。
//       B 侧只负责"一个突发一旦开始就连续搬完、不在中途切换"。
//     （原注释写"O-3 建议 16 或 32 word"，与集成实取值 64 不一致，已订正 —— 那条
//       只是阶段 11 的早期建议值，不是接口约定。）
// ============================================================================
`include "safevision_defs.vh"

module memory_arbiter #(
    parameter integer MAX_BURSTS   = 4,     // N：单次 grant 连续突发上限（防独占，待实测）
    parameter integer STARVE_LIMIT = 64,    // 最长等待周期，超限即临时提权（待实测）
    // Optional A integration optimization; default preserves B's 16-bit
    // counter and all existing positional parameters. Arbitration only tests
    // count >= MAX_BURSTS, so saturation above that threshold is equivalent.
    parameter integer COMPACT_CONSEC_COUNTER = 0,
    // Legacy defaults preserve the portable B contract. A real scan has no
    // backpressure: reserve enough pixels for command gaps and a complete
    // checked landing bank before serving an arbitrarily fast producer.
    parameter [15:0] HIGH_WATER = 16'd48,
    parameter [15:0] CRITICAL_WATER = 16'd0
)(
    input  wire        clk,                 // mem_clk 125MHz
    input  wire        rst_n,               // 低有效
    input  wire [15:0] video_fifo_level,    // 像素读 FIFO 水位（手册 7.13 水位驱动）

    // ---- 读通道：Video Read（video_read_dma / frame_reader）----
    input  wire        rd_req,
    input  wire [31:0] rd_addr,             // 逻辑字节地址（突发起始）
    input  wire [15:0] rd_len,              // 本次突发 word 数
    output reg         rd_ack,              // 单拍：突发被受理，开始搬运
    output wire        rd_busy,             // 高：该通道突发进行中
    output wire [31:0] rd_data,             // 读回数据（组合转发）
    output wire        rd_data_valid,       // 与 rd_data 同拍有效

    // ---- 写通道：Frame Write（slot_writer）----
    input  wire        wr_req,
    input  wire [31:0] wr_addr,
    input  wire [31:0] wr_data,             // 逐 word 连续给出（突发被受理后）
    input  wire [15:0] wr_len,
    output reg         wr_ack,              // 单拍：突发被受理
    output wire        wr_busy,

    // ---- 第三通道：SD / 调试访问（最低优先级）----
    input  wire        sd_req,
    input  wire        sd_wr,               // 1=写 0=读
    input  wire [31:0] sd_addr,
    input  wire [31:0] sd_wdata,
    input  wire [15:0] sd_len,
    output reg         sd_ack,
    output wire        sd_busy,
    output wire [31:0] sd_rdata,
    output wire        sd_rdata_valid,

    // ---- 到 mem_ctrl（interface_spec §3.4 mem_ctrl 端口）----
    output reg         mem_req,
    output reg         mem_wr,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_wstrb,          // 字节选通（全字写 = 4'hF，对接 mem_ctrl）
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,
    input  wire        mem_rdata_valid,     // 读数据有效（可由 mem_ctrl 打拍）

    // ---- 观测 ----
    output reg  [15:0] wr_starve_cnt,       // 写侧真正的饥饿事件数（防饥饿正常时恒 0）
    output reg  [15:0] rd_starve_cnt        // 读侧真正的饥饿事件数
);

    // ------------------------------------------------------------------------
    // 常量
    // ------------------------------------------------------------------------
    localparam [1:0]  CH_NONE = 2'd0,
                      CH_RD   = 2'd1,       // Video Read
                      CH_WR   = 2'd2,       // Frame Write
                      CH_SD   = 2'd3;       // SD / 调试

    // ★ 设计目标，待实测（手册 7.13 学习卡片给的初值 16 / 48）
    localparam [15:0] LOW_WM  = 16'd16;
    localparam [15:0] HIGH_WM = HIGH_WATER;

    localparam [15:0] MAX_BURSTS_C   = MAX_BURSTS;
    localparam [15:0] STARVE_LIMIT_C = STARVE_LIMIT;

    // ------------------------------------------------------------------------
    // 内部状态
    // ------------------------------------------------------------------------
    reg  [1:0]  cur_ch;        // 当前/最近一次被授权的通道
    reg         busy;          // 1 = 一个突发正在搬运
    reg  [15:0] word_left;     // 本突发剩余 word 数
    reg         transfer_active; // one prime cycle after ack, then req/ready transfers
    reg         cur_wr;          // write/read mode latched with the burst
    reg  [15:0] responses_left; // retain channel ownership until ALL read responses
    reg  [31:0] cur_addr;      // 本突发当前 word 的逻辑字节地址
    reg  [1:0]  last_ch;       // 上一次授权的通道
    function integer consecutive_width;
        input integer n;
        integer v;
        begin
            consecutive_width=1;
            for(v=n;v>1;v=v>>1)consecutive_width=consecutive_width+1;
        end
    endfunction
    localparam integer CONSEC_WIDTH=COMPACT_CONSEC_COUNTER?
        consecutive_width(MAX_BURSTS):16;
    reg [CONSEC_WIDTH-1:0] consec_cnt;

    reg  [15:0] rd_wait_cnt;   // 最长等待时间计数器（内部，不对外）
    reg  [15:0] wr_wait_cnt;
    reg         rd_starve_event,wr_starve_event; // diagnostics delayed one cycle
    reg         grant_event;    // 授权事件迟一拍（见 consec_cnt 结算处时序说明）
    reg  [1:0]  grant_ch;
    reg  [15:0] sd_wait_cnt;

    // ---- 紧迫（超限即临时提权）----
    wire rd_urg = (rd_wait_cnt >= STARVE_LIMIT_C);
    wire wr_urg = (wr_wait_cnt >= STARVE_LIMIT_C);
    wire sd_urg = (sd_wait_cnt >= STARVE_LIMIT_C);

    // ---- N 突发独占上限屏蔽：仅当"别路在等"且自己没超时才屏蔽（安全阀）----
    wire rd_mask = (last_ch == CH_RD) && (consec_cnt >= MAX_BURSTS_C) &&
                   (wr_req | sd_req) && !rd_urg;
    wire wr_mask = (last_ch == CH_WR) && (consec_cnt >= MAX_BURSTS_C) &&
                   (rd_req | sd_req) && !wr_urg;
    wire sd_mask = (last_ch == CH_SD) && (consec_cnt >= MAX_BURSTS_C) &&
                   (rd_req | wr_req) && !sd_urg;

    wire video_critical = video_fifo_level < CRITICAL_WATER;
    wire rd_e = rd_req & (~rd_mask | video_critical);
    wire wr_e = wr_req & ~wr_mask;
    wire sd_e = sd_req & ~sd_mask;

    // ---- 水位：像素 FIFO 缓冲充足 -> 让一次路给写侧 ----
    wire vid_full = (video_fifo_level > HIGH_WM);

    // ------------------------------------------------------------------------
    // 仲裁（组合）
    // ------------------------------------------------------------------------
    reg [1:0] winner;
    always @(*) begin
        winner = CH_NONE;
        if (busy) begin
            winner = CH_NONE;                 // 传输中不重新仲裁（突发边界才切换）
        end else if (video_critical) begin
            // Reserve the bus even during the checked DMA's short request
            // bubbles. Starting a buffered write here would impose another
            // physical write/drain/quiet turn-around before the next read.
            // The core disables this reservation when its MEM DMA is idle.
            winner = rd_e ? CH_RD : CH_NONE;
        end else if (rd_urg && rd_e) begin
            winner = CH_RD;                   // 超时优先，防饥饿
        end else if (wr_urg && wr_e) begin
            winner = CH_WR;
        end else if (sd_urg && sd_e) begin
            winner = CH_SD;
        end else if (vid_full) begin
            winner = wr_e ? CH_WR : (sd_e ? CH_SD : (rd_e ? CH_RD : CH_NONE));
        end else begin
            winner = rd_e ? CH_RD : (wr_e ? CH_WR : (sd_e ? CH_SD : CH_NONE));
        end
    end

    // Requests are accepted only on mem_req && mem_ready. The selected writer
    // must hold wr_data/sd_wdata during !mem_ready and advance it only on its
    // accepted word (wr_busy/sd_busy && mem_req && mem_ready && mem_wr).
    // No per-word write ack is added: all existing module ports are preserved.
    always @* begin
        mem_req   = busy && transfer_active && (word_left != 0);
        mem_wr    = cur_wr;
        mem_addr  = cur_addr;
        mem_wdata = (cur_ch == CH_WR) ? wr_data : sd_wdata;
        mem_wstrb = cur_wr ? 4'hF : 4'h0;
    end

    wire mem_fire = mem_req && mem_ready;
    wire response_fire = busy && !cur_wr && (responses_left != 0) && mem_rdata_valid;
    wire commands_done = (word_left == 0) || (mem_fire && word_left == 1);
    wire responses_done = cur_wr || (responses_left == 0) ||
                          (response_fire && responses_left == 1);

    assign rd_data       = mem_rdata;
    assign rd_data_valid = response_fire && (cur_ch == CH_RD);
    assign sd_rdata      = mem_rdata;
    assign sd_rdata_valid= response_fire && (cur_ch == CH_SD);
    assign rd_busy = busy && (cur_ch == CH_RD);
    assign wr_busy = busy && (cur_ch == CH_WR);
    assign sd_busy = busy && (cur_ch == CH_SD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_ch <= CH_NONE;
            busy <= 1'b0;
            transfer_active <= 1'b0;
            cur_wr <= 1'b0;
            word_left <= 0;
            responses_left <= 0;
            cur_addr <= 0;
            last_ch <= CH_NONE;
            consec_cnt <= 0;
            rd_wait_cnt <= 0;
            wr_wait_cnt <= 0;
            sd_wait_cnt <= 0;
            rd_ack <= 0;
            wr_ack <= 0;
            sd_ack <= 0;
            wr_starve_cnt <= 0;
            rd_starve_cnt <= 0;
            wr_starve_event <= 0;
            rd_starve_event <= 0;
            grant_event     <= 1'b0;
            grant_ch        <= CH_NONE;
        end else begin
            rd_ack <= 0;
            wr_ack <= 0;
            sd_ack <= 0;
            // Register diagnostic events before their 16-bit saturating counters;
            // this cuts the winner priority tree out of the counter enable path.
            rd_starve_event <= !busy && rd_urg && winner != CH_RD;
            wr_starve_event <= !busy && wr_urg && winner != CH_WR;
            if(rd_starve_event && rd_starve_cnt != 16'hFFFF)
                rd_starve_cnt <= rd_starve_cnt + 1'b1;
            if(wr_starve_event && wr_starve_cnt != 16'hFFFF)
                wr_starve_cnt <= wr_starve_cnt + 1'b1;
            // ★ 同一招用于 consec_cnt/last_ch（mem→mem 多米诺，2026-10-06）：
            //   授权事件先寄存、下一拍再结算连续授权计数，把 winner 优先树
            //   （连带 rd_req→rd_e 长锥）移出计数器 CE 路径。授权后 busy 至少
            //   占 2 拍（prime 拍 + ≥1 个 transfer 拍），下一次仲裁决策最早在
            //   3 拍之后 ⇒ 迟一拍结算与就地结算对仲裁决策完全等价。
            grant_event <= !busy && (winner != CH_NONE);
            grant_ch    <= winner;
            if (grant_event) begin
                if (last_ch == grant_ch) begin
                    if (consec_cnt != {CONSEC_WIDTH{1'b1}}) consec_cnt <= consec_cnt + 1'b1;
                end else begin
                    last_ch <= grant_ch;
                    consec_cnt <= 1'b1;
                end
            end
            if (!busy) begin
                if (winner != CH_NONE) begin
                    cur_ch <= winner;
                    busy <= 1'b1;
                    transfer_active <= 1'b0;
                    cur_wr <= (winner == CH_WR) || ((winner == CH_SD) && sd_wr);
                    cur_addr <= (winner == CH_RD) ? rd_addr :
                                (winner == CH_WR) ? wr_addr : sd_addr;
                    word_left <= (winner == CH_RD) ? ((rd_len == 0) ? 16'd1 : rd_len) :
                                 (winner == CH_WR) ? ((wr_len == 0) ? 16'd1 : wr_len) :
                                                    ((sd_len == 0) ? 16'd1 : sd_len);
                    if (winner == CH_RD)
                        responses_left <= (rd_len == 0) ? 16'd1 : rd_len;
                    else if (winner == CH_SD && !sd_wr)
                        responses_left <= (sd_len == 0) ? 16'd1 : sd_len;
                    else responses_left <= 0;
                    case (winner)
                        CH_RD: rd_ack <= 1'b1;
                        CH_WR: wr_ack <= 1'b1;
                        CH_SD: sd_ack <= 1'b1;
                        default: ;
                    endcase
                    // consec_cnt/last_ch 的结算已移到 grant_event（上方），
                    // 这里不再就地更新 —— 见那里的时序等价性说明。
                    // ★ 合并 origin/main 后：位宽改用 CONSEC_WIDTH（对方的参数化），
                    //   结算位置仍在本轮 P1 的 grant_event 里（两处改动正交，均保留）。
                end
            end else begin
                // Prime cycle lets a client observe ack and prepare its first word.
                transfer_active <= 1'b1;
                if (mem_fire) begin
                    cur_addr <= cur_addr + 32'd4;
                    word_left <= word_left - 1'b1;
                end
                if (response_fire) responses_left <= responses_left - 1'b1;
                if (commands_done && responses_done) begin
                    busy <= 1'b0;
                    transfer_active <= 1'b0;
                end
            end

            // A grant starts busy on this edge; its counter clears on the next
            // edge while busy owns that channel. Do not put the full winner
            // priority tree in the 125 MHz wait-counter clock-enable path.
            if (rd_req && !(busy && cur_ch == CH_RD)) begin
                if (rd_wait_cnt != 16'hFFFF) rd_wait_cnt <= rd_wait_cnt + 1'b1;
            end else rd_wait_cnt <= 0;
            if (wr_req && !(busy && cur_ch == CH_WR)) begin
                if (wr_wait_cnt != 16'hFFFF) wr_wait_cnt <= wr_wait_cnt + 1'b1;
            end else wr_wait_cnt <= 0;
            if (sd_req && !(busy && cur_ch == CH_SD)) begin
                if (sd_wait_cnt != 16'hFFFF) sd_wait_cnt <= sd_wait_cnt + 1'b1;
            end else sd_wait_cnt <= 0;
        end
    end
endmodule
