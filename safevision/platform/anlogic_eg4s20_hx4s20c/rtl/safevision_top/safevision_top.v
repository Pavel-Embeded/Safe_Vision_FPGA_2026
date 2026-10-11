// ============================================================================
// safevision_top.v — HX4S20C 板级顶层（HDMI B 输出 · 封装内 SDRAM · SD 卡 BMP 播放）
// ----------------------------------------------------------------------------
// 本顶层只做“板级要素”（PLL / 复位 / 厂商 IP / 引脚 / UART 报告），业务逻辑都在
// **可仿真**的模块里：
//
//   sd_bmp_player（B，rtl/storage/sd_bmp_player.v）—— ★ **跑板载 50 MHz（clk，R7）**
//     SD 卡 → FAT32 → file_streamer → bmp_parser → bmp_unpack → 2 像素打包成 32 位字
//   bmp_frame_sink（B，platform/.../rtl/bmp_frame_sink.v）—— 跑 mem_clk 50 MHz
//     官方 a_pixel_fifo（写 50M / 读 50M）+ A 的 bmp_frame_write_bridge（行序重映射）
//     + 帧控制器 → 逐 word 写请求 + 换帧请求
//   safevision_core（A）
//     memory_arbiter ← 写请求；帧读取/双缓冲换帧/合成/OSD/固定速率扫描 → RGB+同步
//   厂商 HDMI 1.4b 发送核 + hdmi_phy_wrapper（TMDS 串化）→ HDMI B 口
//
// ★★ 三条路要分清（别混为一谈）
//   ① SD 卡里的真 BMP → 屏幕：card_mode=1（本顶层主用途）
//   ② 片上应急图形 → 屏幕：启动、媒体/存储故障、KEY3 均有独立 BRAM 画面。
//      旧回落写入器仍保留，但安全画面不依赖它或 SDRAM。
//   ③ ①②都不是 HDMI 电气合规 / 显示器兼容 / 音频的验收证据 ✗
//
// ★ 跨时钟域（通过同步器、mailbox 或双时钟 FIFO）
//   · 像素流 50M → 50M：**官方 a_pixel_fifo**（双时钟 + 32→16 位宽转换），
//     写侧 wr_clk = clk、读侧 = mem_clk；`px_word_ready`（FIFO wr_ready）留在 50M 域 ✓
//   · 帧控制 50M → 50M：`mem_ready`（电平）/`frame_done`（toggle）/`last_frame_ok`
//     （电平）都在 player 内部两级同步 ✓
//   · 帧控制 50M → 50M：`frame_active`/`top_down`/`slot` 由 sink 内部两级同步 ✓
//   · 写口 wr_*（mem 域）直连 core 的 memory_arbiter（mem 域）✓
//   · 换帧请求 mem → sys：统一发布事件，使用带确认的 video_cdc_mailbox
//     传输 slot/generation/crc_ok，目的域寄存完整载荷及 valid ✓
//   · swap_busy sys → mem：单 bit 两级同步（`swap_busy_mem`），再给 sink ✓
//     ★ 注意：core 的 `frame_swap_ctrl` 跑在 **sys_clk**，所以 sink 的 `swap_busy`
//       不能直接接 `swap_state_o`，必须接同步后的 `swap_busy_mem`。
//
// ★ UART：板载 CH340G（D12），115200 8N1，周期性一行 ASCII（见 report 段）。
//   ★ 格式仍是固定 107 字节：ST/FS/SD/CARD/CNT/CUR/RD 取自 **player**（SD 链），
//     PX/F/SLOT/CRC 取自 **sink**（mem 侧的像素与换帧才是真相）；
//     EC 报"有效错误码"——sink 报错时优先报 sink 的（否则板上只看得到 E3）。
// ★ 本文件不生成位流；由 tools/run_board_sta.ps1 控制（默认关）。
// ============================================================================
// ★★ 2026-10-11：存储器时钟档。`Clk_sft` 必须是半周期(180°)，见 sv_board_memory_pll.v 的长注释。
//   ★★ 关键教训：`MEM_CLK_HZ`（下面的模块参数）**必须与这里一致** —— 它决定
//      UART 波特率分频（uart_tx 的 CLK_FREQ）、sink 超时、guard 超时。
//      改时钟而忘了它 ⇒ 波特率偏 ⇒ **串口全是乱码**（本轮踩过两次：50MHz 与 100MHz 档）。
//   ⇒ 现在统一成一个宏 `SAFEVISION_MEM_CLK_HZ`，同时喂 `SAFEVISION_SDRAM_CLK_HZ`
//      （给 global_def.v 算刷新）与模块参数 `MEM_CLK_HZ`（给波特率/超时）。
`ifdef SAFEVISION_DIAG_MEM100P0
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_MEM100P1
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_MEM100P2
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_MEM100P8
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_D4KR
// ★ 2026-10-11：100MHz + 精确 180° + **dm 修复（队友原版策略）** + **REFRESH_ROWS=4096**。
//   与上午那版 `SV-100M`（4096、无修复、"撕裂但认得出"）**只差 dm 修复这一个变量**——
//   用来把"花屏到底是 dm 修复造成、还是 2048 刷新不足造成"一刀切开。
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_D10R
// ★ 2026-10-11：与 D100 同一时钟档，但适配器的 DQM 释放策略改成"细化版"
//   （写流水排空后才把 App_wr_dm 放成 0，见 sdram_app_adapter.v 里的长注释）。
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_D100
// ★ 2026-10-11：100MHz + 精确 180°(5ns) + **DQM 修复**。与上午那版 `SV-100M` 的
//   唯一区别就是 DQM 修复（那次没带修复，屏幕是"撕裂但认得出是卡里的图"）。
//   ⇒ 用来把"100MHz 下的撕裂"到底是"被 DQM 掩掉的读"还是"换帧不同步"分开。
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_MEM100
`define SAFEVISION_MEM_CLK_HZ 100000000
`elsif SAFEVISION_DIAG_MEM111
`define SAFEVISION_MEM_CLK_HZ 111111111
`elsif SAFEVISION_DIAG_MEM125
`define SAFEVISION_MEM_CLK_HZ 125000000
`elsif SAFEVISION_DIAG_MEM62
`define SAFEVISION_MEM_CLK_HZ 62500000
`elsif SAFEVISION_DIAG_MEM180
`define SAFEVISION_MEM_CLK_HZ 50000000
`else
`define SAFEVISION_MEM_CLK_HZ 40000000
`endif
`define SAFEVISION_SDRAM_CLK_HZ `SAFEVISION_MEM_CLK_HZ
// ★ 2026-10-11 18:55 改回 4096，并说明为什么（这是一次被证实的实验错误）：
//   17:32 我把它从 4096 改成官方 global_def.v 的 2**ROW_WIDTH=2048（每行 31.25µs、
//   2048 行正好 64ms）。**从那以后的所有构建全部花屏**，而 17:32 之前唯一出过
//   "认得出卡里的图"的构建（上午 12:52 的 SV-100M）用的正是 4096（每行 15.6µs、
//   32ms 全刷 = 2 倍余量）。⇒ 2048 与 4096 成了**没被控制的变量**：
//   "dm 修复有害"与"2048 刷新不足"两个解释目前无法区分。
//   ⇒ 先回到所有已知结果对应的 4096，把刷新这一项从方程里去掉；
//     4096 = 2 倍余量，官方值只是"恰好满足"，对本板并未证明够用。
`define SAFEVISION_REFRESH_ROWS 4096
`include "pixel_format_defs.vh"
// Default video mode; the TD flow overrides it with -define SAFEVISION_BOARD_HD.
`ifndef SAFEVISION_BOARD_HD
`define SAFEVISION_BOARD_HD 0
`endif
// ★★ 诊断开关（2026-10-10）：板上 `PH=3 B=0000 BAD=<槽基址>` ⇒ 读回校验**从第 0 块起全灭**。
//   要分清"校验器/签名表坏了"还是"SDRAM 读写真的不通"，必须做一次**二分**：
//     正常位流                       STORAGE_INTEGRITY=1（读回校验 + 显示块校验都开）
//     `-define SAFEVISION_DIAG_NO_INTEGRITY` ⇒ STORAGE_INTEGRITY=0（走旧路径：
//       写排空后直接发布、显示用未校验 DMA）—— 若此时图能正常出，说明**数据通路是好的**，
//       问题在校验器；若仍是白屏/花屏，说明 SDRAM 往返本身有问题。
`ifdef SAFEVISION_DIAG_NO_INTEGRITY
`define SV_INT_DEF 0
`else
`define SV_INT_DEF 1
`endif
module safevision_top #(
    parameter integer HD = `SAFEVISION_BOARD_HD,
    parameter integer MEM_CLK_HZ = `SAFEVISION_MEM_CLK_HZ,
    // ★ 合并 origin/main 后：字体路径用对方的（相对工程路径，A 侧改动），
    //   同时保留本轮新增的两个"可测性参数"（MODE_TO_N / RPT_PERIOD_N）——两者正交。
    parameter FONT_FILE = "font8x16.mem",
    // 上电后等多久判定“卡不可用”而回落到片上测试图案（mem 拍）
    parameter [31:0] MODE_TO_N = MEM_CLK_HZ*3/10,       // 300 ms @50MHz
    // UART 状态行的发送周期（mem 拍）。默认 500 ms @50MHz。
    // ★ 提成 parameter 只是**为了可测**：整行 107 字节在 115200 波特下要 ~9.3 ms，
    //   仿真里等 500 ms 太贵。TD 流程不覆盖它 ⇒ 综合结果与原来完全一致。
    parameter [31:0] RPT_PERIOD_N = MEM_CLK_HZ/2,
    parameter [15:0] PLAYER_SPI_INIT_DIV=16'd249,
    parameter [15:0] PLAYER_SPI_FAST_DIV=16'd1,
    parameter integer STORAGE_INTEGRITY=`SV_INT_DEF
)(
    // ---- 板级引脚（引脚号见 project/board_verify/board_b.adc）----
    input  wire        clk,             // R7  50 MHz
    input  wire        rst_n,           // A2  KEY_1（低有效）
    input  wire        btn_next,        // B2  下一幅
    input  wire        btn_auto,        // C1  自动连播
    input  wire        btn_emergency,   // B1  KEY3, hold for on-chip safety scene
    output wire        uart_txd,        // D12 板载 CH340G，115200 8N1
    output wire [3:0]  led,             // A4/A3/C10/B12
    // SD 卡（SPI 模式）
    output wire        sd_ncs,          // A12
    output wire        sd_dclk,         // A14
    output wire        sd_mosi,         // A13
    input  wire        sd_miso,         // B14
    // HDMI B（TMDS 正端；负端由 TD 按 LVDS33 自动配对）
    output wire        HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P,
    output wire        HDMI_DDC_SCL,
    inout  wire        HDMI_DDC_SDA
);

    // ========================================================================
    // 时钟与复位
    // ========================================================================
    wire sys_clk, mem_clk, mem_clk_sft, pixel_clk, serial_clk;
    wire sys_lock, video_lock;
    wire ref_rst_n, common_rst_n, mem_rst_n, pixel_rst_n, sys_rst_n;

    reset_sync reset_ref(.clk(clk), .async_rst_n(rst_n), .rst_n(ref_rst_n));

    sv_board_memory_pll system_pll(.refclk(clk), .reset(1'b0), .extlock(sys_lock),
        .clk0_out(sys_clk), .clk1_out(mem_clk), .clk2_out(mem_clk_sft));

    generate
        if (HD == 0) begin : video_base
            sv_video_vga_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
                .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
        end else begin : video_hd
            sv_video_hd_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
                .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
        end
    endgenerate

    assign common_rst_n = ref_rst_n && sys_lock && video_lock;
    reset_sync reset_mem  (.clk(mem_clk),   .async_rst_n(common_rst_n), .rst_n(mem_rst_n));
    reset_sync reset_pixel(.clk(pixel_clk), .async_rst_n(common_rst_n), .rst_n(pixel_rst_n));
    reset_sync reset_sys(.clk(sys_clk),.async_rst_n(common_rst_n),.rst_n(sys_rst_n));

    // ========================================================================
    // 封装内 SDRAM（EG_PHY_SDRAM_2M_32，硬核、不出引脚）
    // ========================================================================
    wire        sdr_init_done, sdr_ref_valid, sdr_busy;
    wire        app_wr_en, app_rd_en, sdr_rd_en;
    wire [20:0] app_wr_addr, app_rd_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din, sdr_rd_dout;

    sdram memory_ip(.Clk(mem_clk), .Clk_sft(mem_clk_sft), .Rst(~mem_rst_n),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout));

    wire        adapter_req, adapter_wr, adapter_ready, adapter_rvalid, adapter_init;
    wire adapter_write_idle;
    wire adapter_fault,memory_error;
    reg card_mode; reg [31:0] mode_cnt;
    wire [31:0] adapter_addr, adapter_wdata, adapter_rdata;
    wire [3:0]  adapter_wstrb;

    // ★ 2026-10-11：适配器读模式开关。
    //   背景：d28（2026-10-06，唯一验证过能出图的状态）的顶层**根本没有适配器**，
    //   core 是直连 SDRAM IP 的。适配器（含读缓存 rbuf / rexp / 预取）是 d28 之后
    //   才加进来的，而它正是"读回全 1"最可疑的一段（TB 只用契约模型验过）。
    //   `-define SAFEVISION_DIAG_SLOW_READ` ⇒ 关掉 FAST_READ/PREFETCH，退回适配器
    //   自带的简单读握手（r_go/r_sv），把"两 bank 预取缓存"这条最新逻辑整段去掉。
