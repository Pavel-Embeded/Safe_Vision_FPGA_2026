// ============================================================================
// tb_top_sdram_loopback.sv — 板级 SDRAM 回环顶层（`top_sdram_loopback`）**带桩仿真**
// ----------------------------------------------------------------------------
// ★★ 为什么以前没有这个 TB、现在有了
//   该顶层例化的是两个 ModelSim 编译不了的单元（安路 RSA 加密的 `sdr_*.enc.v`
//   与 TD 的 `EG_PHY_PLL` 宏），所以历史上**进不了回归**、只能烧板。
//   但"顶层的状态机 / soak 循环 / 报告装配 / 地址生成 / 图案生成"**都是我们自己的逻辑**，
//   用 `verification/models/vendor_ip_stub.sv` 把那两个黑盒顶掉就能测。
//
// ★★ 本 TB 能证明什么 / 不能证明什么（**务必分清**）
//   能：① 上电 → 等 init →（写 → 等落地 → 读 → 等收齐）× ROUNDS → 发报告 这条**序列真会跑完**；
//       ② 报告是**定长 190 Byte** 且**逐字节正确**（含 `CFG` / `RND` / `PAT` / `TOT` / `BAD0`）；
//       ③ **soak 轮次与图案模式轮换真的生效**（`RND=3/3`、`PAT=2`、`TOT=3×1024`）；
//       ④ **出错立即停（fail fast）**：注入 1 bit 错后只跑 1 轮就出报告，
//          且 `BAD0` 精确定位到**轮次 : 地址 / 期望 / 实际**；
//       ⑤ `led[3:0]` 最终 = `8`（全通过）或 `3`（数据不一致）。
//   不能：**SDRAM 的协议与数据完整性** —— 桩是理想存储器（不模拟初始化/刷新/CAS/突发窗口/
//       地址每拍自增，也永远不会报协议错），写进去立刻就能无损读出来，所以这里 `BAD=0000`
//       是**构造保证**的。⇒ 协议与数据完整性**仍然只认 M-11 / 阶段 10 的上板实测**。
//
// 过关标准（2026-10-04；`ROUNDS=3` 覆盖 soak 循环）：
//   阶段 1（不注入故障，3 轮全过）：
//     T1  报告恰好 190 Byte
//     T2  报告**逐字节**与期望串一致
//     T2b `RND` 行正确（证明 soak 真的跑了 3 轮、图案模式轮换到 2）
//     T3  顶层最终进成功态：`led[3:0] == 4'h8`
//   阶段 2（第 2 轮 mode 1，在 0x2805 注入 1 bit 错）：
//     T4  报告恰好 190 Byte（**第 2 轮检测到错误后停止，不进入第 3 轮**）
//     T5  报告**逐字节**一致 —— `RND=2/3 PAT=1`、`BAD=0001`、
//         `BAD0=00000002:002805 E=64F2D804 A=64F2D805`
//     T5b `BAD0` 行正确（第 2 轮:地址 定位正确）
//     T6  `led[3:0] == 4'h3`（错误主码 03 = 数据不一致）
// ============================================================================
`timescale 1ns / 1ps

module tb_top_sdram_loopback;

    // ---- 板载 50 MHz（R7）----
    reg clk = 1'b0;
    always #10 clk = ~clk;

    // ---- 采样用的 125 MHz（与桩内部产生的那一路同频同相：都从 0 开始）----
    reg clk125 = 1'b0;
    always #4 clk125 = ~clk125;

    reg  rst_n = 1'b0;
    wire uart_txd;
    wire [3:0] led;

    // ------------------------------------------------------------------------
    // DUT：只缩短"等待类"参数（上电/超时），**测试内容保持默认**
    //   ⇒ TEST_WORDS = 1024、ADDR_SHIFT = 11、ADDR_LOWSTEP = 1（全片稀疏扫描）
    //   ⇒ ROUNDS = 3（覆盖 soak 循环与图案模式轮换；板上默认是 1）
    // ------------------------------------------------------------------------
    top_sdram_loopback #(
        .POWERUP_CYC    (24'd200),
        .INIT_TO_CYC    (24'd2000),
        .RD_WAIT_TO_CYC (20'd20000),
        .ROUNDS         (32'd3)
    ) u_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_txd (uart_txd),
        .led      (led)
    );

    // ------------------------------------------------------------------------
    // UART 8N1 接收模型（115200，DIV = 125e6/115200 = 1085）
    //   等起始位下降沿 → 1.5 bit 后采 bit0 → 之后每 1 bit 采一位
    //   ★ 两个阶段共用同一个接收循环：**不清 rx_n**，改用 `base` 偏移取第二段
    //     （rx_n / rxbuf 只由这一个 initial 块写，避免双驱动）
    // ------------------------------------------------------------------------
    localparam integer DIV = 1085;

    reg [7:0] rxbuf [0:511];
    integer   rx_n;
    integer   base;
    integer   b;
    reg [7:0] rx_byte;

    initial begin
        rx_n = 0;
        forever begin
            @(negedge uart_txd);
            repeat (DIV + DIV/2) @(posedge clk125);      // 落到 bit0 中心
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_txd;
                if (b != 7) repeat (DIV) @(posedge clk125);
            end
            if (rx_n < 512) begin
                rxbuf[rx_n] = rx_byte;
                rx_n = rx_n + 1;
            end
            repeat (DIV/2) @(posedge clk125);            // 让过停止位
        end
    end

    // ------------------------------------------------------------------------
    // 断言工具
    // ------------------------------------------------------------------------
    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // 期望报告（阶段 1：ROUNDS=3，3 轮全过；模式循环 0→1→2，故最后一轮 PAT=2）
    localparam [8*190-1:0] EXP1 = {
        "SV-SDRAM-LOOP",                               8'h0D, 8'h0A,
        "INIT=01 LOCK=01",                             8'h0D, 8'h0A,
        "CFG=0B1 BASE=000000 N=000400",                8'h0D, 8'h0A,
        "RND=00000003/00000003 PAT=2",                 8'h0D, 8'h0A,
        "W=0400 R=0400 CAP=0400 BAD=0000",             8'h0D, 8'h0A,
        "TOT=0000000C00",                              8'h0D, 8'h0A,
        "BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000",  8'h0D, 8'h0A,
        "DONE",                                        8'h0D, 8'h0A
    };

    // 期望报告（阶段 2：第 2 轮 mode 1，在 0x2805 注入 1 bit 错）
    //   0x2805 = 5 * 2049（第 6 个测试点）；mode 1 的 xorshift32 图案 = 0x64F2D804
    localparam [8*190-1:0] EXP2 = {
        "SV-SDRAM-LOOP",                               8'h0D, 8'h0A,
        "INIT=01 LOCK=01",                             8'h0D, 8'h0A,
        "CFG=0B1 BASE=000000 N=000400",                8'h0D, 8'h0A,
        "RND=00000002/00000003 PAT=1",                 8'h0D, 8'h0A,
        "W=0400 R=0400 CAP=0400 BAD=0001",             8'h0D, 8'h0A,
        "TOT=0000000800",                              8'h0D, 8'h0A,
        "BAD0=00000002:002805 E=64F2D804 A=64F2D805",  8'h0D, 8'h0A,
        "DONE",                                        8'h0D, 8'h0A
    };

    // 单行文本落成定宽 localparam 向量再比（便于失败时定位）
    localparam [8*27-1:0] RND1_EXP   = "RND=00000003/00000003 PAT=2";
    localparam [8*42-1:0] BAD0_2_EXP = "BAD0=00000002:002805 E=64F2D804 A=64F2D805";

    // ★★ 切片口径（踩过一次，写清楚）：`got` 里**第 0 个收到的字节在最高位**，
    //   所以"流字节 [a..b]"对应的切片是 `got[8*(189-b) +: 8*(b-a+1)]`
    //   —— **基址按末字节 b 取，不是首字节 a**。按 a 取会把字节顺序倒过来，
    //   表现是"整串比对（T2）通过、单行比对（T2b/T5b）却失败"。
    //   字节布局（190 B）：L1 0..14 / L2 15..31 / L3 32..61 / L4 62..90 /
    //                      L5 91..123 / L6 124..139 / L7 140..183 / L8 184..189
    localparam [10:0] RND_LO  = 8*(189-88);    // RND  行文本 = 字节 62..88
    localparam [10:0] BAD0_LO = 8*(189-181);   // BAD0 行文本 = 字节 140..181

    reg [8*190-1:0] got;
    integer i;

    // 看门狗（两段报告各约 16.5 ms 仿真时间 ⇒ 给足 200 ms）
    initial begin
        #200_000_000;
        $display("[FAIL] tb_top_sdram_loopback 看门狗超时（rx_n=%0d, led=%0d）", rx_n, led);
        $finish;
    end

    // ------------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        // ================= 阶段 1：不注入故障，ROUNDS=3 全部通过 =================
        wait (rx_n >= 190);
        #100000;                        // 再给状态机几拍进 ST_OK

        check(rx_n == 190, "T1 报告恰好 190 Byte（3 轮）");

        got = 0;
        for (i = 0; i < 190; i = i + 1)
            got = { got[8*189-1:0], rxbuf[i] };
        if (got !== EXP1) begin
            $display("[INFO] got[0..7]     = %02x %02x %02x %02x %02x %02x %02x %02x",
                     rxbuf[0], rxbuf[1], rxbuf[2], rxbuf[3],
                     rxbuf[4], rxbuf[5], rxbuf[6], rxbuf[7]);
            $display("[INFO] got[62..67]   = %02x %02x %02x %02x %02x %02x",
                     rxbuf[62], rxbuf[63], rxbuf[64], rxbuf[65], rxbuf[66], rxbuf[67]);
            $display("[INFO] got[124..129] = %02x %02x %02x %02x %02x %02x",
                     rxbuf[124], rxbuf[125], rxbuf[126], rxbuf[127], rxbuf[128], rxbuf[129]);
        end
        check(got === EXP1, "T2 报告逐字节正确（190 Byte，3 轮全过）");
        check(got[RND_LO +: 8*27] === RND1_EXP,
              "T2b RND 行正确（RND=00000003/00000003 PAT=2）");
        check(led === 4'h8, "T3 led = 8（成功态）");

        // ================= 阶段 2：在**第 2 轮 mode 1**注入 1 bit 错，验证 BAD0 锁存 =================
        base = rx_n;                                // 第二段报告的起始偏移
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        // 等到第 2 轮已完成写入、处于写落地等待期间，再只对读回注入故障。
        //   这样测试的是"前一轮无错 → 下一轮首次错误 → BAD0 必须记录第 2 轮信息"，
        //   正好复现 111710 那次板上现象（RND=2、BAD=1、BAD0 却仍是无错哨兵）。
        wait ((u_top.rnd === 32'd1) && (u_top.st === 4'd3));
        u_top.u_sdram.STUB_ERR_ADDR = 21'h002805;   // 5 * 2049（第 6 个稀疏点）
        u_top.u_sdram.STUB_ERR_XOR  = 32'h00000001;

        wait (rx_n >= base + 190);
        #100000;

        check((rx_n - base) == 190, "T4 报告恰好 190 Byte（注入故障后只跑 1 轮）");

        got = 0;
        for (i = 0; i < 190; i = i + 1)
            got = { got[8*189-1:0], rxbuf[base + i] };
        if (got !== EXP2) begin
            $display("[INFO] got[62..67]   = %02x %02x %02x %02x %02x %02x",
                     rxbuf[base+62], rxbuf[base+63], rxbuf[base+64],
                     rxbuf[base+65], rxbuf[base+66], rxbuf[base+67]);
            $display("[INFO] got[140..147] = %02x %02x %02x %02x %02x %02x %02x %02x",
                     rxbuf[base+140], rxbuf[base+141], rxbuf[base+142], rxbuf[base+143],
                     rxbuf[base+144], rxbuf[base+145], rxbuf[base+146], rxbuf[base+147]);
        end
        check(got === EXP2, "T5 报告逐字节正确（含 BAD=0001 与 BAD0 定位）");
        check(got[BAD0_LO +: 8*42] === BAD0_2_EXP,
              "T5b BAD0 定位正确（轮次:地址 期望 实际）");
        check(led === 4'h3, "T6 led = 3（数据不一致）");

        $display("[TB] tb_top_sdram_loopback done, errors=%0d (rx_n=%0d, led=%0h)", errors, rx_n, led);
        $finish;
    end

endmodule
