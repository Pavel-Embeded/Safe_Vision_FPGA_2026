// ============================================================================
// top_sdram_loopback.v — 板级 SDRAM 官方 Demo 回环验证顶层（B 链 · 学习阶段 9 第一步）
// ----------------------------------------------------------------------------
// 依据：手册 7.9「SDRAM 先跑官方 Demo」——先用厂商 SDRAM 控制器证明硬核能用，
//       再把它接到帧缓存链路上。
//       落点依据：docs/PROJECT_STRUCTURE.md（板级相关一切归 platform/…/）。
//
// 定位：这是【接引脚、不属产品链】的 bring-up 顶层，**不是** A 的产品顶层
//       safevision_top.v。本文件只做一件事：
//
//         上电 → 等 PLL 锁定 → 等 SDRAM IP 初始化完成 → 写图案进 SDRAM
//         → 等落地 → 读回 → 按序比对 → 经 UART 发【纯 ASCII 报告】
//
//       报告是纯 ASCII（KEY=HEX，末行 DONE），和阶段 6 顶层同一口径：这样串口
//       助手用【文本模式】保存也不会踩"≥0x80 被换成 EF BF BD"的那个有损坑。
//
// ★★ 仿真边界（2026-10-04 纠正）
//   厂商 SDRAM 控制器的真正实现是 `ip/sdram/sdr_as_ram.enc.v` 等三个文件，
//   本机未验证兼容的控制器仿真模型。tb_sdram_loopback.sv 用应用侧行为模型
//   验证图案、回环、超时和 UART；不能证明加密控制器、物理 DQ 或 AC 时序。
//   完整验收仍须最终布局布线 STA 和对应版本的上板读写测试。
//
// ★★ EG4S20 的 SDRAM 是【封装内裸片】（die-in-package），不是外挂芯片
//   `EG_PHY_SDRAM_2M_32` 是硬核：2M × 32 bit = 8 MB。SDRAM 的 55 根
//   （addr/ba/dq/dm/ras/cas/we/cs 等）**不出芯片引脚**，所以在 FPGA 顶层
//   不该出现、`constraints/pin.adc` 里也**不该有** SDRAM 引脚 —— 例程包里
//   确实一条都没有，这不是遗漏。（`ip/sdram/sdram.v` 里那几个 `SDRAM_*` 信号
//   在综合时是内部 `wire`，只有 `SIMULATION` 宏打开才会变成端口。）
//
// ★ 时钟方案（照例程，2026-10-02 采用 A 方案）
//   板载 50 MHz（R7）→ `sv_system_pll`：C0=100M（外部端口留空，内部反馈保留）、
//   C1=125M = SDRAM 侧 `Clk`、C2=125M 180° 相移 = `Clk_sft`。
//   为什么必须跟例程走 125M + 180°：SDRAM 的初始化/刷新/CAS 是硬时序，
//   `Clk_sft` 是采样相位，**同源 PLL 做相移，不能用反相器代替**。
//
//   ★ 全部逻辑（含 uart_tx）都放在 125 MHz 域，**刻意不做跨时钟域**：
//     报告为 190 Byte，UART 才是瓶颈（115200 下约 17 ms），把 uart_tx 也挂在
//     125 MHz 上（DIV = 125e6/115200 = 1085，误差 0.006%）比引一条 CDC 更简单、
//     更少变量。C0 在 wrapper 内接 PLL fbclk；寄存器扇出 0 不代表反馈悬空。
//     当前单一 C0 反馈网络保留 NORMAL 补偿，C2 经专用 BUFG；最终路由须复查。
//     若初始化超时（LED=1），检查 pll_locked、复位、加密件与最终时钟路由。
//     不能用添加无业务意义的 C0 负载代替反馈检查。超时分支不发送 UART 报告。
//
// ★ 测试图案：由 `rtl/memory/sdr_pat_gen.v` 统一产生 32-bit 数据。
//   mode 0 是 A 修订版的完整 21-bit 可逆签名；mode 1–5 保留 B 的 LFSR、walking-1/0、
//   全 0/全 1 和相邻位交替压力图案。独立 TB 对 mode 0 穷举反解，避免写读同错漏检。
//
// ★ 稀疏地址配置：默认 ADDR_SHIFT=11、ADDR_LOWSTEP=1、TEST_WORDS=1024，步长 2049，
//   采样点跨越 2M-word 地址范围；这是高位地址译码抽样，不表示每个 bank/row/column
//   或每个存储单元都逐一访问。连续扫描须用 ADDR_SHIFT=0、ADDR_LOWSTEP=0。
//
// ★★★ soak：每轮执行写入、等待落地、读回和比较；六种图案逐轮循环，TOT 累计 word 数。
//   错误 fail-fast 停止并记录轮次/地址/期望/实际；ST_RDWAIT 必须等待整个比较流水提交。
//   板级 10 秒、10 分钟及约 60 分钟配置均曾零错完成；这不等于 STA 收敛或全容量逐字测试。
//   单轮稀疏扫描约 22 us；ROUNDS=161,000,000 约 60 分钟。
//   `sdr_pat_gen` 的 mode 0 使用全部地址位；其它模式用于数据线和相邻线压力。
//
// ★ 硬约定遵守情况（对照项目规则 §5）
//   - 每个"等外部回应"的状态都有独立超时：等 Sdr_init_done（ERR=01）、
//     等读回收齐（ERR=02）各挂一个自己的计数器，不共用。
//   - 读写突发**不重叠**：写完 → 落地等待 → 再读（例程也是靠 App_rd_busy/App_wr_busy
//     把两个方向错开，app 接口不支持同时读写）。
//   - 一个 reg 只有一个驱动源；不用除法取模；字符串里不用 `\r`（要回车写 8'h0D）。
//
// ★ LED 状态码（led[3:0]，高电平点亮，不用串口也能看）
//     1 = 上电等待   2 = 等 SDRAM 初始化   3 = 写图案   4 = 等写落地
//     5 = 发读命令   6 = 等读回收齐          7 = 发 UART 报告
//     8 = 成功（数据全对）   1/2/3 = 失败（错误主码低 4 位，见下表）
//   错误主码：01 = SDRAM 初始化超时   02 = 读回不齐（有读命令没返回）
//             03 = 数据不一致（返回了但对不上）
//
// ★ 电脑侧对账：报告 **190 Byte** 定长（2026-10-04 由 136 扩到 190：加了**轮次/图案模式行**
//   与**累计搬运量行**，并给首个错点行加了**轮次**），行格式固定：
//     SV-SDRAM-LOOP\r\n                               (15)
//     INIT=x LOCK=x\r\n                               (17)
//     CFG=hhx BASE=hhhhhh N=hhhhhh\r\n                 (30) ← ADDR_SHIFT/LOWSTEP / 基址 / 每轮 word 数
//     RND=hhhhhhhh/hhhhhhhh PAT=h\r\n                 (29) ← 已跑轮数 / 总轮数 / 本轮图案模式
//     W=hhhh R=hhhh CAP=hhhh BAD=hhhh\r\n             (33) ← **本轮**的计数
//     TOT=hhhhhhhhhh\r\n                              (16) ← 累计比对字数（40 bit，不重置）
//     BAD0=hhhhhhhh:hhhhhh E=hhhhhhhh A=hhhhhhhh\r\n  (44) ← 首个错点：轮次 : 地址 / 期望 / 实际
//     DONE\r\n                                        (6)
//   取数是自己跟自己比：`W == R == CAP == TEST_WORDS` 且 `BAD == 0000` 才算过。
//   单轮配置示例报告（BASE=0、2049 stride、1024 samples、ROUNDS=1）：
//     CFG=0B1 BASE=000000 N=000400
//     RND=00000001/00000001 PAT=0  (when parameter ROUNDS=1)
//     W=0400 R=0400 CAP=0400 BAD=0000
//     TOT=0000000400
//     BAD0=FFFFFF:FFFFFF E=00000000 A=00000000      ← FFFFFF = 无错（地址最大 0x1FFFFF）
//   ★★ 为什么要把配置 / 轮次 / 图案模式 / 首个错点都打进报告：这是**一次烧板拿全部信息**
//      的做法（阶段 10 的「地址斜坡探针」经验，见 docs/B链-原理讲解-入门版.md）。
//      没有 CFG 就分不清这次烧的是哪套参数；只有 BAD 计数而**不知道错在哪一轮、哪个地址**，
//      就得再烧一次才能定位。
//   ★ 报告索引用 8 位**倒计数**（从 189 递减到 0）；现先按索引选行并寄存，
//     再从寄存行选字节，不使用 `RPT_LEN-1-idx` 构造 190:1 宽选择器。
//   ★ `led=7` 仅表示 ST_REPORT；115200 8N1 的 190 Byte 报告约 17 ms 后应
//     转 `led=8`（通过）或 `led=3`（数据不一致）。持久停 7 需核实实际位流、
//     UART 握手/引脚与 COM 口采集；不能将瞬时 7 当成失败码。
// ============================================================================