`ifdef SAFEVISION_DIAG_SLOW_READ
    localparam integer ADAPTER_FAST_READ=0, ADAPTER_PREFETCH=0;
`else
    localparam integer ADAPTER_FAST_READ=1, ADAPTER_PREFETCH=1;
`endif
    sdram_app_adapter #(.FAST_READ(ADAPTER_FAST_READ),.PREFETCH_READ(ADAPTER_PREFETCH)) adapter(.clk(mem_clk), .rst_n(mem_rst_n),
        .req(adapter_req), .wr(adapter_wr), .addr(adapter_addr),
        .wdata(adapter_wdata), .wstrb(adapter_wstrb),
        .rdata(adapter_rdata), .rdata_valid(adapter_rvalid),
        .ready(adapter_ready), .init_done(adapter_init), .write_idle(adapter_write_idle),
        .protocol_fault(adapter_fault),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout));

    wire        mem_req, mem_wr, mem_ready, mem_rvalid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;

    mem_ctrl memory(.clk(mem_clk), .rst_n(mem_rst_n), .init_done(),
        .req(mem_req), .wr(mem_wr), .addr(mem_addr), .wdata(mem_wdata),
        .wstrb(mem_wstrb), .rdata(mem_rdata), .rdata_valid(mem_rvalid),
        .ready(mem_ready), .mem_error(memory_error),
        .sdram_req(adapter_req), .sdram_wr(adapter_wr), .sdram_addr(adapter_addr),
        .sdram_wdata(adapter_wdata), .sdram_wstrb(adapter_wstrb),
        .sdram_rdata(adapter_rdata), .sdram_rdata_valid(adapter_rvalid),
        .sdram_ready(adapter_ready), .sdram_init_done(adapter_init));

    // ---- core 的写通道应答（同一时刻只有一个生产者，两边共用）----
    wire prod_wr_ack, prod_wr_busy;
    // Board writers issue one word and retain its data until wr_ready.
    // The arbiter's wr_ack is only a GRANT: its prime cycle, a cache quiet
    // interval or a physical write flush may still delay mem_ready. Releasing
    // the writer at grant lets a queued next pixel pair replace the current
    // data before acceptance. Complete this producer word at the real edge.
    wire prod_word_accepted=prod_wr_busy&&mem_req&&mem_wr&&mem_ready;

    // ========================================================================
    // ① SD 卡 BMP 播放引擎（**50 MHz 域**，方案 A）+ mem 侧帧接收器
    //
    //   ★ 方案 A 的跨界结构（2026-10-06）：
    //       sd_bmp_player（clk 50M）── 32 位打包像素 ──► 官方 a_pixel_fifo
    //                                                  （写 50M / 读 50M）
    //         ◄── mem_ready / frame_done / last_frame_ok ── bmp_frame_sink（mem 域）
    //       sink 拿着 FIFO 的读侧 + A 的 bmp_frame_write_bridge + 帧控制器，
    //       写出 wr_* 给 core 的 memory_arbiter，并发出换帧请求。
    //
    //   ★ 为什么整条媒体链回到 50 MHz：它原本就是按 50 MHz 设计并 STA 过的
    //     （`top_stage6_fat32_mount.v` 头注 / `constraints/timing.sdc`），
    //     历史上塞进 125 MHz 的 mem 域后链内长路径（88 位目录名解码＋十进制乘法、
    //     bmp_unpack 的乘法器、LBA 计算）在 8 ns 预算下过不去。
    //     50 MHz 下 SPI 仍是瓶颈 ⇒ **不损失吞吐**。
    // ========================================================================
    // ---- 播放引擎（clk = 板载 50 MHz 域）----
    wire [31:0] pl_px_word;                  // 2 像素打包（低半字先）
    wire        pl_px_word_valid, pl_px_word_ready;
    wire        pl_frame_active, pl_top_down;
    wire [1:0]  pl_slot;
    wire [3:0]  pl_state, pl_fail_stage;
    wire [7:0]  pl_ec, pl_ed;
    wire [7:0]  pl_r1;                       // ★ SD 初始化诊断：最近一次 R1 原始字节
    wire [2:0]  pl_seq;                      // ★ SD 初始化诊断：挂在哪条命令
    wire        pl_sd_ready, pl_card_usable;
    wire [3:0]  pl_file_cnt;
    wire [1:0]  pl_cur_file;
    wire [31:0] pl_file_size, pl_bytes_rd;
    wire [18:0] pl_px_written;               // ★ 语义已改为"当前行内列号"（仅遥测）
    wire        pl_frame_ok;
    wire [15:0] pl_frame_cnt;

    // ---- 帧接收器（mem_clk = 50 MHz 域）----
    wire integrity_begin,integrity_top_down,integrity_done,integrity_pass,integrity_fault;
    wire [1:0] integrity_slot;
    wire verify_req,verify_ack,verify_busy,verify_valid;
    wire [31:0] verify_addr,verify_data,lookup_addr,lookup_crc;
    wire lookup_valid,video_integrity_fault;
    wire [31:0] integrity_bad_addr,integrity_expected,integrity_actual;
    wire [31:0] video_bad_addr,video_expected,video_actual,integrity_words;
    wire [31:0] integrity_word_last;      // 诊断 v4：最后一次读回的第 0 个字
    wire [11:0] integrity_fail_cnt;       // 诊断 v4：坏块数
    wire [15:0] integrity_blocks,display_fifo_level;
    wire display_dma_active;
    reg playback_fault;
    reg [31:0] playback_bad_addr,playback_expected,playback_actual;
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)begin playback_fault<=0;playback_bad_addr<=0;playback_expected<=0;playback_actual<=0;end
        else if(video_integrity_fault&&!playback_fault)begin
            playback_fault<=1;playback_bad_addr<=video_bad_addr;
            playback_expected<=video_expected;playback_actual<=video_actual;
        end
    wire        sk_wr_req;
    wire [31:0] sk_wr_addr, sk_wr_data;
    wire [15:0] sk_wr_len;
    wire        sk_swap_toggle, sk_swap_crc_ok;
    wire [1:0]  sk_swap_slot;
    wire [7:0]  sk_swap_gen;
    wire        sk_mem_ready, sk_frame_done, sk_frame_ok;
    wire [3:0]  sk_state;
    wire [7:0]  sk_ec, sk_ed;
    wire [15:0] sk_frame_cnt;
    wire [18:0] sk_px_written;
    reg         swap_busy_mem;          // sys 域同步过来的“换帧进行中”

    // 按键消抖（板级要素：机械按键抖动会一次按出多幅）
    //   ★ 必须做在 **player 的时钟域（clk，50 MHz）**：消抖后的信号直接进 player，
    //     若在 mem 域消抖，消抖结果还要再跨一次域（多一处 CDC、多一处约束）。
    //     按键本身是异步输入，`board_cdc.sdc` 已按异步端口处理。
    //
    // ★★ 语义修正（2026-10-06，由新增的顶层 TB 抓到）：
    //   原写法 `btn_next_db = (dn_cnt == 16'hFFFF)` 只表示"电平稳定了 65536 拍"，
    //   **按下和松开都为 1** ⇒ 按钮等于被永久按住：
    //     · `btn_auto` 恒 1 ⇒ 自动连播永远停不下来；
    //     · `btn_next` 恒 1 ⇒ "下一幅"按钮失效（一直处于"被按下"）；
    //     · `restart` 恒 1 ⇒ player 在 S_ERROR 里会无限重启。
    //   ⇒ 改成"稳定 **且** 按下"，并把 `btn_next` 做成**按下沿单拍脉冲**
    //     （player 端口注释写的就是"脉冲：下一幅"），`btn_auto` 保持**电平**（连播开关）。
    (* keep = "true" *) reg [1:0] next_sync, auto_sync;
    // HX4S20 schematic 6_EX_DEVICE.pdf: 10k pull-ups, switches to GND.
    // Board pins are active LOW. The player receives normalized press signals.
    wire next_pressed=~next_sync[1],auto_pressed=~auto_sync[1];
    reg [15:0] dn_cnt, da_cnt;
    reg        dn_s, da_s;
    reg        dn_db, dn_db_d, da_db;

    // ★★ 消抖实现必须用 **else 链**把"锁存输出"挂在"计数器满"那一支上：
    //   写成 `dn_db = (dn_cnt == 16'hFFFF) && btn_next` 会有个隐蔽毛刺 ——
    //   空闲时电平一直稳定 ⇒ `dn_cnt` **早已饱和在 0xFFFF**，于是按下的那一拍
    //   `(dn_cnt==0xFFFF) && btn_next` 立刻为 1 ⇒ **消抖窗被整个绕过**（本 TB 抓到）。
    //   改成 else 链后，按下那一拍走的是 `btn_next != dn_s` 分支（只清计数器、不动输出），
    //   输出要等**新电平稳定满窗**之后才更新 ⇒ 真消抖、且无毛刺。
    always @(posedge clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            next_sync<=2'b11;auto_sync<=2'b11;
            dn_cnt <= 16'd0; da_cnt <= 16'd0; dn_s <= 1'b0; da_s <= 1'b0;
            dn_db <= 1'b0; dn_db_d <= 1'b0; da_db <= 1'b0;
        end else begin
            next_sync<={next_sync[0],btn_next};auto_sync<={auto_sync[0],btn_auto};
            dn_s <= next_pressed; da_s <= auto_pressed;

            if (next_pressed != dn_s)        dn_cnt <= 16'd0;
            else if (dn_cnt != 16'hFFFF) dn_cnt <= dn_cnt + 16'd1;
            else                         dn_db  <= next_pressed;    // 稳定满窗才更新输出

            if (auto_pressed != da_s)        da_cnt <= 16'd0;
            else if (da_cnt != 16'hFFFF) da_cnt <= da_cnt + 16'd1;
            else                         da_db  <= auto_pressed;

            dn_db_d <= dn_db;
        end
    end

    wire btn_next_db = dn_db & ~dn_db_d;   // 按下沿 → 单拍脉冲（"下一幅"）
    wire btn_auto_db = da_db;              // 电平（"自动连播"开关）

    // A missing swap acknowledgement leaves active-slot ownership uncertain.
    // Latch this fault until common reset. Transfer only the stable single-bit
    // fault level into the player's domain; never decode MEM telemetry there.
    reg swap_fault_latched;
    wire sink_fatal_ref;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) swap_fault_latched <= 1'b0;
        else if (sk_ec == 8'hF1) swap_fault_latched <= 1'b1;
    end
    video_level_sync sink_fatal_sync(.clk(clk),.rst_n(ref_rst_n),
        .async_level(swap_fault_latched),.level(sink_fatal_ref));

    sd_bmp_player #(
        // ★ 本模块的时钟就是板载 50 MHz（R7 的原始晶振），不再经过 PLL：
        //   top_stage5/6 原本就是 "single 50 MHz domain, no PLL"，零风险。
        .CLK_HZ(50_000_000),.CLK_DIV_INIT(PLAYER_SPI_INIT_DIV),.CLK_DIV_FAST(PLAYER_SPI_FAST_DIV)
    ) player (
        .clk(clk), .rst_n(ref_rst_n),
        .run(1'b1),
        .btn_next(btn_next_db), .btn_auto(btn_auto_db),
        // A swap-ACK timeout can mean PIX already committed while SYS lost
        // the acknowledgement. Local retry cannot infer the active slot.
        // Preserve that slot until KEY1/common reset reinitializes both sides.
        // Media-stream aborts also need common reset: the child stream/sector
        // FSMs are not reset by a local player restart. KEY2 retries SD init;
        // KEY1 resets the complete chain after other errors.
        .restart(btn_next_db && !sink_fatal_ref && (pl_fail_stage == 4'd1)),
        .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .px_word(pl_px_word), .px_word_valid(pl_px_word_valid),
        .px_word_ready(pl_px_word_ready),
        .frame_active(pl_frame_active), .top_down_o(pl_top_down), .slot_o(pl_slot),
        .mem_ready(sk_mem_ready && card_mode && adapter_init && !(STORAGE_INTEGRITY && (integrity_fault || playback_fault)) && !swap_fault_latched && (sk_ec != 8'hF1)), .frame_done(sk_frame_done),
        .last_frame_ok(sk_frame_ok),
        .state_o(pl_state), .fail_stage(pl_fail_stage),
        .err_code(pl_ec), .err_detail(pl_ed),
        .init_r1(pl_r1), .init_seq(pl_seq),
        .sd_ready(pl_sd_ready), .card_usable(pl_card_usable),
        .file_cnt(pl_file_cnt), .cur_file(pl_cur_file),
        .cur_file_size(pl_file_size), .cur_bytes_rd(pl_bytes_rd),
        .cur_px_written(pl_px_written), .last_frame_ok_o(pl_frame_ok),
        .frame_cnt(pl_frame_cnt)
    );

    // ---- 帧接收器：官方 a_pixel_fifo（写 50M / 读 50M）+ A 的桥 + 帧控制器 ----
    //   ★ wr_clk 必须是 player 的时钟（clk）；clk/rst_n 是 mem 域
    //   ★ swap_busy 用 `swap_busy_mem`（已从 sys 域两级同步进 mem 域）：
    //     core 的 frame_swap_ctrl 跑在 **sys_clk**（见 frame_swap_ctrl.v 头注），
    //     所以不能把 `swap_state_o` 直接接进来（那是 sys→mem 的 CDC）✗
    bmp_frame_sink #(.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(STORAGE_INTEGRITY),
        .GAP_TIMEOUT(MEM_CLK_HZ/250),.SWAP_TO_N(MEM_CLK_HZ/10),.WRITE_TO_N(MEM_CLK_HZ/2)) sink (
        .clk(mem_clk), .rst_n(mem_rst_n), .wr_clk(clk),
        .px_word(pl_px_word), .px_word_valid(pl_px_word_valid),
        .px_word_ready(pl_px_word_ready),
        .frame_active(pl_frame_active), .top_down(pl_top_down), .slot(pl_slot),
        .mem_ready(sk_mem_ready), .frame_done(sk_frame_done),
        .last_frame_ok(sk_frame_ok),
        .wr_req(sk_wr_req), .wr_addr(sk_wr_addr), .wr_data(sk_wr_data),
        .wr_len(sk_wr_len), .wr_ready(prod_word_accepted && card_mode),
        .write_drained(adapter_write_idle && !prod_wr_busy),
        .verify_done(integrity_done),.verify_pass(integrity_pass),
        .source_begin(integrity_begin),.source_slot(integrity_slot),.source_top_down(integrity_top_down),
        .swap_toggle(sk_swap_toggle), .swap_slot(sk_swap_slot),
        .swap_generation(sk_swap_gen), .swap_crc_ok(sk_swap_crc_ok),
        .swap_busy(swap_busy_mem),
        .state_o(sk_state), .err_code(sk_ec), .err_detail(sk_ed),
        .frame_cnt(sk_frame_cnt), .px_written(sk_px_written)
    );

    // ========================================================================
    // ★★ 50 MHz（player）→ 50 MHz（mem）：遥测/状态字段**逐字段两级同步**
    //
    //   为什么必须有这一层：Plan A 把 player 搬到了 50 MHz 域，但 **UART 状态行、
    //   card_mode 回落判据、LED** 都还在 mem 域。如果让 mem 域的组合逻辑直接读
    //   player 的寄存器，TD 会报出 board_clk→mem 组 **55 条违例**（最差 −1.77 ns、
    //   Logic Level 6）—— 而且那是**真 CDC（跨域组合读）**，不只是时序问题 ✗。
    //   ⇒ 每个字段先过两级触发器，mem 域只读同步后的副本。
    //
    //   ★ 语义说明（重要，别过度解读）：状态行是"每 500 ms 刷新一次的诊断信息"，
    //     而且是**逐字节**发出去的（整行 ~9.3 ms），本来就不是原子快照；
    //     多 bit 字段（cur_bytes_rd / frame_cnt）在**值变化的那 1~2 拍**可能被读到
    //     中间值 —— 只影响该次显示的数值、没有功能后果，下一次报告即自愈。
    //     这一层要解决的是"消除亚稳态 + 把跨域路径变成同步器首级（可约束）"。
    //   ★ 每个字段用**独立的两级寄存器**，不做位宽拼接（拼接截断已踩过坑）。
    // ========================================================================
    reg [3:0]  t_state1, t_state, t_fail1, t_fail;
    reg [7:0]  t_ec1,    t_ec;
    reg [7:0]  t_ed1,    t_ed;      // ★ err_detail（细分码）：分不清"卡不应答/CRC/token"时靠它
    reg [7:0]  t_r1_1,   t_r1;      // ★ SD 初始化的 R1 原始字节
    reg [2:0]  t_seq_1,  t_seq;     // ★ SD 初始化挂在哪条命令
    reg        t_sd1,    t_sd,   t_card1, t_card, t_fok1, t_fok;
    reg [3:0]  t_fcnt1,  t_fcnt;
    reg [1:0]  t_cur1,   t_cur;
    reg [31:0] t_bytes1, t_bytes;
    reg [15:0] t_fcnt16_1, t_fcnt16;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            t_state1<=4'd0; t_state<=4'd0; t_fail1<=4'd0; t_fail<=4'd0;
            t_ec1<=8'd0;    t_ec<=8'd0;
            t_ed1<=8'd0;    t_ed<=8'd0;
            t_r1_1<=8'd0;   t_r1<=8'd0;
            t_seq_1<=3'd0;  t_seq<=3'd0;
            t_sd1<=1'b0;    t_sd<=1'b0;    t_card1<=1'b0; t_card<=1'b0;
            t_fok1<=1'b0;   t_fok<=1'b0;
            t_fcnt1<=4'd0;  t_fcnt<=4'd0;  t_cur1<=2'd0;  t_cur<=2'd0;
            t_bytes1<=32'd0;t_bytes<=32'd0;
            t_fcnt16_1<=16'd0; t_fcnt16<=16'd0;
        end else begin
            t_state1 <= pl_state;        t_state  <= t_state1;
            t_fail1  <= pl_fail_stage;   t_fail   <= t_fail1;
            t_ec1    <= pl_ec;           t_ec     <= t_ec1;
            t_ed1    <= pl_ed;           t_ed     <= t_ed1;
            t_r1_1   <= pl_r1;           t_r1     <= t_r1_1;
            t_seq_1  <= pl_seq;          t_seq    <= t_seq_1;
            t_sd1    <= pl_sd_ready;     t_sd     <= t_sd1;
            t_card1  <= pl_card_usable;  t_card   <= t_card1;
            t_fok1   <= pl_frame_ok;     t_fok    <= t_fok1;
            t_fcnt1  <= pl_file_cnt;     t_fcnt   <= t_fcnt1;
            t_cur1   <= pl_cur_file;     t_cur    <= t_cur1;
            t_bytes1 <= pl_bytes_rd;     t_bytes  <= t_bytes1;
            t_fcnt16_1 <= pl_frame_cnt;  t_fcnt16 <= t_fcnt16_1;
        end
    end

    // ========================================================================
    // ② 回落：片上固定测试图案（写 slot 0；2026-10-05 已上板点亮过）
    // ========================================================================
    reg  fb_start, fb_go, fb_valid, fb_toggle, fb_submitted, fb_drain_on;
    reg  [9:0] fb_x, fb_y, fb_drain;
    wire fb_ready, fb_wr_req, fb_wr_done, fb_crc_ok, fb_wr_error;
    wire [3:0] fb_slot_valid;
    wire [31:0] fb_wr_addr, fb_wr_data;
    wire [15:0] fb_wr_len;
    wire [18:0] fb_px;

    // ★★ `card_mode` / `mode_cnt` 必须**先声明再使用**：紧跟着的回落逻辑就要用 card_mode。
    //   原来声明在后面（原第 373 行）⇒ 后果有两条：
    //     ① ModelSim 直接报 `Undefined variable: 'card_mode'` + `already declared` ⇒ **顶层根本编译不过**；
    //     ② 按 Verilog 隐式网规则，前面的使用会**另建一根 1 bit 隐式网**，与后面的 reg
    //        **不是同一个对象** ⇒ 卡/回落的选择 mux 会读到一根未驱动的网。
    //   TD 恰好容忍了这种写法（所以板上回落路径当时是通的），但这是**工具相关的隐患**，
    //   本项目在 `sd_bmp_player.v` 文件头已把同类问题记为"既有踩坑"。
    reg fb_swap_seen,fb_swap_acked;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            fb_start<=1'b0; fb_go<=1'b0; fb_valid<=1'b0; fb_x<=10'd0; fb_y<=10'd0;
            fb_toggle<=1'b0; fb_submitted<=1'b0; fb_drain_on<=1'b0; fb_drain<=10'd0;
        end else begin
            fb_start <= 1'b0;
            if (card_mode || fb_submitted) begin
                fb_valid <= 1'b0;
            end else begin
                if (sdr_init_done && !fb_go) begin fb_start <= 1'b1; fb_go <= 1'b1; end
                if (fb_go) begin
                    // 像素推进：只在“本拍被接受”时前进（用当前值判断，避免同一像素被收两次）
                    if (fb_valid && fb_ready) begin
                        if (fb_x == `SV_FRAME_WIDTH-1) begin
                            fb_x <= 10'd0;
                            if (fb_y == `SV_FRAME_HEIGHT-1) begin
                                fb_y <= `SV_FRAME_HEIGHT;      // 标记送完
                                fb_valid <= 1'b0;
                            end else begin
                                fb_y <= fb_y + 10'd1;
                                fb_valid <= 1'b1;
                            end
                        end else begin
                            fb_x <= fb_x + 10'd1;
                            fb_valid <= 1'b1;
                        end
                    end else if (fb_y != `SV_FRAME_HEIGHT) begin
                        fb_valid <= 1'b1;                      // 等 ready，继续给同一像素
                    end
                    // 写完成 → 给适配器排空 → 提交换帧
                    // ★ 槽号必须是 **0**：`fb_writer` 是 `.slot_sel(2'd0)`，
                    //   `frame_writer` 只会置 `slot_valid[0]`。原写成 `[1]` ⇒ 这个条件
                    //   **永不成立** ⇒ `fb_drain_on`/`fb_submitted` 永不起 ⇒ 回落帧
                    //   写进去了却**从不提交换帧**（屏幕上永远看不到它，`led[2]` 也不亮）。
                    //   （由新增的顶层 TB 抓到。）
                    if (!fb_drain_on) begin
                        if (fb_wr_done && fb_crc_ok && fb_slot_valid[0]) fb_drain_on <= 1'b1;
                    end else if (fb_drain == 10'd1023 && adapter_write_idle && !prod_wr_busy) begin
                        fb_toggle   <= ~fb_toggle;
                        fb_submitted<= 1'b1;
                        fb_drain_on <= 1'b0;
                    end else begin
                        if(fb_drain!=10'd1023)fb_drain <= fb_drain + 10'd1;
                    end
                end
            end
        end
    end

    wire [15:0] fb_rgb565 = {fb_x[9:5], fb_y[8:3], fb_x[8:4]};

    frame_writer #(.GAP_TIMEOUT(32'd12500000)) fb_writer(
        .clk(mem_clk), .rst_n(mem_rst_n), .start(fb_start), .slot_sel(2'd0),
        .slot_base(`SV_IMG0_BASE),
        .din(fb_rgb565), .din_valid(fb_valid), .din_ready(fb_ready),
        .wr_req(fb_wr_req), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .wr_len(fb_wr_len), .wr_ready(prod_word_accepted && !card_mode), .wr_done(fb_wr_done),
        .slot_valid(fb_slot_valid), .crc_ok(fb_crc_ok), .crc_value(), .px_cnt(fb_px),
        .wr_error(fb_wr_error), .err_code(), .err_detail());

    // ---- Producer ownership: complete fallback before returning to the card ----
    //   ★ card_mode / mode_cnt 的**声明已挪到上面**（回落逻辑先用后声明是隐患，见那里的注释）
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            card_mode<=1'b1;mode_cnt<=0;fb_swap_seen<=0;fb_swap_acked<=0;
`ifdef SAFEVISION_DIAG_FORCE_FALLBACK
            // ★★ 诊断（2026-10-10）：强制走**回落路径**。彩条图案由**片上生成**
            //   （不经过 SD 卡 / FAT32 / FIFO），写进 SDRAM 槽 0，再由显示读回。
            //   用途：把"真实 SDRAM 的写+读往返"从卡路径里**单独拎出来**——
            //     彩条显示正常  ⇒ SDRAM 往返是好的 ⇒ 问题在卡路径的数据
            //     彩条花屏/白屏 ⇒ SDRAM 往返真的坏了
            //   这条路径 2026-10-05 曾在板上点亮过，是已知可用的参照。
            card_mode<=1'b0;
`endif
        end else begin
`ifdef SAFEVISION_DIAG_FORCE_FALLBACK
            card_mode<=1'b0;      // 常驻回落：卡路径让位，只跑彩条
`endif
            if(fb_submitted && swap_busy_mem)fb_swap_seen<=1;
            if(fb_swap_seen && !swap_busy_mem)fb_swap_acked<=1;
            // A late/restarted card may take over only after fallback display
            // ownership was acknowledged and no writer still owns the arbiter.
            if(!card_mode && fb_swap_acked && t_card && !prod_wr_busy)card_mode<=1;

            // The unified publisher below removes source-toggle mux edges.
            // Never switch away from a writer while it owns an in-flight frame.
            if (t_card && !fb_go) begin card_mode <= 1'b1; mode_cnt <= 32'd0; end
            else if (card_mode && !fb_go && t_fcnt16 == 16'd0) begin
                if (!STORAGE_INTEGRITY && mode_cnt >= MODE_TO_N) card_mode <= 1'b0;      // 超时 → 回落
                else mode_cnt <= mode_cnt + 32'd1;
            end
        end
    end

    //   ★ 卡路径的写口与换帧请求现在都由 **sink**（mem 域）产生 ⇒ 可直接与
    //     回落图案做 mux，不再有"player 在 50M 域产生 wr_*"的跨域问题 ✓
    wire        prod_wr_req  = card_mode ? sk_wr_req  : fb_wr_req;
    wire [31:0] prod_wr_addr = card_mode ? sk_wr_addr : fb_wr_addr;
    wire [31:0] prod_wr_data = card_mode ? sk_wr_data : fb_wr_data;
    wire [15:0] prod_wr_len  = card_mode ? sk_wr_len  : fb_wr_len;
    // A mux of two independent toggles creates false events on owner changes.
    // Publish selected source EVENTS into one toggle and one stable mailbox.
    reg sk_toggle_d,fb_toggle_d,publish_toggle;
    reg [1:0] publish_slot;reg [7:0] publish_gen;reg publish_crc;
    always @(posedge mem_clk or negedge mem_rst_n)begin
      if(!mem_rst_n)begin
        sk_toggle_d<=0;fb_toggle_d<=0;publish_toggle<=0;
        publish_slot<=0;publish_gen<=0;publish_crc<=0;
      end else begin
        sk_toggle_d<=sk_swap_toggle;fb_toggle_d<=fb_toggle;
        if(card_mode && (sk_swap_toggle!=sk_toggle_d))begin
          publish_toggle<=~publish_toggle;publish_slot<=sk_swap_slot;
          publish_gen<=publish_gen+1'b1;publish_crc<=sk_swap_crc_ok;
        end else if(!card_mode && (fb_toggle!=fb_toggle_d))begin
          publish_toggle<=~publish_toggle;publish_slot<=0;
          publish_gen<=publish_gen+1'b1;publish_crc<=fb_crc_ok;
        end
      end
    end
    wire prod_toggle=publish_toggle;
    wire [1:0] prod_slot=publish_slot;
    wire [7:0] prod_gen=publish_gen;
    wire prod_crc_ok=publish_crc;

    // ========================================================================
    // 跨域打包：mem 域（生产者） → sys 域（core 的 frame_swap_ctrl）
    // ========================================================================
    wire [1:0] slot_sys;
    wire [7:0] gen_sys;
    wire crc_sys,frame_ready,submit_ready;
    reg sent_toggle;
    wire submit_valid=(prod_toggle!=sent_toggle);
    always @(posedge mem_clk or negedge mem_rst_n)begin
      if(!mem_rst_n)sent_toggle<=0;
      else if(submit_valid&&submit_ready)sent_toggle<=prod_toggle;
    end
    // Reuse the non-droppable A mailbox. No logic consumes the metastability
    // stage. The source payload is held through an acknowledged transfer;
    // dst_data and dst_valid are registered together before core samples them.
    video_cdc_mailbox #(.WIDTH(11)) board_frame_mailbox(
      .src_clk(mem_clk),.src_rst_n(mem_rst_n),.src_data({prod_crc_ok,prod_slot,prod_gen}),
      .src_valid(submit_valid),.src_ready(submit_ready),
      .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_data({crc_sys,slot_sys,gen_sys}),
      .dst_valid(frame_ready),.dst_ready(1'b1));

    // ========================================================================
    // A 的整机核心
    // ========================================================================
    wire [23:0] rgb;
    wire [11:0] out_x, out_y;
    wire        out_de, out_vs, active, swap_error, frame_fault;
    wire [2:0]  swap_state;
    wire [31:0] underflows, missed, overflows;
    wire [11:0] scan_x,scan_y;
    wire scan_de,scan_frame_start,safety_active;
    wire [1:0] safety_level;
    wire [23:0] safety_rgb;wire safety_valid;
    reg media_fault_ref,storage_fault_mem;
    always @(posedge clk or negedge ref_rst_n)
        if(!ref_rst_n)media_fault_ref<=0;else media_fault_ref<=(pl_state==4'd10);
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)storage_fault_mem<=0;
        else storage_fault_mem<=memory_error||adapter_fault||(STORAGE_INTEGRITY&&(integrity_fault||playback_fault))||swap_fault_latched||fb_wr_error||(sk_ec!=0);
    board_display_guard display_guard(
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(scan_frame_start),
        .active_frame(active),.frame_fault(frame_fault),
        .media_fault_async(media_fault_ref),
        .storage_fault_async(storage_fault_mem),
        .manual_async(!btn_emergency),.safety_active(safety_active),.warning_level(safety_level));
    emergency_graphics #(.HD(HD),.FONT_FILE(FONT_FILE)) safety_scene(
        .clk(pixel_clk),.rst_n(pixel_rst_n),.de(scan_de),.frame_start(scan_frame_start),
        .x(scan_x),.y(scan_y),.active(safety_active),.direction(2'd2),
        .warning_level(safety_level),.rgb(safety_rgb),.valid(safety_valid));

    // ========================================================================
    // ★★ 2026-10-11：guard 的**写入侧跟踪**是 MEM 域的最差路径，必须能整块去掉。
    //
    //   实测（NOINTG 档 route.timing）：
    //     Begin: integrity/source_words_reg[11].clk
    //     End  : integrity/source_words_reg[27].ce
    //     Data Path Delay 14.683ns, Logic Level 12  ⇒ MEM 域 Fmax 仅 66.8MHz
    //   ⇒ 存储器时钟被迫从 125MHz 降到 40MHz（为容纳 guard）。
    //
    //   而 SDRAM IP 的**所有**验证过能工作的配置都是 125MHz：
    //     · 厂商例程 lab_ex4_tf 的 sys_pll（C1=125M 0° / C2=125M 180°）
    //     · 仓库里上板跑通过的 SDRAM 回环自检 top_sdram_loopback（同一套 sys_pll）
    //     · d28（2026-10-06，唯一验证过能出图的一版，旧 PLL = 125MHz）
    //   而 40MHz / 50MHz 全部失败（白屏 / 故障 / 设计不稳）。
    //
    //   `STORAGE_INTEGRITY=0` 时 guard 的跟踪逻辑**毫无用处**，却把 MEM 域拖到 14.7ns。
    //   ⇒ `-define SAFEVISION_DIAG_NO_GUARD`：整块不例化，输出全部置 0，
    //     把 MEM 域让出来给 125MHz。
    // ========================================================================
`ifdef SAFEVISION_DIAG_NO_GUARD
    assign integrity_fault=1'b0, integrity_pass=1'b0, integrity_done=1'b0;
    assign integrity_bad_addr=32'd0, integrity_expected=32'd0, integrity_actual=32'd0;
    assign integrity_word_last=32'd0, integrity_fail_cnt=12'd0;
    assign integrity_words=32'd0, integrity_blocks=16'd0;
    assign lookup_crc=32'd0, lookup_valid=1'b0;
    assign verify_req=1'b0, verify_addr=32'd0;
`else
    frame_integrity_guard #(.TIMEOUT(MEM_CLK_HZ)) integrity(
        .clk(mem_clk),.rst_n(mem_rst_n),.frame_begin(integrity_begin),.frame_slot(integrity_slot),
        .top_down(integrity_top_down),.accepted(prod_word_accepted&&card_mode),
        .write_addr(prod_wr_addr),.write_data(prod_wr_data),
        .verify_start(STORAGE_INTEGRITY && sk_state==4 && adapter_write_idle && !prod_wr_busy),
        .verify_allow(!display_dma_active || display_fifo_level>=16'd3000),
        .verify_done(integrity_done),.verify_pass(integrity_pass),.fault(integrity_fault),
        .rd_req(verify_req),.rd_addr(verify_addr),.rd_len(),.rd_ack(verify_ack),.rd_busy(verify_busy),
        .rd_data(verify_data),.rd_valid(verify_valid),.lookup_addr(lookup_addr),
        .lookup_crc(lookup_crc),.lookup_valid(lookup_valid),.bad_addr(integrity_bad_addr),
        .bad_expected(integrity_expected),.bad_actual(integrity_actual),
        .last_read_word(integrity_word_last),.fail_cnt(integrity_fail_cnt),
        .source_words(integrity_words),.checked_blocks(integrity_blocks));
`endif

    safevision_core #(.HD(HD), .FONT_FILE(FONT_FILE),.EMERGENCY_LATENCY(4),.DMA_STREAMING(1),.DMA_CHECKED(STORAGE_INTEGRITY),.FIFO_AW(STORAGE_INTEGRITY?11:12),.BURST_WORDS(STORAGE_INTEGRITY?64:256)) core(
        .sys_clk(sys_clk), .mem_clk(mem_clk), .pixel_clk(pixel_clk), .rst_n(common_rst_n),
        .frame_ready(frame_ready), .wr_frame_index(1'b0), .wr_slot_id(slot_sys),
        .wr_generation(gen_sys), .wr_crc_ok(crc_sys),
        .active_commit(), .active_next(), .generation_next(), .frame_index_next(),
        .swap_error(swap_error), .swap_state_o(swap_state),
        .frame_start_evt_b(), .swap_ack_evt_b(),
        .wr_req(prod_wr_req), .wr_addr(prod_wr_addr), .wr_data(prod_wr_data),
        .wr_len(prod_wr_len), .wr_ack(prod_wr_ack), .wr_busy(prod_wr_busy),
        .sd_req(verify_req&&STORAGE_INTEGRITY), .sd_wr(1'b0), .sd_addr(verify_addr), .sd_wdata(32'd0), .sd_len(16'd64),
        .sd_ack(verify_ack), .sd_busy(verify_busy), .sd_rdata(verify_data), .sd_rdata_valid(verify_valid),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_rdata_valid(mem_rvalid),
        .wr_starve_cnt(), .rd_starve_cnt(),
        .cfg_valid(1'b0), .cfg_ready(), .cfg_osd_enable(1'b0), .cfg_mode(2'd0),
        .cfg_fps_tens(4'd6), .cfg_fps_ones(4'd0), .cfg_sd_ok(1'b1),
        .cfg_origin_x(12'd0), .cfg_origin_y(12'd0), .cfg_foreground(24'hffffff),
        .emergency_rgb(safety_rgb), .emergency_valid(safety_valid),
        .scan_x(scan_x), .scan_y(scan_y), .scan_de(scan_de), .scan_frame_start(scan_frame_start),
        .rgb(rgb), .x(out_x), .y(out_y), .hsync(), .vsync(out_vs), .de(out_de),
        .pixel_valid(), .line_start(), .frame_start(), .active_frame_start(),
        .hblank(), .vblank(), .selected_layer(), .pix_active_slot(),
        .pix_generation(), .pix_frame_index(), .pix_active_valid(active),
        .pix_frame_fault(frame_fault), .pix_underflow_count(underflows),
        .pix_missed_frame_count(missed), .mem_overflow_count(overflows),
        .mem_fifo_pixels(display_fifo_level), .mem_dma_bytes(), .mem_dma_active(display_dma_active), .mem_dma_done(),
        .mem_fetch_state(),.expected_crc(lookup_crc),.expected_valid(lookup_valid),.crc_lookup_addr(lookup_addr),
        .integrity_fault(video_integrity_fault),.bad_addr(video_bad_addr),.bad_expected(video_expected),.bad_actual(video_actual));

    // sys → mem：换帧进行中（单 bit 两级同步）
    wire swap_busy_sys = (swap_state != 3'd0);
    reg  [2:0] sb_sync;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin sb_sync <= 3'd0; swap_busy_mem <= 1'b0; end
        else begin
            sb_sync <= {sb_sync[1:0], swap_busy_sys};
            swap_busy_mem <= sb_sync[2];
        end
    end

    // ========================================================================
    // HDMI B：厂商 1.4b 发送核 + TMDS 串化
    //   Fixed-rate RGB scan enters the existing A AXIS queue.
    // ========================================================================
    wire [23:0] axis_data;
    wire axis_valid,axis_user,axis_last,axis_ready,hdmi_backpressure;
    wire hdmi_resync;wire [31:0] hdmi_dropped_frames;wire [4:0] hdmi_queue_level;
    // Fixed scan cannot stop on AXIS ready. Reuse A's tested queue, keeping
    // data/user/last stable under bounded backpressure. Overflow resets the
    // transmitter and waits for a new complete frame, rather than corrupting
    // all following line boundaries.
    hdmi_video_bridge #(.HD(HD),.QUEUE_AW(4)) hdmi_queue(
      .clk(pixel_clk),.rst_n(pixel_rst_n),.rgb(rgb),.de(out_de),.x(out_x),.y(out_y),
      .axis_valid(axis_valid),.axis_user(axis_user),.axis_last(axis_last),.axis_data(axis_data),
      .axis_ready(axis_ready),.resync(hdmi_resync),.overflow_sticky(hdmi_backpressure),
      .dropped_frames(hdmi_dropped_frames),.queue_level(hdmi_queue_level));
    wire tx_reset=!pixel_rst_n||hdmi_resync;
    wire phy_rst_n;
    reset_sync reset_phy(.clk(serial_clk),.async_rst_n(!tx_reset),.rst_n(phy_rst_n));

    // 时钟稳定后打一拍读 EDID（照厂商例程）
    reg [16:0] edid_count; reg edid_trig;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin edid_count <= 17'd0; edid_trig <= 1'b0; end
        else begin
            edid_trig <= 1'b0;
            // Queue resync resets the entire transmitter, including its DDC
            // state. Start a new settling epoch and read EDID once again.
            // tx_reset is pixel-domain; no new asynchronous reset is created.
            if (tx_reset) edid_count <= 17'd0;
            else if (edid_count < 17'd100000) begin
                edid_count <= edid_count + 17'd1;
                if (edid_count == 17'd99999) edid_trig <= 1'b1;
            end
        end
    end

    wire [9:0] ch0, ch1, ch2, chclk;
    wire       hdmi_locked;

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"), .HTOTAL(HD ? 1650 : 800),
        .HSA(HD ? 40 : 96), .HFP(HD ? 110 : 16),
        .HBP(HD ? 220 : 48), .HACTIVE(HD ? 1280 : 640),
        .VTOTAL(HD ? 750 : 525), .VSA(HD ? 5 : 2),
        .VFP(HD ? 5 : 10), .VBP(HD ? 20 : 33),
        .VACTIVE(HD ? 720 : 480), .VIDEO_VIC(HD ? 4 : 1),
        .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"),
        .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
    ) transmitter(
        .I_pixel_clk(pixel_clk), .I_rst(tx_reset),
        .I_edid_read_trig(edid_trig), .O_edid_read_valid(), .O_edid_read_data(),
        .I_axis_s_user(axis_user), .I_axis_s_valid(axis_valid),
        .I_axis_s_last(axis_last), .I_axis_s_data(axis_data),
        .O_axis_s_ready(axis_ready),
        .I_audio_valid(1'b0), .I_audio_left_data(24'd0), .I_audio_right_data(24'd0),
        .I_acr_valid(1'b0), .I_acr_cts(20'd0), .I_acr_n(20'd0),
        .O_video_locked(hdmi_locked),
        .O_ddc_scl(HDMI_DDC_SCL), .IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(ch0), .O_ch1_tmds_data(ch1),
        .O_ch2_tmds_data(ch2), .O_clk_tmds_data(chclk));

    hdmi_phy_wrapper #(.DEVICE("EG")) serializer(
        .I_pixel_clk(pixel_clk), .I_serial_clk(serial_clk), .I_rst(!phy_rst_n),
        .I_tmds_channel_0(ch0), .I_tmds_channel_1(ch1),
        .I_tmds_channel_2(ch2), .I_tmds_channel_clk(chclk),
        .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P),
        .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P));

    // ========================================================================
    // UART 状态报告：周期性一行 ASCII（115200 8N1），固定 **107** 字节 + CRLF
    //   SV-PLAY ST=x FS=x EC=xx SD=x CARD=x CNT=x CUR=x RD=xxxxxxxx PX=xxxxx F=xxxx SLOT=x CRC=x ED=xx R1=xx SQ=x
    //   ★ ED=xx 是 `err_detail` 细分码（2026-10-06 新增）：主码 EC 只说"SD 初始化失败"，
    //     细分码才分得清是 `0x11` 协商失败 / `0x21` 响应超时 / `0x22` CRC16 / `0x23` token
    //     —— 板上排"卡接触"还是"卡应答错"就靠它。
    //   ★ R1=xx / SQ=x（2026-10-06 新增，SD 初始化诊断）：R1 是初始化里最近一次收到的
    //     R1 原始字节、SQ 是挂在哪条命令（0=CMD0/1=CMD8/2=CMD55/3=ACMD41）。
    //     判读：R1=FF ⇒ 卡没应答（接触/供电）；R1=05 ⇒ 非法命令（卡没听懂 ⇒ 时钟/位序）；
    //     R1=00 ⇒ 卡应答但状态不对；R1=01 且 SQ=1 ⇒ CMD8 回显/电压不符。
    //   ★ 每字节分两步（先算进寄存器、再送），避免把一个大 mux 直接压在
    //     UART 握手路径上（既有踩坑：报告选择器曾是最差路径）。
    // ========================================================================
    localparam integer RPT_LEN    = 189;
    localparam [31:0]  RPT_PERIOD = RPT_PERIOD_N;          // 见模块 parameter 注释

    // Snapshot integrity diagnostics at packet start. PH: 0 writing/idle,
    // 1 readback, 2 approved, 3 source/readback fault, 4 playback CRC fault.
    reg [3:0] diagnostic_phase;
    reg [31:0] diagnostic_addr,diagnostic_expected,diagnostic_actual,diagnostic_words;
    reg [15:0] diagnostic_blocks;
    reg [7:0]  ridx;
    reg [31:0] rper;
    reg        rbusy, rload;
    reg        rwait;               // rload 相位的等待拍（见下面 FSM 注释）
    reg [7:0]  rbyte;
    wire       uart_ready;
    // ★ `rbyte_c`（当前字节的组合值）**必须先声明再使用**：下面的发送状态机就要读它。
    //   原来声明在后面（原第 585 行）⇒ ModelSim 报 `Undefined variable: 'rbyte_c'` +
    //   `already declared`，顶层编译不过；同时按隐式网规则会多出一根未驱动的 1 bit 网。
    reg [7:0]  rbyte_c;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            ridx <= 8'd0; rper <= 32'd0; rbusy <= 1'b0; rload <= 1'b0; rbyte <= 8'd0;
            rwait <= 1'b0;
            diagnostic_phase<=0;diagnostic_addr<=0;diagnostic_expected<=0;
            diagnostic_actual<=0;diagnostic_words<=0;diagnostic_blocks<=0;
        end else begin
            if (!rbusy) begin
                if (rper >= RPT_PERIOD) begin
                    rper <= 32'd0; rbusy <= 1'b1; ridx <= 8'd0; rload <= 1'b1;
                    diagnostic_phase<=playback_fault?4:integrity_fault?3:integrity_pass?2:sk_state==4?1:0;
                    diagnostic_addr<=playback_fault?playback_bad_addr:integrity_bad_addr;
                    diagnostic_expected<=playback_fault?playback_expected:integrity_expected;
                    diagnostic_actual<=playback_fault?playback_actual:integrity_actual;
`ifdef SAFEVISION_DIAG_WORDPROBE
                    // ★ 诊断 v4 报文语义（与 v3 不同，务必按 v4 判读）：
                    //   W  = **整个校验过程最后一次读回的第 0 个字**
                    //        （反向校验 ⇒ 最后一次读的是第 0 块=槽基址）
                    //   B  = {sdr_init_done, adapter_init, adapter_fault(protocol_fault),
                    //         memory_error, fail_cnt[11:0]}
                    //        高 4 位 = 存储子系统健康位；低 12 位 = **坏块数**（不是通过数！）
                    //        2400 ⇒ 全部块都错；1 ⇒ 只有最先校验的那块错。
                    //   先确认抬头是 `SV-WPR4`（ID=26101004）再采数。
                    diagnostic_words<=integrity_word_last;
                    diagnostic_blocks<={sdr_init_done,adapter_init,adapter_fault,
                                        memory_error,integrity_fail_cnt};
`else
                    diagnostic_words<=integrity_words;diagnostic_blocks<=integrity_blocks;
`endif
                end else rper <= rper + 32'd1;
            end else if (rload) begin
                // ★ 时序（mem→mem 多米诺，2026-10-06）：ridx 刚更新后**故意等 1 拍**
                //   再把 rbyte_c 算进 rbyte —— 使"ridx → 90 路报告 mux → rbyte"成为
                //   **真实的 2 周期路径**，配合 board_cdc.sdc 的 set_multicycle_path 2
                //   （理由见那边）。ridx 扇出 54、net 占 73%，mux 数据源横跨全芯片，
                //   单周期切不动，只能给足采样周期。代价：每字节多 1 拍（当前 20 ns；旧配置 8 ns），
                //   相对 ~4340 拍/字节（115200@50M）可忽略。
                if (rwait) begin
                    rbyte <= rbyte_c;                     // 第 1 步：把字节算进寄存器
                    rload <= 1'b0;
                    rwait <= 1'b0;
                end else rwait <= 1'b1;
            end else if (uart_ready) begin
                if (ridx == RPT_LEN-1) begin rbusy <= 1'b0; ridx <= 8'd0; end
                else begin ridx <= ridx + 8'd1; rload <= 1'b1; end
            end
        end
    end

    function [7:0] hexc;
        input [3:0] v;
        begin
            hexc = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h41 + {4'd0, v} - 8'd10);
        end
    endfunction

    // 当前字节（组合），只在 rload 那一拍被寄存进 rbyte
    //   ★ EC 报"有效错误码"：sink 报错时优先报 sink 的（它只在 S_ERROR 里非 0，
    //     恢复即清零）—— 否则板上只看得到 player 的 E3（等 mem 侧超时），
    //     看不到到底是 FIFO/桥/换帧哪一步出的问题 ✗
    wire [7:0] rpt_ec = (sk_ec != 8'h00) ? sk_ec : t_ec;
    // ★ rbyte_c 的声明已挪到上面（见那里的注释：先用后声明是隐患）
    always @* begin
        case (ridx)
            8'd0: rbyte_c = 8'h53; 8'd1: rbyte_c = 8'h56; 8'd2: rbyte_c = 8'h2D;
`ifdef SAFEVISION_DIAG_FORCE_FALLBACK
            // 诊断版 F：强制回落彩条 ⇒ 抬头 `SV-FBK `（53 56 2D 46 42 4B 20）
            8'd3: rbyte_c = 8'h46; 8'd4: rbyte_c = 8'h42; 8'd5: rbyte_c = 8'h4B;
            8'd6: rbyte_c = 8'h20;
`elsif SAFEVISION_DIAG_MEM100P0
            // 100MHz + 0ns 相位 ⇒ 抬头 `SV-P0NS`（53 56 2D 50 30 4E 53）
            8'd3: rbyte_c = 8'h50; 8'd4: rbyte_c = 8'h30; 8'd5: rbyte_c = 8'h4E;
            8'd6: rbyte_c = 8'h53;
`elsif SAFEVISION_DIAG_MEM100P1
            // 100MHz + 1ns 相位 ⇒ 抬头 `SV-P1NS`（53 56 2D 50 31 4E 53）
            8'd3: rbyte_c = 8'h50; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h4E;
            8'd6: rbyte_c = 8'h53;
`elsif SAFEVISION_DIAG_MEM100P2
            // 100MHz + 2ns 相位 ⇒ 抬头 `SV-P2NS`（53 56 2D 50 32 4E 53）
            8'd3: rbyte_c = 8'h50; 8'd4: rbyte_c = 8'h32; 8'd5: rbyte_c = 8'h4E;
            8'd6: rbyte_c = 8'h53;
`elsif SAFEVISION_DIAG_MEM100P8
            // 100MHz + 8ns 相位 ⇒ 抬头 `SV-P8NS`（53 56 2D 50 38 4E 53）
            8'd3: rbyte_c = 8'h50; 8'd4: rbyte_c = 8'h38; 8'd5: rbyte_c = 8'h4E;
            8'd6: rbyte_c = 8'h53;
`elsif SAFEVISION_DIAG_D4KR
            // ★ 诊断版 D4KR：100MHz/精确180° + dm 修复 + **REFRESH_ROWS=4096**
            //   ⇒ 抬头 `SV-D4KR`（53 56 2D 44 34 4B 52）。与上午 `SV-100M` 只差 dm 修复。
            8'd3: rbyte_c = 8'h44; 8'd4: rbyte_c = 8'h34; 8'd5: rbyte_c = 8'h4B;
            8'd6: rbyte_c = 8'h52;
`elsif SAFEVISION_DIAG_D10R
            // ★ 诊断版 D10R：100MHz/精确180° + **细化版 DQM 释放策略** ⇒ 抬头 `SV-D10R`
            //   （53 56 2D 44 31 30 52）。与 `SV-D100`（队友原版策略）一对一对照。
            8'd3: rbyte_c = 8'h44; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h30;
            8'd6: rbyte_c = 8'h52;
`elsif SAFEVISION_DIAG_D100
            // ★ 诊断版 D100：100MHz + 精确 180°(5ns) + **DQM 修复** ⇒ 抬头 `SV-D100`
            //   （53 56 2D 44 31 30 30）。与 `SV-100M`（同一时钟档但无 DQM 修复）一眼可分。
            8'd3: rbyte_c = 8'h44; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h30;
            8'd6: rbyte_c = 8'h30;
`elsif SAFEVISION_DIAG_MEM100
            // ★ 诊断版 M100：去 guard + 100MHz + 精确 180°(5ns) ⇒ 抬头 `SV-100M`
            //   （53 56 2D 31 30 30 4D）
            8'd3: rbyte_c = 8'h31; 8'd4: rbyte_c = 8'h30; 8'd5: rbyte_c = 8'h30;
            8'd6: rbyte_c = 8'h4D;
`elsif SAFEVISION_DIAG_MEM111
            // 111.1MHz + 4ns ⇒ `SV-111M`（53 56 2D 31 31 31 4D），备用
            8'd3: rbyte_c = 8'h31; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h31;
            8'd6: rbyte_c = 8'h4D;
`elsif SAFEVISION_DIAG_MEM125
            // ★ 诊断版 M125：去掉 guard + 存储器时钟回 125MHz/180° ⇒ 抬头 `SV-125M`
            //   （53 56 2D 31 32 35 4D）
            8'd3: rbyte_c = 8'h31; 8'd4: rbyte_c = 8'h32; 8'd5: rbyte_c = 8'h35;
            8'd6: rbyte_c = 8'h4D;
`elsif SAFEVISION_DIAG_MEM187
            // ★ 诊断版 M8：40MHz + Clk_sft=+13ns(187.2°) ⇒ 抬头 `SV-M187`
            //   （53 56 2D 4D 31 38 37）。建立窗口最大，SDRAM 边界余量 +2.2ns。
            8'd3: rbyte_c = 8'h4D; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h38;
            8'd6: rbyte_c = 8'h37;
`elsif SAFEVISION_DIAG_MEM172
            // ★ 诊断版 M7：40MHz + Clk_sft=+12ns(172.8°≈180°) ⇒ 抬头 `SV-M172`
            //   （53 56 2D 4D 31 37 32）。只动相位、不动频率的干净实验。
            8'd3: rbyte_c = 8'h4D; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h37;
            8'd6: rbyte_c = 8'h32;
`elsif SAFEVISION_DIAG_MEM180
            // ★ 诊断版 M：SDRAM Clk_sft 修正为半周期(180°) + 50MHz ⇒ 抬头 `SV-M180`
            //   （53 56 2D 4D 31 38 30）。这是"修根因"的那一版。
            8'd3: rbyte_c = 8'h4D; 8'd4: rbyte_c = 8'h31; 8'd5: rbyte_c = 8'h38;
            8'd6: rbyte_c = 8'h30;
`elsif SAFEVISION_DIAG_SLOW_READ
            // ★ 诊断版 S：关掉适配器预取缓存 ⇒ 抬头 `SV-SLOW`（53 56 2D 53 4C 4F 57）
            8'd3: rbyte_c = 8'h53; 8'd4: rbyte_c = 8'h4C; 8'd5: rbyte_c = 8'h4F;
            8'd6: rbyte_c = 8'h57;
`elsif SAFEVISION_DIAG_NO_INTEGRITY
            // ★ 诊断版 D：整包**第一个词**就不同 ⇒ 一眼可辨，不用找 ID=。
            //   正常版 `SV-PLAY`（53 56 2D 50 4C 41 59）
            //   诊断版 `SV-DIAG`（53 56 2D 44 49 41 47）
            8'd3: rbyte_c = 8'h44; 8'd4: rbyte_c = 8'h49; 8'd5: rbyte_c = 8'h41;
            8'd6: rbyte_c = 8'h47;
`elsif SAFEVISION_DIAG_WORDPROBE
            // ★ 诊断版 W4：字探针 v4（反向校验 + 原始读回字 + 坏块总数）⇒ 抬头 `SV-WPR4`
            //   （53 56 2D 57 50 52 34）。与 v3 的 `SV-WPR3`（…52 33）一眼可分。
            8'd3: rbyte_c = 8'h57; 8'd4: rbyte_c = 8'h50; 8'd5: rbyte_c = 8'h52;
            8'd6: rbyte_c = 8'h34;
`else
            8'd3: rbyte_c = 8'h50; 8'd4: rbyte_c = 8'h4C; 8'd5: rbyte_c = 8'h41;
            8'd6: rbyte_c = 8'h59;
`endif
            8'd7: rbyte_c = 8'h20; 8'd8: rbyte_c = 8'h53;
            8'd9: rbyte_c = 8'h54; 8'd10: rbyte_c = 8'h3D;                    // "SV-PLAY ST="
            8'd11: rbyte_c = hexc(t_state);
            8'd12: rbyte_c = 8'h20; 8'd13: rbyte_c = 8'h46; 8'd14: rbyte_c = 8'h53;
            8'd15: rbyte_c = 8'h3D;                                           // " FS="
            8'd16: rbyte_c = hexc(t_fail);
            8'd17: rbyte_c = 8'h20; 8'd18: rbyte_c = 8'h45; 8'd19: rbyte_c = 8'h43;
            8'd20: rbyte_c = 8'h3D;                                           // " EC="
            8'd21: rbyte_c = hexc(rpt_ec[7:4]); 8'd22: rbyte_c = hexc(rpt_ec[3:0]);
            8'd23: rbyte_c = 8'h20; 8'd24: rbyte_c = 8'h53; 8'd25: rbyte_c = 8'h44;
            8'd26: rbyte_c = 8'h3D;                                           // " SD="
            8'd27: rbyte_c = hexc({3'd0, t_sd});
            8'd28: rbyte_c = 8'h20; 8'd29: rbyte_c = 8'h43; 8'd30: rbyte_c = 8'h41;
            8'd31: rbyte_c = 8'h52; 8'd32: rbyte_c = 8'h44; 8'd33: rbyte_c = 8'h3D; // " CARD="
            8'd34: rbyte_c = hexc({3'd0, t_card});
            8'd35: rbyte_c = 8'h20; 8'd36: rbyte_c = 8'h43; 8'd37: rbyte_c = 8'h4E;
            8'd38: rbyte_c = 8'h54; 8'd39: rbyte_c = 8'h3D;                   // " CNT="
            8'd40: rbyte_c = hexc(t_fcnt);
            8'd41: rbyte_c = 8'h20; 8'd42: rbyte_c = 8'h43; 8'd43: rbyte_c = 8'h55;
            8'd44: rbyte_c = 8'h52; 8'd45: rbyte_c = 8'h3D;                   // " CUR="
            8'd46: rbyte_c = hexc({2'd0, t_cur});
            8'd47: rbyte_c = 8'h20; 8'd48: rbyte_c = 8'h52; 8'd49: rbyte_c = 8'h44;
            8'd50: rbyte_c = 8'h3D;                                           // " RD="
            8'd51: rbyte_c = hexc(t_bytes[31:28]); 8'd52: rbyte_c = hexc(t_bytes[27:24]);
            8'd53: rbyte_c = hexc(t_bytes[23:20]); 8'd54: rbyte_c = hexc(t_bytes[19:16]);
            8'd55: rbyte_c = hexc(t_bytes[15:12]); 8'd56: rbyte_c = hexc(t_bytes[11:8]);
            8'd57: rbyte_c = hexc(t_bytes[7:4]);   8'd58: rbyte_c = hexc(t_bytes[3:0]);
            8'd59: rbyte_c = 8'h20; 8'd60: rbyte_c = 8'h50; 8'd61: rbyte_c = 8'h58;
            8'd62: rbyte_c = 8'h3D;                                           // " PX="
            8'd63: rbyte_c = hexc({1'b0, sk_px_written[18:16]});
            8'd64: rbyte_c = hexc(sk_px_written[15:12]); 8'd65: rbyte_c = hexc(sk_px_written[11:8]);
            8'd66: rbyte_c = hexc(sk_px_written[7:4]);   8'd67: rbyte_c = hexc(sk_px_written[3:0]);
            8'd68: rbyte_c = 8'h20; 8'd69: rbyte_c = 8'h46; 8'd70: rbyte_c = 8'h3D; // " F="
            8'd71: rbyte_c = hexc(sk_frame_cnt[15:12]); 8'd72: rbyte_c = hexc(sk_frame_cnt[11:8]);
            8'd73: rbyte_c = hexc(sk_frame_cnt[7:4]);   8'd74: rbyte_c = hexc(sk_frame_cnt[3:0]);
            8'd75: rbyte_c = 8'h20; 8'd76: rbyte_c = 8'h53; 8'd77: rbyte_c = 8'h4C;
            8'd78: rbyte_c = 8'h4F; 8'd79: rbyte_c = 8'h54; 8'd80: rbyte_c = 8'h3D; // " SLOT="
            8'd81: rbyte_c = hexc({2'd0, sk_swap_slot});
            8'd82: rbyte_c = 8'h20; 8'd83: rbyte_c = 8'h43; 8'd84: rbyte_c = 8'h52;
            8'd85: rbyte_c = 8'h43; 8'd86: rbyte_c = 8'h3D;                   // " CRC="
            8'd87: rbyte_c = hexc({3'd0, sk_swap_crc_ok});
            8'd88: rbyte_c = 8'h20; 8'd89: rbyte_c = 8'h45; 8'd90: rbyte_c = 8'h44;
            8'd91: rbyte_c = 8'h3D;                                           // " ED="
            8'd92: rbyte_c = hexc(t_ed[7:4]); 8'd93: rbyte_c = hexc(t_ed[3:0]);
            8'd94: rbyte_c = 8'h20; 8'd95: rbyte_c = 8'h52; 8'd96: rbyte_c = 8'h31;
            8'd97: rbyte_c = 8'h3D;                                           // " R1="
            8'd98: rbyte_c = hexc(t_r1[7:4]); 8'd99: rbyte_c = hexc(t_r1[3:0]);
            8'd100: rbyte_c = 8'h20; 8'd101: rbyte_c = 8'h53; 8'd102: rbyte_c = 8'h51;
            8'd103: rbyte_c = 8'h3D;                                          // " SQ="
            8'd104: rbyte_c = hexc({1'b0, t_seq});
            8'd105: rbyte_c = 8'h0D; 8'd106: rbyte_c = 8'h0A;                 // CRLF
            8'd107: rbyte_c = 8'h53;
            8'd108: rbyte_c = 8'h56;
            8'd109: rbyte_c = 8'h2d;
            8'd110: rbyte_c = 8'h4d;
            8'd111: rbyte_c = 8'h45;
            8'd112: rbyte_c = 8'h4d;
            8'd113: rbyte_c = 8'h20;
            8'd114: rbyte_c = 8'h49;
            8'd115: rbyte_c = 8'h44;
            8'd116: rbyte_c = 8'h3d;
            8'd117: rbyte_c = 8'h32;
            8'd118: rbyte_c = 8'h36;
            8'd119: rbyte_c = 8'h31;
            8'd120: rbyte_c = 8'h30;
            8'd121: rbyte_c = 8'h31;
            8'd122: rbyte_c = 8'h30;
            8'd123: rbyte_c = 8'h30;
