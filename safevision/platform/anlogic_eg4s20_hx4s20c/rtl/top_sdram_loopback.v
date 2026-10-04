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
//     报告只有 71 Byte，UART 才是瓶颈（115200 下约 6.2 ms），把 uart_tx 也挂在
//     125 MHz 上（DIV = 125e6/115200 = 1085，误差 0.006%）比引一条 CDC 更简单、
//     更少变量。C0 在 wrapper 内接 PLL fbclk；寄存器扇出 0 不代表反馈悬空。
//     当前单一 C0 反馈网络保留 NORMAL 补偿，C2 经专用 BUFG；最终路由须复查。
//     若初始化超时（LED=1），检查 pll_locked、复位、加密件与最终时钟路由。
//     不能用添加无业务意义的 C0 负载代替反馈检查。超时分支不发送 UART 报告。
//
// ★ 测试图案：32 bit、包含全部 21 个地址位；不同合法地址得到不同图案。
//   连续 256 个低位地址使每个数据位都出现 0 和 1；单次地址变化不必翻转所有位。
//   写侧与读侧共用图案函数；TB 独立反解地址并穷举全地址范围，防止同错漏检。
//
// ★ 参数化的稀疏扫描：ADDR_SHIFT 默认 0 = 连续地址块；
//   ADDR_SHIFT=11、TEST_WORDS=1024、BASE_ADDR=0 时步长为 2048 word，
//   采样地址 0..2095104，只改变地址位 [20:11]，不是全部 bank/row/列或容量覆盖。
//   用移位实现步长是刻意的：**可综合 RTL 禁用 `/` 和 `%`**（项目规则 §5 第 10 条），
//   而 2 的幂用移位即可（ADDR_SHIFT 是编译期常数）。
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
// ★ 电脑侧对账：报告 71 Byte 是**定长**的，行格式固定：
//     SV-SDRAM-LOOP\r\n
//     INIT=x LOCK=x\r\n
//     W=hhhh R=hhhh CAP=hhhh BAD=hhhh\r\n
//     DONE\r\n
//   取数是自己跟自己比：W == R == CAP == TEST_WORDS 且 BAD == 0000 才算过。
//   理想的完整报告（默认参数）：
//     W=1000 R=1000 CAP=1000 BAD=0000
// ============================================================================

