// ============================================================================
// framebuffer_loopback_core.v — 阶段 10 帧缓存回环【可仿真核心】（mem_clk 域）
// ----------------------------------------------------------------------------
// 依据：手册 7.10「Frame Buffer 帧缓存」、7.16.1「DMA 思想」
//       docs/interface_spec.md §三 3.4（slot_writer → mem_arbiter → mem_ctrl）、
//         §五（冻结地址表）、§一（valid&&ready 双判 / 只传逻辑字节地址）
//
// 定位：本模块是"把一帧写进 SDRAM 帧槽、再整帧读回逐像素比对"的**不带引脚**
//       核心。它不认板子，只认一个通用的 SDRAM 后端（req/ready 事务口）：
//         · 仿真时后端 = verification/models/frame_memory_model.sv
//         · 上板时后端 = platform/.../rtl/sdram_app_adapter.v + 厂商 `sdram` IP
//       所以本模块**能进 ModelSim 回归**；板级加密 IP 不可仿真的问题被隔离在
//       板级顶层与适配器里，核心里没有加密件。
//
// 数据通路（全程 mem_clk 单域）：
//   LFSR 像素源 -> frame_writer（2 像素/word、严格 640x480、抽样 CRC）
//              -> memory_arbiter（写通道）-> mem_ctrl -> 后端(SDRAM)
//   mem_ctrl <- memory_arbiter（读通道）<- video_read_dma（突发预取）
//              <- 像素 FIFO(sync_fifo) <- 自检器（同一条 LFSR 逐像素比对）
//
// ★ 自检原理：写侧与读侧跑**同一条 16bit LFSR**（每像素推进一步）。帧槽是行优
//   先连续布局，读 DMA 又按线性字节地址顺序取回，所以"写进去的第 i 个像素"与
//   "读回来的第 i 个像素"必须是同一个值。任何一个像素对不上就 bad_cnt++。
//   这条 LFSR 覆盖全部 16 位，比只写下标/常数更能暴露数据线与地址译码错误。
//
// ★ 硬约定遵守（项目规则 §5）
//   - 每个"等外部回应"的状态都有**独立**超时：等 init(done)、写帧、读帧各一条。
//   - 读写的清零/记账逻辑放在状态机之外、对所有状态生效。
//   - 一个 reg 只有一个驱动源；不用 `/` `%`（字地址换算、突发长度都是 2 的幂）。
//   - 报告用显式字节 8'h0D / 8'h0A（★ 绝不写 "\r\n"，Verilog-2001 没有 \r 转义）。
//   - 地址一律取自 rtl/include/pixel_format_defs.vh，禁止裸地址。
//
// ★ 地址斜坡自检探针（2026-10-03 新增，为"整帧仍有 3/4 像素错"定位用）
//   动机：板级实测寻址/读/写通路已通（帧前 2 个 word、连续 4 地址自检都对），但整帧
//   仍有 ≈3/4 像素错、首个不符像素 ≈ word 5。旧自检只回 4 个**固定图案**
//   （1111/2222/3333/4444），只能判"对不对"，**判不出错在哪个地址上**。
//   做法（交接文档路线 A）：**写进去的值 = 它自己的字地址**，于是"回读值"直接就是
//   "这份数据当初被写在哪个地址" ⇒ 一次上板即可读出：错位几 / 步长几 / 丢没丢。
//     · 探针 A：从字节 0x4000（字地址 0x1000，16 对齐）起**连续写 32 个 word**
//       （值 = 0x1000..0x101F，正好两段 16 字写突发），再从同一基址**顺序读回 32 个**，
//       但**不存回读数**（那要 512 个寄存器）：改为边读边与期望值比对，只报三个数 ——
//       `AM`（32 位匹配位图，bit N=1 表示第 N 个回读等于期望）、
//       `AF`（首个不符的序号，`FF`=全对）、`AV`（该序号上回读到的值）。
//     · 探针 C：A 读完之后，**另起一次预取**只读 4 个字（字 0x1004 起）。
//       ★ 这是**区分"写错"还是"读错"的关键**：读侧若"一次突发内只推进 4 个字"，
//         任何新突发的**前 4 个**都是对的 ⇒ C 回读的就是字 0x1004..0x1007 的**真实内容**。
//         于是 C=1004 1005 1006 1007 ⇒ 写侧正常；C=1000 1001 1002 1003 ⇒ **写侧**也错。
//     · 探针 B：从字节 0x40D4（字地址 0x1035，**≠ 16 对齐**）起写 4 个 word、读回 4 个
//       （同样落在一个新突发的前 4 个位置上），是"非对齐基址"的对照。
//   ★ 三个探针都在帧槽 0 内，随后被整帧写入覆盖，不留残留。
//   ★ 板上实测（2026-10-03，ID 195845，354 Byte 版）就是靠 A/B 差异定案的：
//     `A0..A3=1000 1001 1002 1003` 对、`A4..AF` 又重复回这 4 个，而 `B0..B3` 全对
//     ⇒ "一次连续读突发里读地址只推进 4 个字就回绕"，与帧级 `BAD` 恰为 3/4 完全吻合。

