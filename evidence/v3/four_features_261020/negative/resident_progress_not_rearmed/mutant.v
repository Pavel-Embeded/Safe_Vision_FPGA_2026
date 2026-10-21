// ============================================================================
// sd_bmp_player.v — 可综合的“SD 卡 BMP → 帧槽”播放引擎（B 链 · 整链装配）
// ----------------------------------------------------------------------------
// 定位：把此前**只存在于测试台**里的那条整链，做成**可综合、可复用**的模块：
//
//   SD 卡（SPI）
//     → sd_initializer（CMD0/CMD8/ACMD41/CMD58）
//     → mbr_parser（分区表 → 卷基址）
//     → fat32_boot_parser（BPB → 几何）
//     → file_index 前置：idx_clear → fat32_directory_scanner(+walker) → idx_commit
//     → file_streamer（+walker、sd_sector_reader）→ bmp_parser → bmp_unpack
//     → 2 像素打包成 32 位字 → `px_word`（→ 官方 a_pixel_fifo 写侧）
//
// ★ 行序重映射与逐 word 写请求（`bmp_frame_write_bridge`）**不在本模块**了：
//   方案 A 把它连同换帧握手一起挪到 **mem 侧**的 `bmp_frame_sink`
//   （因为只有 mem 侧才知道 br_done/crc_ok，且换帧要交给 core 的 frame_swap_ctrl）。
//   本模块只负责把像素打包好、按 `mem_ready` 开帧、按 `frame_done` 收帧。
//
// ★ 时钟域（**方案 A**，2026-10-06 重构）：**全部逻辑跑在板载 50 MHz（clk，R7）**。
//   为什么不再跑 mem_clk(125MHz)：这条链原本就是按 50 MHz 设计并 STA 过的
//   （`top_stage6_fat32_mount.v` 头注、`constraints/timing.sdc`），搬进 125 MHz 后
//   链内长路径（88 位目录名解码＋十进制乘法、bmp_unpack 的乘法器、LBA 计算）
//   在 8 ns 预算下过不去。⇒ 整链回到 50 MHz，只在**边界**跨一次。
//   ⇒ 本模块**内部没有任何跨时钟域**，CDC 只发生在模块边界（都在板级顶层处理）：
//      · 像素流：32 位打包字 → 官方 `a_pixel_fifo` 写侧（本域），读侧在 mem 域 ✓
//      · `mem_ready`（电平）/`frame_done`（toggle）从 mem 域来 ⇒ 本模块内两级同步
//      · `frame_active`/`top_down_o`/`slot_o` 送给 mem 域的 sink（sink 侧同步）
//      · 写口（wr_req/...）与换帧请求已**不在本模块**（挪到 mem 侧 bmp_frame_sink）
//
// ★ SPI 分频必须按**实际 clk**算：SCLK = clk / (2*(div+1))
//     clk=50MHz：初始化段 div=62 → 396.8 kHz（规范 100~400 kHz ✓）
//                数据段   div=0 → 12.5 MHz（spi_master 把 0 钳到 1；≤25 MHz ✓）
//   ★ 默认宏 `SD_DIV_INIT/FAST` 是按 **100 MHz** 定的（124→400kHz、1→25MHz）；
//     在 50 MHz 下直接用默认会得到 200 kHz / 25 MHz —— 25 MHz 恰好卡在规范上限、
//     且实测 SCLK 会因钳位变成 12.5 MHz 反而更慢。本模块默认参数已按 50 MHz 取好。
//
// ★★ 各阶段 `start` / `scan_en` / `idx_clear` / `idx_commit` 都是**单拍脉冲**
//    （不是电平！）—— 本模块用“进入状态的那一拍打一次脉冲”的写法；
//    若持续拉高会让被启动模块反复复位自己的 FSM、永久跑不完 ✗。
//
// ★ 每个“等外部回应”的状态都有**独立超时**（项目硬约定），超时进 S_ERROR。
//
// ★ 本模块不碰引脚、不含厂商 IP ⇒ **可用 ModelSim 直接仿真**
//   （见 verification/unit/tb_sd_bmp_player.sv）。
// ============================================================================
`include "safevision_defs.vh"
`include "pixel_format_defs.vh"