`ifdef SAFEVISION_DIAG_FORCE_FALLBACK
            8'd124: rbyte_c = 8'h46; // 'F' = FORCE_FALLBACK build
`elsif SAFEVISION_DIAG_MEM100P0
            8'd124: rbyte_c = 8'h41; // 'A' = 100MHz/0ns 相位
`elsif SAFEVISION_DIAG_MEM100P1
            8'd124: rbyte_c = 8'h42; // 'B' = 100MHz/1ns 相位
`elsif SAFEVISION_DIAG_MEM100P2
            8'd124: rbyte_c = 8'h32; // '2' = 100MHz/2ns 相位
`elsif SAFEVISION_DIAG_MEM100P8
            8'd124: rbyte_c = 8'h38; // '8' = 100MHz/8ns 相位
`elsif SAFEVISION_DIAG_D4KR
            8'd124: rbyte_c = 8'h4B; // 'K' = D4KR build（100MHz/180° + dm 修复 + 刷新4096）
`elsif SAFEVISION_DIAG_D10R
            8'd124: rbyte_c = 8'h52; // 'R' = D10R build（100MHz/180° + 细化版 DQM 释放）
`elsif SAFEVISION_DIAG_D100
            8'd124: rbyte_c = 8'h51; // 'Q' = D100 build（100MHz/180° + DQM 修复）
