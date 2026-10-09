// ============================================================================
// tb_safevision_top.sv — 板级顶层 `safevision_top` 的仿真（此前**零覆盖**）
// ----------------------------------------------------------------------------
// 为什么需要它：`safevision_top` 以前**不在任何 TB 里**，只过 TD 综合 + STA。
//   而方案 A 恰恰改了顶层的一大块**只有顶层才有**的逻辑：
//     · player 挂板载 50 MHz、sink 挂 mem_clk（跨域边界在顶层）
//     · **遥测两级同步层**（`t_*`）+ UART 状态行的字段映射（PX/F/SLOT/CRC 改指 sink）
//     · `card_mode` 回落判据 + `!fb_go` 守卫
//     · 按键消抖搬到 player 的时钟域
//   这些都不在任何单元 TB 里 ⇒ 本 TB 专门覆盖它们。
//
// 覆盖内容（本 TB 用**卡不可用**的场景，因为回落路径 + 遥测/卡路径判据都在这一支）：
//   T1 复位 / PLL 锁定 / SDRAM 初始化 → `led[0]`
//   T2 顶层真的把 UART 状态行发出来了，且**格式正确**（定长 107 字节 + CRLF + 各字段标签）
//   T3 卡不可用时：`SD=0`、`CARD=0`（顶层遥测同步层把 player 的状态搬过来了）
//   T4 超时后 `card_mode` 回落（1→0）且 `fb_go/fb_submitted` 起 → 片上图案接管 + `led[2]`
//   T5 HDMI AXI-Stream 真的在跑（发送核桩统计 beat 数上涨）且 `video_locked`
//   T6 按键消抖确实在 **player 的时钟域**工作（脉冲 btn_next → `btn_next_db` 起）
//
// ★ 不能证明什么（别越界）：
//   · 三个厂商 IP 是**桩**（见 models/top_ip_stub.sv）⇒ 不证明 HDMI/TMDS/DDC/EDID/PLL 任何电气或协议层面的事；
//   · SDRAM 是**理想存储器桩** ⇒ 不证明 SDRAM 协议/时序/数据完整性；
//   · 本 TB 用**卡不可用**的场景 ⇒ **"顶层 + 真卡" 这条链没有被本 TB 覆盖**
//     （SD 初始化/挂载/整帧播放由 `tb_sd_bmp_player` 在 player+sink 层面覆盖）；
//   · 不证明 TD 综合/布局布线/STA。
// ============================================================================
`timescale 1ns/1ps

module tb_safevision_top;

    // ---------------------------------------------------------------- 板级时钟/复位
    reg clk   = 1'b0;   always #10 clk = ~clk;      // R7：50 MHz
    reg rst_n = 1'b0;                               // A2：低有效

    integer errors = 0;
    task check;
        input        cond;
        input string msg;
        begin
            if (cond) $display("[PASS] %s", msg);
            else begin $display("[FAIL] %s", msg); errors = errors + 1; end
        end
    endtask

    // ---------------------------------------------------------------- DUT 引脚
    reg  btn_next = 1'b1, btn_auto = 1'b1;
    wire uart_txd;
    wire [3:0] led;
    wire sd_ncs, sd_dclk, sd_mosi, sd_miso;
    wire HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P, HDMI_DDC_SCL;
    wire HDMI_DDC_SDA;

    // ★ 缩短两个"等"的参数（都只是可测性参数，TD 不覆盖 ⇒ 综合结果不变）：
    //   MODE_TO_N   = 4 ms 判卡不可用（50 MHz）
    //   RPT_PERIOD_N= 3 ms 发一次状态行（一行 107 字节 @115200 要 ~9.3 ms）
    safevision_top #(
        .HD(0),
        .MODE_TO_N(32'd200_000),
        .RPT_PERIOD_N(32'd150_000),
        .FONT_FILE("font8x16.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .btn_next(btn_next), .btn_auto(btn_auto),.btn_emergency(1'b1),
        .uart_txd(uart_txd), .led(led),
        .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .HDMI_D0_P(HDMI_D0_P), .HDMI_D1_P(HDMI_D1_P), .HDMI_D2_P(HDMI_D2_P),
        .HDMI_CLK_P(HDMI_CLK_P),
        .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA)
    );

    // ---------------------------------------------------------------- SD 卡模型（卡不可用）
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;
    sd_spi_card_model #(.VOL_BASE(32'd16), .VOL_SECTORS(2048)) u_card (
        .sclk(sd_dclk), .cs_n(sd_ncs), .mosi(sd_mosi), .miso(sd_miso),
        .i_dead(1'b1),                              // ★ 卡不可用 ⇒ 走回落路径
        .o_cmd(o_cmd), .o_arg(o_arg), .o_acmd41_arg(o_acmd41_arg),
        .o_cmd_cnt(o_cmd_cnt), .o_acmd41_cnt(o_acmd41_cnt), .o_cmd_valid(o_cmd_valid)
    );

    // ---------------------------------------------------------------- UART 接收（按 mem_clk 采样）
    // Board memory/UART domain is now 50 MHz; receive the physical 115200 baud
    // line using the same declared frequency, rather than the legacy 125 MHz.
    localparam integer BIT_TICKS = 50_000_000 / 115_200;      // 434

    task uart_get_byte;
        output [7:0] b;
        output       ok;
        integer i;
        begin
            ok = 1'b0; b = 8'h00;
            @(negedge uart_txd);                            // 起始位
            repeat (BIT_TICKS/2) @(posedge dut.mem_clk);    // 到起始位中心
            if (uart_txd !== 1'b0) ok = 1'b0;               // 起始位校验失败
            else begin
                for (i = 0; i < 8; i = i + 1) begin
                    repeat (BIT_TICKS) @(posedge dut.mem_clk);
                    b[i] = uart_txd;
                end
                repeat (BIT_TICKS) @(posedge dut.mem_clk);  // 停止位
                ok = 1'b1;
            end
        end
    endtask

    // 抓一整行到 line[]；返回长度
    reg [7:0] line [0:255];
    integer   line_len;
    task uart_get_line;
        integer n; reg [7:0] b; reg ok;
        begin
            line_len = 0;
            // 先找到 "SV" 开头（行首）
            for (n = 0; n < 400; n = n + 1) begin
                uart_get_byte(b, ok);
                if (ok && b == 8'h53) begin                 // 'S'
                    uart_get_byte(line[1], ok);
                    if (ok && line[1] == 8'h56) begin       // 'V'
                        line[0] = 8'h53; line_len = 2;
                        // 继续收到 CRLF
                        for (n = 2; n < 200; n = n + 1) begin
                            uart_get_byte(line[n], ok);
                            if (!ok) begin n = 200; end
                            else begin
                                line_len = line_len + 1;
                                if (line[n] == 8'h0A) n = 200;   // LF 结束
                            end
                        end
                        n = 400;
                    end
                end
            end
        end
    endtask

    // 在 line 里找子串（ASCII），返回起始下标，找不到返回 -1
    function integer find_str;
        input [8*8-1:0] pat;          // 最多 8 字符
        input integer   plen;
        integer i, j, hit;
        begin
            find_str = -1;
            for (i = 0; i <= line_len - plen; i = i + 1) begin
                hit = 1;
                for (j = 0; j < plen; j = j + 1)
                    if (line[i+j] !== pat[(plen-1-j)*8 +: 8]) hit = 0;
                if (hit && find_str < 0) find_str = i;
            end
        end
    endfunction

    function [3:0] hexval;
        input [7:0] c;
        begin
            if (c >= 8'h30 && c <= 8'h39) hexval = c - 8'h30;
            else if (c >= 8'h41 && c <= 8'h46) hexval = c - 8'h37;
            else hexval = 4'hF;
        end
    endfunction

    // T6 用：脉冲是**单拍**的，轮询可能擦肩而过 ⇒ 用监视器锁存"见过脉冲"
    reg saw_next_pulse = 1'b0;
    reg saw_auto_hold  = 1'b0;
    always @(posedge clk) begin
        if (dut.btn_next_db) saw_next_pulse <= 1'b1;
        if (dut.btn_auto_db) saw_auto_hold  <= 1'b1;
    end

    // T4 用：统计 mem→sys 的 frame_ready 事件（1 拍脉冲，随机采样会漏）
    integer fr_pulses = 0;
    always @(posedge dut.sys_clk) if (dut.frame_ready) fr_pulses <= fr_pulses + 1;

    // T7 探针用：vsync 脉冲计数 + commit 的 pending 是否曾置起
    integer vs_pulses = 0;
    reg pending_seen = 1'b0;
    always @(posedge dut.pixel_clk) begin
        if (dut.core.display.scan_frame_start) vs_pulses <= vs_pulses + 1;
        if (dut.core.display.slot.pending) pending_seen <= 1'b1;
    end

    // ========================================================================
    // T8 ★ 缺陷 26 回归：SD 初始化自动重试的"沉降窗"必须对**每一次**重试成立
    //   旧实现 `S_INITR` 不清 `init_arm` ⇒ 重试回到 `S_INIT` 那一拍它仍是饱和值 7
    //   ⇒ `if (init_arm >= 4)` 立刻成立，而 `init_error` 是电平、还没被新 start 的
    //   `do_soft_reset` 清掉 ⇒ **立刻再判一次错** ⇒ 16 次重试在 ~30 拍内烧完
    //   （真正跑起来的初始化尝试 ≈8 次）—— 这就是"自动重试没救活卡"的原因。
    //   本 TB 用**卡不可用**场景 ⇒ 必然走重试路径 ⇒ 这里能抓到。
    //   检查点：每次从 `S_INITR` 回到 `S_INIT` 时，`init_arm` 必须已为 0。
    // ========================================================================
    localparam [3:0] T8_S_INIT  = 4'd1;    // 与 sd_bmp_player 的状态编码一致
    localparam [3:0] T8_S_INITR = 4'd11;
    integer t8_retries = 0;                // 观察到的"重试回到 S_INIT"次数
    integer t8_bad_arm = 0;                // 其中 init_arm 没清零的次数
    reg     t8_prev_initr = 1'b0;
    always @(posedge dut.player.clk) begin
        t8_prev_initr <= (dut.player.state_o == T8_S_INITR);
        if (t8_prev_initr && (dut.player.state_o == T8_S_INIT)) begin
            t8_retries = t8_retries + 1;
            if (dut.player.init_arm !== 3'd0) t8_bad_arm = t8_bad_arm + 1;
        end
    end

    // ---------------------------------------------------------------- 主流程
    integer guard;
    reg [7:0] b; reg ok;
    initial begin
        btn_next = 1'b1; btn_auto = 1'b1;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        // ================================================================
        // T1 复位 / 锁定 / SDRAM 初始化 → led[0]
        //   led[0] = sys_lock && video_lock && sdr_init_done
        // ================================================================
        $display("[TB] T1: reset -> PLL lock + SDRAM init (led[0])");
        guard = 0;
        while (!led[0] && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(led[0] === 1'b1, "T1a) led[0]=1 (sys/video PLL locked + SDRAM init done)");

        // ================================================================
        // T2/T3 UART 状态行：格式 + 卡不可用的字段
        // ================================================================
        $display("[TB] T2: UART status line format + fields (card unusable)");
        uart_get_line;
        check(line_len == 107, "T2a) status line is exactly 107 bytes");
        check(line[105] == 8'h0D && line[106] == 8'h0A, "T2b) status line ends with CRLF");
        check(find_str("SV-PLAY", 7) == 0, "T2c) status line starts with 'SV-PLAY'");
        check(find_str(" ST=", 4) > 0, "T2d) status line has ' ST=' field");
        check(find_str(" SD=", 4) > 0, "T2e) status line has ' SD=' field");
        check(find_str(" CARD=", 6) > 0, "T2f) status line has ' CARD=' field");
        check(find_str(" RD=", 4) > 0, "T2g) status line has ' RD=' field");
        check(find_str(" PX=", 4) > 0, "T2h) status line has ' PX=' field (from sink)");
        check(find_str(" F=", 3) > 0, "T2i) status line has ' F=' field (from sink)");
        check(find_str(" SLOT=", 6) > 0, "T2j) status line has ' SLOT=' field (from sink)");
        check(find_str(" CRC=", 5) > 0, "T2k) status line has ' CRC=' field (from sink)");
        check(find_str(" ED=", 4) > 0, "T2l) status line has ' ED=' field (err_detail)");
        // ED 是两位 hexc：这里只验**格式**（两位合法十六进制），不绑具体值 ——
        // 现在 player 会先自动重试 16 次，抓这一行时可能还没锁存错误（ED=00），
        // 也可能已经失败（ED=11/21/22/23）。绑值会让 TB 变脆。
        begin
            integer ed_i;
            reg [7:0] e0, e1;
            ed_i = find_str(" ED=", 4);
            e0 = line[ed_i+4]; e1 = line[ed_i+5];
            check(((e0 >= 8'h30 && e0 <= 8'h39) || (e0 >= 8'h41 && e0 <= 8'h46)) &&
                  ((e1 >= 8'h30 && e1 <= 8'h39) || (e1 >= 8'h41 && e1 <= 8'h46)),
                  "T2m) ED= field carries two hex digits");
        end
        // R1 / SQ：SD 初始化诊断（只验格式与字段存在，不绑值——卡不可用场景下
        // R1 的具体值取决于卡/接触，TB 里没有真卡）
        check(find_str(" R1=", 4) > 0, "T2n) status line has ' R1=' field (SD R1 byte)");
        check(find_str(" SQ=", 4) > 0, "T2o) status line has ' SQ=' field (SD command index)");
        // SD=0 / CARD=0（卡不可用）—— 这两个字段来自顶层遥测同步层
        begin
            integer i, sd_i, cd_i;
            sd_i = find_str(" SD=", 4);
            cd_i = find_str(" CARD=", 6);
            check(line[sd_i+4] === 8'h30, "T3a) SD=0 with an unusable card");
            check(line[cd_i+6] === 8'h30, "T3b) CARD=0 with an unusable card");
        end

        // ================================================================
        // T4 回落：card_mode 1→0 且片上图案接管
        // ================================================================
        $display("[TB] T4: fallback takes over when the card never becomes usable");
        guard = 0;
        while (dut.card_mode !== 1'b0 && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.card_mode === 1'b0, "T4a) card_mode fell back to 0 (card unusable)");
        guard = 0;
        while (!dut.fb_submitted && guard < 8_000_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.fb_submitted === 1'b1, "T4b) fallback pattern was written and submitted");
        // ★ led[1] = "回落帧已提交且 CRC 通过"（顶层注释原来把 led[1]/led[2] 写反了，已更正）
        check(led[1] === 1'b1, "T4c) led[1]=1 (fallback frame available + CRC ok)");
        // 换帧事件**跨域送达 core 的 sys 域**（mem→sys 打包同步这一段是顶层的活）
        //   ★ core 的"提交 + 显示激活"（active）由 T7 正式覆盖：曾观察到 active 不置起
        //     （fr_pulses=1、swap_state=0、swap_error=0、active=0），根因是顶层打包跨域的
        //     载荷与 frame_ready 同拍捕获导致首帧请求被丢（非 SDRAM 桩问题），已修复。
        // Submission is a MEM-domain event, not arrival at the SYS mailbox.
        // Bound the actual crossing instead of sampling on the submission edge.
        guard=0;
        while(fr_pulses<1 && guard<100)begin @(posedge dut.sys_clk);guard=guard+1;end
        check(fr_pulses >= 1, "T4d) fallback swap event reached the core sys domain");
        check(dut.player.frame_cnt === 16'd0, "T4e) card path never produced a frame (frame_cnt=0)");

        // ================================================================
        // T5 HDMI 路真的在跑
        // ================================================================
        $display("[TB] T5: HDMI AXI-Stream is alive");
        check(dut.transmitter.O_video_locked === 1'b1, "T5a) transmitter reports video_locked");
        check(dut.transmitter.axis_beats > 1000,
              "T5b) HDMI AXI-Stream beats are flowing (display chain alive)");
        check(dut.transmitter.axis_lasts > 10,
              "T5c) line 'last' beats are flowing (timing generator alive)");
        check(dut.hdmi_backpressure === 1'b0, "T5d) no HDMI backpressure fault latched");

        // ================================================================
        // T6 按键消抖：在 player 的 50 MHz 域里工作，且语义正确
        //   ★ 这里专门验证"松开时不能算按下"（原实现的 `btn_next_db` 恒 1）
        // ================================================================
        $display("[TB] T6: button debounce runs in the player's 50 MHz domain");
        check(dut.btn_next_db === 1'b0, "T6a) next-button idle low (released != pressed)");
        check(dut.btn_auto_db === 1'b0, "T6b) auto-play idle low");

        @(posedge clk); btn_next = 1'b0; btn_auto = 1'b0;
        // 等消抖电平落定（约 65536 个 clk 拍）
        guard = 0;
        while (!dut.dn_db && guard < 200_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.dn_db === 1'b1, "T6c) debounced press level asserted");
        check(guard > 60_000,
              "T6d) debounce took ~65536 clk cycles (it really runs on the 50 MHz domain)");
        // ★ 监视器在**下一个沿**才采样到脉冲 ⇒ 先放几拍再看，否则会误判"没出脉冲"
        repeat (4) @(posedge clk);
        check(saw_next_pulse === 1'b1, "T6e) next-button produced a press pulse");
        check(saw_auto_hold  === 1'b1, "T6f) auto-play produced a held level");
        // 按住不放时，btn_next 只应出**一次**脉冲（不能每拍都"下一幅"）
        repeat (2000) @(posedge clk);
        check(dut.btn_next_db === 1'b0,
              "T6g) next-button stays low while held (one-shot pulse, not a level)");
        check(dut.btn_auto_db === 1'b1, "T6h) auto-play stays high while held (level)");
        @(posedge clk); btn_next = 1'b1; btn_auto = 1'b1;

        // ================================================================
        // T7 换帧全链路：commit → pending → 下一个 frame_start → active
        //   ★ 覆盖原"未查清项"：active 曾不置起。根因 = 顶层 mem→sys 打包跨域的
        //     载荷与 frame_ready 同拍捕获（swap_ctrl 看到旧 crc_sys=0，首帧请求被丢）。
        //     修复后这里正式断言，一整帧 VGA ≈ 834k 个 50MHz 拍，给 2M 余量。
        // ================================================================
        $display("[TB] T7: swap commit reaches the display (pending -> active)");
        guard = 0;
        while (dut.active !== 1'b1 && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(pending_seen === 1'b1, "T7a) swap request reached pixel-domain commit (pending set)");
        check(dut.active === 1'b1, "T7b) display activated (active=1) within 2 video frames");
        check(led[2] === 1'b1, "T7c) led[2]=1 (picture active, no swap error)");
        $display("[TB] T7 info: active=%b after %0d clk (vs_pulses=%0d swap_error=%b frame_fault=%b)",
                 dut.active, guard, vs_pulses, dut.swap_error, dut.frame_fault);

        // ----------------------------------------------------------------
        // T8 缺陷 26 回归（卡不可用 ⇒ 必然走过自动重试路径）
        // ----------------------------------------------------------------
        $display("[TB] T8: SD init auto-retry settle window (defect 26)");
        $display("[TB] T8 info: retries seen=%0d, bad init_arm on entry=%0d",
                 t8_retries, t8_bad_arm);
        check(t8_retries > 0, "T8a) SD init failure did go through the auto-retry path");
        check(t8_bad_arm == 0, "T8b) init_arm was cleared on every retry entry (defect 26)");

        $display("============================================");
        if (errors == 0) $display("  SAFEVISION-TOP PASS (0 error)");
        else             $display("  SAFEVISION-TOP FAIL (%0d error)", errors);
        $display("============================================");
        $finish;
    end

    // 总看门狗
    integer wd;
    initial begin
        wd = 0;
        while (wd < 60_000_000) begin @(posedge clk); wd = wd + 1; end
        $display("[FAIL] watchdog: card_mode=%b fb_submitted=%b pl_state=%0d pl_ec=0x%02x led=%b",
                 dut.card_mode, dut.fb_submitted, dut.pl_state, dut.pl_ec, led);
        $display("  SAFEVISION-TOP FAIL (watchdog)");
        $finish;
    end

endmodule