module top_sdram_loopback #(
    parameter integer CLK_FREQ      = 50_000_000,   // 板载晶振
    parameter integer MEM_CLK_FREQ  = 125_000_000,  // sv_system_pll C1，uart 也用这个
    parameter integer BAUD          = 115200,

    parameter [23:0]  POWERUP_CYC   = 24'd2_500_000,  // 上电等待 @125MHz
    parameter [23:0]  INIT_TO_CYC   = 24'd2_000_000,  // 等 Sdr_init_done 的超时 @125MHz

    parameter [20:0]  BASE_ADDR     = 21'd0,          // 起始 word 地址
    parameter [20:0]  TEST_WORDS    = 21'd1024,       // **每轮**测试 word 数
    parameter integer ADDR_SHIFT    = 11,             // 步长高位：1 << ADDR_SHIFT
    parameter integer ADDR_LOWSTEP  = 1,              // 步长低位：0 或 1（1 = 让低位地址位也变）
    parameter [31:0]  ROUNDS        = 32'd27_000_000,          // ★ soak：跑多少轮（1 = 单轮 = 原来的行为）

    parameter integer BURST_N       = 128,            // 一次突发多少个 word
    parameter integer BURST_GAP     = 16,             // 突发之间空多少拍

    parameter [15:0]  WR_DRAIN_CYC  = 16'd512,        // 写完后等写落地
    parameter [19:0]  RD_WAIT_TO_CYC= 20'd200_000     // 等读回收齐的超时 @125MHz
)(
    // ---- 板级引脚（引脚号见同目录 ../constraints/pin.adc）----
    input  wire        clk,        // R7   FPGA_GCLK  50 MHz
    input  wire        rst_n,      // A2   KEY_1       低有效按键
    output wire        uart_txd,   // D12  USB-UART 发送（板载 CH340G，115200 8N1）
    output wire [3:0]  led         // A4/A3/C10/B12 = LED0..LED3，高电平点亮
);

    // ------------------------------------------------------------------------
    // 上电复位：按键（异步、带抖动）先同步到 50 MHz，再与 PLL 锁定相与，
    //           最后在 125 MHz 域做同步释放。每一个目标时钟域单独例化。
    // ------------------------------------------------------------------------
    wire rst_ref_n;          // 50 MHz 域
    wire pll_locked;
    wire rst_mem_n;          // 125 MHz 域
    wire rst_mem;            // SDRAM IP 要的是【高有效】Rst

    reset_sync u_rst_ref (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_ref_n)
    );

    // ------------------------------------------------------------------------
    // 时钟：50 MHz -> sv_system_pll（100M / 125M / 125M@180°）
    //   C0 外部端口不接业务负载；wrapper 内的 NORMAL 反馈始终连接。
    // ------------------------------------------------------------------------
    wire ext_mem_clk;
    wire ext_mem_clk_sft;

    sv_system_pll u_sys_pll (
        .refclk   (clk),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (),
        .clk1_out (ext_mem_clk),
        .clk2_out (ext_mem_clk_sft)
    );

    reset_sync u_rst_mem (
        .clk        (ext_mem_clk),
        .async_rst_n(rst_ref_n & pll_locked),
        .rst_n      (rst_mem_n)
    );

    assign rst_mem = ~rst_mem_n;

    // ------------------------------------------------------------------------
    // SDRAM 控制器（厂商加密 IP 的外壳，见 ../ip/sdram/）
    // ------------------------------------------------------------------------
    wire        sdr_init_done;
    wire        sdr_init_ref_vld;   // 例程里是纯直通、不参与判断，这里只留给 ChipWatcher
    wire        sdr_busy;           // 同上
    wire        app_wr_en;
    wire [20:0] app_wr_addr;
    wire [31:0] app_wr_din;
    wire [3:0]  app_wr_dm;
    wire        app_rd_en;
    wire [20:0] app_rd_addr;
    wire        sdr_rd_en;
    wire [31:0] sdr_rd_dout;

    // UART 握手（uart_tx 例化在文件末尾，这里先声明，避免前向引用）
    wire        uart_tx_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    // ------------------------------------------------------------------------
    // 顶层状态机（125 MHz 域，全程单时钟域）
    // ------------------------------------------------------------------------
    localparam [3:0] ST_POWER    = 4'd0,
                     ST_INITWAIT = 4'd1,
                     ST_WRITE    = 4'd2,
                     ST_DRAIN    = 4'd3,
                     ST_READ     = 4'd4,
                     ST_RDWAIT   = 4'd5,
                     ST_ROUND    = 4'd9,    // ★ 轮次边界：只停一拍，让各计数块自己清零（避免多驱动）
                     ST_REPORT   = 4'd6,
                     ST_OK       = 4'd7,
                     ST_ERR      = 4'd8;

    // 突发周期 = 突发长度 + 间隔（编译期常数）
    localparam integer PERIOD = BURST_N + BURST_GAP;

    // 报告长度（15 + 17 + 30 + 29 + 33 + 16 + 44 + 6 = 190 Byte，定长）
    localparam integer RPT_LEN  = 190;
    localparam [7:0]   RPT_LAST = RPT_LEN - 1;     // 189（倒计数起点）

    // 配置字的两个字段（integer parameter 不能直接位选，先落到定宽 localparam）
    localparam [7:0] SHIFT_BYTE  = ADDR_SHIFT;     // 0..20
    localparam [3:0] LOWSTEP_NIB = ADDR_LOWSTEP;   // 0 或 1
    // 步长低位开关（编译期常数 ⇒ 工具会把未选中的那一路折叠掉）
    localparam       LOWSTEP_EN  = (ADDR_LOWSTEP != 0);

    reg  [3:0]  st;
    reg  [23:0] pwr_cnt;
    reg  [23:0] init_to_cnt;
    reg  [15:0] drain_cnt;
    reg  [19:0] rdwait_to_cnt;
    reg  [7:0]  err_code;
    reg  [7:0]  rpt_idx;       // 8 位**倒计数**：RPT_LAST .. 0
    reg         rpt_run;       // 报告发射中
    reg  [8*44-1:0] rpt_line_q; // 两级报告选择的第一级：当前报告行
    reg  [5:0]  rpt_byte_pos_q; // 当前字节在行内的反向索引
    reg         rpt_line_valid;
    reg  [7:0]  rpt_byte_q;     // 两级报告选择的第二级：UART 待发字节
    reg         rpt_byte_valid;
    reg  [7:0]  t_wr;
    reg  [7:0]  t_rd;
    reg  [20:0] wr_i;          // 本轮已写 word 数
    reg  [20:0] rd_i;          // 本轮已发读命令数
    reg  [20:0] cap_cnt;       // 本轮已收到返回 word 数
    reg  [15:0] bad_cnt;       // **本轮**比对不符 word 数（每轮清零，配合 fail-fast）

    // ---- soak：轮次 / 图案模式 / 累计搬运量 ----
    reg  [31:0] rnd;           // 当前轮（0-based；报告里显示 rnd+1）
    reg  [2:0]  pat_mode;      // 本轮图案模式 0..5（逐轮循环，见 sdr_pat_gen.v 头注）
    reg  [39:0] tot_cnt;       // 累计比对字数（**不重置**）⇒ 报告 TOT = 实际搬运量

    // ---- 回读四级流水（压短 cap_cnt → sdr_pat_gen → 比较器 → BAD0 CE 的路径）----
    //   sample_* : 延迟应答到来时锁住地址/数据/模式；期望图案下一拍算。
    //   expect_* : 锁存图案、地址、数据；下一拍做 32bit 比较。
    //   cmp_*    : 锁存比较结果；下一拍提交 checked_cnt / bad_cnt / BAD0。
    //   checked_cnt 是"比较流水已提交"数，ST_RDWAIT 必须等它而不是仅看 cap_cnt。
    reg         sample_v;
    reg  [20:0] sample_addr;
    reg  [31:0] sample_data;
    reg  [2:0]  sample_mode;
    reg         expect_v;
    reg  [20:0] expect_addr;
    reg  [31:0] expect_data;
    reg  [31:0] expect_pat;
    reg         cmp_v;
    reg  [3:0]  cmp_bad_bytes;
    reg  [20:0] cmp_addr;
    reg  [31:0] cmp_exp;
    reg  [31:0] cmp_act;
    reg  [20:0] checked_cnt;

    // ---- 首个不符点（诊断用；bad0_set=0 表示"全对"）----
    reg         bad0_set;
    reg  [31:0] bad0_rnd;      // 首个不符发生在**第几轮**（1-based，与报告口径一致）
    reg  [20:0] bad0_addr;     // 首个不符的地址
    reg  [31:0] bad0_exp;      // 该地址的期望值
    reg  [31:0] bad0_act;      // 该地址实际读回的值

    // 地址 = BASE_ADDR + index * STRIDE，其中 STRIDE = (1 << ADDR_SHIFT) + ADDR_LOWSTEP
    //   ★ 必须写在 wr_i / rd_i / cap_cnt 声明**之后**，否则 Verilog 会先建 1 bit 隐式网线
    wire [20:0] wr_addr  = BASE_ADDR + (wr_i    << ADDR_SHIFT) + (LOWSTEP_EN ? wr_i    : 21'd0);
    wire [20:0] rd_addr  = BASE_ADDR + (rd_i    << ADDR_SHIFT) + (LOWSTEP_EN ? rd_i    : 21'd0);
    wire [20:0] cap_addr = BASE_ADDR + (cap_cnt << ADDR_SHIFT) + (LOWSTEP_EN ? cap_cnt : 21'd0);

    // ---- 测试图案：由可仿真的 `sdr_pat_gen` 产生（写侧 / 读侧期望值各一个实例）----
    //   ★ 读侧从 sample_addr 寄存器计算，不能直接由 cap_cnt 的加法器驱动比较器。
    //   ★ 两侧必须用**同一个** pat_mode；流水排空后才允许进入下一轮。
    wire [31:0] pat_wr;
    wire [31:0] pat_rd;
    sdr_pat_gen u_pat_wr ( .addr(wr_addr),     .mode(pat_mode),   .pat(pat_wr) );
    sdr_pat_gen u_pat_rd ( .addr(sample_addr), .mode(sample_mode), .pat(pat_rd) );

    // 应用侧握手：突发内逐拍使能，突发之间静默
    assign app_wr_en = (st == ST_WRITE) && (t_wr < BURST_N) && (wr_i < TEST_WORDS);
    assign app_rd_en = (st == ST_READ ) && (t_rd < BURST_N) && (rd_i < TEST_WORDS);

    assign app_wr_addr = wr_addr;
    assign app_wr_din  = pat_wr;
    assign app_wr_dm   = 4'b0000;      // 全字节写入（与例程一致）
    assign app_rd_addr = rd_addr;

    // ---- 写侧计数：只随 app_wr_en 前进 ----
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            t_wr <= 8'd0;
            wr_i <= 21'd0;
        end else if (st == ST_ROUND) begin          // ★ 轮次边界：本轮写计数清零
            t_wr <= 8'd0;
            wr_i <= 21'd0;
        end else if (st == ST_WRITE) begin
            if (t_wr == PERIOD - 1) t_wr <= 8'd0;
            else                    t_wr <= t_wr + 8'd1;
            if (app_wr_en)          wr_i <= wr_i + 21'd1;
        end
    end

    // ---- 读侧计数：只随 app_rd_en 前进 ----
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            t_rd <= 8'd0;
            rd_i <= 21'd0;
        end else if (st == ST_ROUND) begin          // ★ 轮次边界：本轮读计数清零
            t_rd <= 8'd0;
            rd_i <= 21'd0;
        end else if (st == ST_READ) begin
            if (t_rd == PERIOD - 1) t_rd <= 8'd0;
            else                    t_rd <= t_rd + 8'd1;
            if (app_rd_en)          rd_i <= rd_i + 21'd1;
        end
    end

    // ---- 收数 + 期望图案 + 分字节比较 + 提交：四级流水 ----
    //   sdr_rd_en 才是取数时刻（读侧是延迟应答式）；第 k 个返回对应第 k 个读命令。
    //   ★ 2026-10-04 11:16 的布线报告抓到真问题：
    //       cap_cnt → 地址加法 → mode1 xorshift/mux → 32bit 比较 → bad0_* CE
    //       Logic Level 8 / 11.311ns / SWNS -3.591ns / 90 endpoints。
    //     把这条组合路径拆成 4 拍：响应采样 → 图案计算 → 比较 → 错误提交。
    //   ★ ST_RDWAIT 必须等 `checked_cnt`（已提交比较数），不能只看 `cap_cnt`（已收数据数），
    //     否则状态机会在比较流水排空前切换 pat_mode / 发报告。
    wire rd_capture = sdr_rd_en && ((st == ST_READ) || (st == ST_RDWAIT)) &&
                      (cap_cnt < TEST_WORDS);

    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            cap_cnt       <= 21'd0;
            checked_cnt   <= 21'd0;
            bad_cnt       <= 16'd0;
            tot_cnt       <= 40'd0;
            bad0_set      <= 1'b0;
            bad0_rnd      <= 32'd0;
            bad0_addr     <= 21'd0;
            bad0_exp      <= 32'd0;
            bad0_act      <= 32'd0;
            sample_v      <= 1'b0;
            sample_addr   <= 21'd0;
            sample_data   <= 32'd0;
            sample_mode   <= 3'd0;
            expect_v      <= 1'b0;
            expect_addr   <= 21'd0;
            expect_data   <= 32'd0;
            expect_pat    <= 32'd0;
            cmp_v         <= 1'b0;
            cmp_bad_bytes <= 4'b0000;
            cmp_addr      <= 21'd0;
            cmp_exp       <= 32'd0;
            cmp_act       <= 32'd0;
        end else if (st == ST_ROUND) begin
            // ★ 轮次边界：清本轮计数与流水 valid；累计 TOT / 全局首错不清
            cap_cnt       <= 21'd0;
            checked_cnt   <= 21'd0;
            bad_cnt       <= 16'd0;
            sample_v      <= 1'b0;
            expect_v      <= 1'b0;
            cmp_v         <= 1'b0;
            cmp_bad_bytes <= 4'b0000;
        end else begin
            // valid 每拍前推，空拍自然冲刷
            sample_v <= rd_capture;
            expect_v <= sample_v;
            cmp_v    <= expect_v;

            // Stage 0：收 SDRAM 响应，锁存它对应的地址、模式和数据
            if (rd_capture) begin
                cap_cnt     <= cap_cnt + 21'd1;
                tot_cnt     <= tot_cnt + 40'd1;       // 累计量不随轮次重置
                sample_addr <= cap_addr;
                sample_mode <= pat_mode;
                sample_data <= sdr_rd_dout;
            end

            // Stage 1：地址派生 / LFSR / walking 等图案组合计算的输出在本拍寄存
            if (sample_v) begin
                expect_addr <= sample_addr;
                expect_data <= sample_data;
                expect_pat  <= pat_rd;
            end

            // Stage 2：32 位比较与诊断数据一起寄存
            if (expect_v) begin
                cmp_addr <= expect_addr;
                cmp_exp  <= expect_pat;
                cmp_act  <= expect_data;
                cmp_bad_bytes <= {
                    (expect_data[31:24] != expect_pat[31:24]),
                    (expect_data[23:16] != expect_pat[23:16]),
                    (expect_data[15:8]  != expect_pat[15:8]),
                    (expect_data[7:0]   != expect_pat[7:0])
                };
            end

            // Stage 3：只从已寄存的比较结果提交计数 / 首错（短 CE 路径）
            if (cmp_v) begin
                checked_cnt <= checked_cnt + 21'd1;
                if (|cmp_bad_bytes) begin
                    bad_cnt <= bad_cnt + 16'd1;
                    if (!bad0_set) begin
                        bad0_rnd  <= rnd + 32'd1;     // 报告口径 1-based
                        bad0_addr <= cmp_addr;
                        bad0_exp  <= cmp_exp;
                        bad0_act  <= cmp_act;
                        bad0_set  <= 1'b1;
                    end
                end
            end
        end
    end

    // ---- 主序列 ----
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            st            <= ST_POWER;
            pwr_cnt       <= 24'd0;
            init_to_cnt   <= 24'd0;
            drain_cnt     <= 16'd0;
            rdwait_to_cnt <= 20'd0;
            err_code      <= 8'h00;
            rpt_idx       <= RPT_LAST;
            rpt_run       <= 1'b0;
            rnd           <= 32'd0;
            pat_mode      <= 3'd0;
        end else begin
            case (st)
            // 上电等待：等板级电源与 PLL 稳定
            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INITWAIT;
                else                        pwr_cnt <= pwr_cnt + 24'd1;
            end
            // 等 SDRAM IP 初始化完成 —— 独立超时出口
            ST_INITWAIT: begin
                if (sdr_init_done)                 st <= ST_WRITE;
                else if (init_to_cnt >= INIT_TO_CYC) begin
                    err_code <= 8'h01;
                    st       <= ST_ERR;
                end else init_to_cnt <= init_to_cnt + 24'd1;
            end
            // 写图案（分突发，靠 t_wr 计数）
            ST_WRITE: begin
                if (wr_i >= TEST_WORDS) st <= ST_DRAIN;
            end
            // 等写落地，再换方向（读写突发不允许重叠）
            ST_DRAIN: begin
                if (drain_cnt >= WR_DRAIN_CYC) st <= ST_READ;
                else                           drain_cnt <= drain_cnt + 16'd1;
            end
            // 发读命令（分突发）
            ST_READ: begin
                if (rd_i >= TEST_WORDS) begin
                    rdwait_to_cnt <= 20'd0;
                    st            <= ST_RDWAIT;
                end
            end
            // 等读回收齐 —— 独立超时出口
            ST_RDWAIT: begin
                if (checked_cnt >= TEST_WORDS) begin
                    // ★ soak 决策：**出错立即停（fail fast）** 或跑满轮数 ⇒ 出报告；否则进下一轮
                    if ((bad_cnt != 16'd0) || ((rnd + 32'd1) >= ROUNDS)) st <= ST_REPORT;
                    else                                                  st <= ST_ROUND;
                end else if (rdwait_to_cnt >= RD_WAIT_TO_CYC) begin
                    err_code <= 8'h02;
                    st       <= ST_ERR;
                end else rdwait_to_cnt <= rdwait_to_cnt + 20'd1;
            end
            // ★ 轮次边界（只停一拍）：轮次 +1、图案模式 0..5 循环、清落地计时；
            //   各计数块（wr_i/rd_i/cap_cnt/bad_cnt）在**它们自己的 always 块**里看到
            //   `st == ST_ROUND` 时清零 —— 绝不能在这里写它们（一个 reg 只能有一个驱动源）
            ST_ROUND: begin
                rnd        <= rnd + 32'd1;
                pat_mode   <= (pat_mode == 3'd5) ? 3'd0 : (pat_mode + 3'd1);
                drain_cnt  <= 16'd0;
                st         <= ST_WRITE;
            end
            // 发报告（逐字节，uart 背压；索引**倒计数**，理由见文件头）
            ST_REPORT: begin
                if (!rpt_run) begin
                    rpt_run <= 1'b1;          // 装索引（只做一次），下一拍起预取字节
                    rpt_idx <= RPT_LAST;
                end else if (rpt_byte_valid && uart_tx_ready) begin
                    if (rpt_idx == 8'd0) begin
                        rpt_run <= 1'b0;
                        if (bad_cnt != 16'd0) begin
                            err_code <= 8'h03;
                            st       <= ST_ERR;
                        end else st <= ST_OK;
                    end else rpt_idx <= rpt_idx - 8'd1;
                end
            end
            ST_OK : st <= ST_OK;      // 停住，LED 保持 8
            ST_ERR: st <= ST_ERR;     // 停住，LED 显示错误主码低 4 位
            default: st <= ST_POWER;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // LED 状态码（组合，纯观察用）
    // ------------------------------------------------------------------------
    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER   : led_code = 4'h1;
            ST_INITWAIT: led_code = 4'h2;
            ST_WRITE   : led_code = 4'h3;
            ST_DRAIN   : led_code = 4'h4;
            ST_READ    : led_code = 4'h5;
            ST_RDWAIT  : led_code = 4'h6;
            ST_ROUND   : led_code = 4'h3;    // 与 ST_WRITE 同码（轮次边界只停一拍，看不出差别）
            ST_REPORT  : led_code = 4'h7;
            ST_OK      : led_code = 4'h8;
            default    : led_code = err_code[3:0];   // ST_ERR：01/02/03
        endcase
    end

    assign led = led_code;

    // ------------------------------------------------------------------------
    // UART 报告：定长 190 Byte 纯 ASCII，行尾显式写 8'h0D / 8'h0A
    //   （★ 不要写 "\r\n"：Verilog-2001 的转义表里没有 \r，会编成字母 r）
    // ------------------------------------------------------------------------
    // 一个 nibble -> ASCII 大写十六进制
    function [7:0] hx;
        input [3:0] n;
        begin
            hx = (n < 4'd10) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
        end
    endfunction

    function [15:0] hex8;
        input [7:0] v;
        begin
            hex8 = { hx(v[7:4]), hx(v[3:0]) };
        end
    endfunction

    function [31:0] hex16;
        input [15:0] v;
        begin
            hex16 = { hx(v[15:12]), hx(v[11:8]), hx(v[7:4]), hx(v[3:0]) };
        end
    endfunction

    function [47:0] hex24;
        input [23:0] v;
        begin
            hex24 = { hx(v[23:20]), hx(v[19:16]), hx(v[15:12]),
                      hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction

    function [63:0] hex32;
        input [31:0] v;
        begin
            hex32 = { hx(v[31:28]), hx(v[27:24]), hx(v[23:20]), hx(v[19:16]),
                      hx(v[15:12]), hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction

    function [79:0] hex40;                 // 40 bit = 10 个 hex 字符
        input [39:0] v;
        begin
            hex40 = { hx(v[39:36]), hx(v[35:32]), hx(v[31:28]), hx(v[27:24]), hx(v[23:20]),
                      hx(v[19:16]), hx(v[15:12]), hx(v[11:8]),  hx(v[7:4]),   hx(v[3:0]) };
        end
    endfunction

    // 报告用字段：配置 + 轮次/图案 + 首个错点
    //   全对时用哨兵：BAD0 地址 = 0xFFFFFF（地址最大 0x1FFFFF）、轮次 = 0xFFFFFFFF
    wire [23:0] base24   = { 3'b0, BASE_ADDR  };
    wire [23:0] n24      = { 3'b0, TEST_WORDS };
    wire [23:0] bad0_rep = bad0_set ? { 3'b0, bad0_addr } : 24'hFFFFFF;
    wire [31:0] exp_rep  = bad0_set ? bad0_exp : 32'd0;
    wire [31:0] act_rep  = bad0_set ? bad0_act : 32'd0;
    wire [31:0] rnd_rep  = bad0_set ? bad0_rnd : 32'hFFFFFFFF;   // 无错 ⇒ FFFFFFFF
    wire [31:0] rnd_cur  = rnd + 32'd1;                          // 报告口径 1-based

    // 逐段长度：L1 15 / L2 17 / L3 30 / L4 29 / L5 33 / L6 16 / L7 44 / L8 6 ⇒ 合计 190
    wire [8*15-1:0] rpt_l1 = { "SV-SDRAM-LOOP", 8'h0D, 8'h0A };
    wire [8*17-1:0] rpt_l2 = { "INIT=", hex8({7'b0, sdr_init_done}),
                               " LOCK=", hex8({7'b0, pll_locked}), 8'h0D, 8'h0A };
    // L3 = "CFG=" 4 + 2 + 1 + " BASE=" 6 + 6 + " N=" 3 + 6 = 28，+CRLF = 30
    wire [8*30-1:0] rpt_l3 = { "CFG=", hex8(SHIFT_BYTE), hx(LOWSTEP_NIB),
                               " BASE=", hex24(base24), " N=", hex24(n24), 8'h0D, 8'h0A };
    // L4 = "RND=" 4+8 + "/" 1+8 + " PAT=" 5+1 = 27，+CRLF = 29
    wire [8*29-1:0] rpt_l4 = { "RND=", hex32(rnd_cur), "/", hex32(ROUNDS),
                               " PAT=", hx(pat_mode), 8'h0D, 8'h0A };
    // L5 = "W=" 2+4 + " R=" 3+4 + " CAP=" 5+4 + " BAD=" 5+4 = 31，+CRLF = 33
    wire [8*33-1:0] rpt_l5 = { "W=",   hex16(wr_i[15:0]),
                               " R=",  hex16(rd_i[15:0]),
                               " CAP=",hex16(cap_cnt[15:0]),
                               " BAD=",hex16(bad_cnt),      8'h0D, 8'h0A };
    // L6 = "TOT=" 4+10 = 14，+CRLF = 16
    wire [8*16-1:0] rpt_l6 = { "TOT=", hex40(tot_cnt), 8'h0D, 8'h0A };
    // L7 = "BAD0=" 5+8 + ":" 1+6 + " E=" 3+8 + " A=" 3+8 = 42，+CRLF = 44
    wire [8*44-1:0] rpt_l7 = { "BAD0=", hex32(rnd_rep), ":", hex24(bad0_rep),
                               " E=",   hex32(exp_rep),
                               " A=",   hex32(act_rep),     8'h0D, 8'h0A };
    wire [8*6-1:0]  rpt_l8 = { "DONE", 8'h0D, 8'h0A };

    // ★ 两级倒计数选字节：先用 rpt_idx 选报告行，再从该行选字节。
    //   rpt_idx 从 RPT_LAST 递减；每段区间对应一行，字节顺序仍为 MSB→LSB。
    //   把 190:1 的宽选择拆开，避免 BAD0 数据经十六进制编码后再穿过整份报告 mux。
    reg [8*44-1:0] rpt_line_sel;
    reg [5:0]      rpt_byte_pos;
    always @* begin
        rpt_line_sel = { {(44-6){8'h00}}, rpt_l8 };
        rpt_byte_pos = rpt_idx[5:0];
        if (rpt_idx >= 8'd175) begin
            rpt_line_sel = rpt_l1;
            rpt_byte_pos = rpt_idx - 8'd175;
        end else if (rpt_idx >= 8'd158) begin
            rpt_line_sel = rpt_l2;
            rpt_byte_pos = rpt_idx - 8'd158;
        end else if (rpt_idx >= 8'd128) begin
            rpt_line_sel = rpt_l3;
            rpt_byte_pos = rpt_idx - 8'd128;
        end else if (rpt_idx >= 8'd99) begin
            rpt_line_sel = rpt_l4;
            rpt_byte_pos = rpt_idx - 8'd99;
        end else if (rpt_idx >= 8'd66) begin
            rpt_line_sel = rpt_l5;
            rpt_byte_pos = rpt_idx - 8'd66;
        end else if (rpt_idx >= 8'd50) begin
            rpt_line_sel = rpt_l6;
            rpt_byte_pos = rpt_idx - 8'd50;
        end else if (rpt_idx >= 8'd6) begin
            rpt_line_sel = rpt_l7;
            rpt_byte_pos = rpt_idx - 8'd6;
        end
    end

    // 第一拍寄存整行，第二拍只从 44 Byte 行内选目标字节；
    // UART 按字节握手期间保持 rpt_byte_q，不改变 190 Byte 报告协议。
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            rpt_line_q     <= {(8*44){1'b0}};
            rpt_byte_pos_q <= 6'd0;
            rpt_line_valid <= 1'b0;
            rpt_byte_q     <= 8'd0;
            rpt_byte_valid <= 1'b0;
        end else if (st != ST_REPORT || !rpt_run) begin
            rpt_line_valid <= 1'b0;
            rpt_byte_valid <= 1'b0;
        end else if (!rpt_byte_valid && !rpt_line_valid && (rpt_idx < RPT_LEN)) begin
            rpt_line_q     <= rpt_line_sel;
            rpt_byte_pos_q <= rpt_byte_pos;
            rpt_line_valid <= 1'b1;
        end else if (!rpt_byte_valid && rpt_line_valid) begin
            rpt_byte_q     <= rpt_line_q[{rpt_byte_pos_q, 3'b000} +: 8];
            rpt_byte_valid <= 1'b1;
            rpt_line_valid <= 1'b0;
        end else if (rpt_byte_valid && uart_tx_ready) begin
            rpt_byte_valid <= 1'b0;
        end
    end

    assign uart_tx_valid = (st == ST_REPORT) && rpt_run && rpt_byte_valid;
    assign uart_tx_data  = rpt_byte_q;

    // ------------------------------------------------------------------------
    // 例化：厂商 SDRAM 控制器
    // ------------------------------------------------------------------------
    sdram u_sdram (
        .Clk              (ext_mem_clk),
        .Clk_sft          (ext_mem_clk_sft),
        .Rst              (rst_mem),
        .Sdr_init_done    (sdr_init_done),
        .Sdr_init_ref_vld (sdr_init_ref_vld),
        .Sdr_busy         (sdr_busy),
        .App_wr_en        (app_wr_en),
        .App_wr_addr      (app_wr_addr),
        .App_wr_dm        (app_wr_dm),
        .App_wr_din       (app_wr_din),
        .App_rd_en        (app_rd_en),
        .App_rd_addr      (app_rd_addr),
        .Sdr_rd_en        (sdr_rd_en),
        .Sdr_rd_dout      (sdr_rd_dout)
    );

    // ------------------------------------------------------------------------
    // 例化：UART 发送（125 MHz 域，115200 8N1）
    // ------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ (MEM_CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (ext_mem_clk),
        .rst_n     (rst_mem_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_tx_ready),
        .txd       (uart_txd)
    );

endmodule