`elsif SAFEVISION_DIAG_MEM100
            8'd124: rbyte_c = 8'h30; // '0' = MEM100 build（无 guard + 100MHz/180°）
`elsif SAFEVISION_DIAG_MEM111
            8'd124: rbyte_c = 8'h31; // '1' = MEM111 build（无 guard + 111MHz/4ns）
`elsif SAFEVISION_DIAG_MEM125
            8'd124: rbyte_c = 8'h4D; // 'M' = MEM125 build（无 guard + 125MHz/180°）
`elsif SAFEVISION_DIAG_MEM187
            8'd124: rbyte_c = 8'h39; // '9' = MEM187 build（40MHz, Clk_sft=+13ns）
`elsif SAFEVISION_DIAG_MEM172
            8'd124: rbyte_c = 8'h37; // '7' = MEM172 build（40MHz, Clk_sft=+12ns≈180°）
`elsif SAFEVISION_DIAG_MEM180
            8'd124: rbyte_c = 8'h38; // '8' = MEM180 build（Clk_sft=180°, 50MHz）
`elsif SAFEVISION_DIAG_SLOW_READ
            8'd124: rbyte_c = 8'h53; // 'S' = SLOW_READ build（适配器预取关闭）
`elsif SAFEVISION_DIAG_NO_INTEGRITY
            // ★ 诊断版自报身份（2026-10-10）：末位由 '2' 改 'D' ⇒ 串口报 `ID=2610100D`。
            //   目的：确认"诊断位流到底有没有烧进去"。正常版仍是 `ID=26101002`，TB 不受影响。
            8'd124: rbyte_c = 8'h44; // 'D' = DIAG build, STORAGE_INTEGRITY=0
