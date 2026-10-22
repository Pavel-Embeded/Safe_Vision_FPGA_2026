// ============================================================================
// tb_bram_adapter_aligned.sv — 突发桥适配器单元 TB（逐字事务口 <-> 厂商 App 口）
// ----------------------------------------------------------------------------
// 被测：platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v
//
// ★ 为什么要有这个 TB：适配器接的是**安路加密 IP**（sdr_*.enc.v），整机没法仿真；
//   但适配器**自身**的逻辑可以被仿真 —— 只要在 TB 里放一个"厂商 app 口行为模型"。
//
// ★★ 本 TB 的厂商模型按 **M-11 已验形态** 写（`top_sdram_loopback.v`，板上跑通
//   4096 个连续 word、`BAD=0000`）：
//     · 写：`App_wr_en` 高就写 `App_wr_din` 到 `App_wr_addr`（按 `App_wr_dm` 选字节）；
//     · 读：`App_rd_en` 高就**每拍采样一次 `App_rd_addr`**、每拍一条读命令，
//           延迟 `RD_LAT` 拍后按 **1:1 顺序**逐拍从 `Sdr_rd_en`/`Sdr_rd_dout` 返回。
//   ★ 诚实说明：这个模型**不能**复现板上观察到的"一次突发里只推进 4 个字就回绕"
//     （那是厂商内部的实现细节，我们还没有它的规范）。但它是**唯一被实物证明可行**
//     的形态，能守住本工程最贵的那条约束 —— **连发期间地址必须每拍自增**：
//     旧版适配器（把地址推进挂在 `Sdr_rd_en` 上、延迟窗内地址"钉住"）在本 TB 下
//     必然失败（读回值会变成"同一个字重复若干拍"），新版才能过。
//   ⇒ 它**不能替代上板**，但能把"再犯同一个协议错"挡在烧板之前。
//
// 断言：
//   D1 初始化：init_done 上抬后 ready 才可用
//   D2 写突发形态：`App_wr_en` 连发期间 `App_wr_addr` **每拍 +1**（无重复/无钉住）
//   D3 写 16 个连续字（值 = 地址）全部落到正确地址
//   D4 读突发形态：`App_rd_en` 连发期间 `App_rd_addr` **每拍 +1**
//   D5 读 32 个连续字（**跨两次预取**）逐字与写入值相等
//   D6 非 16 对齐基址（字 0x1035）：写 4 读 4 正确
// ============================================================================
`timescale 1ns / 1ps

module tb_bram_adapter_aligned;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #4 clk = ~clk;              // 8 ns -> 125 MHz

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ---------------------------------------------------------------
    // 事务口（TB 当上游，时序照 mem_read_burst：req 等 ready，数据晚到）
    // ---------------------------------------------------------------
    reg         rq = 1'b0, rw = 1'b0;
    reg  [31:0] ra = 32'd0, rwd = 32'd0;
    reg  [3:0]  rstrb = 4'hF;
    wire [31:0] rd;
    wire        rvl, rdy, idn;

    // ---------------------------------------------------------------
    // 厂商 app 口
    // ---------------------------------------------------------------
    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    // 厂商模型的输出（必须用 reg：它们由下面的 always 块驱动；且要在例化之前声明）
    reg         sdr_rd_en   = 1'b0;
    reg  [31:0] sdr_rd_dout = 32'd0;

    // ★ 必须先声明：例化端口里用到它，否则会被当隐式网线、与后面的 reg 冲突
    reg         sdr_init_done = 1'b0;

    sdram_app_adapter u_dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .req               (rq),
        .wr                (rw),
        .addr              (ra),
        .wdata             (rwd),
        .wstrb             (rstrb),
        .rdata             (rd),
        .rdata_valid       (rvl),
        .ready             (rdy),
        .init_done         (idn),
        .Sdr_init_done     (sdr_init_done),
        .Sdr_init_ref_vld  (1'b0),
        .Sdr_busy          (1'b0),
        .App_wr_en         (app_wr_en),
        .App_wr_addr       (app_wr_addr),
        .App_wr_dm         (app_wr_dm),
        .App_wr_din        (app_wr_din),
        .App_rd_en         (app_rd_en),
        .App_rd_addr       (app_rd_addr),
        .Sdr_rd_en         (sdr_rd_en),
        .Sdr_rd_dout       (sdr_rd_dout)
    );

    // ---------------------------------------------------------------
    // 厂商模型
    // ---------------------------------------------------------------
    integer    init_cnt      = 0;

    localparam integer MEMW   = 1 << 16;     // 64K word 足够覆盖探针地址
    localparam integer RD_LAT = 4;           // 读命令 -> 数据 的延迟（照例程延迟应答）

    reg [31:0] mem [0:MEMW-1];

    always @(posedge clk) if (init_cnt < 100) init_cnt <= init_cnt + 1;
    always @(posedge clk) if (init_cnt >= 100) sdr_init_done <= 1'b1;

    // ---- 写侧：en 高就写（每拍一个），dm=0 表示写该字节 ----
    always @(posedge clk) begin
        if (app_wr_en) begin
            if (!app_wr_dm[0]) mem[app_wr_addr][7:0]   <= app_wr_din[7:0];
            if (!app_wr_dm[1]) mem[app_wr_addr][15:8]  <= app_wr_din[15:8];
            if (!app_wr_dm[2]) mem[app_wr_addr][23:16] <= app_wr_din[23:16];
            if (!app_wr_dm[3]) mem[app_wr_addr][31:24] <= app_wr_din[31:24];
        end
    end

    // ---- 读侧：en 高就每拍入一条命令；RD_LAT 拍后 1:1 逐拍返回 ----
    reg [20:0] pl_a [0:RD_LAT];
    reg        pl_v [0:RD_LAT];
    integer    i;

    always @(posedge clk) begin
        sdr_rd_en   <= 1'b0;
        if (pl_v[RD_LAT]) begin
            sdr_rd_en   <= 1'b1;
            sdr_rd_dout <= mem[pl_a[RD_LAT]];
        end
        for (i = RD_LAT; i > 0; i = i - 1) begin
            pl_a[i] <= pl_a[i-1];
            pl_v[i] <= pl_v[i-1];
        end
        pl_a[0] <= app_rd_addr;
        pl_v[0] <= app_rd_en;             // ★ 每拍采样：en 高就发一条命令
    end

    // ---------------------------------------------------------------
    // 突发形态监视：连发期间地址必须每拍 +1（本 TB 的核心判据）
    // ---------------------------------------------------------------
    integer    wr_burst = 0, rd_burst = 0;
    reg [20:0] wr_prev = 21'd0, rd_prev = 21'd0;
    integer    wr_step_bad = 0, rd_step_bad = 0;
    integer    wr_beats = 0, rd_beats = 0;
    integer    rd_gap_min = 9999, rd_gap = 0;
    reg        rd_seen = 1'b0;

    always @(posedge clk) begin
        // ---- 写突发 ----
        if (app_wr_en) begin
            if (wr_burst > 0) begin
                if (app_wr_addr !== (wr_prev + 21'd1)) wr_step_bad <= wr_step_bad + 1;
            end
            wr_prev  <= app_wr_addr;
            wr_burst <= wr_burst + 1;
            wr_beats <= wr_beats + 1;
        end else begin
            wr_burst <= 0;
        end

        // ---- 读突发 + 突发之间的静默 ----
        if (app_rd_en) begin
            if (rd_burst > 0) begin
                if (app_rd_addr !== (rd_prev + 21'd1)) rd_step_bad <= rd_step_bad + 1;
            end
            rd_prev  <= app_rd_addr;
            rd_burst <= rd_burst + 1;
            rd_beats <= rd_beats + 1;
            if (rd_seen && (rd_gap < rd_gap_min)) rd_gap_min <= rd_gap;   // 两次突发之间的静默拍数
            rd_gap   <= 0;
            rd_seen  <= 1'b1;
        end else begin
            rd_burst <= 0;
            rd_gap   <= rd_gap + 1;
        end
    end

    // ---------------------------------------------------------------
    // 事务驱动
    // ★ 四个坑（本 TB 自己全踩过，别再犯）—— 都出在"握手到底发生在哪一拍"：
    //   1) 用**阻塞赋值**驱动 rq/rw 后紧跟 `while (!rdy)`：同一 delta 里读到的还是
    //      旧的组合 ready ⇒ 误判。⇒ 驱动一律用非阻塞赋值。
    //   2) `while (!rdy)` 在 `rdy` 为 **X** 时也会退出（`!X` 不为真）⇒ 同样误判。
    //      ⇒ 判据写成 `rdy !== 1'b1`。
    //   3) ★★ 握手是**在上升沿**被被测模块吃掉的：req 必须**恰好跨一个上升沿**。
    //      · 在 negedge 检测到 ready 就在 negedge 撤 req ⇒ 该上升沿采到的 req=0，
    //        握手丢失（ready 给了、供给没提交）；
    //      · 若为了躲 1) 而多等一个 negedge 再撤 ⇒ req 跨了**两个**上升沿，
    //        同一个字被**写两遍 / 接受两次**（本 TB 实测：每个值落进两个连续地址）。
    //      ⇒ 正确写法：`@(negedge clk)` 拉高 req → `@(posedge clk)` 对齐 → 在每个
    //        **上升沿**判 ready → **在 ready=1 的那个上升沿同拍撤 req**。
    //   4) 无进展时必须有计数上限，否则任务会死等（仿真挂住看不出原因）。
    // ---------------------------------------------------------------
    integer to_rdy = 0;      // 等 ready 超时次数（必须为 0）
    integer to_rvl = 0;      // 等 rdata_valid 超时次数（必须为 0）

    task wr_word;
        input [31:0] a;
        input [31:0] d;
        integer g;
        begin
            @(negedge clk);
            rq <= 1'b1; rw <= 1'b1; ra <= a; rwd <= d; rstrb <= 4'hF;
            g = 0;
            @(posedge clk);                       // 对齐到上升沿（req 已拉高）
            while ((rdy !== 1'b1) && (g < 5000)) begin @(posedge clk); g = g + 1; end
            if (g >= 5000) to_rdy = to_rdy + 1;
            rq <= 1'b0;                           // 握手拍撤请求（恰好跨一个上升沿）
            @(negedge clk);
        end
    endtask

    task rd_word;
        input  [31:0] a;
        output [31:0] d;
        integer g;
        begin
            @(negedge clk);
            rq <= 1'b1; rw <= 1'b0; ra <= a;
            g = 0;
            @(posedge clk);                       // 对齐到上升沿（req 已拉高）
            while ((rdy !== 1'b1) && (g < 5000)) begin @(posedge clk); g = g + 1; end
            if (g >= 5000) to_rdy = to_rdy + 1;
            rq <= 1'b0;                           // 握手拍撤请求
            g = 0;
            while ((rvl !== 1'b1) && (g < 5000)) begin @(negedge clk); g = g + 1; end
            if (g >= 5000) to_rvl = to_rvl + 1;
            d = rd;                               // rvl 有效那一拍取数
            @(negedge clk);
        end
    endtask

    // ---------------------------------------------------------------
    // 主流程
    // ---------------------------------------------------------------
    reg  [31:0] v;
    integer     k;
    integer     mism16 = 0, mism32 = 0, mism4 = 0, mism_jump = 0;
    reg  [31:0] rbuf [0:31];

    initial begin
        for (k = 0; k < MEMW; k = k + 1) mem[k] = 32'hDEAD_BEEF;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        while (!idn) @(negedge clk);
        repeat (5) @(negedge clk);

        // ---- D2/D3：写 32 个连续字（值 = 字地址 0x1000+k，正好覆盖两次 16 字突发）----
        for (k = 0; k < 32; k = k + 1) wr_word(32'h1000 + k, 32'h1000 + k);
        repeat (80) @(negedge clk);        // 等突发写出（攒字+flush）

        // ---- D4/D5：读 32 个连续字（跨两次 16 字预取）----
        for (k = 0; k < 32; k = k + 1) begin
            rd_word(32'h1000 + k, v);
            rbuf[k] = v;
            if (v !== (32'h1000 + k)) mism32 = mism32 + 1;
        end
        for (k = 0; k < 16; k = k + 1) if (rbuf[k] !== (32'h1000 + k)) mism16 = mism16 + 1;

        // ---- D6：非 16 对齐基址（0x1035）写 4 读 4 ----
        for (k = 0; k < 4; k = k + 1) wr_word(32'h1035 + k, 32'h1035 + k);
        repeat (200) @(negedge clk);       // 4 个字走"攒字停顿后强制写出"这条路，等久一点
        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1035 + k, v);
            if (v !== (32'h1035 + k)) mism4 = mism4 + 1;
        end

        // ---- D7：★ 缓冲**还没排空**时跳到缓冲外的地址 ----
        //   读 4 个 0x1000..0x1003（缓冲里还剩 12 个），立刻跳去读 0x1035..0x1038。
        //   上一版适配器的预取触发条件含 `rcnt==0` ⇒ 这种"跳变"会**永久死等**
        //   （板上实测：探针 B 就是这样，看门狗 ERR=06、后面整帧写入全被跳过）。
        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1000 + k, v);
            if (v !== (32'h1000 + k)) mism_jump = mism_jump + 1;
        end
        for (k = 0; k < 4; k = k + 1) begin
            rd_word(32'h1035 + k, v);
            if (v !== (32'h1035 + k)) mism_jump = mism_jump + 1;
        end

        repeat (10) @(negedge clk);

        $display("---- 适配器结果 ----");
        $display("  写拍数=%0d 写地址不连续次数=%0d", wr_beats, wr_step_bad);
        $display("  读拍数=%0d 读地址不连续次数=%0d 两次读突发最小静默=%0d 拍",
                 rd_beats, rd_step_bad, rd_gap_min);
        $display("  16 字错=%0d / 32 字错=%0d / 非对齐 4 字错=%0d / 跳变 8 字错=%0d",
                 mism16, mism32, mism4, mism_jump);
        $display("  等 ready 超时=%0d 次 / 等 rdata_valid 超时=%0d 次", to_rdy, to_rvl);

        check(idn === 1'b1,                                   "D1 init_done 上抬");
        check((wr_beats >= 32) && (wr_step_bad == 0),         "D2 写突发地址每拍 +1");
        check(mism16 == 0,                                    "D3 写 32 连续字、前 16 字落对地址");
        check((rd_beats >= 32) && (rd_step_bad == 0),         "D4 读突发地址每拍 +1");
        check((mism32 == 0) && (to_rdy == 0) && (to_rvl == 0),
                                                              "D5 读 32 连续字（跨两次预取）逐字相等");
        check(mism4 == 0,                                     "D6 非 16 对齐基址写 4 读 4 正确");
        check((mism_jump == 0) && (to_rdy == 0) && (to_rvl == 0),
                                                              "D7 缓冲未排空时跳变地址不死等、数据正确");

        $display("========================================");
        $display("  断言总数 %0d，失败 %0d", total, errors);
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("========================================");
        $display("[TB] tb_bram_adapter_aligned done errors=%0d comparisons=%0d",errors,total);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