module sd_bmp_player #(
    // ★ 本模块的时钟就是**板载 50 MHz**（方案 A）；名字不再叫 CLK_HZ_MEM
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer SHARED_SERVICE = 0,
    parameter integer GUARDED_CS = 0,
    parameter integer MID_REF_SAMPLE = 0,
    parameter integer RESIDENT_CACHE = 0,
    // SPI 分频（见文件头推导；按 50 MHz 取默认）
    // ★★ 2026-10-06 板级实测后：初始化时钟由 396.8 kHz **降到 100 kHz**。
    //   背景：真卡初始化约 1/10 成功、`ED=11`（CMD0 的 R1 ≠ 0x01）；加内部上拉后
    //   **仍报 11 而非 21** ⇒ MISO 确实被驱动、不是"悬空噪声" ⇒ 更像边沿质量/信号完整性
    //   问题。SD 规范允许初始化段 100–400 kHz，取低端留最大裕量（数据段 12.5 MHz 不变）。
    parameter [15:0]  CLK_DIV_INIT = 16'd249,      // 50MHz/(2*250) = 100 kHz
    parameter [15:0]  CLK_DIV_FAST = 16'd0,        // 钳到 1 ⇒ 50MHz/(2*2) = 12.5 MHz
    // ★ 行序重映射与逐 word 写出（bmp_frame_write_bridge）已挪到 **mem 侧**的
    //   bmp_frame_sink（它才知道 br_done/crc_ok，换帧握手也一并归它）✓
    // 各阶段超时（各自独立计数器；按 50 MHz 折算的墙钟时间）
    parameter [31:0]  INIT_TO_N    = 32'd100_000_000,  // 2s @50MHz: includes the card's <=1s ACMD41 window
    parameter [31:0]  MOUNT_TO_N   = 32'd5_000_000,    // 100ms：等 MBR/BPB/目录/索引
    parameter [31:0]  STREAM_TO_N  = 32'd150_000_000,  // 3s no-progress in resident mode; legacy whole-file deadline
    parameter [31:0]  SWAP_TO_N    = 32'd5_000_000,    // 100ms：等换帧
    parameter [31:0]  PILOT_TO_N   = 32'd2_500_000,    // 50ms：等索引查找结果落定
    // ★ 2026-10-06 新增：SD 初始化失败后**自动重试**（真卡在复位后偶发不应答时非常有效）。
    //   总时长受 INIT_TO_N 约束（to_cnt 跨重试累加）。板级显示独立在
    //   300ms 后回落；慢卡完成后等待回落槽 ACK，再接管写口。
    parameter [3:0]   INIT_RETRY_MAX = 4'd15           // 最多重试 15 次（含首次共 16 次尝试）
)(
    input  wire        clk,          // 板载 50 MHz（R7）
    input  wire        rst_n,
    input  wire        cs_guard_rst_n, // global REF reset; guard survives media abort

    // ---- 控制 ----
    input  wire        run,          // 电平：允许开跑（板级顶层给；上升沿触发一次完整流程）
    input  wire        btn_next,     // 脉冲：下一幅
    input  wire        btn_auto,     // 电平：自动连播
    input  wire        restart,      // 脉冲：S_ERROR 下重来一遍（可带电插卡后重试）

    // ---- SD 卡 SPI 引脚 ----
    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso,

    // ---- 像素流出口（→ 板级顶层 sink 里的**官方** a_pixel_fifo 写侧，50M→125M）----
    //   ★ 用官方 IP 跨域：双时钟 + 自带 32→16 位宽转换（本模块把 2 个像素打包成
    //     一个 32 位字，低半字先），不自己写异步 FIFO ✓
    //   ★ 这三个信号**都在本 50 MHz 域**（FIFO 写侧），不需要再同步 ✓
    output wire [31:0] px_word,       // 2 像素打包（低半字 = 先到的像素）
    output wire        px_word_valid,
    input  wire        px_word_ready, // ← FIFO 的 wr_ready
    output reg         frame_active,  // 本帧正在产出像素（电平，随帧起落）
    output reg         top_down_o,    // 本帧行序（帧内稳定，随 frame_active 打包）
    output wire [1:0]  slot_o,        // 本帧目标槽（帧内稳定）

    // ---- 与 mem 侧帧控制器握手（跨界只走这 3 个慢信号）----
    input  wire        mem_ready,     // mem 侧空闲且 FIFO 已排空 ⇒ 可以开始一帧
    input  wire        frame_done,    // toggle：mem 侧已完成（桥写完 + 换帧走完）
    input  wire        last_frame_ok, // 电平：刚完成那帧是否成功（随 frame_done 采）

    // ---- 状态 / 遥测（稳定电平，供 UART 报告与 LED）----
    output reg  [3:0]  state_o,
    output reg  [3:0]  fail_stage,   // 出错发生在哪个阶段（0=none）
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    // ★ 2026-10-06 新增诊断（SD 初始化不稳定时定位用）：
    //   init_r1  = SD 初始化里最近一次收到的 R1 原始字节（`FF`=卡没应答 / `05`=非法命令…）
    //   init_seq = 挂在哪条命令：0=CMD0, 1=CMD8, 2=CMD55, 3=ACMD41
    output wire [7:0]  init_r1,
    output wire [2:0]  init_seq,
    output reg         sd_ready,     // 1 = SD 初始化完成（同时用作 SPI 总线归属）
    output reg         card_usable,  // 1 = 挂载+索引完成且至少 1 幅
    output wire [3:0]  file_cnt,     // 由 file_index 直接驱动（wire，不能是 reg）
    output reg  [1:0]  cur_file,
    output reg  [31:0] cur_file_size,
    output reg  [31:0] cur_bytes_rd,
    output reg  [18:0] cur_px_written,
    output reg         last_frame_ok_o,   // 采样到的 mem 侧上一帧是否成功
    output reg  [15:0] frame_cnt,
    output reg [3:0] cache_valid,
    output reg [2:0] cache_count,
    output reg [63:0] cache_keys,
    output reg [15:0] rejected_files,
    // Resident images own SD during preload. After four approvals the WAV
    // source in THIS reference-clock domain owns this shared sector reader.
    // Addresses are volume-relative; this module adds vol_base exactly once.
    input wire[444:0] external_core_cmd,output wire[836:0] external_core_rsp,output wire external_service_ready,
    input wire ext_rd_en,input wire[31:0] ext_rd_addr,input wire[15:0] ext_rd_len,
    output wire ext_rd_ready,output wire[7:0] ext_data,output wire ext_data_valid,
    input wire ext_data_ready,output wire ext_data_last,ext_rd_done,ext_timeout,ext_crc_error,
    output wire[7:0] ext_err_code,ext_err_detail,
    output wire[7:0] fs_sec_per_clus,
    output wire[31:0] fs_fat_start_lba,fs_data_start_lba,fs_root_dir_lba,fs_root_clus,fs_total_clus,
    output reg[31:0] progress_count,
    output reg[15:0] last_reject_error,last_reject_key
);

    // ========================================================================
    // 状态定义
    // ========================================================================
    localparam [3:0] S_IDLE   = 4'd0,
                     S_INIT   = 4'd1,
                     S_MBR    = 4'd2,
                     S_BOOT   = 4'd3,
                     S_SCAN   = 4'd4,
                     S_INDEX  = 4'd5,
                     S_PICK   = 4'd6,      // 让 file_index 的 sel_* 落定
                     S_READY  = 4'd7,
                     S_STREAM = 4'd8,
                     S_SWAP   = 4'd9,
                     S_ERROR  = 4'd10,
                     S_REJECT = 4'd12, // drain one in-flight sector, forbid new requests
                     S_CLEAN = 4'd13,  // reset only the file pipeline after bus quiescence
                     S_INITR  = 4'd11;     // ★ SD 初始化失败后**重试**：停一拍再回 S_INIT

    // 本模块细分码（对外主码沿用项目错误码表；阶段与超时单列）
    localparam [7:0] MY_TO_INIT   = 8'hE1,
                     MY_TO_MOUNT  = 8'hE2,
                     MY_TO_STREAM = 8'hE3,
                     MY_TO_SWAP   = 8'hE4,
                     MY_NO_FILE   = 8'hE5;

    localparam [3:0] ST_INIT = 4'd1, ST_MBR = 4'd2, ST_BOOT = 4'd3,
                     ST_SCAN = 4'd4, ST_IDX = 4'd5, ST_PICK = 4'd6,
                     ST_STREAM = 4'd7, ST_SWAP = 4'd8;

    // ========================================================================
    // 所有网线先声明（严禁在 always 里用到“声明在后面”的 wire：Verilog 会建
    // 隐式 1 bit 网线，整链静默卡死且不报错 —— 既有踩坑记录）
    // ========================================================================
    // sd_initializer
    wire        sdhc, init_done, init_error;
    wire [7:0]  init_ec, init_ed;
    wire        init_cs_n, init_txv;
    wire [7:0]  init_txd;
    wire [15:0] init_div;
    reg         init_start;

    // mbr_parser
    reg         mp_start;
    wire        mp_done, mp_has;
    wire [7:0]  mp_ec, mp_ed;
    wire [31:0] mp_vol_base, mp_part_secs;
    wire [31:0] mp_rd_addr; wire [15:0] mp_rd_len; wire mp_rd_en, mp_data_ready;

    // fat32_boot_parser
    reg         bp_start;
    wire        bp_done, bp_err;
    wire [7:0]  bp_ec, bp_ed;
    wire [15:0] bp_bps;
    wire [7:0]  bp_spc, bp_nfat;
    wire [31:0] bp_fat_lba, bp_root_clus, bp_root_lba, bp_data_lba, bp_tot_sec, bp_tot_clus;
    wire [31:0] bp_rd_addr; wire [15:0] bp_rd_len; wire bp_rd_en, bp_data_ready;

    // fat32_directory_scanner
    reg         scan_en;
    wire        scan_done, dir_bad;
    wire [7:0]  dn_ec, dn_ed;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid, ent_ready;
    wire [31:0] dn_rd_addr; wire [15:0] dn_rd_len; wire dn_rd_en, dn_data_ready;
    wire [31:0] dn_wk_cur, dn_wk_next;
    wire        dn_wk_start, dn_wk_rst, dn_wk_busy, dn_wk_done, dn_wk_eoc, dn_wk_err;
    wire [7:0]  dn_wk_ec, dn_wk_ed;
    wire [31:0] wd_rd_addr; wire [15:0] wd_rd_len; wire wd_rd_en, wd_data_ready;

    // file_index
    reg         idx_clear, idx_commit;
    wire        idx_done;
    wire [3:0]  file_valid;
    wire        insufficient;
    wire [7:0]  idx_ec, idx_ed;
    wire [31:0] sel_first_clus, sel_size;
    wire        sel_valid;
    wire [31:0] sel_wav_clus, sel_wav_size;
    wire        sel_wav_valid;
    wire [15:0] bmp_seen, wav_seen;

    // file_streamer
    reg         fst_start;
    wire        fst_busy, fst_done, fst_error;
    wire [7:0]  fst_ec, fst_ed;
    wire [31:0] fst_bytes;
    wire [7:0]  fst_data;
    wire        fst_valid, fst_sof, fst_eof;
    wire [31:0] fst_rd_addr; wire [15:0] fst_rd_len; wire fst_rd_en, fst_data_ready;
    wire [31:0] fst_wk_cur, fst_wk_next;
    wire        fst_wk_start, fst_wk_rst, fst_wk_busy, fst_wk_done, fst_wk_eoc, fst_wk_err;
    wire [7:0]  fst_wk_ec, fst_wk_ed;
    wire [31:0] wf_rd_addr; wire [15:0] wf_rd_len; wire wf_rd_en, wf_data_ready;

    // bmp_parser
    wire        bp_ready;
    wire        bmp_check_done, bmp_check_error;
    wire [7:0]  bmp_ec, bmp_ed;
    wire [15:0] bmp_width, bmp_height;
    wire        bmp_top_down;
    wire [7:0]  bmp_bpp;
    wire [31:0] bmp_compression, bmp_pixel_off, bmp_file_size_o;
    wire [7:0]  bpo_data;
    wire        bpo_valid, bpo_sof, bpo_eof, bpo_ready;

    // bmp_unpack
    wire [15:0] bpu_pixel;
    wire        bpu_valid, bpu_ready;
    wire [9:0]  bpu_x, bpu_y;
    wire        bpu_sof, bpu_eof, bpu_done, bpu_error;
    wire [7:0]  bpu_ec, bpu_ed;

    // ---- 2 像素打包成 32 位字（官方 a_pixel_fifo 写侧 32 位、读侧 16 位）----
    //   ★ 官方 FIFO 是"低半字先"⇒ 低半 = 先到的像素 ✓
    //   ★ px_word/px_word_valid 直接是端口；px_word_ready 也来自端口（FIFO wr_ready）
    reg  [15:0] lo_px;
    reg         have_lo;
    reg  [31:0] hold_word;
    reg         hold_valid;
    assign px_word       = hold_word;
    assign px_word_valid = hold_valid;

    // sd_sector_reader + spi_master（共享一条 SD 总线）
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to, rd_crc;
    wire [7:0]  rd_ec, rd_ed;
    wire        rd_cs_n, rd_txv;
    wire [7:0]  rd_txd;
    wire [15:0] rd_div;
    wire        spi_busy, spi_rxv, spi_tx_ready;
    wire        spi_engine_ready, spi_cs_ready;
    assign spi_tx_ready=spi_engine_ready && spi_cs_ready;
    wire [7:0]  spi_rxd;

    // ---- 控制侧寄存器（必须声明在**例化之前**：file_index 要用 pick_slot）----
    reg [15:0] cursor_key;
    wire [15:0] selected_key;
    // The file pipeline is reset only while the card/reader are already idle.
    // SPI initialization, mounted geometry and accepted caches survive.
    wire file_rst_n = rst_n && !(RESIDENT_CACHE && state_o==S_CLEAN);
    reg  [1:0]  out_slot;       // 本帧目标槽（0/1 交替）
    reg  [1:0]  pick_slot;      // 给 file_index 的查找槽（= 目标文件号）
    reg  [31:0] pick_to;        // S_PICK 等 sel_* 落定
    // 最后一个合法槽号：file_index 最多 4 槽（sel_slot 2 bit），file_cnt 可能 =4
    wire [1:0]  last_slot = (file_cnt == 4'd4) ? 2'd3 : (file_cnt[1:0] - 2'd1);

    // ========================================================================
    // 读总线仲裁：按状态选前段哪个 master 拥有 reader
    //   （形态照抄 top_stage6_fat32_mount.v 的既有做法）
    // ========================================================================
    wire scan_wk = (state_o == S_SCAN)   && dn_wk_busy;
    wire strm_wk = (state_o == S_STREAM) && fst_wk_busy;
    wire ext_owner=RESIDENT_CACHE && state_o==S_READY && cache_count==4;
    assign ext_rd_ready=ext_owner && rd_ready;
    assign ext_data=rd_data;
    assign ext_data_valid=ext_owner && rd_data_valid;
    assign ext_data_last=ext_owner && rd_data_last;
    assign ext_rd_done=ext_owner && rd_done;
    assign ext_timeout=ext_owner && rd_to;
    assign ext_crc_error=ext_owner && rd_crc;
    assign ext_err_code=rd_ec,ext_err_detail=rd_ed;
    assign fs_sec_per_clus=bp_spc,fs_fat_start_lba=bp_fat_lba,fs_data_start_lba=bp_data_lba;
    assign fs_root_dir_lba=bp_root_lba,fs_root_clus=bp_root_clus,fs_total_clus=bp_tot_clus;

    wire        bus_rd_en   = (state_o == S_MBR)  ? mp_rd_en :
                              (state_o == S_BOOT) ? bp_rd_en :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_en : dn_rd_en) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_en : fst_rd_en) :
                              ext_owner ? ext_rd_en : 1'b0;
    wire [31:0] bus_rd_addr = (state_o == S_MBR)  ? mp_rd_addr :
                              (state_o == S_BOOT) ? bp_rd_addr :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_addr : dn_rd_addr) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_addr : fst_rd_addr) :
                              ext_owner ? ext_rd_addr : 32'd0;
    wire [15:0] bus_rd_len  = (state_o == S_MBR)  ? mp_rd_len :
                              (state_o == S_BOOT) ? bp_rd_len :
                              (state_o == S_SCAN) ? (scan_wk ? wd_rd_len : dn_rd_len) :
                              (state_o == S_STREAM) ? (strm_wk ? wf_rd_len : fst_rd_len) :
                              ext_owner ? ext_rd_len : 16'd0;
    wire        bus_data_ready = (state_o == S_MBR)  ? mp_data_ready :
                                 (state_o == S_BOOT) ? bp_data_ready :
                                 (state_o == S_SCAN) ? (scan_wk ? wd_data_ready : dn_data_ready) :
                                 (state_o == S_STREAM) ? (strm_wk ? wf_data_ready : fst_data_ready) :
                                 ext_owner ? ext_data_ready : 1'b1;
    // Real card payload consumption (directory/FAT/media alike), not a local
    // free-running heartbeat. Transfer the whole counter through a mailbox.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)progress_count<=0;
        else if(rd_data_valid && bus_data_ready)progress_count<=progress_count+1'b1;
    end

    // ★★ 卷基址只加一次（interface_spec §3.2.1）：mbr_parser 读卡 0 号扇区时
    //    自身相对地址 = 0，且那时 mp_vol_base 仍为 0 ⇒ 恰好落在卡的 0 号扇区。
    wire [31:0] rd_addr_to_reader = bus_rd_addr + mp_vol_base;

    // ========================================================================
    // 前段例化
    // ========================================================================
    sd_initializer #(
        .CLK_DIV_INIT(CLK_DIV_INIT)
    ) u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start),
        .sdhc(sdhc), .init_done(init_done), .init_error(init_error),
        .err_code(init_ec), .err_detail(init_ed), .retry_cnt(), .dbg_state(),
        .dbg_r1(init_r1), .dbg_seq(init_seq),
        .spi_cs_n(init_cs_n), .spi_clk_div(init_div),
        .spi_tx_valid(init_txv), .spi_tx_data(init_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    mbr_parser u_mbr (
        .clk(clk), .rst_n(rst_n), .start(mp_start),
        .parse_done(mp_done), .err_code(mp_ec), .err_detail(mp_ed), .dbg_state(),
        .has_mbr(mp_has), .vol_base_lba(mp_vol_base), .part_secs(mp_part_secs),
        .sd_rd_addr(mp_rd_addr), .sd_rd_len(mp_rd_len), .sd_rd_en(mp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(mp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_boot_parser u_boot (
        .clk(clk), .rst_n(rst_n), .start(bp_start),
        .mount_done(bp_done), .mount_error(bp_err), .err_code(bp_ec), .err_detail(bp_ed),
        .dbg_state(),
        .bytes_per_sec(bp_bps), .sec_per_clus(bp_spc), .num_fats(bp_nfat),
        .fat_start_lba(bp_fat_lba), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .total_sec(bp_tot_sec), .total_clus(bp_tot_clus),
        .sd_rd_addr(bp_rd_addr), .sd_rd_len(bp_rd_len), .sd_rd_en(bp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(bp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );


    // Ownership changes invalidate every persistent done/status bit before use.
    reg service_owner_q,service_gap;
    always @(posedge clk or negedge rst_n)
      if(!rst_n)begin service_owner_q<=0;service_gap<=0;end
      else begin service_owner_q<=ext_owner;service_gap<=(service_owner_q==ext_owner);end
    wire service_ready_int=service_gap&&(service_owner_q==ext_owner)&&rst_n;
    wire[444:0] local_core_cmd,selected_core_cmd;
    wire[836:0] physical_core_rsp;
    assign external_service_ready=SHARED_SERVICE&&ext_owner&&service_ready_int;
    assign external_core_rsp=external_service_ready?physical_core_rsp:837'd0;
    // service_ready_int implies service_owner_q==ext_owner. During the
    // two-edge ownership gap the entire kernel is held in reset, so selecting
    // the registered owner preserves every observable transaction and removes
    // binary-state decode from the445-bit mux before the LBA DSP/add path.
    assign selected_core_cmd=service_owner_q?external_core_cmd:local_core_cmd;
assign local_core_cmd={file_rst_n,scan_en,ent_ready,1'b0,1'b1,fst_start,sel_first_clus,sel_size,bp_ready,265'd0,1'b0,32'd0,state_o==S_STREAM?fst_wk_rst:dn_wk_rst,state_o==S_STREAM?fst_wk_start:dn_wk_start,state_o==S_STREAM?fst_wk_cur:dn_wk_cur,({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_ready}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_data_valid}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_data_last}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_done}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_to}}),({((state_o==S_SCAN&&scan_wk)||(state_o==S_STREAM&&strm_wk)),(state_o==S_STREAM&&!strm_wk),(state_o==S_SCAN&&!scan_wk)}&{3{rd_crc}}),rd_data,rd_ec,rd_ed};
wire svc_d_scan_done;
wire svc_d_dir_bad;
wire [7:0] svc_d_err_code;
wire [7:0] svc_d_err_detail;
wire [3:0] svc_d_dbg_state;
wire [87:0] svc_d_ent_name;
wire [7:0] svc_d_ent_attr;
wire [31:0] svc_d_ent_first_clus;
wire [31:0] svc_d_ent_size;
wire [15:0] svc_d_ent_index;
wire svc_d_ent_valid;
wire [31:0] svc_d_sd_rd_addr;
wire [15:0] svc_d_sd_rd_len;
wire svc_d_sd_rd_en;
wire svc_d_sd_data_ready;
wire [31:0] svc_d_wk_cur_clus;
wire svc_d_wk_start;
wire svc_d_wk_rst_walk;
wire svc_f_busy;
wire svc_f_done;
wire svc_f_error;
wire [7:0] svc_f_err_code;
wire [7:0] svc_f_err_detail;
wire [31:0] svc_f_bytes_rd;
wire [3:0] svc_f_dbg_state;
wire [7:0] svc_f_data;
wire svc_f_valid;
wire svc_f_sof;
wire svc_f_eof;
wire svc_f_idle_between_sectors;
wire [264:0] svc_f_context_out;
wire [31:0] svc_f_sd_rd_addr;
wire [15:0] svc_f_sd_rd_len;
wire svc_f_sd_rd_en;
wire svc_f_sd_data_ready;
wire [31:0] svc_f_wk_cur_clus;
wire svc_f_wk_start;
wire svc_f_wk_rst_walk;
wire svc_w_busy;
wire svc_w_done;
wire [31:0] svc_w_next_clus;
wire svc_w_eoc;
wire svc_w_error;
wire [7:0] svc_w_err_code;
wire [7:0] svc_w_err_detail;
wire [31:0] svc_w_hop_cnt;
wire [3:0] svc_w_dbg_state;
wire [31:0] svc_w_sd_rd_addr;
wire [15:0] svc_w_sd_rd_len;
wire svc_w_sd_rd_en;
wire svc_w_sd_data_ready;
assign {svc_d_scan_done,svc_d_dir_bad,svc_d_err_code,svc_d_err_detail,svc_d_dbg_state,svc_d_ent_name,svc_d_ent_attr,svc_d_ent_first_clus,svc_d_ent_size,svc_d_ent_index,svc_d_ent_valid,svc_d_sd_rd_addr,svc_d_sd_rd_len,svc_d_sd_rd_en,svc_d_sd_data_ready,svc_d_wk_cur_clus,svc_d_wk_start,svc_d_wk_rst_walk,svc_f_busy,svc_f_done,svc_f_error,svc_f_err_code,svc_f_err_detail,svc_f_bytes_rd,svc_f_dbg_state,svc_f_data,svc_f_valid,svc_f_sof,svc_f_eof,svc_f_idle_between_sectors,svc_f_context_out,svc_f_sd_rd_addr,svc_f_sd_rd_len,svc_f_sd_rd_en,svc_f_sd_data_ready,svc_f_wk_cur_clus,svc_f_wk_start,svc_f_wk_rst_walk,svc_w_busy,svc_w_done,svc_w_next_clus,svc_w_eoc,svc_w_error,svc_w_err_code,svc_w_err_detail,svc_w_hop_cnt,svc_w_dbg_state,svc_w_sd_rd_addr,svc_w_sd_rd_len,svc_w_sd_rd_en,svc_w_sd_data_ready}=physical_core_rsp;
generate if(SHARED_SERVICE)begin:shared_service
      v3_shared_fs_service service(.clk(clk),.rst_n(service_ready_int),.sec_per_clus(bp_spc),
       .fat_start_lba(bp_fat_lba),.data_start_lba(bp_data_lba),.root_dir_lba(bp_root_lba),
       .root_clus(bp_root_clus),.total_clus(bp_tot_clus),.core_cmd(selected_core_cmd),.core_rsp(physical_core_rsp));
    end else begin:no_shared_service
      assign physical_core_rsp=837'd0;
    end endgenerate

wire legacy_u_scan_scan_done;
assign scan_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_scan_done:1'd0):legacy_u_scan_scan_done;
wire legacy_u_scan_dir_bad;
assign dir_bad=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_dir_bad:1'd0):legacy_u_scan_dir_bad;
wire [7:0] legacy_u_scan_err_code;
assign dn_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_err_code:8'd0):legacy_u_scan_err_code;
wire [7:0] legacy_u_scan_err_detail;
assign dn_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_err_detail:8'd0):legacy_u_scan_err_detail;
wire [87:0] legacy_u_scan_ent_name;
assign ent_name=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_name:88'd0):legacy_u_scan_ent_name;
wire [7:0] legacy_u_scan_ent_attr;
assign ent_attr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_attr:8'd0):legacy_u_scan_ent_attr;
wire [31:0] legacy_u_scan_ent_first_clus;
assign ent_first_clus=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_first_clus:32'd0):legacy_u_scan_ent_first_clus;
wire [31:0] legacy_u_scan_ent_size;
assign ent_size=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_size:32'd0):legacy_u_scan_ent_size;
wire [15:0] legacy_u_scan_ent_index;
assign ent_index=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_index:16'd0):legacy_u_scan_ent_index;
wire legacy_u_scan_ent_valid;
assign ent_valid=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_ent_valid:1'd0):legacy_u_scan_ent_valid;
wire [31:0] legacy_u_scan_sd_rd_addr;
assign dn_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_addr:32'd0):legacy_u_scan_sd_rd_addr;
wire [15:0] legacy_u_scan_sd_rd_len;
assign dn_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_len:16'd0):legacy_u_scan_sd_rd_len;
wire legacy_u_scan_sd_rd_en;
assign dn_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_rd_en:1'd0):legacy_u_scan_sd_rd_en;
wire legacy_u_scan_sd_data_ready;
assign dn_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_sd_data_ready:1'd0):legacy_u_scan_sd_data_ready;
wire [31:0] legacy_u_scan_wk_cur_clus;
assign dn_wk_cur=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_cur_clus:32'd0):legacy_u_scan_wk_cur_clus;
wire legacy_u_scan_wk_start;
assign dn_wk_start=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_start:1'd0):legacy_u_scan_wk_start;
wire legacy_u_scan_wk_rst_walk;
assign dn_wk_rst=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_d_wk_rst_walk:1'd0):legacy_u_scan_wk_rst_walk;
fat32_directory_scanner u_scan (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:rst_n), .scan_en(scan_en),
        .scan_done(legacy_u_scan_scan_done), .dir_bad(legacy_u_scan_dir_bad), .err_code(legacy_u_scan_err_code), .err_detail(legacy_u_scan_err_detail),
        .dbg_state(),
        .sec_per_clus(bp_spc), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .ent_name(legacy_u_scan_ent_name), .ent_attr(legacy_u_scan_ent_attr), .ent_first_clus(legacy_u_scan_ent_first_clus),
        .ent_size(legacy_u_scan_ent_size), .ent_index(legacy_u_scan_ent_index), .ent_valid(legacy_u_scan_ent_valid), .ent_ready(ent_ready),
        .sd_rd_addr(legacy_u_scan_sd_rd_addr), .sd_rd_len(legacy_u_scan_sd_rd_len), .sd_rd_en(legacy_u_scan_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_scan_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed),
        .wk_cur_clus(legacy_u_scan_wk_cur_clus), .wk_start(legacy_u_scan_wk_start), .wk_rst_walk(legacy_u_scan_wk_rst_walk),
        .wk_busy(dn_wk_busy), .wk_done(dn_wk_done), .wk_next_clus(dn_wk_next),
        .wk_eoc(dn_wk_eoc), .wk_error(dn_wk_err), .wk_err_code(dn_wk_ec), .wk_err_detail(dn_wk_ed)
    );

    wire legacy_u_wk_dir_busy;
assign dn_wk_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_busy:1'd0):legacy_u_wk_dir_busy;
wire legacy_u_wk_dir_done;
assign dn_wk_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_done:1'd0):legacy_u_wk_dir_done;
wire [31:0] legacy_u_wk_dir_next_clus;
assign dn_wk_next=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_next_clus:32'd0):legacy_u_wk_dir_next_clus;
wire legacy_u_wk_dir_eoc;
assign dn_wk_eoc=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_eoc:1'd0):legacy_u_wk_dir_eoc;
wire legacy_u_wk_dir_error;
assign dn_wk_err=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_error:1'd0):legacy_u_wk_dir_error;
wire [7:0] legacy_u_wk_dir_err_code;
assign dn_wk_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_code:8'd0):legacy_u_wk_dir_err_code;
wire [7:0] legacy_u_wk_dir_err_detail;
assign dn_wk_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_detail:8'd0):legacy_u_wk_dir_err_detail;
wire [31:0] legacy_u_wk_dir_sd_rd_addr;
assign wd_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_addr:32'd0):legacy_u_wk_dir_sd_rd_addr;
wire [15:0] legacy_u_wk_dir_sd_rd_len;
assign wd_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_len:16'd0):legacy_u_wk_dir_sd_rd_len;
wire legacy_u_wk_dir_sd_rd_en;
assign wd_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_en:1'd0):legacy_u_wk_dir_sd_rd_en;
wire legacy_u_wk_dir_sd_data_ready;
assign wd_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_data_ready:1'd0):legacy_u_wk_dir_sd_data_ready;
fat32_cluster_walker u_wk_dir (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:rst_n), .rst_walk(dn_wk_rst), .start(dn_wk_start),
        .cur_clus(dn_wk_cur), .busy(legacy_u_wk_dir_busy), .done(legacy_u_wk_dir_done), .next_clus(legacy_u_wk_dir_next_clus),
        .eoc(legacy_u_wk_dir_eoc), .error(legacy_u_wk_dir_error), .err_code(legacy_u_wk_dir_err_code), .err_detail(legacy_u_wk_dir_err_detail),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(legacy_u_wk_dir_sd_rd_addr), .sd_rd_len(legacy_u_wk_dir_sd_rd_len), .sd_rd_en(legacy_u_wk_dir_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_wk_dir_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ---- 扫描器 → 索引：插一拍切断长组合路径 ----
    // ★ 实测（board_verify base 模式）最差路径是
    //     u_scan/ent_name_reg[*] → u_idx/mux42 / s_size.ce，15.03ns @8ns 预算、
    //     Logic Level 11 ⇒ 88 位目录名解码＋4 槽索引选择很长。这里先把**边界**
    //     打一拍（file_index 的 ent_ready 恒 1、不反压，所以加一拍不改握手语义）。
    //   ★ 但要注意：这只切掉“边界”那一段；如果 file_index 内部解码本身仍超预算，
    //     还需在模块内部继续切 —— 见本文件头“时序”那一节。
    reg  [87:0] ent_name_q;
    reg  [7:0]  ent_attr_q;
    reg  [31:0] ent_first_clus_q, ent_size_q;
    reg  [15:0] ent_index_q;
    reg         ent_valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ent_name_q <= 88'd0; ent_attr_q <= 8'd0; ent_first_clus_q <= 32'd0;
            ent_size_q <= 32'd0; ent_index_q <= 16'd0; ent_valid_q <= 1'b0;
        end else begin
            ent_name_q       <= ent_name;
            ent_attr_q       <= ent_attr;
            ent_first_clus_q <= ent_first_clus;
            ent_size_q       <= ent_size;
            ent_index_q      <= ent_index;
            ent_valid_q      <= ent_valid;
        end
    end

    file_index #(.CURSOR_MODE(RESIDENT_CACHE),.CANDIDATE_SLOTS(RESIDENT_CACHE?1:4)) u_idx (
        .clk(clk), .rst_n(rst_n),
        .ent_name(ent_name_q), .ent_attr(ent_attr_q), .ent_first_clus(ent_first_clus_q),
        .ent_size(ent_size_q), .ent_index(ent_index_q),
        .ent_valid(ent_valid_q), .ent_ready(ent_ready),
        .cursor_key(cursor_key), .sel_key(selected_key),
        .idx_clear(idx_clear), .idx_commit(idx_commit), .idx_done(idx_done),
        .file_cnt(file_cnt), .file_valid(file_valid), .insufficient(insufficient),
        .err_code(idx_ec), .err_detail(idx_ed),
        .sel_slot(RESIDENT_CACHE?2'd0:pick_slot), .sel_first_clus(sel_first_clus), .sel_size(sel_size),
        .sel_valid(sel_valid),
        .sel_wav_first_clus(sel_wav_clus), .sel_wav_size(sel_wav_size),
        .sel_wav_valid(sel_wav_valid),
        .bmp_seen(bmp_seen), .wav_seen(wav_seen)
    );

    wire legacy_u_fst_busy;
assign fst_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_busy:1'd0):legacy_u_fst_busy;
wire legacy_u_fst_done;
assign fst_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_done:1'd0):legacy_u_fst_done;
wire legacy_u_fst_error;
assign fst_error=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_error:1'd0):legacy_u_fst_error;
wire [7:0] legacy_u_fst_err_code;
assign fst_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_err_code:8'd0):legacy_u_fst_err_code;
wire [7:0] legacy_u_fst_err_detail;
assign fst_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_err_detail:8'd0):legacy_u_fst_err_detail;
wire [31:0] legacy_u_fst_bytes_rd;
assign fst_bytes=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_bytes_rd:32'd0):legacy_u_fst_bytes_rd;
wire [7:0] legacy_u_fst_data;
assign fst_data=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_data:8'd0):legacy_u_fst_data;
wire legacy_u_fst_valid;
assign fst_valid=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_valid:1'd0):legacy_u_fst_valid;
wire legacy_u_fst_sof;
assign fst_sof=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sof:1'd0):legacy_u_fst_sof;
wire legacy_u_fst_eof;
assign fst_eof=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_eof:1'd0):legacy_u_fst_eof;
wire [31:0] legacy_u_fst_sd_rd_addr;
assign fst_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_addr:32'd0):legacy_u_fst_sd_rd_addr;
wire [15:0] legacy_u_fst_sd_rd_len;
assign fst_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_len:16'd0):legacy_u_fst_sd_rd_len;
wire legacy_u_fst_sd_rd_en;
assign fst_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_rd_en:1'd0):legacy_u_fst_sd_rd_en;
wire legacy_u_fst_sd_data_ready;
assign fst_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_sd_data_ready:1'd0):legacy_u_fst_sd_data_ready;
wire [31:0] legacy_u_fst_wk_cur_clus;
assign fst_wk_cur=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_cur_clus:32'd0):legacy_u_fst_wk_cur_clus;
wire legacy_u_fst_wk_start;
assign fst_wk_start=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_start:1'd0):legacy_u_fst_wk_start;
wire legacy_u_fst_wk_rst_walk;
assign fst_wk_rst=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_f_wk_rst_walk:1'd0):legacy_u_fst_wk_rst_walk;
file_streamer u_fst (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:file_rst_n),
        .start(fst_start), .first_clus(sel_first_clus), .file_size(sel_size),
        .busy(legacy_u_fst_busy), .done(legacy_u_fst_done), .error(legacy_u_fst_error),
        .err_code(legacy_u_fst_err_code), .err_detail(legacy_u_fst_err_detail),
        .bytes_rd(legacy_u_fst_bytes_rd), .dbg_state(),
        .data(legacy_u_fst_data), .valid(legacy_u_fst_valid), .ready(bp_ready), .sof(legacy_u_fst_sof), .eof(legacy_u_fst_eof),
        .sec_per_clus(bp_spc), .fat_start_lba(bp_fat_lba),
        .data_start_lba(bp_data_lba), .total_clus(bp_tot_clus),
        .wk_cur_clus(legacy_u_fst_wk_cur_clus), .wk_start(legacy_u_fst_wk_start), .wk_rst_walk(legacy_u_fst_wk_rst_walk),
        .wk_busy(fst_wk_busy), .wk_done(fst_wk_done), .wk_next_clus(fst_wk_next),
        .wk_eoc(fst_wk_eoc), .wk_error(fst_wk_err),
        .wk_err_code(fst_wk_ec), .wk_err_detail(fst_wk_ed),
        .sd_rd_addr(legacy_u_fst_sd_rd_addr), .sd_rd_len(legacy_u_fst_sd_rd_len), .sd_rd_en(legacy_u_fst_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_fst_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    wire legacy_u_wk_fst_busy;
assign fst_wk_busy=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_busy:1'd0):legacy_u_wk_fst_busy;
wire legacy_u_wk_fst_done;
assign fst_wk_done=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_done:1'd0):legacy_u_wk_fst_done;
wire [31:0] legacy_u_wk_fst_next_clus;
assign fst_wk_next=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_next_clus:32'd0):legacy_u_wk_fst_next_clus;
wire legacy_u_wk_fst_eoc;
assign fst_wk_eoc=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_eoc:1'd0):legacy_u_wk_fst_eoc;
wire legacy_u_wk_fst_error;
assign fst_wk_err=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_error:1'd0):legacy_u_wk_fst_error;
wire [7:0] legacy_u_wk_fst_err_code;
assign fst_wk_ec=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_code:8'd0):legacy_u_wk_fst_err_code;
wire [7:0] legacy_u_wk_fst_err_detail;
assign fst_wk_ed=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_err_detail:8'd0):legacy_u_wk_fst_err_detail;
wire [31:0] legacy_u_wk_fst_sd_rd_addr;
assign wf_rd_addr=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_addr:32'd0):legacy_u_wk_fst_sd_rd_addr;
wire [15:0] legacy_u_wk_fst_sd_rd_len;
assign wf_rd_len=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_len:16'd0):legacy_u_wk_fst_sd_rd_len;
wire legacy_u_wk_fst_sd_rd_en;
assign wf_rd_en=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_rd_en:1'd0):legacy_u_wk_fst_sd_rd_en;
wire legacy_u_wk_fst_sd_data_ready;
assign wf_data_ready=SHARED_SERVICE?(!ext_owner&&service_ready_int?svc_w_sd_data_ready:1'd0):legacy_u_wk_fst_sd_data_ready;
fat32_cluster_walker u_wk_fst (
        .clk(clk), .rst_n(SHARED_SERVICE?1'b0:file_rst_n), .rst_walk(fst_wk_rst), .start(fst_wk_start),
        .cur_clus(fst_wk_cur), .busy(legacy_u_wk_fst_busy), .done(legacy_u_wk_fst_done), .next_clus(legacy_u_wk_fst_next_clus),
        .eoc(legacy_u_wk_fst_eoc), .error(legacy_u_wk_fst_error), .err_code(legacy_u_wk_fst_err_code), .err_detail(legacy_u_wk_fst_err_detail),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(legacy_u_wk_fst_sd_rd_addr), .sd_rd_len(legacy_u_wk_fst_sd_rd_len), .sd_rd_en(legacy_u_wk_fst_sd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(legacy_u_wk_fst_sd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ---- 媒体链：字节流 → 像素 → 行序重映射 → 逐 word 写请求 ----
    bmp_parser #(.VARIABLE_SIZE(RESIDENT_CACHE)) u_bmp (
        .clk(clk), .rst_n(file_rst_n),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .eof(fst_eof),
        .file_size(sel_size),
        .check_done(bmp_check_done), .check_error(bmp_check_error),
        .err_code(bmp_ec), .err_detail(bmp_ed),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down),
        .bpp(bmp_bpp), .compression(bmp_compression), .pixel_off(bmp_pixel_off),
        .file_size_o(bmp_file_size_o), .dbg_state(),
        .out_data(bpo_data), .out_valid(bpo_valid), .out_ready(bpo_ready),
        .out_sof(bpo_sof), .out_eof(bpo_eof)
    );

    // 打包器：2 个像素 → 1 个 32 位字（低半字先），带 1 字保持位
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lo_px <= 16'd0; have_lo <= 1'b0; hold_word <= 32'd0; hold_valid <= 1'b0;
        end else if (RESIDENT_CACHE && state_o==S_CLEAN) begin
            lo_px<=0;have_lo<=0;hold_word<=0;hold_valid<=0;
        end else begin
            if (hold_valid && px_word_ready) hold_valid <= 1'b0;   // 先出队
            if (bpu_valid && bpu_ready) begin
                if (!have_lo) begin
                    lo_px   <= bpu_pixel;
                    have_lo <= 1'b1;
                end else begin
                    hold_word  <= {bpu_pixel, lo_px};             // 高=后到，低=先到
                    hold_valid <= 1'b1;
                    have_lo    <= 1'b0;
                end
            end
        end
    end
    // 保持位空着才收新像素（同一拍出队+装新字不冲突：后者覆盖前者 ✓）
    assign bpu_ready = !hold_valid || px_word_ready;

    generate if(RESIDENT_CACHE)begin:normalized_bmp
    v3_bmp_normalizer u_unpack (
        .clk(clk),.rst_n(file_rst_n),.din(bpo_data),.din_valid(bpo_valid),.din_ready(bpo_ready),.din_sof(bpo_sof),.din_eof(bpo_eof),
        .width(bmp_width),.height(bmp_height),.top_down(bmp_top_down),
        .pixel(bpu_pixel),.pixel_valid(bpu_valid),.pixel_ready(bpu_ready),.x(bpu_x),.y(bpu_y),.img_sof(bpu_sof),.img_eof(bpu_eof),
        .done(bpu_done),.error(bpu_error),.err_code(bpu_ec),.err_detail(bpu_ed),.dbg_state());
    end else begin:legacy_bmp
    bmp_unpack u_unpack (
        .clk(clk), .rst_n(file_rst_n),
        .din(bpo_data), .din_valid(bpo_valid), .din_ready(bpo_ready),
        .din_sof(bpo_sof), .din_eof(bpo_eof),
        // bmp_parser rejects every wrong width/height before bpo_valid rises.
        // Expose the validated V3 geometry to synthesis so its generic unpack
        // multipliers disappear; the legacy path keeps the original inputs.
        .width(RESIDENT_CACHE ? 16'd640 : bmp_width),
        .height(RESIDENT_CACHE ? (bmp_top_down ? -16'sd480 : 16'd480) : bmp_height),
        .top_down(bmp_top_down),
        .pixel_off(bmp_pixel_off),
        .pixel(bpu_pixel), .pixel_valid(bpu_valid), .pixel_ready(bpu_ready),
        .x(bpu_x), .y(bpu_y), .img_sof(bpu_sof), .img_eof(bpu_eof),
        .done(bpu_done), .error(bpu_error), .err_code(bpu_ec), .err_detail(bpu_ed),
        .dbg_state()
    );
    end endgenerate

    assign slot_o = out_slot;      // 帧内稳定，随 frame_active 打包给 mem 侧

    generate if(RESIDENT_CACHE)begin:checked_reader
    sd_checked_sector_reader #(
        .CLK_DIV_FAST(CLK_DIV_FAST)
    ) u_rd (
        .clk(clk), .rst_n(file_rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len),
        .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_div),
        .spi_tx_valid(rd_txv), .spi_tx_data(rd_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    end else begin:legacy_reader
    sd_sector_reader #(
        .CLK_DIV_FAST(CLK_DIV_FAST)
    ) u_rd (
        .clk(clk), .rst_n(file_rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len),
        .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_div),
        .spi_tx_valid(rd_txv), .spi_tx_data(rd_txd),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rxd), .spi_rx_valid(spi_rxv)
    );

    end endgenerate

    // ★ SD 总线归属用**自己的** sd_ready，不用 init_done：init_done 是电平，
    //   在 S_ERROR → restart 重跑时它可能还高高挂着，那样会把 SPI 错划给 reader
    //   而让重新初始化永远跑不完 ✗。
    wire        spi_use_reader = sd_ready;
    wire        spi_txv  = spi_use_reader ? rd_txv  : init_txv;
    wire [7:0]  spi_txd  = spi_use_reader ? rd_txd  : init_txd;
    wire [15:0] spi_div  = spi_use_reader ? rd_div  : init_div;
    wire raw_cs_n=init_cs_n & rd_cs_n;
    generate if(GUARDED_CS)begin:guarded_cs
      v3_spi_cs_guard guard(.ref_clk(clk),.ref_rst_n(cs_guard_rst_n),
        .raw_cs_n(raw_cs_n),.raw_sclk(sd_dclk),.cs_n(sd_ncs),.cs_ready(spi_cs_ready));
    end else begin:direct_cs
      assign sd_ncs=raw_cs_n;assign spi_cs_ready=1'b1;
    end endgenerate

    spi_master #(
        .CLK_FREQ(CLK_HZ),.MID_REF_SAMPLE(MID_REF_SAMPLE)
    ) u_spi (
        .clk(clk), .rst_n(rst_n), .clk_div(spi_div), .cs_n(raw_cs_n),
        .tx_valid(spi_txv && spi_cs_ready), .tx_data(spi_txd), .tx_ready(spi_engine_ready),
        .rx_data(spi_rxd), .rx_valid(spi_rxv), .busy(spi_busy),
        .sclk(sd_dclk), .mosi(sd_mosi), .miso(sd_miso)
    );

    // ========================================================================
    // 控制状态机
    //   每个阶段的 start/scan_en/idx_* 都是**单拍脉冲**：用“进入状态第一拍打一次”
    // ========================================================================
    reg [3:0]  state_d;
    reg [31:0] to_cnt;
    reg [1:0]  scan_sub;        // S_SCAN 子步：0=idx_clear，1=scan_en，2=等 done
    reg        stream_kicked;   // S_STREAM 只踢一次 start
    reg [3:0]  init_try;        // ★ SD 初始化已重试次数（init_done 清零）
    reg [2:0]  init_arm;        // ★ 每次发 start 后的"沉降窗"：等 initializer 清掉上一次的 init_error
    reg        fd_d, fd_pending;// frame_done（toggle）边沿检测
    reg fst_done_d,file_done_seen;reg unpack_done_seen;
    always@(posedge clk or negedge rst_n)
      if(!rst_n)unpack_done_seen<=0;
      else if(state_o!=S_STREAM||!stream_kicked)unpack_done_seen<=0;
      else if(bpu_done&&!bpu_error)unpack_done_seen<=1;
    // Landing may precede the last CMD17 padding and CRC. Keep ownership
    // until BOTH completions arrive; never start an already busy streamer.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin fst_done_d<=0;file_done_seen<=0;end
        else begin
            fst_done_d<=fst_done;
            if(state_o!=S_STREAM || !stream_kicked)file_done_seen<=0;
            else if(fst_done && !fst_done_d)file_done_seen<=1;
        end
    end

    wire state_new = (state_o != state_d);

    // ========================================================================
    // ★ 125 MHz（mem 侧）→ 50 MHz（本域）的两级同步
    //   `mem_ready` 是电平、`frame_done` 是 toggle、`last_frame_ok` 是电平：
    //   三个都先过两级触发器再使用，绝不把 mem 域的信号直接进组合逻辑（CDC 纪律）
    //   ★ last_frame_ok 在 sink 里先于 frame_done 落定（S_WRITE 里就锁存，S_SWAP
    //     走完才翻 frame_done）⇒ 等本域看到 frame_done 变化时它已稳定多拍，
    //     两级同步是"打包数据"的标准处理 ✓
    // ========================================================================
    reg [1:0] mr_sync;      // mem_ready
    reg [1:0] fd_sync;      // frame_done（toggle）
    reg [1:0] lok_sync;     // last_frame_ok
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin mr_sync <= 2'd0; fd_sync <= 2'd0; lok_sync <= 2'd0; end
        else begin
            mr_sync  <= {mr_sync[0],  mem_ready};
            fd_sync  <= {fd_sync[0],  frame_done};
            lok_sync <= {lok_sync[0], last_frame_ok};
        end
    end
    wire mem_ready_s = mr_sync[1];

    // mem 侧完成事件的边沿检测（在同步后的 toggle 上做）
    //   ★ fd_pending 只在 **S_STREAM**（本帧在飞）里有意义：
    //     原来只在进 S_SWAP 时清，若 sink 在 player 空闲期（S_READY/S_PICK）翻了一次
    //     frame_done（例如 sink 走了 S_ERROR 兜底路径），fd_pending 会一直挂着，
    //     下一帧一开帧就**立刻跳 S_SWAP** ⇒ frame_cnt 虚增、那一帧没写 ✗
    //   ★ fd_d 仍然每拍无条件跟踪，保证比较基准不会过期
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin fd_d <= 1'b0; fd_pending <= 1'b0; end
        else begin
            fd_d <= fd_sync[1];
            if (state_o == S_STREAM && stream_kicked) begin
                if (fd_sync[1] != fd_d) fd_pending <= 1'b1;
            end else begin
                fd_pending <= 1'b0;          // 不在收帧状态 ⇒ 丢弃过期的完成事件
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_d        <= S_IDLE;
            state_o        <= S_IDLE;
            fail_stage     <= 4'd0;
            err_code       <= 8'h00;
            err_detail     <= 8'h00;
            sd_ready       <= 1'b0;
            card_usable    <= 1'b0;
            init_start     <= 1'b0;
            mp_start       <= 1'b0;
            bp_start       <= 1'b0;
            scan_en        <= 1'b0;
            idx_clear      <= 1'b0;
            idx_commit     <= 1'b0;
            fst_start      <= 1'b0;
            to_cnt         <= 32'd0;
            scan_sub       <= 2'd0;
            stream_kicked  <= 1'b0;
            init_try       <= 4'd0;
            init_arm       <= 3'd0;
            pick_slot      <= 2'd0;
            pick_to        <= 32'd0;
            cur_file       <= 2'd0;
            cur_file_size  <= 32'd0;
            cur_bytes_rd   <= 32'd0;
            cur_px_written <= 19'd0;
            last_frame_ok_o <= 1'b0;
            frame_cnt      <= 16'd0;
            cursor_key<=0;cache_valid<=0;cache_count<=0;cache_keys<=0;rejected_files<=0;
            last_reject_error<=0;last_reject_key<=0;
            out_slot       <= RESIDENT_CACHE ? 2'd0 : 2'd1;     // 先写 1 号槽（与 core 初始 active_next 错开）
            frame_active   <= 1'b0;
            top_down_o     <= 1'b0;
            // ★ fd_d / fd_pending 的复位在**上面那个边沿检测块**里做，这里绝不能再写：
            //   同一个 net 被两个 always 驱动，ModelSim 只是告警、TD 直接报
            //   `HDL-8007 net is constantly driven from multiple places` 并把它变成
            //   黑盒 ⇒ 综合直接失败 ✗（已踩过）
        end else begin
            // ---- 默认：所有单拍脉冲归零 ----
            init_start <= 1'b0;
            mp_start   <= 1'b0;
            bp_start   <= 1'b0;
            scan_en    <= 1'b0;
            idx_clear  <= 1'b0;
            idx_commit <= 1'b0;
            fst_start  <= 1'b0;

            state_d <= state_o;

            // 遥测快照
            cur_bytes_rd   <= fst_bytes;
            cur_px_written <= bpu_x;      // 遥测：当前行内列号（改用像素链自身信号）

            case (state_o)
                // ------------------------------------------------------------
                S_IDLE: begin
                    sd_ready    <= 1'b0;
                    card_usable <= 1'b0;
                    to_cnt      <= 32'd0;
                    init_try    <= 4'd0;       // ★ 每次重来都从"第 0 次重试"起算
                    if (run) state_o <= S_INIT;
                end

                // ------------------------------------------------------------
                // SD 初始化：失败**自动重试**（真卡在复位后偶发不应答时非常有效）
                //   ★ 重试路径 S_INIT → S_INITR → S_INIT：`state_new` 再次成立 ⇒ 再发一个
                //     干净的 start；initializer 在 M_ERR 收到 start 会走完整软复位
                //     （`do_soft_reset` 清 init_error/init_done/err_code/err_detail）。
                //   ★ `init_error` 是**电平**、要等它被清掉才能再判错 ⇒ 用 `init_arm`
                //     设 5 拍沉降窗，否则会在重发 start 的那几拍里把旧错误当成新错误，
                //     15 次重试会在 ~50 拍内被瞬间耗尽（这条时序陷阱必须留注释）。
                //   ★ `to_cnt` **跨重试累加**（不在此清零）⇒ 重试总时长仍受 INIT_TO_N 约束，
                //     不会挤掉顶层 `MODE_TO_N`(300 ms) 的回落窗口。
                S_INIT: begin
                    if (state_new) begin init_start <= 1'b1; init_arm <= 3'd0; end
                    else if (init_arm != 3'd7) init_arm <= init_arm + 3'd1;
                    to_cnt <= to_cnt + 32'd1;
                    if (init_arm >= 3'd4) begin      // 沉降窗过后才开始判错
                        if (init_done) begin
                            sd_ready <= 1'b1;
                            to_cnt   <= 32'd0;
                            init_try <= 4'd0;
                            state_o  <= S_MBR;
                        end else if (init_error) begin
                            if (init_try < INIT_RETRY_MAX) begin
                                init_try <= init_try + 4'd1;
                                state_o  <= S_INITR;
                            end else begin
                                fail_stage <= ST_INIT;
                                err_code   <= init_ec;     // 报**最后一次**失败的原因
                                err_detail <= init_ed;
                                state_o    <= S_ERROR;
                            end
                        end else if (to_cnt >= INIT_TO_N) begin
                            fail_stage <= ST_INIT;
                            err_code   <= MY_TO_INIT;
                            state_o    <= S_ERROR;
                        end
                    end
                end

                // ------------------------------------------------------------
                // S_INITR：只停一拍，下一拍 state_new 再发 start
                // ★★ 2026-10-06 复核修（缺陷 26）：这里**必须把 init_arm 清零**。
                //   原来只写 `state_o <= S_INIT`，于是重试回到 S_INIT 那一拍 `init_arm`
                //   还是上一轮的**饱和值 7** ⇒ `if (init_arm >= 3'd4)` **立刻成立**，
                //   而此时 initializer 还没收到新 start、`init_error` 仍是 1
                //   ⇒ 立刻又判一次错 ⇒ 每次重试只花 2 拍、且不停给 initializer 打 start
                //   ⇒ **16 次重试在 ~30 拍内烧完，真正的初始化尝试 ≈8 次**（且每次都被
                //   下一次 start 打断）。这就是"自动重试没救活卡"的原因。
                //   在 S_INITR 清 0 后，回到 S_INIT 时 init_arm=0 ⇒ 沉降窗对**每一次**尝试
                //   都成立（要等 5 拍才开始判错）。
                S_INITR: begin
                    init_arm <= 3'd0;                  // ★ 缺陷 26 的修复
                    state_o  <= S_INIT;
                end

                // ------------------------------------------------------------
                S_MBR: begin
                    if (state_new) mp_start <= 1'b1;      // ★ 单拍
                    to_cnt <= to_cnt + 32'd1;
                    // ★ parse_done 是**电平**，错误看 err_code（不是独立 flag）
                    if (mp_done) begin
                        if (mp_ec != 8'h00) begin
                            fail_stage <= ST_MBR;
                            err_code   <= mp_ec;
                            err_detail <= mp_ed;
                            state_o    <= S_ERROR;
                        end else begin
                            to_cnt  <= 32'd0;
                            state_o <= S_BOOT;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_MBR;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end

                // ------------------------------------------------------------
                S_BOOT: begin
                    if (state_new) bp_start <= 1'b1;      // ★ 单拍
                    to_cnt <= to_cnt + 32'd1;
                    if (bp_done) begin
                        if (bp_err) begin
                            fail_stage <= ST_BOOT;
                            err_code   <= bp_ec;
                            err_detail <= bp_ed;
                            state_o    <= S_ERROR;
                        end else begin
                            to_cnt   <= 32'd0;
                            scan_sub <= 2'd0;
                            state_o  <= S_SCAN;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_BOOT;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end

                // ------------------------------------------------------------
                // 目录遍历：idx_clear（单拍）→ scan_en（单拍）→ 等 scan_done
                //            → idx_commit（单拍）→ S_INDEX
                S_SCAN: begin
                    to_cnt <= to_cnt + 32'd1;
                    case (scan_sub)
                        2'd0: begin idx_clear <= 1'b1; scan_sub <= 2'd1; end
                        2'd1: begin scan_en   <= 1'b1; scan_sub <= 2'd2; end
                        2'd2: begin scan_sub<=2'd3; end // let scanner consume start and clear stale done
                        default: begin
                            if (scan_done) begin
                                if (dir_bad) begin
                                    fail_stage <= ST_SCAN;
                                    err_code   <= dn_ec;
                                    err_detail <= dn_ed;
                                    state_o    <= S_ERROR;
                                end else begin
                                    idx_commit <= 1'b1;   // ★ 单拍
                                    to_cnt     <= 32'd0;
                                    state_o    <= S_INDEX;
                                end
                            end else if (to_cnt >= MOUNT_TO_N) begin
                                fail_stage <= ST_SCAN;
                                err_code   <= MY_TO_MOUNT;
                                state_o    <= S_ERROR;
                            end
                        end
                    endcase
                end

                // ------------------------------------------------------------
                S_INDEX: begin
                    to_cnt <= to_cnt + 32'd1;
                    if (idx_done) begin
                        to_cnt <= 32'd0;
                        if (file_cnt == 4'd0) begin
                            fail_stage <= ST_IDX;
                            err_code   <= MY_NO_FILE;
                            state_o    <= S_ERROR;
                        end else begin
                            card_usable <= !RESIDENT_CACHE;
                            cur_file    <= 2'd0;
                            pick_slot   <= 2'd0;
                            state_o     <= S_READY;
                        end
                    end else if (to_cnt >= MOUNT_TO_N) begin
                        fail_stage <= ST_IDX;
                        err_code   <= MY_TO_MOUNT;
                        state_o    <= S_ERROR;
                    end
                end

                // ------------------------------------------------------------
                // 选片：等 file_index 的 sel_* 落定（cur_file 变了要等几拍）
                //   file_index 对 [0, file_cnt-1] 内的槽保证 sel_valid=1，所以
                //   这里不写“跳过非法槽”的循环，避免潜在死循环 ✗
                S_PICK: begin
                    pick_slot <= cur_file;
                    pick_to   <= pick_to + 32'd1;
                    if (pick_to >= 32'd3) begin
                        pick_to <= 32'd0;
                        if (!sel_valid) begin
                            fail_stage <= ST_PICK;
                            err_code   <= MY_NO_FILE;
                            state_o    <= S_ERROR;
                        end else begin
                            cur_file_size <= sel_size;
                            state_o       <= S_STREAM;
                        end
                    end
                end

                // ------------------------------------------------------------
                // 等“开播 / 下一幅”：首幅自动播；之后看 btn_auto 或 btn_next
                S_READY: begin
                    to_cnt <= 32'd0;
                    if (RESIDENT_CACHE) begin
                        if(cache_count<4) begin pick_to<=0;state_o<=S_PICK;end
                    end else if (frame_cnt == 16'd0) begin
                        // 首幅：播 0 号
                        cur_file  <= 2'd0;
                        pick_slot <= 2'd0;
                        pick_to   <= 32'd0;
                        state_o   <= S_PICK;
                    end else if (btn_next || btn_auto) begin
                        // 换下一幅（到末尾回绕；last_slot 已保证在合法范围）
                        cur_file  <= (cur_file == last_slot) ? 2'd0 : (cur_file + 2'd1);
                        pick_slot <= (cur_file == last_slot) ? 2'd0 : (cur_file + 2'd1);
                        pick_to   <= 32'd0;
                        state_o   <= S_PICK;
                    end
                end

                // ------------------------------------------------------------
                S_STREAM: begin
                    // Variable BMPs can exceed a fixed3-second transfer time.
                    // Keep a bounded NO-PROGRESS timeout for resident loads;
                    // both actual input consumption and accepted normalized
                    // pixels count. Legacy player timing remains unchanged.
                    if(1'b0)to_cnt<=0;
                    else to_cnt <= to_cnt + 32'd1;
                    // ★ 等 mem 侧空闲（官方 FIFO 已排空）才开帧：
                    //   避免上一帧残留像素被当成本帧的开头（那会让本帧 CRC 必错）
                    if (!stream_kicked && mem_ready_s && !fst_busy && rd_ready) begin
                        fst_start     <= 1'b1;              // ★ 单拍
                        frame_active  <= 1'b1;
                        stream_kicked <= 1'b1;
                    end
                    // ★★ 行序必须等**本帧 BMP 头解析完**才锁存，不能在开帧那一拍取：
                    //    `bmp_parser.check_done` 是单拍脉冲，`bmp_top_down` 是"结果寄存器"，
                    //    开帧时它还是**上一幅**的值 ⇒ 会拿错行序 ✗（已踩过）。
                    //    头解析（54 字节）远早于第一个像素（要读几十个扇区），
                    //    所以 mem 侧的桥在"首个被接受的像素"捕获行序时它早已稳定 ✓
                    if (stream_kicked && bmp_check_done) top_down_o <= bmp_top_down;
                    cur_file_size <= sel_size;

                    // 本帧像素产完（bmp_unpack.done）后，等 mem 侧"写完 + 换帧走完"
                    if (stream_kicked && fd_pending && file_done_seen && (!RESIDENT_CACHE||unpack_done_seen) && !bpu_error && !bmp_check_error && !fst_error && rd_ready && !spi_busy && !rd_crc && !rd_to) begin
                        frame_active  <= 1'b0;
                        last_frame_ok_o <= lok_sync[1];    // 采样 mem 侧电平（已两级同步）
                        stream_kicked <= 1'b0;
                        to_cnt        <= 32'd0;
                        if (lok_sync[1]) begin
                            frame_cnt <= frame_cnt + 16'd1;
                            if(RESIDENT_CACHE) begin
                                cache_valid[out_slot]<=1;cache_count<=cache_count+1'b1;
                                cache_keys[out_slot*16+:16]<=selected_key;
                                if(cache_count==3)card_usable<=1;
                            end
                            state_o <= S_SWAP;
                        end else begin
                            // A failed sink completion must not transfer slot
                            // ownership or count as a successful displayed frame.
                            fail_stage <= ST_STREAM;
                            err_code <= 8'hE3;
                            err_detail <= 8'h01;
                            state_o <= S_ERROR;
                        end
                    end else if (fst_error || bpu_error || bmp_check_error || (stream_kicked && (rd_crc || rd_to))) begin
                        stream_kicked <= 1'b0;
                        frame_active  <= 1'b0;
                        fail_stage    <= ST_STREAM;
                        err_code      <= (rd_crc || rd_to) ? rd_ec : fst_error ? fst_ec : (bpu_error ? bpu_ec : bmp_ec);
                        err_detail    <= (rd_crc || rd_to) ? rd_ed : fst_error ? fst_ed : (bpu_error ? bpu_ed : bmp_ed);
                        state_o       <= RESIDENT_CACHE ? S_REJECT : S_ERROR;
                        if(RESIDENT_CACHE)to_cnt<=0;
                    end else if (to_cnt >= STREAM_TO_N) begin
                        stream_kicked <= 1'b0;
                        frame_active  <= 1'b0;
                        fail_stage    <= ST_STREAM;
                        err_code      <= MY_TO_STREAM;
                        state_o       <= S_ERROR;
                    end
                end

                // ------------------------------------------------------------
                // 换帧已在 mem 侧完成（含 core 的 swap）⇒ 换另一槽、准备下一幅
                S_SWAP: begin
                    to_cnt <= 0;
                    if(RESIDENT_CACHE) begin
                        // Every accepted image owns a DIFFERENT resident slot.
                        // Candidate cursor advances on both pass and rejection.
                        out_slot<=cache_count[1:0];cursor_key<=selected_key;
                        if(cache_count==4) begin state_o<=S_READY;fail_stage<=0;err_code<=0;err_detail<=0;end
                        else if(cur_file==last_slot) begin
                            cur_file<=0;pick_slot<=0;scan_sub<=0;state_o<=S_SCAN;
                        end else begin cur_file<=cur_file+1'b1;pick_slot<=cur_file+1'b1;state_o<=S_READY;end
                    end else begin out_slot<=out_slot^2'b01;state_o<=S_READY;end
                end

                // ------------------------------------------------------------
                S_REJECT: begin
                    // state-based bus mux supplies data_ready=1, rd_en=0 here.
                    // Finish the active CMD17 before resetting its consumers.
                    frame_active<=0;to_cnt<=to_cnt+1'b1;
                    if(rd_ready && !spi_busy)begin state_o<=S_CLEAN;to_cnt<=0;end
                    else if(to_cnt>=STREAM_TO_N)begin err_code<=MY_TO_STREAM;state_o<=S_ERROR;end
                end
                S_CLEAN: begin
                    to_cnt<=to_cnt+1'b1;
                    if(to_cnt==3)begin
                        rejected_files<=rejected_files+1'b1;cursor_key<=selected_key;
                        last_reject_error<={err_code,err_detail};last_reject_key<=selected_key;
                        to_cnt<=0;stream_kicked<=0;
                        if(cur_file==last_slot)begin
                            cur_file<=0;pick_slot<=0;scan_sub<=0;state_o<=S_SCAN;
                        end else begin cur_file<=cur_file+1'b1;pick_slot<=cur_file+1'b1;state_o<=S_READY;end
                    end
                end
                S_ERROR: begin
                    sd_ready    <= 1'b0;
                    card_usable <= 1'b0;
                    if (restart) begin
                        to_cnt     <= 32'd0;
                        init_try   <= 4'd0;      // ★ 重来时重试计数清零（再给满 16 次机会）
                        init_arm   <= 3'd0;
                        fail_stage <= 4'd0;
                        err_code   <= 8'h00;
                        err_detail <= 8'h00;
                        frame_cnt  <= 16'd0;
                        cursor_key<=0;cache_valid<=0;cache_count<=0;cache_keys<=0;rejected_files<=0;
                        last_reject_error<=0;last_reject_key<=0;
                        out_slot<=RESIDENT_CACHE?0:1;
                        cur_file   <= 2'd0;
                        pick_slot  <= 2'd0;
                        state_o    <= S_INIT;
                    end
                end

                default: state_o <= S_IDLE;
            endcase
        end
    end

endmodule