module top_sdram_loopback #(
    parameter integer CLK_FREQ      = 50_000_000,   // 板载晶振
    parameter integer MEM_CLK_FREQ  = 125_000_000,  // sv_system_pll C1，uart 也用这个
    parameter integer BAUD          = 115200,

    parameter [23:0]  POWERUP_CYC   = 24'd2_500_000,  // 上电等待 @125MHz
    parameter [23:0]  INIT_TO_CYC   = 24'd2_000_000,  // 等 Sdr_init_done 的超时 @125MHz

    parameter [20:0]  BASE_ADDR     = 21'd0,          // 起始 word 地址
    parameter [20:0]  TEST_WORDS    = 21'd4096,       // 测试 word 数（= 16 KB）
    parameter integer ADDR_SHIFT    = 0,              // 步长 = 1 << ADDR_SHIFT（0 = 连续）

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
    // 32-bit address signature. Recover a[7:0] from byte 1, then recover
    // a[20:13] / a[12:5] from bytes 3 / 2. Thus all 21 bits are distinguishable.
    // Mixing the low byte into each output byte also exercises every DQ bit
    // in a contiguous 256-word test. This is not a complete SDRAM march test.
    // ------------------------------------------------------------------------
    function [31:0] pat_of;
        input [20:0] a;
        begin
            pat_of = { (8'hA5 ^ a[7:0] ^ a[20:13]),
                       (8'h5A ^ a[7:0] ^ a[12:5]),
                       (8'h3C ^ a[7:0]),
                       (8'hC3 ^ {a[4:0], a[7:5]}) };
        end
    endfunction

    // ------------------------------------------------------------------------
    // 顶层状态机（125 MHz 域，全程单时钟域）
    // ------------------------------------------------------------------------
    localparam [3:0] ST_POWER    = 4'd0,
                     ST_INITWAIT = 4'd1,
                     ST_WRITE    = 4'd2,
                     ST_DRAIN    = 4'd3,
                     ST_READ     = 4'd4,
                     ST_RDWAIT   = 4'd5,
                     ST_REPORT   = 4'd6,
                     ST_OK       = 4'd7,
                     ST_ERR      = 4'd8;

    // 突发周期 = 突发长度 + 间隔（编译期常数）
    localparam integer PERIOD = BURST_N + BURST_GAP;

    // 报告长度（15 + 17 + 33 + 6 = 71 Byte，定长）
    localparam integer RPT_LEN = 71;

    reg  [3:0]  st;
    reg  [23:0] pwr_cnt;
    reg  [23:0] init_to_cnt;
    reg  [15:0] drain_cnt;
    reg  [19:0] rdwait_to_cnt;
    reg  [7:0]  err_code;
    reg  [6:0]  rpt_idx;
    reg  [7:0]  t_wr;
    reg  [7:0]  t_rd;
    reg  [20:0] wr_i;          // 已写 word 数
    reg  [20:0] rd_i;          // 已发读命令数
    reg  [20:0] cap_cnt;       // 已收到返回 word 数
    reg  [15:0] bad_cnt;       // 比对不符数
    reg  [3:0]  compare_bad_bytes;
    reg         compare_valid;

    // 地址 = BASE_ADDR + index * (1 << ADDR_SHIFT)；用移位，不用乘除
    //   （必须写在 wr_i / rd_i 声明之后，否则 Verilog 会先建 1 bit 隐式网线）
    wire [20:0] wr_addr = BASE_ADDR + (wr_i << ADDR_SHIFT);
    wire [20:0] rd_addr = BASE_ADDR + (rd_i << ADDR_SHIFT);

    // 应用侧握手：突发内逐拍使能，突发之间静默
    assign app_wr_en = (st == ST_WRITE) && (t_wr < BURST_N) && (wr_i < TEST_WORDS);
    assign app_rd_en = (st == ST_READ ) && (t_rd < BURST_N) && (rd_i < TEST_WORDS);

    assign app_wr_addr = wr_addr;
    assign app_wr_din  = pat_of(wr_addr);
    assign app_wr_dm   = 4'b0000;      // 全字节写入（与例程一致）
    assign app_rd_addr = rd_addr;

    // ---- 写侧计数：只随 app_wr_en 前进 ----
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
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
        end else if (st == ST_READ) begin
            if (t_rd == PERIOD - 1) t_rd <= 8'd0;
            else                    t_rd <= t_rd + 8'd1;
            if (app_rd_en)          rd_i <= rd_i + 21'd1;
        end
    end

    // ---- 收数据：sdr_rd_en 才是取数时刻（读侧是延迟应答式）----
    //      第 k 个返回对应第 k 个读命令（例程也是这么假设的，1:1 不丢）
    // Compare bytes in parallel, then count one bad word on the following edge.
    // This cuts the input-PAD -> 32-bit reduction -> counter enable path.
    // The last comparison completes when RDWAIT enters REPORT, before prefetch.
    wire capture_accept = sdr_rd_en && ((st == ST_READ) || (st == ST_RDWAIT)) &&
                          (cap_cnt < TEST_WORDS);
    wire [31:0] expected_word = pat_of(BASE_ADDR + (cap_cnt << ADDR_SHIFT));
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            cap_cnt <= 21'd0;
            bad_cnt <= 16'd0;
            compare_bad_bytes <= 4'b0000;
            compare_valid <= 1'b0;
        end else begin
            compare_valid <= capture_accept;
            if (capture_accept) begin
                cap_cnt <= cap_cnt + 21'd1;
                compare_bad_bytes <= {
                    (sdr_rd_dout[31:24] != expected_word[31:24]),
                    (sdr_rd_dout[23:16] != expected_word[23:16]),
                    (sdr_rd_dout[15:8]  != expected_word[15:8]),
                    (sdr_rd_dout[7:0]   != expected_word[7:0])
                };
            end
            if (compare_valid && (|compare_bad_bytes))
                bad_cnt <= bad_cnt + 16'd1;
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
            rpt_idx       <= 7'd0;
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
                if (cap_cnt >= TEST_WORDS)               st <= ST_REPORT;
                else if (rdwait_to_cnt >= RD_WAIT_TO_CYC) begin
                    err_code <= 8'h02;
                    st       <= ST_ERR;
                end else rdwait_to_cnt <= rdwait_to_cnt + 20'd1;
            end
            // 发报告（逐字节，uart 背压）
            ST_REPORT: begin
                if (rpt_idx >= RPT_LEN) begin
                    if (bad_cnt != 16'd0) begin
                        err_code <= 8'h03;
                        st       <= ST_ERR;
                    end else st <= ST_OK;
                end else if (uart_tx_valid && uart_tx_ready) rpt_idx <= rpt_idx + 7'd1;
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
            ST_REPORT  : led_code = 4'h7;
            ST_OK      : led_code = 4'h8;
            default    : led_code = err_code[3:0];   // ST_ERR：01/02/03
        endcase
    end

    assign led = led_code;

    // ------------------------------------------------------------------------
    // UART 报告：定长 71 Byte 纯 ASCII，行尾显式写 8'h0D / 8'h0A
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

    wire [8*15-1:0] rpt_l1 = { "SV-SDRAM-LOOP", 8'h0D, 8'h0A };
    wire [8*17-1:0] rpt_l2 = { "INIT=", hex8({7'b0, sdr_init_done}),
                               " LOCK=", hex8({7'b0, pll_locked}), 8'h0D, 8'h0A };
    wire [8*33-1:0] rpt_l3 = { "W=",   hex16(wr_i[15:0]),
                               " R=",  hex16(rd_i[15:0]),
                               " CAP=",hex16(cap_cnt[15:0]),
                               " BAD=",hex16(bad_cnt),      8'h0D, 8'h0A };
    wire [8*6-1:0]  rpt_l4 = { "DONE", 8'h0D, 8'h0A };

    wire [8*RPT_LEN-1:0] rpt_vec = { rpt_l1, rpt_l2, rpt_l3, rpt_l4 };

    // rpt_idx 超范围时钳到 0，避免出现负的下标（综合期已知安全）
    wire [6:0] rpt_sel  = (rpt_idx < RPT_LEN) ? rpt_idx : 7'd0;
    wire [7:0] rpt_byte = rpt_vec[ 8*(RPT_LEN-1-rpt_sel) +: 8 ];

    // Register the wide report-byte selector before the UART input shifter.
    // Index advances only on acceptance; prefetch while UART is busy and hold
    // the byte until ready. No bytes are skipped or duplicated under backpressure.
    reg [7:0] rpt_byte_q;
    reg       rpt_byte_valid;
    always @(posedge ext_mem_clk or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            rpt_byte_q     <= 8'd0;
            rpt_byte_valid <= 1'b0;
        end else if (st != ST_REPORT) begin
            rpt_byte_valid <= 1'b0;
        end else if (!rpt_byte_valid && (rpt_idx < RPT_LEN)) begin
            rpt_byte_q     <= rpt_byte;
            rpt_byte_valid <= 1'b1;
        end else if (rpt_byte_valid && uart_tx_ready) begin
            rpt_byte_valid <= 1'b0;
        end
    end

    assign uart_tx_valid = (st == ST_REPORT) && rpt_byte_valid;
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
