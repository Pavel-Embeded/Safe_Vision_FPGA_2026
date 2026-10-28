// ============================================================================
// bmp_frame_sink.v — mem 侧帧接收器（125 MHz 域）
// ----------------------------------------------------------------------------
// 方案 A 的跨界落点：SD/媒体链跑 **50 MHz**（`sd_bmp_player`），本模块在 **125 MHz
// mem 域**把像素收下来、写进帧槽、并完成换帧握手。
//
// 组成（**全部复用现成件，不自研通用件** ✓ —— 用户明确的开发方针）：
//   · **官方 `a_pixel_fifo`**：双时钟 + 自带 32→16 位宽转换（低半字先），
//     `wr_ready` 反压、FWFT 读 ⇒ 不自己写异步 FIFO
//   · **A 的 `bmp_frame_write_bridge`**：行序重映射 + 逐 word 写出
//   · 本模块只写**帧控制器**（业务逻辑，官方没有）
//
// 帧生命周期（★ 关键：避免上一帧残留像素污染本帧）：
//   ① 空闲时 **持续排空 FIFO**（丢弃），并对外给 `mem_ready=1`
//   ② SD 侧见 `mem_ready` 才开帧 ⇒ `frame_active` 上升（经两级同步到本域）
//   ③ 本模块在 `frame_active` 上升沿采样 `top_down`/`slot`（电平已稳定多拍，
//      属"打包数据"跨域），pulse `bridge.start`
//   ④ 桥逐 word 写；`br_done` ⇒ 锁存 `crc_ok`，pulse 换帧请求（slot/generation/
//      crc_ok 一起打包，交给板级顶层同步到 sys 域的 frame_swap_ctrl）
//   ⑤ 等 `swap_busy` 起→落（有独立超时）⇒ 翻 `frame_done`（toggle）通知 SD 侧，
//      回到 ①
//
// ★ 本模块内部**没有**跨域组合路径：
//   · 32 位像素只经官方 FIFO 跨界（**写侧 wr_clk = 50 MHz，读侧 clk = 125 MHz**）
//   · 50 MHz 来的电平（frame_active/top_down/slot）先过两级同步再用
//   · 给回 50 MHz 的 mem_ready/frame_done/last_frame_ok 都是本域寄存器输出
// ============================================================================
`include "pixel_format_defs.vh"

module bmp_frame_sink #(
    parameter integer FIFO_AW     = 10,           // 官方 FIFO 地址宽（可用字数 = 2^AW-1）
    parameter [31:0]  GAP_TIMEOUT = 32'd500_000,  // 4 ms @125MHz（FAT 读停顿）
    parameter [31:0]  SWAP_TO_N   = 32'd12_500_000, // 100 ms：等换帧（busy 起→落）
    // ★ 这是**无进展**超时，不是 S_WRITE 总时长：桥只要还在推进像素就重新计时。
    //   为什么必须这样（已踩过，会让板子每帧都被掐断）：
    //   真实板级一帧的像素要喂 ~590 ms（50 MHz 板载时钟、SPI 12.5 MHz SCLK、
    //   921654 字节），而按"总时长"计时时 400 ms 的默认值会**中途触发** ⇒
    //   每帧只写进去约 2/3 就被判超时。TB 里没暴露是因为 tb_sd_bmp_player 把
    //   SPI 分频调到最快档（236 ms < 400 ms）—— 仿真跑得快反而掩盖了真问题。
    parameter [31:0]  WRITE_TO_N  = 32'd50_000_000  // 400 ms：**无进展**才算超时
    ,parameter integer REQUIRE_WRITE_DRAIN = 0, REQUIRE_READBACK = 0, RESIDENT_LOAD = 0
    ,parameter integer SOURCE_PROGRESS_AWARE = 0
)(
    input  wire        clk,            // mem_clk 125 MHz（读侧 / 帧控制器）
    input  wire        rst_n,          // mem 域低有效
    input  wire        wr_clk,         // ★ 50 MHz（FIFO 写侧 = SD 播放引擎所在域）

    // ---- 与 SD 侧（50 MHz 域）的接口 ----
    input  wire [31:0] px_word,        // 32 位打包像素（低半字 = 先到的像素）
    input  wire        px_word_valid,
    output wire        px_word_ready,  // = FIFO wr_ready（反压回 SD 侧，**本就在 50M 域**）
    input  wire        frame_active,   // 电平：SD 侧本帧正在产像素
    input  wire        top_down,       // 电平：本帧行序（帧内稳定）
    input  wire [1:0]  slot,           // 电平：本帧目标槽（帧内稳定）
    output reg         mem_ready,      // 电平：空闲且 FIFO 已排空 ⇒ 可开一帧
    output reg         frame_done,     // toggle：本帧已完成（桥写完 + 换帧走完）
    output reg         last_frame_ok,  // 电平：刚完成那帧是否成功

    // ---- 帧写口（→ core 的 memory_arbiter，mem 域）----
    output wire        wr_req,
    output wire [31:0] wr_addr,
    output wire [31:0] wr_data,
    output wire [15:0] wr_len,
    input  wire        wr_ready,

    // ---- 换帧请求（板级顶层打包同步到 sys 域）----
    output reg         swap_toggle,
    output reg  [1:0]  swap_slot,
    output reg  [7:0]  swap_generation,
    output reg         swap_crc_ok,
    input  wire        swap_busy,      // = core 的 (swap_state_o != IDLE)

    // ---- 遥测（UART / LED）----
    output reg  [3:0]  state_o,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [15:0] frame_cnt,
    output reg  [18:0] px_written,
    input wire write_drained,verify_done,verify_pass,
    output wire source_begin,output wire [1:0] source_slot,output wire source_top_down,
    input wire source_progress
);

    // ========================================================================
    // 状态
    // ========================================================================
    localparam [3:0] S_DRAIN = 4'd0,   // 空闲：排空 FIFO，给 mem_ready
                     S_WRITE = 4'd1,   // 桥正在写
                     S_SWAP  = 4'd2,   // 等 core 换帧走完
                     S_ERROR = 4'd3,
                     S_FLUSH = 4'd4;

    localparam [7:0] MY_TO_SWAP = 8'hF1,
                     MY_TO_FRAME= 8'hF2;

    // ========================================================================
    // 50 MHz → 125 MHz：电平两级同步（帧内稳定 ⇒ 打包数据）
    // ========================================================================
    reg [2:0] fa_sync;
    reg [1:0] td_sync;
    reg [3:0] sl_sync;      // ★ 2 位总线 × 2 级 = 4 位（写成 [1:0] 会被截断，
                            //   只剩 slot[1] ⇒ 槽号永远变成 0，整帧写错槽）✗ 已踩过

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fa_sync <= 3'd0; td_sync <= 2'd0; sl_sync <= 4'd0;
        end else begin
            fa_sync <= {fa_sync[1:0], frame_active};
            td_sync <= {td_sync[0],    top_down};
            sl_sync <= {sl_sync[1:0],  slot};
        end
    end
    // ★ 边沿检测必须是"第 2 级上升、且第 3 级还没到"（fa_sync[1] && !fa_sync[2]）：
    //   fa_sync[2] 只是 fa_sync[1] 的延迟版，写成 fa_sync[2] && !fa_sync[1] 时
    //   两级会在同一拍一起变 1 ⇒ 条件**永不成立**，sink 永远出不了 S_DRAIN
    //   （表现：字节全读完、像素全被当垃圾排掉、一帧都写不进去）✗ —— 已踩过
    //   同时它也天然滤掉 frame_active 的下降沿（下降时 [2]=1,[1]=0，不触发）
    wire fa_rise = fa_sync[1] && !fa_sync[2];        // 开帧事件

    // ========================================================================
    // 官方 a_pixel_fifo：写侧 32 位 / 读侧 16 位（FWFT）
    //   ★ 写侧时钟必须是 **wr_clk（50 MHz，SD 播放引擎域）**，读侧才是 clk（125 MHz）：
    //     这样像素才是真的跨域（双时钟 FIFO 的意义所在）
    //   ★ rst 是"公共异步高有效"，IP 内部会按各域同步释放 ⇒ 直接给 ~rst_n ✓
    //     （复位期间 wr_ready = wr_reset_done && !full && !rst = 0，SD 侧不会误推）
    // ========================================================================
    wire        fifo_full, fifo_afull, fifo_empty, fifo_aempty;
    wire [15:0] fifo_rd_data;
    wire        fifo_rd_valid;
    wire [FIFO_AW-1:0] fifo_wr_words;
    wire [FIFO_AW:0]   fifo_rd_pixels;
    wire        fifo_rd_en;
    wire        fifo_rst = ~rst_n;

    a_pixel_fifo #(.AW(FIFO_AW)) u_fifo (
        .rst(fifo_rst),
        .wr_clk(wr_clk), .wr_data(px_word), .wr_en(px_word_valid),
        .full(fifo_full), .almost_full(fifo_afull),
        .wr_words(fifo_wr_words), .wr_ready(px_word_ready),
        .rd_clk(clk), .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_rd_valid), .empty(fifo_empty), .almost_empty(fifo_aempty),
        .rd_pixels(fifo_rd_pixels)
    );

    // ========================================================================
    // 桥：像素 → 行序重映射 → 逐 word 写请求
    // ========================================================================
    reg         br_start;
    wire        br_start_ready, br_done, br_crc_ok, br_err;
    wire [3:0]  br_slot_valid;
    wire [15:0] br_crc_value;
    wire [18:0] br_px_cnt;
    wire [7:0]  br_ec, br_ed;

    reg  [1:0]  slot_lat;        // 开帧时锁存的槽（帧内不变）
    assign source_begin=br_start;assign source_slot=slot_lat;assign source_top_down=td_sync[1];
    wire [31:0] slot_base = `SV_SLOT_BASE(slot_lat);
    wire        br_din_ready;

    // ========================================================================
    // ★★ 1 级 skid：把官方 FIFO 的**组合读数据**寄存一拍再交给桥
    // ------------------------------------------------------------------------
    // 为什么必须要有（TD 实测，2026-10-06）：
    //   官方 FIFO 是 FWFT + `OUTREG_EN="NOREG"` ⇒ `rd_data` 是 ERAM 的**组合输出**。
    //   直接送进桥的 CRC 组合链（`px_pair` → 4 级级联 crc16）会形成 mem→mem 的最差路径：
    //     `sink/u_fifo/fifo/ram_inst/ramread0` → `sink/u_bridge/writer/crc_src_b[5]`
    //     8.165 ns / 8.0 ns 预算（cell 5.07 ns + net 3.10 ns）⇒ **−0.445 ns 违例**。
    //   寄存一拍后该路径变成"从触发器出发"，省掉 ERAM 的 clk-to-out 与那段布线。
    //   ★ 这样**不用改 A 的 `frame_writer`**（改动面小、回归面小），也不改 FIFO 参数
    //     （把 `OUTREG_EN` 改成 `"OUTREG"` 会把 FIFO 从 FWFT 变成非 FWFT，会打断握手 ✗）。
    // ★ 保持 FWFT 语义：FIFO 侧仍是"有数据就取"，只是先取进 skid 再交给桥。
    // ★ 非写帧状态一律清 sk_valid ⇒ skid **不可能**把上一帧的残留像素带进下一帧。
    // ========================================================================
    reg  [15:0] sk_data;
    reg         sk_valid;
    wire        sk_ready = br_din_ready;                       // 桥的接收意愿
    wire        sk_load  = fifo_rd_valid && (!sk_valid || sk_ready);
    wire        br_din_valid = sk_valid && (state_o == S_WRITE);

    // Retain a real byte event if it coincides with healthy adapter activity.
    // It can extend a source wait only after all pending pixels/writes drain.
    reg source_progress_pending;
    wire source_wait_credit=SOURCE_PROGRESS_AWARE && source_progress_pending &&
        state_o==S_WRITE && fa_sync[2] && write_drained &&
        !wr_req && !sk_valid && fifo_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sk_data <= 16'd0; sk_valid <= 1'b0;
        end else if (state_o != S_WRITE) begin
            sk_valid <= 1'b0;                                  // 非写帧状态：丢弃 skid
        end else begin
            if (sk_load)                   sk_data  <= fifo_rd_data;
            if (sk_load)                   sk_valid <= 1'b1;
            else if (sk_valid && sk_ready) sk_valid <= 1'b0;
        end
    end

    // 桥：行序用**实时**同步值（见下），像素从 skid 取
    bmp_frame_write_bridge #(
        .GAP_TIMEOUT(GAP_TIMEOUT),.EXACT_SAMPLE_COMPARE(RESIDENT_LOAD),
        .SOURCE_PROGRESS_AWARE(SOURCE_PROGRESS_AWARE)
    ) u_bridge (
        .clk(clk), .rst_n(rst_n && !(RESIDENT_LOAD && state_o==S_ERROR)), .start(br_start), .top_down(td_sync[1]),
        .slot_sel(slot_lat), .slot_base(slot_base),
        .din(sk_data), .din_valid(br_din_valid), .din_ready(br_din_ready),
        .wr_req(wr_req), .start_ready(br_start_ready),
        .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ready),
        .wr_done(br_done), .slot_valid(br_slot_valid),
        .crc_ok(br_crc_ok), .crc_value(br_crc_value), .px_cnt(br_px_cnt),
        .wr_error(br_err), .err_code(br_ec), .err_detail(br_ed),
        .source_progress(source_wait_credit)
    );

    // ★ 弹出时机：把 FIFO 的数据取进 skid 那一拍弹（skid 空着，或本拍正被桥取走）；
    //   空闲/排空时（非 S_WRITE）无条件弹掉，避免残留像素污染下一帧
    assign fifo_rd_en = (state_o == S_WRITE) ? sk_load : fifo_rd_valid;

    // ========================================================================
    // 帧控制器
    // ========================================================================
    reg [31:0] to_cnt;
    reg        swap_seen;
    reg [2:0]  empty_settle;      // FIFO 报空后再稳几拍才算真空
    reg [18:0] px_d;              // 上一拍的像素计数（判"有没有进展"）

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)source_progress_pending<=0;
        else if(!SOURCE_PROGRESS_AWARE || state_o!=S_WRITE || !fa_sync[2])source_progress_pending<=0;
        else if(source_wait_credit || br_px_cnt!=px_d || (wr_req && wr_ready))source_progress_pending<=source_progress;
        else if(source_progress)source_progress_pending<=1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_o        <= S_DRAIN;
            br_start       <= 1'b0;
            mem_ready      <= 1'b0;
            frame_done     <= 1'b0;
            last_frame_ok  <= 1'b0;
            swap_toggle    <= 1'b0;
            swap_slot      <= 2'd0;
            swap_generation<= 8'd1;
            swap_crc_ok    <= 1'b0;
            slot_lat       <= 2'd1;
            to_cnt         <= 32'd0;
            swap_seen      <= 1'b0;
            empty_settle   <= 3'd0;
            err_code       <= 8'h00;
            err_detail     <= 8'h00;
            frame_cnt      <= 16'd0;
            px_written     <= 19'd0;
            px_d           <= 19'd0;
        end else begin
            br_start <= 1'b0;
            px_written <= br_px_cnt;
            px_d       <= br_px_cnt;      // 用于判"本拍是否有进展"

            case (state_o)
                // ------------------------------------------------------------
                // 空闲：持续排空 FIFO；连续几拍报空 ⇒ 才算真排空、给 mem_ready
                S_DRAIN: begin
                    if (fifo_empty) begin
                        if (empty_settle != 3'd7) empty_settle <= empty_settle + 3'd1;
                    end else begin
                        empty_settle <= 3'd0;
                    end
                    mem_ready <= (empty_settle == 3'd7);

                    if (fa_rise) begin
                        // 开帧：采样槽号（已稳定多拍）并启动桥
                        //   ★ 行序不在这里锁存，见 u_bridge 例化处注释
                        slot_lat     <= sl_sync[3:2];
                        br_start     <= 1'b1;               // ★ 单拍
                        mem_ready    <= 1'b0;
                        to_cnt       <= 32'd0;
                        swap_seen    <= 1'b0;
                        last_frame_ok<= 1'b0;
                        state_o      <= S_WRITE;
                    end
                end

                // ------------------------------------------------------------
                S_WRITE: begin
                    // ★ 超时按**无进展**计：桥这一拍还在推进像素（px_cnt 变了）就重新计时。
                    //   按"总时长"计会让真实板级每帧都在 400 ms 被掐断（一帧要 ~590 ms）✗
                    if (br_px_cnt != px_d) to_cnt <= 32'd0;
                    else if (source_wait_credit) to_cnt <= 32'd0;
                    else                   to_cnt <= to_cnt + 32'd1;

                    if (br_done) begin
                        last_frame_ok  <= br_crc_ok;
                        // ★ 一帧成功 ⇒ 清掉粘滞的错误码（"证明能工作了"才清）
                        err_code       <= 8'h00;
                        err_detail     <= 8'h00;
                        // 打包换帧请求（交板级顶层同步到 sys 域）
                        swap_crc_ok    <= br_crc_ok;
                        swap_slot      <= slot_lat;
                        swap_generation<= swap_generation + 8'd1;
                        if (!REQUIRE_WRITE_DRAIN && !REQUIRE_READBACK) swap_toggle <= ~swap_toggle;
                        to_cnt         <= 32'd0;
                        state_o        <= (REQUIRE_WRITE_DRAIN || REQUIRE_READBACK) ? S_FLUSH : S_SWAP;
                    end else if ((RESIDENT_LOAD && !fa_sync[2]) || br_err) begin
                        last_frame_ok<= 1'b0;
                        err_code   <= br_ec;
                        err_detail <= br_ed;
                        empty_settle<=0;
                        state_o    <= S_ERROR;
                    end else if (SOURCE_PROGRESS_AWARE && (source_wait_credit || br_px_cnt!=px_d)) begin
                        // The qualified progress above resets this deadline on
                        // this edge. Completed frames and errors keep priority.
                    end else if (to_cnt >= WRITE_TO_N) begin
                        last_frame_ok<= 1'b0;
                        err_code   <= MY_TO_FRAME;
                        empty_settle<=0;
                        state_o    <= S_ERROR;
                    end
                end

                // ------------------------------------------------------------
                // 等 core 的换帧走完（busy 起 → 落），独立超时兜底
                //   ★ 超时判断必须**独立于** swap_busy：写成
                //     `if(busy)… else if(seen)… else if(to_cnt>=TO)…` 时，busy 一直为 1
                //     就永远走不到超时分支 ⇒ sink 永久停在 S_SWAP ✗
                //     （core 的 frame_swap_ctrl 若进了 S_SAFE，swap_state != 0 会一直挂着）
                S_FLUSH: begin
                    // Writer ack means arbiter grant, not physical completion.
                    // Hold frame metadata until the adapter's buffered tail and
                    // the granted write transaction have both drained.
                    to_cnt <= to_cnt + 32'd1;
                    if (REQUIRE_READBACK && verify_done && !verify_pass) begin
                        last_frame_ok<=0;swap_crc_ok<=0;err_code<=8'hF3;state_o<=S_ERROR;
                    end else if (write_drained && (!REQUIRE_READBACK || (verify_done && verify_pass))) begin
                        swap_toggle <= ~swap_toggle;
                        to_cnt <= 32'd0;
                        state_o <= S_SWAP;
                    end else if (to_cnt >= WRITE_TO_N) begin
                        last_frame_ok <= 1'b0;
                        err_code <= MY_TO_FRAME;
                        state_o <= S_ERROR;
                    end
                end

                S_SWAP: begin
                    to_cnt <= to_cnt + 32'd1;
                    if (swap_busy) swap_seen <= 1'b1;

                    if(RESIDENT_LOAD)begin
                        // Load acknowledgement follows write drain/readback,
                        // independently of a later frame-boundary presentation.
                        if(last_frame_ok)frame_cnt<=frame_cnt+1'b1;
                        frame_done<=~frame_done;to_cnt<=0;empty_settle<=0;state_o<=S_DRAIN;
                    end else if (to_cnt >= SWAP_TO_N) begin
                        // 兜底：无论 busy 起没起、落没落，都不卡死；翻 frame_done 让 SD 侧推进
                        swap_seen    <= 1'b0;
                        last_frame_ok<= 1'b0;
                        err_code     <= MY_TO_SWAP;
                        frame_done   <= ~frame_done;
                        to_cnt       <= 32'd0;
                        empty_settle <= 3'd0;
                        state_o      <= S_DRAIN;
                    end else if (swap_seen && !swap_busy) begin
                        if (last_frame_ok) frame_cnt <= frame_cnt + 16'd1;
                        swap_seen    <= 1'b0;
                        frame_done   <= ~frame_done;        // ★ 通知 SD 侧本帧完成
                        to_cnt       <= 32'd0;
                        empty_settle <= 3'd0;
                        state_o      <= S_DRAIN;
                    end
                end

                // ------------------------------------------------------------
                S_ERROR: begin
                    // Never return the previous frame's success on a failure.
                    last_frame_ok <= 1'b0;
                    mem_ready <= 1'b0;
                    // 排空 FIFO，避免残留像素影响下一次尝试
                    if (fifo_empty) begin
                        if (empty_settle != 3'd7) empty_settle <= empty_settle + 3'd1;
                    end else begin
                        empty_settle <= 3'd0;
                    end
                    // 出错也翻一次 frame_done，让 SD 侧能推进（不会永久卡在 S_STREAM）
                    //   ★ err_code **不在这里清**：否则错误只亮 ~8 拍（64 ns），
                    //     而 UART 状态行 500 ms 才刷一次 ⇒ 板上根本看不到 ✗
                    //     改为粘滞到"下一帧成功"（见 S_WRITE 的 br_done 分支）
                    if (empty_settle == 3'd7) begin
                        frame_done <= ~frame_done;
                        empty_settle<=0;
                        state_o    <= S_DRAIN;
                    end
                end

                default: state_o <= S_DRAIN;
            endcase
        end
    end

endmodule
