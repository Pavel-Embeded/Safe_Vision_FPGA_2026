// ============================================================================
// tb_bmp_frame_sink.sv — `bmp_frame_sink` 的单元验证（★ 真实异步 50M/125M）
// ----------------------------------------------------------------------------
// 为什么单独一个 TB（此前 sink **零仿真覆盖**，只过 TD 综合 + STA）：
//   1. `tb_sd_bmp_player.sv` 把 player 与 sink 接在**同一时钟**上（都 125 MHz），
//      同步器退化为纯延迟 ⇒ **真实的 50 MHz ↔ 125 MHz 异步边界从未被仿真**。
//      本 TB 用**两个独立自由运行的时钟**：wr_clk = 50 MHz、clk = 125 MHz。
//   2. sink 的 `S_ERROR`、两个超时分支、FIFO 排空判据此前**无任何测试**。
//
// 覆盖内容：
//   T1 正常一帧（top_down=0，自底向上文件序）→ 逐像素比对 + 换帧握手 + 槽号 + CRC
//   T2 ★ 行序：紧接着再跑一帧 top_down=1（自顶向下文件序）→ 逐像素比对
//        —— 这一条专门抓"开帧时取到**上一幅**行序"的缺陷（两帧朝向不同才会暴露）
//   T3 换帧 `swap_busy` **一直拉高**（core 卡在 busy）→ 必须仍在 SWAP_TO_N 内翻 frame_done
//   T4 换帧 `swap_busy` **从不拉高**（core 拒了）→ 同样必须超时兜底
//   T5 帧内断流（只开帧不给像素）→ 桥 GAP 超时 → sink 进 S_ERROR → frame_done 兜底
//        → 回 S_DRAIN → 且 `err_code` **粘滞**（下一帧成功才清）
//   T6 空闲期往 FIFO 塞残留字 → `mem_ready` 必须等 FIFO **真排空**才给（防污染下一帧）
//
// ★ 不能证明什么（别越界）：
//   · 不接 A 的 `safevision_core`，用行为存储模型代替 ⇒ 不证明仲裁带宽 / 显示链 / HDMI；
//   · 不证明 TD 综合/布局布线/STA；
//   · 不覆盖 player（`tb_sd_bmp_player.sv` 覆盖整链，但那是同频）。
// ============================================================================
`timescale 1ns/1ps
`include "pixel_format_defs.vh"