`elsif SAFEVISION_DIAG_WORDPROBE
            // 字探针 v4 ⇒ `ID=26101004`（v3 是 26101003）。与抬头 `SV-WPR4` 双重可辨。
            8'd124: rbyte_c = 8'h34; // '4' = wordprobe v4
`else
            8'd124: rbyte_c = 8'h32; // ID=26101002: late BMP header orientation fix
`endif
            8'd125: rbyte_c = 8'h20;
            8'd126: rbyte_c = 8'h50;
            8'd127: rbyte_c = 8'h48;
            8'd128: rbyte_c = 8'h3d;
            8'd129: rbyte_c = hexc(diagnostic_phase[3:0]);
            8'd130: rbyte_c = 8'h20;
            8'd131: rbyte_c = 8'h42;
            8'd132: rbyte_c = 8'h41;
            8'd133: rbyte_c = 8'h44;
            8'd134: rbyte_c = 8'h3d;
            8'd135: rbyte_c = hexc(diagnostic_addr[31:28]);
            8'd136: rbyte_c = hexc(diagnostic_addr[27:24]);
            8'd137: rbyte_c = hexc(diagnostic_addr[23:20]);
            8'd138: rbyte_c = hexc(diagnostic_addr[19:16]);
            8'd139: rbyte_c = hexc(diagnostic_addr[15:12]);
            8'd140: rbyte_c = hexc(diagnostic_addr[11:8]);
            8'd141: rbyte_c = hexc(diagnostic_addr[7:4]);
            8'd142: rbyte_c = hexc(diagnostic_addr[3:0]);
            8'd143: rbyte_c = 8'h20;
            8'd144: rbyte_c = 8'h45;
            8'd145: rbyte_c = 8'h58;
            8'd146: rbyte_c = 8'h50;
            8'd147: rbyte_c = 8'h3d;
            8'd148: rbyte_c = hexc(diagnostic_expected[31:28]);
            8'd149: rbyte_c = hexc(diagnostic_expected[27:24]);
            8'd150: rbyte_c = hexc(diagnostic_expected[23:20]);
            8'd151: rbyte_c = hexc(diagnostic_expected[19:16]);
            8'd152: rbyte_c = hexc(diagnostic_expected[15:12]);
            8'd153: rbyte_c = hexc(diagnostic_expected[11:8]);
            8'd154: rbyte_c = hexc(diagnostic_expected[7:4]);
            8'd155: rbyte_c = hexc(diagnostic_expected[3:0]);
            8'd156: rbyte_c = 8'h20;
            8'd157: rbyte_c = 8'h47;
            8'd158: rbyte_c = 8'h4f;
            8'd159: rbyte_c = 8'h54;
            8'd160: rbyte_c = 8'h3d;
            8'd161: rbyte_c = hexc(diagnostic_actual[31:28]);
            8'd162: rbyte_c = hexc(diagnostic_actual[27:24]);
            8'd163: rbyte_c = hexc(diagnostic_actual[23:20]);
            8'd164: rbyte_c = hexc(diagnostic_actual[19:16]);
            8'd165: rbyte_c = hexc(diagnostic_actual[15:12]);
            8'd166: rbyte_c = hexc(diagnostic_actual[11:8]);
            8'd167: rbyte_c = hexc(diagnostic_actual[7:4]);
            8'd168: rbyte_c = hexc(diagnostic_actual[3:0]);
            8'd169: rbyte_c = 8'h20;
            8'd170: rbyte_c = 8'h57;
            8'd171: rbyte_c = 8'h3d;
            8'd172: rbyte_c = hexc(diagnostic_words[31:28]);
            8'd173: rbyte_c = hexc(diagnostic_words[27:24]);
            8'd174: rbyte_c = hexc(diagnostic_words[23:20]);
            8'd175: rbyte_c = hexc(diagnostic_words[19:16]);
            8'd176: rbyte_c = hexc(diagnostic_words[15:12]);
            8'd177: rbyte_c = hexc(diagnostic_words[11:8]);
            8'd178: rbyte_c = hexc(diagnostic_words[7:4]);
            8'd179: rbyte_c = hexc(diagnostic_words[3:0]);
            8'd180: rbyte_c = 8'h20;
            8'd181: rbyte_c = 8'h42;
            8'd182: rbyte_c = 8'h3d;
            8'd183: rbyte_c = hexc(diagnostic_blocks[15:12]);
            8'd184: rbyte_c = hexc(diagnostic_blocks[11:8]);
            8'd185: rbyte_c = hexc(diagnostic_blocks[7:4]);
            8'd186: rbyte_c = hexc(diagnostic_blocks[3:0]);
            8'd187: rbyte_c = 8'h0d;
            8'd188: rbyte_c = 8'h0a;
            default: rbyte_c = 8'h20;
        endcase
    end

    uart_tx #(.CLK_FREQ(MEM_CLK_HZ), .BAUD(115200)) u_uart(
        .clk(mem_clk), .rst_n(mem_rst_n),
        .tx_valid(rbusy && !rload),
        .tx_data(rbyte),
        .tx_ready(uart_ready),
        .txd(uart_txd));

    // ========================================================================
    // LED
    //   ★ 2026-10-06 更正注释：原来的 led[1]/led[2] 说明与下面的代码**写反了**
    //     （硬件上板时"LED 全亮"两种写法都成立，所以一直没被发现）。以下按**代码实际**写。
    //   led[0] 三个 PLL 锁定 + SDRAM 初始化完成
    //   led[1] 卡路径：已挂载+索引+至少一幅；回落路径：回落帧已提交（且该帧 CRC 通过）
    //   led[2] 画面已激活且换帧无错
    //   led[3] HDMI 已锁定 且 无反压 且 无帧故障
    // ========================================================================
    wire frame_ok_any = card_mode ? t_fok : fb_crc_ok;
    assign led = { hdmi_locked && !hdmi_backpressure && !frame_fault && !swap_error,
                   active && !swap_error,
                   (card_mode ? t_card : fb_submitted) && frame_ok_any,
                   sys_lock && video_lock && sdr_init_done };

endmodule