// ★ 报告（纯 ASCII，KEY=HEX，行尾真 CRLF，定长 208 Byte）：
//     SV-FB-LOOP / INIT=xx / WR=hhhhhh CRC=x SV=x / RD=hhhhhh BAD=hhhhhh
//     W0=hhhhhhhh W1=hhhhhhhh                     帧前两个读回 word（0x59C3ACE1/0x670FB387）
//     AM=hhhhhhhh AF=hh AV=hhhhhhhh               探针 A：匹配位图 / 首个不符序号 / 该处回读值
//     C0=hhhh C1=hhhh C2=hhhh C3=hhhh             探针 C：非零偏移处的 4 个回读值（低 16 位）
//     B0=hhhh B1=hhhh B2=hhhh B3=hhhh             探针 B：非 16 对齐基址的 4 个回读值（低 16 位）
//     BF=hhhhhh / DONE
//   判据（自比）：INIT=01 且 WR=RD=04B000(=307200) 且 CRC=1 且 SV=1 且 BAD=000000
//   且 AM=FFFFFFFF、AF=FF、AV=00000000、C0..C3=1004/1005/1006/1007、
//   B0..B3=1035/1036/1037/1038、BF=000000。
//   ★ C/B 两行只报**低 16 位**：探针地址都在 0x1000~0x1038，低 16 位足以唯一识别
//     （省一半寄存器；帧级 `BAD` 才是全局判据，高位错会被它抓到）。
//   ★ `SC=`（4 个固定图案）与 16 个 `A0..AF` 回读值都已废弃 —— 前者信息量不如斜坡，
//     后者要 512 个寄存器、把 125 MHz 下的报告通路时序打穿了（见下一条）。
//   ★ 报告索引用 9 位、**倒计数**取值（`rpt_vec[8*rpt_idx +: 8]`），索引里**不含减法器**。
//     （STA 记录：2026-10-03 先用 `RPT_LEN-1-rpt_sel` 的加法器 + 2832 bit 向量，
//      自研组 `clkc[1]→clkc[1]` 从 +0.030 ns 掉到 **−1.083 ns / 475 个违例端点**，
//      最差路径全在 `ra_reg → rpt_vec 选择 → u_uart_tx/shifter`；去掉 512 个回读
//      寄存器并把向量缩到 1664 bit 后重做。）
//   ★ 2026-10-03 晚再收一刀：report17 后自研组仍 −0.386 ns / 6 违例（4 条终止在
//     `u_uart_tx/shifter`），把 208:1 的扁平变址改成 **13 块 × 16 Byte 两级 mux +
//     块寄存器**（见文件末"报告 mux"整节）—— 逐字节等价，只是把长走线切在中间。
//   ★ 同日第三次：report18 复算后自研组收到 **−0.081 ns / 2 违例**，但这两条路径的起点
//     变成了 `rpt_idx → 9 位减法器 → rpt_dn[5]（扇出 195）→ 块 mux`（减法器被综合塞进了
//     块选择端）。于是把块号**提前一拍存进寄存器 `blk_nxt`**，关键路径变成
//     `blk_nxt → 块 mux → blk_q`，减法器退回成只喂 5 个 bit 的轻负载路径。
// ============================================================================
`include "safevision_defs.vh"

module framebuffer_loopback_core #(
    parameter [31:0] SLOT_BASE   = `SV_IMG0_BASE,      // 目标槽（冻结地址表）
    parameter [18:0] FRAME_PIX   = `SV_FRAME_PIXELS,   // 640x480 = 307200
    parameter [5:0]  LOW_WATER   = 6'd48,              // 像素 FIFO 预取低水位
    parameter [15:0] GAP_TIMEOUT = 16'd4096,           // frame_writer 帧内无进展超时

    parameter [23:0] INIT_TO_CYC = 24'd16_000_000,     // 等 init_done 超时（值必须 < 2^24）
    parameter [23:0] WR_TO_CYC   = 24'd16_000_000,     // 写一帧超时
    parameter [23:0] RD_TO_CYC   = 24'd16_000_000,     // 读一帧超时
    parameter [15:0] WR_DRAIN_CYC = 16'd2048           // 写完后等写落地（照例程 WR_DRAIN_CYC，读写不重叠）
)(
    input  wire        clk,           // mem_clk 125 MHz
    input  wire        rst_n,         // mem 域低有效

    // ---- 通用 SDRAM 后端事务口（= mem_ctrl 的 sdram_* 侧）----
    output wire        sdram_req,
    output wire        sdram_wr,
    output wire [31:0] sdram_addr,    // 字地址（mem_ctrl 内已 addr>>2）
    output wire [31:0] sdram_wdata,
    output wire [3:0]  sdram_wstrb,
    input  wire [31:0] sdram_rdata,
    input  wire        sdram_rdata_valid,
    input  wire        sdram_ready,
    input  wire        sdram_init_done,

    // ---- 报告字节流（接 uart_tx）----
    output wire        rep_valid,
    output wire [7:0]  rep_data,
    input  wire        rep_ready,

    // ---- 状态 / 结果（供 TB 与 LED 观察）----
    output reg         ok,            // 1：回环完全通过
    output reg  [7:0]  err_code,      // 非 0 表示失败主码
    output reg  [18:0] wr_px,         // frame_writer 报出的像素数
    output reg  [18:0] rd_px,         // 读回并比对的像素数
    output reg  [18:0] bad_px,        // 比对不符数
    output reg         crc_ok,        // frame_writer 抽样 CRC 通过
    output reg         slot_valid     // 槽有效位置起
);

    // ------------------------------------------------------------------------
    // 常量
    // ------------------------------------------------------------------------
    localparam [31:0] FRAME_BYTES = (FRAME_PIX * `SV_RGB565_BYTES_PER_PX);
    localparam integer RPT_LEN = 208;   // 报告定长字节数（见文件头）
    localparam [8:0]   RPT_LAST = 9'd207;   // = RPT_LEN-1，倒计数起点（不回绕、无需减法器）

    // 16bit Fibonacci LFSR：x^16 + x^14 + x^13 + x^11 + 1，种子 0xACE1（非零）
    localparam [15:0] LFSR_SEED = 16'hACE1;

    function [15:0] lfsr_next;
        input [15:0] s;
        begin
            lfsr_next = { s[14:0], (s[15] ^ s[13] ^ s[12] ^ s[10]) };
        end
    endfunction

    // 状态
    localparam [3:0] S_POWER    = 4'd0,
                     S_INIT     = 4'd1,
                     S_WR_START = 4'd2,
                     S_WR_RUN   = 4'd3,
                     S_RD_START = 4'd4,
                     S_RD_RUN   = 4'd5,
                     S_RD_WAIT  = 4'd6,
                     S_REPORT   = 4'd7,
                     S_OK       = 4'd8,
                     S_ERR      = 4'd9,
                     S_RD_DRAIN = 4'd10,  // 写→读之间的落地等待（照例程"等写落地"）
                     S_RAMP     = 4'd11;  // 地址斜坡自检（隔离适配器/突发桥/帧链）

    // ---- 地址斜坡探针的基址（字节地址 = 字地址 << 2；都落在帧槽 0 内）----
    //   只在这里写一次"字地址"，字节地址由移位得来，杜绝两份地址表对不上。
    localparam [31:0] RAMPA_W    = 32'd4096;                        // 0x1000，16 对齐
    localparam [31:0] RAMPB_W    = 32'd4149;                        // 0x1035，≠ 16 对齐
    localparam [31:0] SCR_BYTE   = `SV_IMG0_BASE + (RAMPA_W << 2);  // 0x4000（探针 A 写/读基址）
    localparam [31:0] SCRC_BYTE  = SCR_BYTE + 32'd16;               // 0x4010 = 字 0x1004（探针 C）
    localparam [31:0] SCR2_BYTE  = `SV_IMG0_BASE + (RAMPB_W << 2);  // 0x40D4（探针 B）
    localparam [15:0] RAMP_DRAIN = 16'd512;    // 写→读之间的落地等待（覆盖突发桥的攒字+写出）
    localparam [23:0] RAMP_TO_CYC= 24'd1_000_000;  // 探针"无进展"看门狗（125MHz ≈ 8ms）

    // ------------------------------------------------------------------------
    // frame_writer -> mem_ctrl 写通道（写相直连；协议同 tb_frame_writer：wr_ready=mem_ready）
    // ------------------------------------------------------------------------
    wire        fw_din_ready;
    wire        fw_wr_req;
    wire [31:0] fw_wr_addr;
    wire [31:0] fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid4;
    wire        dma_done_w;
    wire        fw_crc_ok_w;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire        fw_wr_done;
    wire        fw_wr_error;
    wire [7:0]  fw_err_code;
    wire [7:0]  fw_err_detail;

    // ------------------------------------------------------------------------
    // 读突发引擎 <-> video_read_dma
    // ------------------------------------------------------------------------
    wire        rdeng_ack;
    wire        rdeng_busy;
    wire [31:0] rdeng_data;
    wire        rdeng_data_valid;
    wire        dma_rd_req;
    wire [31:0] dma_rd_addr;
    wire [15:0] dma_rd_len;

    // ------------------------------------------------------------------------
    // mem_ctrl 事务口（相位互斥：写相挂 frame_writer，读相挂读突发引擎）
    // ------------------------------------------------------------------------
    wire        rdeng_mem_req;
    wire [31:0] rdeng_mem_addr;
    wire        mem_req;
    wire        mem_wr;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_ready;
    wire [31:0] mem_rdata;
    wire        mem_rdata_valid;
    wire        mem_init_done;
    wire        mem_error;

    // ------------------------------------------------------------------------
    // 像素 FIFO（video_read_dma 写、自检器读）
    // ------------------------------------------------------------------------
    wire        pixfifo_wr;
    wire [15:0] pixfifo_din;
    wire        pixfifo_rd;
    wire [15:0] pixfifo_dout;
    wire        pixfifo_empty;
    wire [7:0]  pixfifo_cnt;        // sync_fifo DEPTH=128 的 data_count（clog2(128)+1 = 8 bit）
    wire [15:0] pixfifo_level = {8'b0, pixfifo_cnt};

    // ------------------------------------------------------------------------
    // 序列控制
    // ------------------------------------------------------------------------
    reg  [3:0]  st;
    reg  [23:0] init_to_cnt;
    reg  [23:0] wr_to_cnt;
    reg  [23:0] rd_to_cnt;
    reg         fw_start;
    reg         dma_start;
    reg  [18:0] wpx_sent;           // 已送出的像素数（写侧）
    reg  [15:0] wlfsr;              // 写侧像素源 LFSR
    reg  [15:0] clfsr;              // 读侧自检 LFSR
    reg         ck_v1, ck_v2;       // 自检流水有效位
    reg  [15:0] ck_pix, ck_exp;     // 自检流水：FIFO 像素 / 期望值
    reg         ck_bad;             // 自检流水：比对结果
    reg  [3:0]  rd_settle;          // 读完 → 报告之间的排空拍（等流水落定）
    reg  [15:0] drain_cnt;          // 写→读之间的落地等待计数
    reg         ramp_req, ramp_wr;  // 自检探针：直接驱动 mem 的 req/wr
    reg  [31:0] ramp_addr, ramp_wdata;
    reg  [4:0]  ramp_ph;            // 探针子步（0..18）
    reg  [15:0] ramp_gap;           // 探针：写→读之间的落地等待
    reg  [23:0] ramp_to;            // 探针：无进展看门狗
    reg  [5:0]  ramp_idx;           // 探针：写序号（A 段 0..31 / B 段 0..3）
    reg  [5:0]  ramp_rdidx;         // 探针：读序号（A 段 0..31 / C、B 段 0..3）
    // ★ 回读结果的收集全部用"移位"而不是"变址写数组"（2026-10-03 晚，为收 STA）：
    //   变址写会生成 32/4 路译码器，而它们的输出又喂给报告 mux（高扇出 + 长走线），
    //   实测 `amask` 的译码网 + `bw` 的扇出网占掉最差路径里 3 ns 以上。
    //   · amask：每比对完一个 A 段回读就**右移一位、把结果从最高位塞进来**
    //     ⇒ 32 次之后 bit0..bit31 正好 = 第 1..第 32 个回读的匹配结果（顺序不变）。
    //   · cwq/bwq：每收一个 word 就**左移 16 位、把新值塞进低半**
    //     ⇒ 4 次之后 {C0,C1,C2,C3} 依次落在 [63:48]/[47:32]/[31:16]/[15:0]。
    //   两者都只有"移位"这一种组合逻辑，报告侧改读固定位段。
    reg  [31:0] amask;              // 探针 A：32 个回读的匹配位图（bit N=1 = 第 N 个等于期望）
    reg  [7:0]  af_idx;             // 探针 A：首个不符序号（8'hFF = 全对）
    reg         af_set;
    reg  [31:0] av_val;             // 探针 A：首个不符序号上回读到的值
    reg  [63:0] cwq;                // 探针 C 回读：4 个 word（各留低 16 位，移位收集）
    reg  [63:0] bwq;                // 探针 B 回读：4 个 word（各留低 16 位，移位收集）
    // 探针 A 第 k 个回读的期望值 = 写进字 0x1000+k 的那个值 = 0x1000+k（值即地址）
    wire [31:0] a_exp = RAMPA_W + {26'd0, ramp_rdidx};
    reg  [31:0] w0_q, w1_q;         // 报告用：前 2 个读回 word（诊断）
    reg  [18:0] bad_first;          // 诊断：首个不符像素的索引（定位错位起点）
    reg         bf_set;
    reg  [2:0]  wcnt;               // 已收 word 数
    reg         half_q;             // 0=等低半 1=已收低半
    reg  [15:0] lo_q;
    reg  [8:0]  rpt_idx;            // 报告索引：9 位、**倒计数**（354 Byte 超出 8 位）
    reg         rpt_run;            // 报告发射中（进 S_REPORT 后先装初值，见状态机）
    // 下一字节索引（倒计数 -1）。唯一的减法器；**只喂状态机的 `rpt_idx` 寄存器**（负载很轻）。
    // ★ 不要再把它接到报告块 mux 的选择端：report18 就是这么被"4 级 ADDER + 扇出 195"
    //   压在关键路径上的。块号请用寄存器 `blk_nxt`，见文件末"报告 mux"一节。
    wire [8:0]  rpt_dn = rpt_idx - 9'd1;

    assign rep_valid = (st == S_REPORT) && rpt_run && rep_ready;
    wire   rep_fire  = rep_valid;   // uart_tx 取走一字节

    // 像素源：LFSR 当前值即"下一个要送出的像素"；只送 FRAME_PIX 个，送满即停。
    // ★ 必须门控 valid：若送满后 valid 仍为 1，frame_writer 会判"像素数超限"
    //   （DET_BMP_SIZE）而不置 slot_valid（这正是第一次跑报 err=02 的原因）。
    wire [15:0] px_src        = wlfsr;
    wire        src_valid     = (st == S_WR_RUN) && (wpx_sent < FRAME_PIX);
    wire        px_src_accept = src_valid && fw_din_ready;

    // ------------------------------------------------------------------------
    // 写侧 LFSR：每被 frame_writer 收走一个像素推进一步
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wlfsr    <= LFSR_SEED;
            wpx_sent <= 19'd0;
        end else if (st == S_WR_START) begin
            wlfsr    <= LFSR_SEED;
            wpx_sent <= 19'd0;
        end else if (px_src_accept) begin
            wlfsr    <= lfsr_next(wlfsr);
            wpx_sent <= wpx_sent + 19'd1;
        end
    end

    // ------------------------------------------------------------------------
    // 读侧自检：每从 FIFO 取走一个像素，与 clfsr 比对并推进一步
    //   fifo 清零门控用 rd_fire = rd & ~empty，空读不动指针（sync_fifo 自带门控）
    // ------------------------------------------------------------------------
    wire chk_active = (st == S_RD_RUN) || (st == S_RD_WAIT);
    assign pixfifo_rd = chk_active && !pixfifo_empty;
    wire   chk_fire   = pixfifo_rd;   // = rd & ~empty

    // ★ 3 级流水：把 "512 深 FIFO 的组合读 -> 16bit 比较 -> 19bit 累加 -> CE" 拆到三拍。
    //   阶段 10 首次综合实测：不分拍时这条链达 9 级 / 10.3ns，125MHz(8ns) 下 SWNS
    //   = -2.579ns（45 个违例端点）。分拍后：级1 只到寄存器，级2/级3 各自独立。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ck_v1 <= 1'b0; ck_v2 <= 1'b0; ck_bad <= 1'b0;
            ck_pix<= 16'd0; ck_exp<= 16'd0;
            clfsr <= LFSR_SEED; rd_px <= 19'd0; bad_px <= 19'd0;
            wcnt <= 3'd0; half_q <= 1'b0; lo_q <= 16'd0;
            w0_q <= 32'd0; w1_q <= 32'd0;
            bad_first <= 19'd0; bf_set <= 1'b0;
        end else if (st == S_RD_START) begin
            ck_v1 <= 1'b0; ck_v2 <= 1'b0; ck_bad <= 1'b0;
            ck_pix<= 16'd0; ck_exp<= 16'd0;
            clfsr <= LFSR_SEED; rd_px <= 19'd0; bad_px <= 19'd0;
            wcnt <= 3'd0; half_q <= 1'b0; lo_q <= 16'd0;
            w0_q <= 32'd0; w1_q <= 32'd0;
            bad_first <= 19'd0; bf_set <= 1'b0;
        end else begin
            // 级1：锁存本拍从 FIFO 读出的像素与期望值（FIFO 组合读只到这一步）
            ck_v1  <= chk_fire;
            ck_pix <= pixfifo_dout;
            ck_exp <= clfsr;
            if (chk_fire) begin
                clfsr <= lfsr_next(clfsr);
                rd_px <= rd_px + 19'd1;
            end
            // 级2：比对已寄存的一对
            ck_v2  <= ck_v1;
            ck_bad <= ck_v1 && (ck_pix !== ck_exp);
            // 级3：累加（与 dout 已解耦）
            if (ck_bad) bad_px <= bad_px + 19'd1;
            // 诊断：记住首个不符像素的位置（≈ 当前 rd_px，误差 2 拍）
            if (ck_bad && !bf_set) begin bad_first <= rd_px; bf_set <= 1'b1; end

            // 诊断：抓前 2 个读回 word（低半=先到像素，与 frame_writer 打包一致）
            if (chk_fire) begin
                if (!half_q) begin
                    lo_q   <= pixfifo_dout;
                    half_q <= 1'b1;
                end else begin
                    half_q <= 1'b0;
                    if (wcnt == 3'd0)      w0_q <= {pixfifo_dout, lo_q};
                    else if (wcnt == 3'd1) w1_q <= {pixfifo_dout, lo_q};
                    if (wcnt < 3'd3) wcnt <= wcnt + 3'd1;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 主序列
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st          <= S_POWER;
            init_to_cnt <= 24'd0;
            wr_to_cnt   <= 24'd0;
            rd_to_cnt   <= 24'd0;
            fw_start    <= 1'b0;
            dma_start   <= 1'b0;
            rd_settle   <= 4'd0;
            drain_cnt   <= 16'd0;
            ramp_req    <= 1'b0;
            ramp_wr     <= 1'b0;
            ramp_ph     <= 5'd0;
            ramp_gap    <= 16'd0;
            ramp_to     <= 24'd0;
            ramp_idx    <= 6'd0;
            ramp_rdidx  <= 6'd0;
            amask       <= 32'd0;
            af_idx      <= 8'hFF;
            af_set      <= 1'b0;
            av_val      <= 32'd0;
            rpt_idx     <= RPT_LAST;
            rpt_run     <= 1'b0;
            ok          <= 1'b0;
            err_code    <= 8'h00;
            wr_px       <= 19'd0;
            crc_ok      <= 1'b0;
            slot_valid  <= 1'b0;
        end else begin
            // 默认单拍脉冲清零
            fw_start  <= 1'b0;
            dma_start <= 1'b0;

            // mem 超时（后端长时间不给 ready）——即时上报
            if (mem_error && (err_code == 8'h00)) err_code <= 8'h06;

            case (st)
            // ---- 上电：等 SDRAM 初始化（独立超时）----
            S_POWER: begin
                st <= S_INIT;
            end
            S_INIT: begin
                if (mem_init_done)                 st <= S_RAMP;
                else if (init_to_cnt >= INIT_TO_CYC) begin
                    err_code <= 8'h01;             // init 超时
                    st       <= S_REPORT;
                end else init_to_cnt <= init_to_cnt + 24'd1;
            end
            // ---- 地址斜坡自检探针（见文件头：写进去的值 = 它自己的字地址）----
            //   全程只有一个 reg 驱动 ramp_*，且 mem 请求在探针期间背靠背连发
            //   （写侧保持 req 高、每收一拍 ready 就把地址 +4、值 +1），
            //   形态与整帧写入一致 —— 这样探针才真的能代表帧通路。
            S_RAMP: begin
                if (mem_error || (ramp_to >= RAMP_TO_CYC)) begin
                    err_code <= 8'h06;        // mem 超时：后端长时间不响应（沿用既有错误码）
                    st       <= S_REPORT;
                end else begin
                    // 无进展看门狗：只要有一拍 ready / rdata_valid 就算有进展
                    if (mem_ready || mem_rdata_valid) ramp_to <= 24'd0;
                    else                              ramp_to <= ramp_to + 24'd1;

                    case (ramp_ph)
                    // ---- 装初值：探针 A 的写基址 ----
                    5'd0: begin
                        ramp_req   <= 1'b0; ramp_wr <= 1'b0;
                        ramp_addr  <= SCR_BYTE;
                        ramp_wdata <= RAMPA_W;
                        ramp_idx   <= 6'd0;
                        ramp_ph    <= 5'd1;
                    end
                    // ---- 探针 A：连续写 32 个 word（值 = 0x1000 + k）----
                    5'd1: begin ramp_req <= 1'b1; ramp_wr <= 1'b1; ramp_ph <= 5'd2; end
                    5'd2: if (mem_ready) begin
                              ramp_addr  <= ramp_addr  + 32'd4;    // 下一个字地址（连续）
                              ramp_wdata <= ramp_wdata + 32'd1;    // 值 = 地址
                              if (ramp_idx == 6'd31) begin
                                  ramp_req <= 1'b0;                // 保持 req 到最后一拍
                                  ramp_ph  <= 5'd3;
                              end else ramp_idx <= ramp_idx + 6'd1;
                          end
                    // ---- A 写落地等待（读写不重叠）；顺带清探针 A 的诊断量 ----
                    5'd3: if (ramp_gap >= RAMP_DRAIN) begin
                              ramp_gap   <= 16'd0;
                              ramp_addr  <= SCR_BYTE;              // 回到基址开始读
                              ramp_rdidx <= 6'd0;
                              amask      <= 32'd0;
                              af_idx     <= 8'hFF;
                              af_set     <= 1'b0;
                              av_val     <= 32'd0;
                              ramp_ph    <= 5'd4;
                          end else ramp_gap <= ramp_gap + 16'd1;
                    // ---- 探针 A：顺序读回 32 个 word，**边读边比对**（不存回读数）----
                    5'd4: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd5; end
                    5'd5: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd6; end
                    5'd6: if (mem_rdata_valid) begin
                              // 匹配位图：用移位收集（**不用变址写**，见 amask 的声明处说明）
                              amask <= {(mem_rdata === a_exp), amask[31:1]};
                              if (!af_set && (mem_rdata !== a_exp)) begin
                                  af_idx <= {2'b0, ramp_rdidx};    // 首个不符的序号
                                  av_val <= mem_rdata;             // 该处实际读回的值
                                  af_set <= 1'b1;
                              end
                              ramp_addr <= ramp_addr + 32'd4;
                              if (ramp_rdidx == 6'd31) begin
                                  ramp_rdidx <= 6'd0;
                                  ramp_addr  <= SCRC_BYTE;         // 探针 C 的基址
                                  ramp_ph    <= 5'd7;
                              end else begin
                                  ramp_rdidx <= ramp_rdidx + 6'd1;
                                  ramp_ph    <= 5'd4;
                              end
                          end
                    // ---- 探针 C：**另起一次预取**只读 4 个字（字 0x1004 起，非零偏移）----
                    //   读侧若"一次突发内只推进 4 个字"，新突发的前 4 个总是对的
                    //   ⇒ C 回读的就是字 0x1004..0x1007 的真实内容，用来判定**写侧**是否正常。
                    5'd7: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd8; end
                    5'd8: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd9; end
                    5'd9: if (mem_rdata_valid) begin
                              cwq <= {cwq[47:0], mem_rdata[15:0]};  // 移位收集（只留低 16 位）
                              ramp_addr      <= ramp_addr + 32'd4;
                              if (ramp_rdidx == 6'd3) begin
                                  ramp_rdidx <= 6'd0;
                                  ramp_idx   <= 6'd0;
                                  ramp_ph    <= 5'd10;
                              end else begin
                                  ramp_rdidx <= ramp_rdidx + 6'd1;
                                  ramp_ph    <= 5'd7;
                              end
                          end
                    // ---- 装初值：探针 B 的写基址（非 16 对齐）----
                    5'd10: begin
                        ramp_addr  <= SCR2_BYTE;
                        ramp_wdata <= RAMPB_W;
                        ramp_idx   <= 6'd0;
                        ramp_ph    <= 5'd11;
                    end
                    // ---- 探针 B：连续写 4 个 word（值 = 0x1035 + k）----
                    5'd11: begin ramp_req <= 1'b1; ramp_wr <= 1'b1; ramp_ph <= 5'd12; end
                    5'd12: if (mem_ready) begin
                              ramp_addr  <= ramp_addr  + 32'd4;
                              ramp_wdata <= ramp_wdata + 32'd1;
                              if (ramp_idx == 6'd3) begin
                                  ramp_req <= 1'b0;
                                  ramp_ph  <= 5'd13;
                              end else ramp_idx <= ramp_idx + 6'd1;
                          end
                    // ---- B 写落地等待 ----
                    5'd13: if (ramp_gap >= RAMP_DRAIN) begin
                               ramp_gap   <= 16'd0;
                               ramp_addr  <= SCR2_BYTE;
                               ramp_rdidx <= 6'd0;
                               ramp_ph    <= 5'd14;
                           end else ramp_gap <= ramp_gap + 16'd1;
                    // ---- 探针 B：顺序读回 4 个 word ----
                    5'd14: begin ramp_req <= 1'b1; ramp_wr <= 1'b0; ramp_ph <= 5'd15; end
                    5'd15: if (mem_ready) begin ramp_req <= 1'b0; ramp_ph <= 5'd16; end
                    5'd16: if (mem_rdata_valid) begin
                               bwq <= {bwq[47:0], mem_rdata[15:0]};  // 移位收集（只留低 16 位）
                               ramp_addr      <= ramp_addr + 32'd4;
                               if (ramp_rdidx == 6'd3) ramp_ph <= 5'd17;
                               else begin
                                   ramp_rdidx <= ramp_rdidx + 6'd1;
                                   ramp_ph    <= 5'd14;
                               end
                           end
                    // ---- 探针结束，进整帧写入 ----
                    5'd17: begin ramp_ph <= 5'd0; st <= S_WR_START; end
                    default: begin ramp_req <= 1'b0; ramp_wr <= 1'b0;
                                   ramp_ph  <= 5'd0; st <= S_WR_START; end
                    endcase
                end
            end
            // ---- 写一帧：pulse start，再持续送像素 ----
            S_WR_START: begin
                fw_start <= 1'b1;
                st       <= S_WR_RUN;
            end
            S_WR_RUN: begin
                if (fw_wr_error) begin
                    err_code  <= 8'h02;            // 写错误（帧不完整/CRC 失败/越界）
                    st        <= S_REPORT;
                end else if (fw_wr_done) begin
                    wr_px     <= fw_px_cnt;
                    crc_ok    <= fw_crc_ok_w;
                    slot_valid<= fw_slot_valid4[0];
                    if (fw_crc_ok_w && fw_slot_valid4[0]) begin
                        drain_cnt <= 16'd0;
                        st        <= S_RD_DRAIN;   // 先等写落地再读（照例程，读写不重叠）
                    end else begin
                        err_code <= 8'h03;         // CRC/槽有效位未通过
                        st       <= S_REPORT;
                    end
                end else if (wr_to_cnt >= WR_TO_CYC) begin
                    err_code  <= 8'h04;            // 写帧超时
                    st        <= S_REPORT;
                end else wr_to_cnt <= wr_to_cnt + 24'd1;
            end
            // ---- 写落地等待（读写不重叠；照例程 WR_DRAIN_CYC）----
            S_RD_DRAIN: begin
                if (drain_cnt >= WR_DRAIN_CYC) st <= S_RD_START;
                else                           drain_cnt <= drain_cnt + 16'd1;
            end
            // ---- 读一帧：pulse start ----
            S_RD_START: begin
                dma_start <= 1'b1;
                rd_settle <= 4'd0;
                st        <= S_RD_RUN;
            end
            S_RD_RUN: begin
                if (dma_done_w) begin
                    rd_to_cnt <= 24'd0;
                    st        <= S_RD_WAIT;
                end else if (rd_to_cnt >= RD_TO_CYC) begin
                    err_code <= 8'h05;              // 读帧超时
                    st       <= S_REPORT;
                end else rd_to_cnt <= rd_to_cnt + 24'd1;
            end
            // ---- 等 FIFO 排空 + 像素数到位 ----
            S_RD_WAIT: begin
                if ((rd_px >= FRAME_PIX) && pixfifo_empty) begin
                    // 再等几拍让自检流水（bad_px 落后 rd_px 两拍）落定
                    if (rd_settle >= 4'd8) begin
                        if (bad_px != 19'd0) err_code <= 8'h07;   // 数据不符
                        st <= S_REPORT;
                    end else rd_settle <= rd_settle + 4'd1;
                end else if (rd_to_cnt >= RD_TO_CYC) begin
                    err_code <= 8'h05;
                    st       <= S_REPORT;
                end else rd_to_cnt <= rd_to_cnt + 24'd1;
            end
            // ---- 发报告（逐字节，uart 背压；索引倒计数，见 rpt_idx 说明）----
            S_REPORT: begin
                if (!rpt_run) begin
                    rpt_run <= 1'b1;          // 装索引（只做一次），下一拍起出字节
                    rpt_idx <= RPT_LAST;
                end else if (rep_fire) begin
                    if (rpt_idx == 9'd0) begin
                        rpt_run <= 1'b0;
                        if (err_code == 8'h00) begin
                            ok <= 1'b1;
                            st <= S_OK;
                        end else st <= S_ERR;
                    end else rpt_idx <= rpt_dn;   // = rpt_idx-1（减法器只喂这里，不进块 mux）
                end
            end
            S_OK : st <= S_OK;
            S_ERR: st <= S_ERR;
            default: st <= S_POWER;
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // 报告装配（定长 208 Byte；每段都标注"逐字节相加 = 声明字节数"）
    // ------------------------------------------------------------------------
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

    // （旧版"4 个固定图案 ramp_pat"已删除：地址斜坡探针的"值 = 地址"信息量更大）
    wire [23:0] wr_px24 = { 5'b0, wr_px };
    wire [23:0] rd_px24 = { 5'b0, rd_px };
    wire [23:0] bad24   = { 5'b0, bad_px };

    // L1 = 10+2 = 12
    wire [8*12-1:0] rpt_l1 = { "SV-FB-LOOP", 8'h0D, 8'h0A };
    // L2 = 5+2+2 = 9
    wire [8*9-1:0]  rpt_l2 = { "INIT=", hex8({7'b0, mem_init_done}), 8'h0D, 8'h0A };
    // L3 = 3+6 + 5+2 + 4+2 + 2 = 24
    wire [8*24-1:0] rpt_l3 = { "WR=",  hex24(wr_px24), " CRC=", hex8({7'b0, crc_ok}),
                               " SV=", hex8({7'b0, slot_valid}), 8'h0D, 8'h0A };
    // L4 = 3+6 + 5+6 + 2 = 22
    wire [8*22-1:0] rpt_l4 = { "RD=", hex24(rd_px24), " BAD=", hex24(bad24), 8'h0D, 8'h0A };
    // L5 = 3+8 + 1+3+8 + 2 = 25（诊断：前 2 个读回 word；期望 W0=59C3ACE1 W1=670FB387）
    wire [8*25-1:0] rpt_l5 = { "W0=", hex32(w0_q), " W1=", hex32(w1_q), 8'h0D, 8'h0A };
    // L6 = 3+8+2 = 13（探针 A：32 个回读的匹配位图；期望 FFFFFFFF）
    wire [8*13-1:0] rpt_l6 = { "AM=", hex32(amask), 8'h0D, 8'h0A };
    // L7 = 3+2+2 = 7（探针 A：首个不符的序号；期望 FF = 全对）
    wire [8*7-1:0]  rpt_l7 = { "AF=", hex8(af_idx), 8'h0D, 8'h0A };
    // L8 = 3+8+2 = 13（探针 A：该序号上实际读回的值；期望 00000000）
    wire [8*13-1:0] rpt_l8 = { "AV=", hex32(av_val), 8'h0D, 8'h0A };
    // L9 = 4×(3+4) + 3 空格 + 2 = 33（探针 C：非零偏移 4 个回读值；期望 1004/1005/1006/1007）
    //   cwq 是移位收集的：第 1 个收到的值落在最高半，依次往下（见 cwq 声明处）
    wire [8*33-1:0] rpt_l9 = { "C0=", hex16(cwq[63:48]), " C1=", hex16(cwq[47:32]),
                               " C2=", hex16(cwq[31:16]), " C3=", hex16(cwq[15:0]), 8'h0D, 8'h0A };
    // L10 = 33（探针 B：非 16 对齐基址 4 个回读值；期望 1035/1036/1037/1038）
    wire [8*33-1:0] rpt_l10 = { "B0=", hex16(bwq[63:48]), " B1=", hex16(bwq[47:32]),
                                " B2=", hex16(bwq[31:16]), " B3=", hex16(bwq[15:0]), 8'h0D, 8'h0A };
    // L11 = 3+6 + 2 = 11（诊断：首个不符像素索引；期望 000000）
    wire [8*11-1:0] rpt_l11 = { "BF=", hex24({5'b0, bad_first}), 8'h0D, 8'h0A };
    // L12 = 4+2 = 6
    wire [8*6-1:0]  rpt_l12 = { "DONE", 8'h0D, 8'h0A };

    // 合计 = 12+9+24+22+25+13+7+13+33+33+11+6 = 208 = RPT_LEN
    wire [8*RPT_LEN-1:0] rpt_vec = { rpt_l1, rpt_l2, rpt_l3, rpt_l4, rpt_l5,
                                     rpt_l6, rpt_l7, rpt_l8, rpt_l9, rpt_l10,
                                     rpt_l11, rpt_l12 };

    // ------------------------------------------------------------------------
    // 报告 mux：**两级 + 一级块寄存器**（2026-10-03 晚，为收 STA）
    // ------------------------------------------------------------------------
    // 起因：report17 实测自研组 `clkc[1]→clkc[1]` SWNS **-0.386ns / 6 个违例端点**，
    //   6 条里有 4 条终止在 `u_uart_tx/shifter_reg`（全是报告通路）。最差路径
    //   `rpt_idx -> rpt_vec 变址 mux -> u_uart_tx/shifter` 数据路径 8.106ns，
    //   其中 **net 占 71%**、`rpt_idx[4]` 扇出 **47** —— 代价主要在"一条 208:1 的
    //   大 mux 被摊平进 uart_tx、输出端要横跨芯片"，而不是逻辑层级深。
    // 做法：把 208 Byte 的扁平变址拆成 **13 块 × 16 Byte** 两级，两级之间插一个
    //   16 Byte 的块寄存器：
    //     第 1 级  rpt_idx -> 块选择（13:1 × 128bit）-> blk_q
    //     第 2 级  blk_q   -> 块内字节选择（16:1 × 8bit）-> rep_data -> uart_tx
    //   块寄存器把"大 mux -> 跨芯片送 uart_tx"这条长走线**切在中间**，第 2 级只剩
    //   一个 16:1 的窄 mux，8 根网直接进 uart_tx。
    // ★ 为什么**逐字节等价**：rpt_idx 逐字节递减 ⇒ 同一个 16 Byte 块内 `rpt_idx[8:4]`
    //   恒定，所以"下一字节所在的块" = "当前块"（跨块那一拍才真的换块）。
    // ★ 为什么**恒 ready（TB `rep_ready=1'b1`、报告逐拍流出）也正确**：blk_q 与 rpt_idx
    //   **在同一个时钟边沿更新**，装的是"下一字节所在的块"；对当前拍而言它与 rpt_idx
    //   始终一致，所以背靠背发射也不会读到旧块。进 S_REPORT 的第一拍另有 `!rpt_run`
    //   分支把 blk_q 直接装成末块初值。⇒ 不需要额外的 priming 拍。
    // ★ 只动 mux 结构：报告内容/接口/字节流**逐字节不变**（TB T8/T9 守住）。
    // ★ RPT_LEN 必须是 16 的整数倍（208 = 13×16）；改报告长度时这条要一起看。
    reg  [8*16-1:0] blk_q;                     // 当前 16 Byte 块（低字节 = 块内偏移 0）
    reg  [4:0]      blk_nxt;                   // 下一字节所在块 = block(rpt_idx-1)（见下）

    // 第 1 级：块选择（13:1 × 128bit），由**寄存器 `blk_nxt` 直接驱动**。
    //   块号 k 覆盖字节 [16k .. 16k+15] = **比特** [128k .. 128k+127] ⇒ 位偏移 = {k, 7'b0}。
    //   ★ 这里最容易写错：`{k, 4'b0000}` 是"k×16 位"，只有 `{k, 7'b0}` 才是"k×128 位"。
    //   ★★ 为什么块号要**提前一拍算好存进寄存器**（report18 的教训）：report18 复算后自研组
    //      只剩 **−0.081 ns / 2 个违例端点**，而这两条路径的起点都是
    //      `rpt_idx → 9 位减法器（4 级 ADDER，0.92 ns）→ rpt_dn[5]（扇出 195，1.73 ns）→ 块 mux`
    //      —— 减法器本来只是给状态机做 `rpt_idx-1`，却被综合塞进了块 mux 的选择端，
    //      于是"9 位借位链 + 195 扇出的网"全压在这条路上。
    //      现在把块号**提前一拍**算好：关键路径变成
    //          `blk_nxt（寄存器）→ 块 mux → blk_q`
    //      减法器则退回成一条**只喂 5 个 bit** 的轻负载路径（`rpt_idx → 5 位条件减法 → blk_nxt`）。
    //   `blk_nxt` 恒等于 `block(rpt_idx - 1)`（"下一个字节所在的块"）；不变量由更新式保证：
    //      只有 `rpt_idx[3:0] == 1`（下一个字节正好跨块）时才 -1，否则保持不变。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_q <= {8*16{1'b0}};
        else if (st == S_REPORT) begin
            if (!rpt_run)                                   // 进报告：装末块初值
                blk_q <= rpt_vec[ {RPT_LAST[8:4], 7'b0000000} +: 128 ];
            else if (rep_fire && (rpt_idx != 9'd0))         // 发射一字节：装"下一字节"的块
                blk_q <= rpt_vec[ {blk_nxt, 7'b0000000} +: 128 ];
        end
    end

    // 块号寄存器：恒 = block(rpt_idx - 1)。★ RPT_LEN 是 16 的倍数 ⇒ RPT_LAST[3:0]=15，
    //   所以 block(RPT_LAST) 与 block(RPT_LAST-1) 同块，初值都用 `RPT_LAST[8:4]`。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) blk_nxt <= 5'd12;
        else if (st == S_REPORT) begin
            if (!rpt_run)                    blk_nxt <= RPT_LAST[8:4];
            else if (rep_fire) begin
                if (rpt_idx[3:0] == 4'd1)    blk_nxt <= blk_nxt - 5'd1;  // 下一字节跨块
            end
        end
    end

    // 第 2 级：块内字节选择（16:1）。rpt_idx[3:0] 就是块内偏移。
    assign rep_data = blk_q[ {rpt_idx[3:0], 3'b000} +: 8 ];

    // ------------------------------------------------------------------------
    // 例化：帧写、仲裁、读 DMA、像素 FIFO、mem_ctrl
    // ------------------------------------------------------------------------
    frame_writer #(
        .GAP_TIMEOUT (GAP_TIMEOUT)
    ) u_fw (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (2'd0),
        .slot_base  (SLOT_BASE),
        .din        (px_src),
        .din_valid  (src_valid),
        .din_ready  (fw_din_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (mem_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid4),
        .crc_ok     (fw_crc_ok_w),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );

    // ------------------------------------------------------------------------
    // 相位互斥 mux：写相 = frame_writer，读相 = 读突发引擎
    //   两相不重叠（先整帧写完再整帧读回），可以直接切，不需要仲裁器。
    //   ★ 不用 memory_arbiter 的原因见 mem_read_burst.v 头注：它的读通道按
    //     "ready 与 data_valid 同拍"写，与本工程 mem_ctrl/模型的 valid-ready
    //     语义不匹配（实测 16 word 突发只回 15 拍）。仲裁器留给阶段 13。
    // ------------------------------------------------------------------------
    wire wr_phase   = (st == S_WR_START) || (st == S_WR_RUN);
    wire ramp_phase = (st == S_RAMP);

    assign mem_req   = ramp_phase ? ramp_req   : (wr_phase ? fw_wr_req  : rdeng_mem_req);
    assign mem_wr    = ramp_phase ? ramp_wr    : (wr_phase ? 1'b1       : 1'b0);
    assign mem_addr  = ramp_phase ? ramp_addr  : (wr_phase ? fw_wr_addr : rdeng_mem_addr);
    assign mem_wdata = ramp_phase ? ramp_wdata : (wr_phase ? fw_wr_data : 32'd0);
    assign mem_wstrb = ramp_phase ? (ramp_wr ? 4'hF : 4'h0) : (wr_phase ? 4'hF : 4'h0);

    mem_read_burst u_rdeng (
        .clk             (clk),
        .rst_n           (rst_n),
        .req             (dma_rd_req),
        .addr            (dma_rd_addr),
        .len             (dma_rd_len),
        .ack             (rdeng_ack),
        .busy            (rdeng_busy),
        .data            (rdeng_data),
        .data_valid      (rdeng_data_valid),
        .mem_req         (rdeng_mem_req),
        .mem_addr        (rdeng_mem_addr),
        .mem_ready       (mem_ready),
        .mem_rdata       (mem_rdata),
        .mem_rdata_valid (mem_rdata_valid)
    );

    video_read_dma #(
        .PIX_DEPTH     (128),
        .LOW_WATER     (LOW_WATER)
    ) u_dma (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (dma_start),
        .frame_base    (SLOT_BASE),
        .pix_fifo_level(pixfifo_level),
        .rd_req        (dma_rd_req),
        .rd_addr       (dma_rd_addr),
        .rd_len        (dma_rd_len),
        .rd_ack        (rdeng_ack),
        .rd_busy       (rdeng_busy),
        .rd_data       (rdeng_data),
        .rd_data_valid (rdeng_data_valid),
        .fifo_wr_data  (pixfifo_din),
        .fifo_wr_en    (pixfifo_wr),
        .rd_bytes_cnt  (),
        .active        (),
        .done          (dma_done_w)
    );

    sync_fifo #(
        .W              (16),
        .DEPTH          (128),
        .ALMOST_FULL_TH (96),
        .ALMOST_EMPTY_TH(8)
    ) u_pixfifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .wr_en        (pixfifo_wr),
        .din          (pixfifo_din),
        .full         (),
        .almost_full  (),
        .rd_en        (pixfifo_rd),
        .dout         (pixfifo_dout),
        .empty        (pixfifo_empty),
        .almost_empty (),
        .data_count   (pixfifo_cnt)
    );

    mem_ctrl u_mem (
        .clk               (clk),
        .rst_n             (rst_n),
        .init_done         (mem_init_done),
        .req               (mem_req),
        .wr                (mem_wr),
        .addr              (mem_addr),
        .wdata             (mem_wdata),
        .wstrb             (mem_wstrb),
        .rdata             (mem_rdata),
        .rdata_valid       (mem_rdata_valid),
        .ready             (mem_ready),
        .mem_error         (mem_error),
        .sdram_req         (sdram_req),
        .sdram_wr          (sdram_wr),
        .sdram_addr        (sdram_addr),
        .sdram_wdata       (sdram_wdata),
        .sdram_wstrb       (sdram_wstrb),
        .sdram_rdata       (sdram_rdata),
        .sdram_rdata_valid (sdram_rdata_valid),
        .sdram_ready       (sdram_ready),
        .sdram_init_done   (sdram_init_done)
    );

endmodule