module tb_bmp_frame_sink;

    // ---------------------------------------------------------------- 几何
    localparam integer W = `SV_FRAME_WIDTH;      // 640
    localparam integer H = `SV_FRAME_HEIGHT;     // 480
    localparam integer PIX = W*H;                // 307200
    localparam integer WORDS = PIX/2;            // 153600

    localparam [31:0] SLOT0_WORD = `SV_IMG0_BASE >> 2;   // 0
    localparam [31:0] SLOT1_WORD = `SV_IMG1_BASE >> 2;   // 163840

    // 缩短超时以便快速覆盖分支（真实值见 bmp_frame_sink.v 默认参数）
    //   ★ GAP 故意设得很大：桥自身的"帧内断流"超时已由既有 `tb_bmp_frame_write_bridge`
    //     覆盖，这里要让 **sink 自己的 S_WRITE 无进展兜底** 成为先触发的那个。
    localparam [31:0] GAP_TO   = 32'd1_000_000;  // 8 ms：本 TB 里不让它触发
    localparam [31:0] WRITE_TO = 32'd20_000;     // 160 us：**无进展**才算超时
    localparam [31:0] SWAP_TO  = 32'd3000;       // 24 us：等换帧

    // ---------------------------------------------------------------- 期望像素
    function [23:0] px24;
        input integer x;
        input integer y;
        begin
            px24 = { (x[7:0] ^ y[7:0]), (x[9:0] + y[9:0]) & 8'hFF, (x[9:0]*3) & 8'hFF };
        end
    endfunction

    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    // 文件序第 j 个像素的 RGB565。
    //   ★ 桥收到的是**文件序**像素，自己按 top_down 重映射到光栅行：
    //     top_down=1 ⇒ 文件行 r 就是光栅行 r；top_down=0 ⇒ 文件行 r 落到光栅行 H-1-r。
    //   所以只要按对应朝向生成文件，写进存储的内容就应当**恒为光栅序** px565(x,y)。
    function [15:0] file_px;
        input integer j;
        input integer td;
        integer x, r, y;
        begin
            x = j % W;
            r = j / W;
            y = td ? r : (H - 1 - r);
            file_px = px565(x, y);
        end
    endfunction

    // 光栅第 k 像素（k = y*W + x）的期望值
    function [15:0] raster_k;
        input integer k;
        begin
            raster_k = px565(k % W, k / W);
        end
    endfunction

    // ---------------------------------------------------------------- 时钟/复位
    // ★ 两个**独立自由运行**的时钟：这才是真实的方案 A 配置
    reg clk    = 1'b0;   always #4  clk    = ~clk;     // 125 MHz（mem 域）
    reg wr_clk = 1'b0;   always #10 wr_clk = ~wr_clk;  // 50 MHz（SD/媒体域）
    reg rst_n  = 1'b0;

    integer errors = 0;
    task check;
        input        cond;
        input string msg;
        begin
            if (cond) $display("[PASS] %s", msg);
            else begin $display("[FAIL] %s", msg); errors = errors + 1; end
        end
    endtask

    // ---------------------------------------------------------------- DUT 接口
    // 50 MHz 侧
    wire [31:0] px_word;
    wire        px_word_valid;
    wire        px_word_ready;
    reg         frame_active, top_down;
    reg  [1:0]  slot;
    // sink → 50 MHz 侧（TB 直接采样，TB 里不建模亚稳态）
    wire        mem_ready, frame_done, last_frame_ok;
    // mem 域
    wire        wr_req;
    wire [31:0] wr_addr, wr_data;
    wire [15:0] wr_len;
    reg         wr_ready;
    wire        swap_toggle, swap_crc_ok;
    wire [1:0]  swap_slot;
    wire [7:0]  swap_generation;
    reg         swap_busy;
    wire [3:0]  state_o;
    wire [7:0]  err_code, err_detail;
    wire [15:0] frame_cnt;
    wire [18:0] px_written;

    bmp_frame_sink #(
        .GAP_TIMEOUT (GAP_TO),
        .SWAP_TO_N   (SWAP_TO),
        .WRITE_TO_N  (WRITE_TO)
    ) dut (
        .clk(clk), .rst_n(rst_n), .wr_clk(wr_clk),
        .px_word(px_word), .px_word_valid(px_word_valid), .px_word_ready(px_word_ready),
        .frame_active(frame_active), .top_down(top_down), .slot(slot),
        .mem_ready(mem_ready), .frame_done(frame_done), .last_frame_ok(last_frame_ok),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ready),
        .swap_toggle(swap_toggle), .swap_slot(swap_slot),
        .swap_generation(swap_generation), .swap_crc_ok(swap_crc_ok),
        .swap_busy(swap_busy),
        .state_o(state_o), .err_code(err_code), .err_detail(err_detail),
        .frame_cnt(frame_cnt), .px_written(px_written)
    );

    localparam [3:0] S_DRAIN = 4'd0, S_WRITE = 4'd1, S_SWAP = 4'd2, S_ERROR = 4'd3;

    // ---------------------------------------------------------------- 存储模型
    localparam integer MEM_WORDS = 1024*1024;
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [4:0]  stall = 5'd0;
    always @(posedge clk) stall <= stall + 5'd1;
    always @(*) wr_ready = (stall != 5'd31);        // 周期性忙一拍，制造真实反压

    always @(posedge clk) begin
        if (wr_req && wr_ready) mem[wr_addr[21:2]] <= wr_data;
    end

    // ---------------------------------------------------------------- 换帧握手模拟
    //   mode 0 = 正常（忙 40 拍后落） 1 = 一直忙（core 卡住） 2 = 从不忙（core 拒绝）
    integer swap_mode = 0;
    reg        sw_d = 1'b0;
    reg [7:0]  sw_cnt = 8'd0;
    always @(posedge clk) begin
        if (swap_mode == 1) begin
            swap_busy <= 1'b1;                       // 一直高
        end else if (swap_mode == 2) begin
            swap_busy <= 1'b0;                       // 从不拉高
        end else begin
            sw_d <= swap_toggle;
            if (swap_toggle != sw_d) sw_cnt <= 8'd40;
            else if (sw_cnt != 8'd0) sw_cnt <= sw_cnt - 8'd1;
            swap_busy <= (sw_cnt != 8'd0);
        end
    end

    // ---------------------------------------------------------------- 逐像素比对
    task cmp_frame;
        input [31:0] base_word;
        input string label;
        integer n, b;
        reg [31:0] got, exp;
        begin
            b = 0;
            for (n = 0; n < WORDS; n = n + 1) begin
                got = mem[base_word + n];
                exp = { raster_k(2*n+1), raster_k(2*n) };
                if (got !== exp) begin
                    if (b == 0)
                        $display("       first mismatch word=%0d addr=0x%08x got=%08x exp=%08x",
                                 n, (base_word+n)<<2, got, exp);
                    b = b + 1;
                end
            end
            if (b == 0) $display("[PASS] %s : %0d words pixel-exact", label, WORDS);
            else begin
                $display("[FAIL] %s : %0d / %0d words differ", label, b, WORDS);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------------------------------------------------------- 驱动任务
    // ========================================================================
    // 像素源：**时钟化驱动器**（关键：绝不能丢字）
    //   ★ 为什么不用 task + @(posedge)：那样写会在"沿前采样 ready、沿后盲目撤 valid"
    //     之间留一个洞 —— 若 ready 恰好在该沿掉下去，这个字就被丢掉，而且
    //     **静默丢**（FIFO 少收、桥少写，帧数还对不上）。本 TB 就踩过：
    //     推 153600 个字，桥只收到 138996 个，凭空少 14604 个。
    //   ⇒ 改成时钟化：只在 **(valid && ready) 的那一拍**才前进到下一个字，
    //     否则保持当前字与 valid 不变，直到被接收为止。
    // ========================================================================
    reg  [31:0] feed_word;
    reg         feed_valid;
    integer     feed_idx = 0, feed_total = 0, feed_td = 0, feed_mode = 0, pushed = 0;
    reg         feed_run = 1'b0;

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            feed_valid <= 1'b0; feed_run <= 1'b0; feed_idx <= 0;
        end else begin
            if (feed_valid && px_word_ready) feed_valid <= 1'b0;   // 本拍被接收
            if (feed_run && !feed_valid && feed_idx < feed_total) begin
                feed_word  <= (feed_mode == 0)
                              ? { file_px(2*feed_idx+1, feed_td), file_px(2*feed_idx, feed_td) }
                              : ((feed_idx == 0) ? 32'hDEAD_BEEF : 32'h1234_5678);
                feed_valid <= 1'b1;
                feed_idx   <= feed_idx + 1;
                pushed     <= pushed + 1;
                if (feed_idx + 1 == feed_total) feed_run <= 1'b0;
            end
        end
    end
    assign px_word       = feed_word;
    assign px_word_valid = feed_valid;

    task start_feed;
        input integer n;
        input integer td;
        begin
            feed_idx = 0; feed_total = n; feed_td = td; feed_run = 1'b1;
        end
    endtask

    task wait_feed_done;
        begin
            while (!(feed_idx == feed_total && !feed_valid)) @(posedge wr_clk);
        end
    endtask

    // 按文件序喂一整帧（td = 该帧朝向）
    task feed_frame;
        input integer npx;
        input integer td;
        begin
            feed_mode = 0;
            start_feed(npx, td);
            wait_feed_done();
        end
    endtask

    // 等 frame_done 翻转一次；返回是否在 limit 拍内发生
    integer fd_seen;
    reg     fd_d = 1'b0;
    task wait_frame_done;
        input integer limit;
        integer g;
        begin
            g = 0; fd_seen = 0;
            while (g < limit) begin
                @(posedge clk);
                if (frame_done != fd_d) begin fd_d = frame_done; fd_seen = 1; g = limit; end
                else g = g + 1;
            end
        end
    endtask

    // 等 mem_ready 拉高（sink 空闲且 FIFO 已排空）
    task wait_ready;
        input integer limit;
        integer g;
        begin
            g = 0;
            while (!mem_ready && g < limit) begin @(posedge clk); g = g + 1; end
        end
    endtask

    // T6 用：连续监视 mem_ready 是否掉过（不能只在一个时刻点采样 —— sink 排空很快）
    reg t6_arm = 1'b0, t6_low = 1'b0;
    always @(posedge clk) if (t6_arm && !mem_ready) t6_low <= 1'b1;

    // ---------------------------------------------------------------- 主流程
    integer guard;
    initial begin
        frame_active = 1'b0; top_down = 1'b0; slot = 2'd1;
        swap_busy = 1'b0; swap_mode = 0;

        repeat (20) @(posedge wr_clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        // ================================================================
        // T6 先做：空闲期塞残留字，`mem_ready` 必须等 FIFO 真排空才给
        //   （若 mem_ready 提前给，上一帧残留像素会被当成本帧开头 ⇒ CRC 必错）
        // ================================================================
        $display("[TB] T6: stray words while idle must be drained before mem_ready");
        t6_arm = 1'b1; t6_low = 1'b0;
        feed_mode = 1; start_feed(2, 0); wait_feed_done();
        repeat (30) @(posedge clk);
        t6_arm = 1'b0;
        check(t6_low == 1'b1, "T6a) mem_ready dropped while the FIFO held stray words");
        wait_ready(20000);
        check(mem_ready === 1'b1, "T6b) mem_ready re-asserts after the FIFO is drained");
        check(mem[`SV_IMG0_BASE>>2] !== 32'hDEAD_BEEF,
              "T6c) stray words were drained, not written into a slot");
        check(state_o === S_DRAIN, "T6d) sink is in S_DRAIN after draining");

        // ================================================================
        // T1 正常一帧：top_down=0（自底向上文件序）→ 写 slot 1
        //   ★ 本条同时是"S_WRITE 超时必须是**无进展**语义"的回归防线：
        //     本帧在 50 MHz 喂满 153600 个字要 ~3 ms，远大于 WRITE_TO(160 us)。
        //     若有人把超时改回"按总时长计"，T1 会立刻失败（这正是板级真实故障）。
        // ================================================================
        $display("[TB] T1: normal frame, top_down=0 -> slot 1 (pixel-exact)");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T1a) frame_done toggled for frame 1");
        check(frame_cnt === 16'd1, "T1b) frame_cnt == 1");
        check(px_written === 19'd307200, "T1c) exactly 307200 pixels written by the bridge");
        check(swap_slot === 2'd1, "T1d) swap request carried slot 1");
        check(swap_crc_ok === 1'b1, "T1e) swap request carried crc_ok=1");
        check(last_frame_ok === 1'b1, "T1f) last_frame_ok = 1");
        check(err_code === 8'h00, "T1g) no error code after a good frame");
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T1h) back to S_DRAIN with mem_ready=1");
        cmp_frame(SLOT1_WORD, "T1i) slot 1 content (frame 1, top_down=0)");

        // ================================================================
        // T2 ★ 行序：紧接着再跑一帧 top_down=1（自顶向下文件序）
        //   ★ 这一条专抓"开帧时 top_down 还是**上一幅**的值"的缺陷 ——
        //     两帧朝向不同才会暴露；若沿用上一帧的 0，本帧会整幅上下翻转。
        // ================================================================
        $display("[TB] T2: next frame with top_down=1 -> slot 0 (catches stale orientation)");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b1; slot <= 2'd0; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 1);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T2a) frame_done toggled for frame 2");
        check(frame_cnt === 16'd2, "T2b) frame_cnt == 2");
        check(swap_slot === 2'd0, "T2c) swap request carried slot 0");
        check(swap_generation === 8'd3, "T2d) swap_generation incremented twice (now 3)");
        wait_ready(20000);
        cmp_frame(SLOT0_WORD, "T2e) slot 0 content (frame 2, top_down=1)");

        // ================================================================
        // T3 换帧 busy **一直高**（core 卡在 busy）→ 必须仍超时兜底
        // ================================================================
        $display("[TB] T3: swap_busy stuck HIGH must still time out (liveness)");
        wait_ready(20000);
        swap_mode = 1;
        swap_busy = 1'b1;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(SWAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T3a) frame_done still toggled while swap_busy stayed high");
        swap_mode = 0; swap_busy = 1'b0;
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T3b) recovered to S_DRAIN with mem_ready=1");

        // ================================================================
        // T4 换帧 busy **从不拉高**（core 拒绝）→ 同样超时兜底
        // ================================================================
        $display("[TB] T4: swap_busy never asserts must still time out");
        wait_ready(20000);
        swap_mode = 2;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd0; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(SWAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T4a) frame_done toggled although swap_busy never asserted");
        swap_mode = 0;
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T4b) recovered to S_DRAIN with mem_ready=1");

        // ================================================================
        // T5 帧内断流：只开帧、一个像素都不给
        //   → sink 的 S_WRITE **无进展**兜底触发（WRITE_TO）→ S_ERROR
        //   并验证：frame_done 兜底翻一次（SD 侧能推进）+ err_code **粘滞**
        // ================================================================
        $display("[TB] T5: starve the frame -> S_WRITE no-progress timeout -> S_ERROR, sticky err_code");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        // 不给任何像素，等 sink 自己超时
        guard = 0;
        while (state_o !== S_ERROR && guard < 200000) begin @(posedge clk); guard = guard + 1; end
        check(state_o === S_ERROR, "T5a) sink entered S_ERROR on frame stall");
        check(err_code !== 8'h00, "T5b) sink latched a non-zero err_code");
        wait_frame_done(GAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T5c) frame_done toggled from S_ERROR (SD side can advance)");
        wait_ready(20000);
        check(state_o === S_DRAIN, "T5d) sink returned to S_DRAIN after the error");
        // ★ 粘滞：回到 S_DRAIN 后错误码**不应**被清掉（否则 500 ms 才刷一次的状态行看不到）
        check(err_code !== 8'h00, "T5e) err_code is STICKY after leaving S_ERROR");

        // 再来一帧成功的 → 错误码应被清掉（"证明能工作了才清"）
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T5f) a subsequent good frame completes");
        check(err_code === 8'h00, "T5g) sticky err_code cleared by a successful frame");

        $display("============================================");
        if (errors == 0) $display("  BMP-FRAME-SINK PASS (0 error)");
        else             $display("  BMP-FRAME-SINK FAIL (%0d error)", errors);
        $display("============================================");
        $finish;
    end

    // 总看门狗
    integer wd;
    initial begin
        wd = 0;
        while (wd < 60_000_000) begin @(posedge clk); wd = wd + 1; end
        $display("[FAIL] watchdog: state=%0d err=0x%02x/0x%02x cnt=%0d px=%0d",
                 state_o, err_code, err_detail, frame_cnt, px_written);
        $display("  BMP-FRAME-SINK FAIL (watchdog)");
        $finish;
    end

endmodule
