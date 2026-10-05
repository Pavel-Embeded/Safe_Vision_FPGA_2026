// ============================================================================
// tb_ab_frame_display.sv — A↔B **全链路集成** TB（B 的阶段 1–16 + A 的阶段 11–15）
// ----------------------------------------------------------------------------
// 为什么要它（现有 TB 的接缝）：
//   · B 侧各阶段都有单模块 TB；`tb_card_to_screen` 覆盖了 SD/FAT32 前段，
//     但它的卡卷只有 64 扇区（~32 KB），装不下 640x480 24bit BMP（921654 字节）
//     ⇒ 只有文件第一扇区（含 54 字节头）真的写在卡上，**文件主体是卡模型默认图案**。
//   · `tb_ab_frame_display`（本文件）覆盖了"帧缓存内容 → 屏幕像素"，但它的 BMP
//     字节流是 **TB 自己合成的**，不经过 SD 卡。
//   · 本文件把**两半合起来**，端到端断言：**屏幕上某个坐标的像素 == 真实写在 SD
//     卡上的 BMP 文件里那个像素**。整条链每一级都是真实模块，无桩。
//
// 链路（全部是真实模块）：
//   sd_spi_card_model（真实 FAT32 卷 + 完整 921654 字节真 BMP 文件）
//     → sd_initializer → sd_sector_reader（CMD17，共享 SPI/读总线）
//     → mbr_parser → fat32_boot_parser → fat32_directory_scanner(+walker) → file_index
//     → file_streamer(+walker) → bmp_parser → bmp_unpack
//     → frame_writer（B·阶段10，逐 word 写 + CRC）
//     → memory_arbiter 写通道（B·阶段13）
//     → 存储模型（真存真取，模拟 mem_ctrl 的下游）
//     → memory_arbiter 读通道（Video Read）
//     → a_video_display_core（A·阶段11–15：帧读取 + 官方异步 FIFO + CDC + 合成 + 扫描）
//     → rgb/hsync/vsync/de → 屏幕像素
//
// ★★ 能证明什么
//   · **整条数据通路是通的**：从 SD 卡上的真实 FAT32 文件字节，到屏幕像素，
//     中间每一级的握手、地址换算（卷基址只加一次）、簇链、字节流都对得上。
//   · `frame_writer` 写进 SDRAM 的**内容**与 A 读出来显示的**内容**一致。
//   · 仲裁器读写两路共用同一个存储口时不会互相破坏（写侧有真实竞争）。
//   · 换帧握手（B 的 swap_ctrl → CDC → A）走通后画面才出现。
//
// ★★ 期望值来自哪里（这是本 TB 的关键）
//   期望像素**不是**另编一套。它由函数 `px24(x,y)` 唯一给出；同一个 `px24` 既用来
//   生成写进卡卷的文件字节（`filebyte`），又用来算屏幕期望像素（`px565`）。
//   ⇒ 只要链路把任意一个字节送错，`pix_bad` 就会非 0。
//   另外 `fst_mism` 直接逐字节比对 file_streamer 的输出与卡上文件字节，进一步把
//   "卡上真文件 → 字节流"这一步钉死。
//
// ★★ 不能证明什么（别越界）
//   · 不验真实 SD 卡的电气/时序 AC：卡模型在 SPI 位级即时应答，没有 NCR / busy 轮询。
//   · 不验多扇区 CMD18：sd_sector_reader 是 CMD17 单扇区（rd_len 必须为 1）。
//   · 卡卷仍是**合成的微型 FAT32 镜像**（1 个 FAT 扇区、32 扇区/簇、声明 2048 扇区），
//     不是真实卡镜像。但**文件主体现在是真字节**（不再是卡模型默认图案）。
//   · 不验真实 SDRAM 的物理 AC/时序；存储模型是理想存储器。
//   · 不验 HDMI 电气层、不验板级。
//   · ★ 时钟域假设：本 TB 把整条 B 链（含 bmp_parser/bmp_unpack）与 frame_writer
//     **都放在 mem_clk**（125 MHz）。若产品里这两级是跨域的，需要在它们之间补
//     CDC FIFO —— 这一点待与 A 确认（见 docs/B链-给A的同步与确认清单.md ①）。
//
// 入口：safevision/tools/run_ab_display_sim.ps1（独立脚本，已登记进 run_all.ps1）。
// ============================================================================
// ★ 排查历史（保留，避免重复劳动）：
//   1. **重复例化 `frame_swap_cdc`** ⇒ `fs_evt_b`/`ack_evt_b` 双驱动 ⇒ 换帧 FSM 超时。
//      A 的 `a_video_display_core` 内部已有一个，TB 不能再放（接线表禁忌）。
//   2. **`TIMEOUT_N` 给得太小**（400 us）⇒ A 的 core 在真实垂直消隐才回 frame_start
//      （一帧 ~16.7 ms）⇒ 用模块默认 5_000_000 拍（=50 ms）。
//   3. **比对窗口太短**（2000 拍落在消隐期 ⇒ pix_ok=0）⇒ 改为"画面激活后跨两整帧"。
//   4. **`active_commit` 检查时机错了**（不是 bug）：A 的 core 从 mailbox 到达就激活
//      画面，而 B 的 FSM 要等到下一个垂直消隐才提交（实测差约一帧）。
//      ⇒ `commits >= 1` 必须放在**跨两整帧之后**（本文件已这么做）。
//   ★ 观测教训：单周期信号必须用 `always` 数边沿；层次引用在 vopt 下不可靠，
//     只信 TB 顶层信号。
//   ★ `a_pixel_fifo_ip.v` 的两个未接端口（`doa`/`dib`）已显式列出后，本 TB 在
//     **ModelSim** 上也能 elaborate（原先 vopt 会内部崩溃）。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"
`include "pixel_format_defs.vh"

module tb_ab_frame_display;

    // ------------------------------------------------------------------------
    // 三个时钟域（与整机一致：sys 100M / mem 125M / pixel 74.25M）
    // ------------------------------------------------------------------------
    reg clk_sys = 1'b0;  always #5.0   clk_sys = ~clk_sys;
    reg clk_mem = 1'b0;  always #4.0   clk_mem = ~clk_mem;
    reg clk_pix = 1'b0;  always #6.734 clk_pix = ~clk_pix;

    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    localparam integer W = 640;
    localparam integer H = 480;
    localparam integer FRAME_PIX = W * H;                       // 307200
    localparam integer FILE_BYTES = 54 + FRAME_PIX*3;           // 921654
    localparam integer FILE_SECTORS = (FILE_BYTES + 511) / 512; // 1801
    localparam integer CLK_HZ_MEM = 125_000_000;

    // ========================================================================
    // 卷几何（与 tb_card_to_screen 同布局；见文件头"不能证明什么"）
    //   VOL_BASE=16（分区 0 起始卡 LBA），SPC=32，RSVD=1，NFAT=1，FATSZ=1，
    //   TOTSEC=2048，RootClus=2，文件首簇=3。
    //   ⇒ data_start_lba = RSVD + NFAT*FATSZ = 2；root_dir_lba = 2；
    //     文件首簇 3 落在卷内 LBA = 2 + (3-2)*32 = 34；
    //     文件占 1801 个扇区 ⇒ 卷内 LBA 34..1834，落在 57 个连续簇 3..59。
    //   ★ 因为簇连续，(文件扇区号 s) 对应的卷内 LBA 恰好 = 34 + s。
    // ========================================================================
    localparam [31:0] VOL_BASE   = 32'd16;
    localparam [7:0]  SPC        = 8'd32;
    localparam [15:0] RSVD       = 16'd1;
    localparam [7:0]  NFAT       = 8'd1;
    localparam [31:0] FATSZ      = 32'd1;
    localparam [31:0] TOTSEC     = 32'd2048;
    localparam [31:0] ROOTCLUS   = 32'd2;
    localparam [31:0] FILE_CLUS  = 32'd3;
    localparam integer FILE_CLUS_N = (FILE_SECTORS + 31) / 32;              // 57
    localparam [31:0] FILE_CLUS_LAST = FILE_CLUS + FILE_CLUS_N - 1;         // 59
    localparam [31:0] VOL_DBR_LBA  = 32'd0;
    localparam [31:0] VOL_FAT_LBA  = 32'd1;
    localparam [31:0] VOL_ROOT_LBA = 32'd2;
    localparam [31:0] VOL_FILE0_LBA = 32'd34;

    // ========================================================================
    // 像素/文件字节的唯一来源：px24(x,y)
    //   BGR 存盘；这里给的是 RGB 语义值。同一个函数既写卡又算期望。
    // ========================================================================
    function [23:0] px24;
        input integer x;
        input integer y;
        begin
            px24 = { (x[7:0] ^ y[7:0]), (x[9:0] + y[9:0]) & 8'hFF, (x[9:0] * 3) & 8'hFF };
        end
    endfunction

    // RGB565（与 bmp_unpack 的截断口径一致：R>>3, G>>2, B>>3）
    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
    endfunction

    // RGB888（把 RGB565 展开成 888，与 A 的 core 的 expand 口径一致）
    function [23:0] expand565;
        input [15:0] p;
        begin
            expand565 = { p[15:11], p[15:13], p[10:5], p[10:9], p[4:0], p[4:2] };
        end
    endfunction

    // ========================================================================
    // BMP 头（54 字节）。height = +480 -> 自底向上（BMP 常规），
    // 所以文件行序是"倒过来"的，bmp_unpack 会翻正。保留该分支以覆盖翻转逻辑。
    // ========================================================================
    reg [7:0] bmp_hdr [0:53];
    initial begin
        integer i;
        for (i = 0; i < 54; i = i + 1) bmp_hdr[i] = 8'h00;
        bmp_hdr[0]  = 8'h42; bmp_hdr[1]  = 8'h4D;                 // "BM"
        bmp_hdr[2]  = (54 + FRAME_PIX*3) & 8'hFF;                 // 文件大小（小端）
        bmp_hdr[3]  = ((54 + FRAME_PIX*3) >> 8) & 8'hFF;
        bmp_hdr[4]  = ((54 + FRAME_PIX*3) >> 16) & 8'hFF;
        bmp_hdr[5]  = ((54 + FRAME_PIX*3) >> 24) & 8'hFF;
        bmp_hdr[10] = 54;                                         // bfOffBits = 54
        bmp_hdr[14] = 40;                                         // biSize = 40
        bmp_hdr[18] = W & 8'hFF;      bmp_hdr[19] = (W >> 8) & 8'hFF;   // biWidth
        bmp_hdr[22] = H & 8'hFF;      bmp_hdr[23] = (H >> 8) & 8'hFF;   // biHeight = +480
        bmp_hdr[26] = 1;                                          // biPlanes
        bmp_hdr[28] = 24;                                         // biBitCount
        bmp_hdr[34] = (FRAME_PIX*3) & 8'hFF;                      // biSizeImage
        bmp_hdr[35] = ((FRAME_PIX*3) >> 8) & 8'hFF;
        bmp_hdr[36] = ((FRAME_PIX*3) >> 16) & 8'hFF;
        bmp_hdr[37] = ((FRAME_PIX*3) >> 24) & 8'hFF;
    end

    // ------------------------------------------------------------------------
    // 卡上文件第 j 个字节。★ 唯一真相：写卡用它，算期望也用它。
    //   j <  54  : BMP 头
    //   j >= 54  : BMP 像素段（行序自底向上，通道 B,G,R）
    //              p = j-54；像素序号 n = p/3；通道 c = p%3；
    //              BMP 行 r = n/W；列 x = n%W；光栅行 y = H-1-r。
    // ------------------------------------------------------------------------
    function [7:0] filebyte;
        input integer j;
        integer p, n, c, r, x, y;
        reg [23:0] pxv;
        begin
            if (j < 54) filebyte = bmp_hdr[j];
            else begin
                p = j - 54;
                n = p / 3;
                c = p - n*3;
                r = n / W;
                x = n - r*W;
                y = H - 1 - r;
                pxv = px24(x, y);
                filebyte = (c == 0) ? pxv[7:0] : (c == 1) ? pxv[15:8] : pxv[23:16];
            end
        end
    endfunction

    // 光栅像素序号 n 的期望 RGB565（n = y*W + x）
    function [15:0] exp565_n;
        input integer n;
        begin
            exp565_n = px565(n % W, n / W);
        end
    endfunction

    // ========================================================================
    // SPI 总线 + SD 卡模型
    // ========================================================================
    wire sd_ncs, sd_dclk, sd_mosi, sd_miso;
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;

    sd_spi_card_model #(
        .VOL_BASE (VOL_BASE)
    ) u_card (
        .sclk         (sd_dclk),
        .cs_n         (sd_ncs),
        .mosi         (sd_mosi),
        .miso         (sd_miso),
        .i_dead       (1'b0),
        .o_cmd        (o_cmd),
        .o_arg        (o_arg),
        .o_acmd41_arg (o_acmd41_arg),
        .o_cmd_cnt    (o_cmd_cnt),
        .o_acmd41_cnt (o_acmd41_cnt),
        .o_cmd_valid  (o_cmd_valid)
    );

    // ========================================================================
    // 前段全部网线先声明（绝不让 always 里用到"声明在后面"的 wire，
    // 否则 Verilog 建隐式 1 bit 网线、整条链卡死且无报错）。
    // ========================================================================
    // sd_initializer
    wire        sdhc, init_done, init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n, init_tx_valid;
    wire [7:0]  init_tx_data;
    wire [15:0] init_clk_div;
    reg         init_start;

    // mbr_parser
    reg         mp_start;
    wire        mp_done, mp_has;
    wire [7:0]  mp_ec, mp_ed;
    wire [31:0] mp_vol_base, mp_part_secs;
    wire [31:0] mp_rd_addr;
    wire [15:0] mp_rd_len;
    wire        mp_rd_en, mp_data_ready;

    // fat32_boot_parser
    reg         bp_start;
    wire        bp_done, bp_err;
    wire [7:0]  bp_ec, bp_ed, bp_spc, bp_nfat;
    wire [15:0] bp_bps;
    wire [31:0] bp_fat_lba, bp_root_clus, bp_root_lba, bp_data_lba, bp_tot_sec, bp_tot_clus;
    wire [31:0] bp_rd_addr;
    wire [15:0] bp_rd_len;
    wire        bp_rd_en, bp_data_ready;

    // fat32_directory_scanner + its walker
    reg         scan_en;
    wire        scan_done, dir_bad;
    wire [7:0]  dn_ec, dn_ed;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid, ent_ready;
    wire [31:0] dn_rd_addr;
    wire [15:0] dn_rd_len;
    wire        dn_rd_en, dn_data_ready;
    wire [31:0] dn_wk_cur, dn_wk_next;
    wire        dn_wk_start, dn_wk_rst, dn_wk_busy, dn_wk_done, dn_wk_eoc, dn_wk_err;
    wire [7:0]  dn_wk_ec, dn_wk_ed;
    wire [31:0] wd_rd_addr;
    wire [15:0] wd_rd_len;
    wire        wd_rd_en, wd_data_ready;

    // file_index
    reg         idx_clear, idx_commit;
    wire        idx_done;
    wire [3:0]  file_cnt, file_valid;
    wire        insufficient;
    wire [7:0]  idx_ec, idx_ed;
    wire [31:0] sel_first_clus, sel_size;
    wire        sel_valid;
    wire [31:0] sel_wav_clus, sel_wav_size;
    wire        sel_wav_valid;
    wire [15:0] bmp_seen, wav_seen;

    // file_streamer + its walker
    reg         fst_start;
    reg  [31:0] fst_first_clus, fst_file_size;
    wire        fst_busy, fst_done, fst_error;
    wire [7:0]  fst_ec, fst_ed;
    wire [31:0] fst_bytes;
    wire [7:0]  fst_data;
    wire        fst_valid, fst_sof, fst_eof;
    wire [31:0] fst_rd_addr;
    wire [15:0] fst_rd_len;
    wire        fst_rd_en, fst_data_ready;
    wire [31:0] fst_wk_cur, fst_wk_next;
    wire        fst_wk_start, fst_wk_rst, fst_wk_busy, fst_wk_done, fst_wk_eoc, fst_wk_err;
    wire [7:0]  fst_wk_ec, fst_wk_ed;
    wire [31:0] wf_rd_addr;
    wire [15:0] wf_rd_len;
    wire        wf_rd_en, wf_data_ready;

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

    // bmp_unpack（bu_pixel_ready 由后段 frame_writer 的 din_ready 驱动）
    wire [15:0] bpu_pixel;
    wire        bpu_valid;
    wire        bu_pixel_ready;
    wire [9:0]  bpu_x, bpu_y;
    wire        bpu_sof, bpu_eof, bpu_done, bpu_error;
    wire [7:0]  bpu_ec, bpu_ed;

    // sd_sector_reader (shared) + spi_master
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to, rd_crc;
    wire [7:0]  rd_ec, rd_ed;
    wire        rd_cs_n, rd_tx_valid;
    wire [7:0]  rd_tx_data;
    wire [15:0] rd_clk_div;
    wire        spi_tx_ready, spi_busy, spi_rx_valid;
    wire [7:0]  spi_rx_data;

    // ========================================================================
    // 读总线归属：phase 选择前段哪个 master 拥有 reader；
    // SCAN/STREAM 期间 walker busy 时让 walker 优先。
    // （照抄 top_stage6_fat32_mount.v 的仲裁形态。）
    // ========================================================================
    localparam [1:0] PH_MBR = 2'd0, PH_BOOT = 2'd1, PH_SCAN = 2'd2, PH_STREAM = 2'd3;
    reg [1:0] phase = PH_MBR;

    wire scan_wk = (phase == PH_SCAN)   && dn_wk_busy;
    wire strm_wk = (phase == PH_STREAM) && fst_wk_busy;

    wire        bus_rd_en   = (phase == PH_MBR)  ? mp_rd_en :
                              (phase == PH_BOOT) ? bp_rd_en :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_en : dn_rd_en) :
                                                   (strm_wk ? wf_rd_en : fst_rd_en);
    wire [31:0] bus_rd_addr = (phase == PH_MBR)  ? mp_rd_addr :
                              (phase == PH_BOOT) ? bp_rd_addr :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_addr : dn_rd_addr) :
                                                   (strm_wk ? wf_rd_addr : fst_rd_addr);
    wire [15:0] bus_rd_len  = (phase == PH_MBR)  ? mp_rd_len :
                              (phase == PH_BOOT) ? bp_rd_len :
                              (phase == PH_SCAN) ? (scan_wk ? wd_rd_len : dn_rd_len) :
                                                   (strm_wk ? wf_rd_len : fst_rd_len);
    wire        bus_data_ready = (phase == PH_MBR)  ? mp_data_ready :
                                 (phase == PH_BOOT) ? bp_data_ready :
                                 (phase == PH_SCAN) ? (scan_wk ? wd_data_ready : dn_data_ready) :
                                                      (strm_wk ? wf_data_ready : fst_data_ready);

    // ★★ 卷基址只加一次（interface_spec §3.2.1）：★★
    //   mbr_parser 读卡的 0 号扇区时自身相对地址 = 0，且此时 mp_vol_base 仍为 0，
    //   故也恰好落到卡的 0 号扇区。
    wire [31:0] rd_addr_to_reader = bus_rd_addr + mp_vol_base;

    // ========================================================================
    // 前段模块例化（全部跑在 clk_mem）
    // ========================================================================
    sd_initializer u_init (
        .clk(clk_mem), .rst_n(rst_n), .start(init_start),
        .sdhc(sdhc), .init_done(init_done), .init_error(init_error),
        .err_code(init_err_code), .err_detail(), .retry_cnt(), .dbg_state(),
        .spi_cs_n(init_cs_n), .spi_clk_div(init_clk_div),
        .spi_tx_valid(init_tx_valid), .spi_tx_data(init_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    mbr_parser u_mbr (
        .clk(clk_mem), .rst_n(rst_n), .start(mp_start),
        .parse_done(mp_done), .err_code(mp_ec), .err_detail(mp_ed), .dbg_state(),
        .has_mbr(mp_has), .vol_base_lba(mp_vol_base), .part_secs(mp_part_secs),
        .sd_rd_addr(mp_rd_addr), .sd_rd_len(mp_rd_len), .sd_rd_en(mp_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(mp_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_boot_parser u_boot (
        .clk(clk_mem), .rst_n(rst_n), .start(bp_start),
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

    fat32_directory_scanner u_scan (
        .clk(clk_mem), .rst_n(rst_n), .scan_en(scan_en),
        .scan_done(scan_done), .dir_bad(dir_bad), .err_code(dn_ec), .err_detail(dn_ed),
        .dbg_state(),
        .sec_per_clus(bp_spc), .root_clus(bp_root_clus),
        .root_dir_lba(bp_root_lba), .data_start_lba(bp_data_lba),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index), .ent_valid(ent_valid), .ent_ready(ent_ready),
        .sd_rd_addr(dn_rd_addr), .sd_rd_len(dn_rd_len), .sd_rd_en(dn_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(dn_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed),
        .wk_cur_clus(dn_wk_cur), .wk_start(dn_wk_start), .wk_rst_walk(dn_wk_rst),
        .wk_busy(dn_wk_busy), .wk_done(dn_wk_done), .wk_next_clus(dn_wk_next),
        .wk_eoc(dn_wk_eoc), .wk_error(dn_wk_err), .wk_err_code(dn_wk_ec), .wk_err_detail(dn_wk_ed)
    );

    fat32_cluster_walker u_wk_dir (
        .clk(clk_mem), .rst_n(rst_n), .rst_walk(dn_wk_rst), .start(dn_wk_start),
        .cur_clus(dn_wk_cur), .busy(dn_wk_busy), .done(dn_wk_done), .next_clus(dn_wk_next),
        .eoc(dn_wk_eoc), .error(dn_wk_err), .err_code(dn_wk_ec), .err_detail(dn_wk_ed),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(wd_rd_addr), .sd_rd_len(wd_rd_len), .sd_rd_en(wd_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(wd_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    file_index u_idx (
        .clk(clk_mem), .rst_n(rst_n),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index), .ent_valid(ent_valid), .ent_ready(ent_ready),
        .idx_clear(idx_clear), .idx_commit(idx_commit), .idx_done(idx_done),
        .file_cnt(file_cnt), .file_valid(file_valid), .insufficient(insufficient),
        .err_code(idx_ec), .err_detail(idx_ed),
        .sel_slot(2'd0), .sel_first_clus(sel_first_clus), .sel_size(sel_size), .sel_valid(sel_valid),
        .sel_wav_first_clus(sel_wav_clus), .sel_wav_size(sel_wav_size), .sel_wav_valid(sel_wav_valid),
        .bmp_seen(bmp_seen), .wav_seen(wav_seen)
    );

    file_streamer u_fst (
        .clk(clk_mem), .rst_n(rst_n),
        .start(fst_start), .first_clus(fst_first_clus), .file_size(fst_file_size),
        .busy(fst_busy), .done(fst_done), .error(fst_error), .err_code(fst_ec), .err_detail(fst_ed),
        .bytes_rd(fst_bytes), .dbg_state(),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .sof(fst_sof), .eof(fst_eof),
        .sec_per_clus(bp_spc), .fat_start_lba(bp_fat_lba),
        .data_start_lba(bp_data_lba), .total_clus(bp_tot_clus),
        .wk_cur_clus(fst_wk_cur), .wk_start(fst_wk_start), .wk_rst_walk(fst_wk_rst),
        .wk_busy(fst_wk_busy), .wk_done(fst_wk_done), .wk_next_clus(fst_wk_next),
        .wk_eoc(fst_wk_eoc), .wk_error(fst_wk_err),
        .wk_err_code(fst_wk_ec), .wk_err_detail(fst_wk_ed),
        .sd_rd_addr(fst_rd_addr), .sd_rd_len(fst_rd_len), .sd_rd_en(fst_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(fst_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    fat32_cluster_walker u_wk_fst (
        .clk(clk_mem), .rst_n(rst_n), .rst_walk(fst_wk_rst), .start(fst_wk_start),
        .cur_clus(fst_wk_cur), .busy(fst_wk_busy), .done(fst_wk_done), .next_clus(fst_wk_next),
        .eoc(fst_wk_eoc), .error(fst_wk_err), .err_code(fst_wk_ec), .err_detail(fst_wk_ed),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(bp_fat_lba), .total_clus(bp_tot_clus),
        .sd_rd_addr(wf_rd_addr), .sd_rd_len(wf_rd_len), .sd_rd_en(wf_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(wf_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to), .sd_crc16_err(rd_crc),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ★★ bmp_parser 及其下游（bmp_unpack / frame_writer / 仲裁 / A core）**保持原样**，
    //    只是把 bmp_parser 的输入从"TB 合成字节流"换成 file_streamer 的真实输出。
    bmp_parser u_bmp (
        .clk(clk_mem), .rst_n(rst_n),
        .data(fst_data), .valid(fst_valid), .ready(bp_ready), .eof(fst_eof),
        .file_size(fst_file_size),
        .check_done(bmp_check_done), .check_error(bmp_check_error),
        .err_code(bmp_ec), .err_detail(bmp_ed),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down),
        .bpp(bmp_bpp), .compression(bmp_compression), .pixel_off(bmp_pixel_off),
        .file_size_o(bmp_file_size_o), .dbg_state(),
        .out_data(bpo_data), .out_valid(bpo_valid), .out_ready(bpo_ready),
        .out_sof(bpo_sof), .out_eof(bpo_eof)
    );

    bmp_unpack u_unpack (
        .clk(clk_mem), .rst_n(rst_n),
        .din(bpo_data), .din_valid(bpo_valid), .din_ready(bpo_ready),
        .din_sof(bpo_sof), .din_eof(bpo_eof),
        .width(bmp_width), .height(bmp_height), .top_down(bmp_top_down), .pixel_off(bmp_pixel_off),
        .pixel(bpu_pixel), .pixel_valid(bpu_valid), .pixel_ready(bu_pixel_ready),
        .x(bpu_x), .y(bpu_y), .img_sof(bpu_sof), .img_eof(bpu_eof),
        .done(bpu_done), .error(bpu_error), .err_code(bpu_ec), .err_detail(bpu_ed),
        .dbg_state()
    );

    sd_sector_reader u_rd (
        .clk(clk_mem), .rst_n(rst_n), .sdhc(sdhc),
        .rd_en(bus_rd_en), .rd_addr(rd_addr_to_reader), .rd_len(bus_rd_len), .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(bus_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to), .crc16_err(rd_crc),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_clk_div),
        .spi_tx_valid(rd_tx_valid), .spi_tx_data(rd_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    wire spi_use_reader = init_done;
    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;
    assign sd_ncs = init_cs_n & rd_cs_n;

    spi_master #(.CLK_FREQ(CLK_HZ_MEM)) u_spi (
        .clk(clk_mem), .rst_n(rst_n), .clk_div(spi_clk_div), .cs_n(sd_ncs),
        .tx_valid(spi_tx_valid), .tx_data(spi_tx_data), .tx_ready(spi_tx_ready),
        .rx_data(spi_rx_data), .rx_valid(spi_rx_valid), .busy(spi_busy),
        .sclk(sd_dclk), .mosi(sd_mosi), .miso(sd_miso)
    );

    // ========================================================================
    // 后段：frame_writer → memory_arbiter → 存储 → A 显示核心
    // ========================================================================
    reg         fw_start = 1'b0;
    wire [1:0]  fw_slot_sel = 2'd1;                       // 写到 IMG1 槽
    wire [31:0] fw_slot_base = `SV_IMG1_BASE;
    wire        fw_wr_req, fw_wr_done, fw_crc_ok, fw_wr_error;
    wire [31:0] fw_wr_addr, fw_wr_data;
    wire [15:0] fw_wr_len;
    wire [3:0]  fw_slot_valid;
    wire [15:0] fw_crc_value;
    wire [18:0] fw_px_cnt;
    wire [7:0]  fw_err_code, fw_err_detail;
    wire        fw_wr_ready;

    // ★ GAP_TIMEOUT 覆盖说明（不是削弱断言）：
    //   原 ab TB 的字节源是 TB 自造的，字节连续 ⇒ 默认 512 拍足够。
    //   现在字节源是**真实 SD/FAT32 链**：file_streamer 每读一个扇区要在 SPI 上
    //   跑一次 CMD17（512 Byte @31.25MHz ≈ 16384 拍 clk_mem），每跨一个簇还要
    //   多读一次 FAT 扇区。这些期间 frame_writer 收不到像素 ⇒ 默认 512 拍必误判
    //   "上游断流"。把 GAP_TIMEOUT 抬到 500_000 拍（=4ms）覆盖一次完整 FAT 读
    //   加余量，同时仍能在 4ms 内抓住真正的上游断流。TB 自身的断言（"5) frame_writer
    //   写帧无错"等）全部保留、未改。
    frame_writer #(.GAP_TIMEOUT(32'd500_000)) u_frame_writer (
        .clk        (clk_mem),
        .rst_n      (rst_n),
        .start      (fw_start),
        .slot_sel   (fw_slot_sel),
        .slot_base  (fw_slot_base),
        .din        (bpu_pixel),
        .din_valid  (bpu_valid),
        .din_ready  (bu_pixel_ready),
        .wr_req     (fw_wr_req),
        .wr_addr    (fw_wr_addr),
        .wr_data    (fw_wr_data),
        .wr_len     (fw_wr_len),
        .wr_ready   (fw_wr_ready),
        .wr_done    (fw_wr_done),
        .slot_valid (fw_slot_valid),
        .crc_ok     (fw_crc_ok),
        .crc_value  (fw_crc_value),
        .px_cnt     (fw_px_cnt),
        .wr_error   (fw_wr_error),
        .err_code   (fw_err_code),
        .err_detail (fw_err_detail)
    );

    wire        arb_rd_req;
    wire [31:0] arb_rd_addr;
    wire [15:0] arb_rd_len;
    wire        arb_rd_ack, arb_rd_busy, arb_rd_data_valid;
    wire [31:0] arb_rd_data;
    wire        arb_wr_ack, arb_wr_busy;

    wire        mem_req, mem_wr;
    reg         mem_ready = 1'b1;      // 本 TB 驱动（存储模型）
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata = 32'd0;     // 本 TB 驱动
    reg         mem_rdata_valid = 1'b0;// 本 TB 驱动

    wire [15:0] pix_fifo_level;

    // frame_writer 的 wr_ready = 仲裁器受理了这一拍（本模块逐 word 请求、len=1）
    assign fw_wr_ready = arb_wr_ack;

    memory_arbiter #(.MAX_BURSTS(4), .STARVE_LIMIT(64)) u_arb (
        .clk              (clk_mem),
        .rst_n            (rst_n),
        .video_fifo_level (pix_fifo_level),
        .rd_req           (arb_rd_req),
        .rd_addr          (arb_rd_addr),
        .rd_len           (arb_rd_len),
        .rd_ack           (arb_rd_ack),
        .rd_busy          (arb_rd_busy),
        .rd_data          (arb_rd_data),
        .rd_data_valid    (arb_rd_data_valid),
        .wr_req           (fw_wr_req),
        .wr_addr          (fw_wr_addr),
        .wr_data          (fw_wr_data),
        .wr_len           (fw_wr_len),
        .wr_ack           (arb_wr_ack),
        .wr_busy          (arb_wr_busy),
        .sd_req           (1'b0),
        .sd_wr            (1'b0),
        .sd_addr          (32'd0),
        .sd_wdata         (32'd0),
        .sd_len           (16'd0),
        .sd_ack           (),
        .sd_busy          (),
        .sd_rdata         (),
        .sd_rdata_valid   (),
        .mem_req          (mem_req),
        .mem_wr           (mem_wr),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_wstrb        (mem_wstrb),
        .mem_ready        (mem_ready),
        .mem_rdata        (mem_rdata),
        .mem_rdata_valid  (mem_rdata_valid),
        .wr_starve_cnt    (),
        .rd_starve_cnt    ()
    );

    // ---- 存储模型：真存真取（模拟 mem_ctrl 的下游）----
    localparam integer MEM_WORDS = 1024 * 1024;              // 4 MiB
    reg [31:0] sd_mem [0:MEM_WORDS-1];

    integer mcyc = 0;
    always @(posedge clk_mem) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 17) != 0);                     // 周期性忙，制造真实竞争
    end

    reg [31:0] raddr_p0, raddr_p1, raddr_p2;
    reg [2:0]  rv_pipe;
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            raddr_p0 <= 0; raddr_p1 <= 0; raddr_p2 <= 0;
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            raddr_p0 <= mem_addr;
            raddr_p1 <= raddr_p0;
            raddr_p2 <= raddr_p1;
            rv_pipe  <= { rv_pipe[1:0], (mem_req && mem_ready && !mem_wr) };
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= sd_mem[raddr_p2[21:2]];
            if (mem_req && mem_ready && mem_wr) sd_mem[mem_addr[21:2]] <= mem_wdata;
        end
    end

    // ========================================================================
    // 换帧握手：frame_swap_ctrl（B·阶段15）→ A 的 core（内部含 frame_swap_cdc）
    // ========================================================================
    reg         frame_ready = 1'b0;
    wire        swap_req_b, mb_fidx_b, mb_crc_b, swap_error, active_commit;
    wire [2:0]  swap_state_o;      // 诊断：帧交换 FSM 当前状态
    wire [1:0]  mb_slot_b, active_next;
    wire [7:0]  mb_gen_b, gen_next;
    wire        fs_evt_b, ack_evt_b;

    // ★ 超时要用能覆盖一整帧的值：A 的 core 在真实垂直消隐才回 frame_start，
    //   一帧约 16.7 ms。模块默认 5_000_000 拍（=50 ms）正是覆盖一整帧加余量。
    frame_swap_ctrl #(.TIMEOUT_N(32'd5_000_000)) u_swap (
        .clk              (clk_sys),
        .rst_n            (rst_n),
        .frame_ready      (frame_ready),
        .wr_frame_index   (1'b0),
        .wr_slot_id       (2'd1),                    // 与 frame_writer 写的槽一致
        .wr_generation    (8'h21),
        .wr_crc_ok        (fw_crc_ok),
        .frame_start      (fs_evt_b),
        .swap_ack         (ack_evt_b),
        .swap_req         (swap_req_b),
        .frame_index      (mb_fidx_b),
        .slot_id          (mb_slot_b),
        .generation       (mb_gen_b),
        .crc_ok           (mb_crc_b),
        .swap_error       (swap_error),
        .active_commit    (active_commit),
        .active_next      (active_next),
        .generation_next  (gen_next),
        .frame_index_next (),
        .state_o          (swap_state_o)
    );

    wire req_evt_a, frame_start_a, swap_ack_a;
    // ★★ 这里**故意不再例化 `frame_swap_cdc`**：A 的 `a_video_display_core` 内部
    //    已经有一个，它把 A 侧的 `frame_start`/`swap_ack` 变成 B 域单拍事件，
    //    从 core 的 `frame_start_evt_b`/`swap_ack_evt_b` 输出。整机里 B 侧**不应该**
    //    再放一份 CDC（接线表禁忌）。

    // ---- ★ 脉冲捕获（必须用 always 数边沿；1 ms 采样看不到单周期事件）----
    integer fs_b_pulses = 0, ack_b_pulses = 0;
    reg     fs_b_d = 1'b0, ack_b_d = 1'b0;
    always @(posedge clk_sys) begin
        fs_b_d  <= fs_evt_b;
        ack_b_d <= ack_evt_b;
        if (fs_evt_b  && !fs_b_d)  fs_b_pulses  = fs_b_pulses  + 1;
        if (ack_evt_b && !ack_b_d) ack_b_pulses = ack_b_pulses + 1;
    end

    // ★ 计数器必须声明在使用它的 always 块之前
    integer a_req_seen = 0, a_acks = 0, commits = 0;
    reg     cmt_d = 1'b0;
    integer acmt_edges = 0, st_changes = 0;
    reg     acmt_d = 1'b0;
    reg [2:0] st_d = 3'd0;
    always @(posedge clk_sys) begin
        if (!rst_n) begin acmt_d <= 1'b0; st_d <= 3'd0; end
        else begin
            acmt_d <= active_commit;
            if (active_commit && !acmt_d) acmt_edges = acmt_edges + 1;
            st_d <= swap_state_o;
            if (swap_state_o !== st_d) begin
                st_changes = st_changes + 1;
                $display("[FSM] t=%0t state %0d -> %0d  active_commit=%b", $time, st_d, swap_state_o, active_commit);
            end
        end
    end

    always @(posedge clk_sys) begin
        if (!rst_n) cmt_d <= 1'b0;
        else begin
            cmt_d <= active_commit;
            if (active_commit && !cmt_d) commits = commits + 1;
        end
    end
    // ★ A 侧的应答（frame_start / swap_ack）由 **A 的 core 内部**产生，TB 不再模拟。

    // ========================================================================
    // A：a_video_display_core（阶段 11–15）
    // ========================================================================
    wire [11:0] scan_x, scan_y;
    wire        scan_de, scan_frame_start;
    wire [23:0] disp_rgb;
    wire [11:0] disp_x, disp_y;
    wire        disp_hs, disp_vs, disp_de, disp_pixel_valid, disp_line_start;
    wire        disp_frame_start, disp_afs, disp_hblank, disp_vblank;
    wire [1:0]  disp_layer, pix_active_slot;
    wire [7:0]  pix_generation;
    wire        pix_active_valid, pix_frame_fault;
    wire [31:0] pix_underflow, pix_missed, mem_overflow;
    wire        mem_dma_active, mem_dma_done;
    wire [2:0]  mem_fetch_state;
    wire [31:0] mem_dma_bytes;

    a_video_display_core #(
        .HD      (0),
        .FIFO_AW (10),
        .BURST_WORDS (64),
        .FONT_FILE ("font8x16.mem")
    ) u_display (
        .sys_clk    (clk_sys),
        .mem_clk    (clk_mem),
        .pixel_clk  (clk_pix),
        .rst_n      (rst_n),
        .swap_req_b          (swap_req_b),
        .mb_frame_index_b    (mb_fidx_b),
        .mb_slot_id_b        (mb_slot_b),
        .mb_generation_b     (mb_gen_b),
        .mb_crc_ok_b         (mb_crc_b),
        .frame_start_evt_b   (fs_evt_b),
        .swap_ack_evt_b      (ack_evt_b),
        .rd_req     (arb_rd_req),
        .rd_addr    (arb_rd_addr),
        .rd_len     (arb_rd_len),
        .rd_ack     (arb_rd_ack),
        .rd_busy    (arb_rd_busy),
        .rd_data    (arb_rd_data),
        .rd_data_valid (arb_rd_data_valid),
        .cfg_valid  (1'b0),
        .cfg_ready  (),
        .cfg_osd_enable (1'b0),
        .cfg_mode   (2'b00),
        .cfg_fps_tens (4'd6),
        .cfg_fps_ones (4'd0),
        .cfg_sd_ok  (1'b1),
        .cfg_origin_x (12'd0),
        .cfg_origin_y (12'd0),
        .cfg_foreground (24'hFFFFFF),
        .emergency_rgb (24'h000000),
        .emergency_valid (1'b0),
        .scan_x     (scan_x),
        .scan_y     (scan_y),
        .scan_de    (scan_de),
        .scan_frame_start (scan_frame_start),
        .rgb        (disp_rgb),
        .x          (disp_x),
        .y          (disp_y),
        .hsync      (disp_hs),
        .vsync      (disp_vs),
        .de         (disp_de),
        .pixel_valid(disp_pixel_valid),
        .line_start (disp_line_start),
        .frame_start(disp_frame_start),
        .active_frame_start (disp_afs),
        .hblank     (disp_hblank),
        .vblank     (disp_vblank),
        .selected_layer (disp_layer),
        .pix_active_slot (pix_active_slot),
        .pix_generation  (pix_generation),
        .pix_frame_index (),
        .pix_active_valid(pix_active_valid),
        .pix_frame_fault (pix_frame_fault),
        .pix_underflow_count (pix_underflow),
        .pix_missed_frame_count (pix_missed),
        .mem_overflow_count (mem_overflow),
        .mem_fifo_pixels (pix_fifo_level),
        .mem_dma_bytes  (mem_dma_bytes),
        .mem_dma_active (mem_dma_active),
        .mem_dma_done   (mem_dma_done),
        .mem_fetch_state(mem_fetch_state)
    );

    // ========================================================================
    // 卷构造（直接写进卡模型）
    // ========================================================================
    task mbr_set_card0;
        begin
            // 注意：**不要**清 u_card.sector[]（它是未映射扇区的兜底图案）。
            // 只覆盖 MBR 用到的几个偏移。
            u_card.sector[450] = 8'h0C;              // FAT32 XINT13
            u_card.sector[454] = VOL_BASE[7:0];      // 分区起始 LBA（小端）
            u_card.sector[455] = VOL_BASE[15:8];
            u_card.sector[456] = VOL_BASE[23:16];
            u_card.sector[457] = VOL_BASE[31:24];
            u_card.sector[458] = 8'h00;              // 分区扇区数 = 0x00010000
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;
            u_card.sector[511] = 8'hAA;
        end
    endtask

    task build_volume;
        integer c, s, o, j;
        begin
            // DBR（卷 LBA 0）
            u_card.mk_fat32_dbr(16'd512, SPC, RSVD, NFAT, FATSZ, ROOTCLUS, TOTSEC, 1'b1);
            // FAT（卷 LBA 1）：FAT[2]=EOC，FAT[3..58]=next，FAT[59]=EOC
            u_card.vol_zero(VOL_FAT_LBA);
            u_card.vol_set_le(VOL_FAT_LBA, 16'd8, 32'h0FFF_FFFF, 3'd4);   // FAT[2]
            for (c = 3; c <= FILE_CLUS_LAST - 1; c = c + 1)
                u_card.vol_set_le(VOL_FAT_LBA, c * 4, c + 1, 3'd4);
            u_card.vol_set_le(VOL_FAT_LBA, FILE_CLUS_LAST * 4, 32'h0FFF_FFFF, 3'd4); // FAT[59]
            // 根目录（卷 LBA 2）：4 条目录项 + 0x00 终止
            u_card.vol_zero(VOL_ROOT_LBA);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd0,  "SV0001  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd32, "SV0002  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd64, "SV0003  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            u_card.mk_dir_entry(VOL_ROOT_LBA, 16'd96, "SV0004  BMP", 8'h20, FILE_CLUS, FILE_BYTES);
            // ★★ 文件主体：把**整幅 921654 字节真 BMP** 写进卷。
            //    文件占 1801 个扇区，簇连续 ⇒ 文件扇区号 s 对应卷内 LBA = 34 + s。
            //    每个扇区整扇区写（末尾不足部分补 0），避免 vol[] 里残留 x。
            for (s = 0; s < FILE_SECTORS; s = s + 1) begin
                u_card.vol_used[VOL_FILE0_LBA + s] = 1'b1;
                for (o = 0; o < 512; o = o + 1) begin
                    j = s*512 + o;
                    u_card.vol[(VOL_FILE0_LBA + s)*512 + o] = (j < FILE_BYTES) ? filebyte(j) : 8'h00;
                end
            end
            // MBR（卡 LBA 0 -> 卡模型默认 sector[] 区）
            mbr_set_card0;
        end
    endtask

    // ========================================================================
    // 监视器
    // ========================================================================
    // 目录项计数（scanner -> file_index）
    integer ent_count = 0;
    reg [87:0] ent0_name;
    reg [31:0] ent0_clus, ent0_size;
    reg [7:0]  ent0_attr;
    always @(posedge clk_mem) begin
        if (rst_n && ent_valid && ent_ready) begin
            if (ent_count == 0) begin
                ent0_name = ent_name; ent0_attr = ent_attr;
                ent0_clus = ent_first_clus; ent0_size = ent_size;
            end
            ent_count = ent_count + 1;
        end
    end

    // file_streamer 逐字节比对卡上文件
    integer fst_got = 0, fst_mism = 0, fst_sof_n = 0, fst_eof_n = 0;
    integer fst_first_bad = -1;
    always @(posedge clk_mem) begin
        if (rst_n && fst_valid && bp_ready) begin
            if (fst_sof) fst_sof_n = fst_sof_n + 1;
            if (fst_data !== filebyte(fst_got)) begin
                fst_mism = fst_mism + 1;
                if (fst_first_bad < 0) begin
                    fst_first_bad = fst_got;
                    $display("[INFO] stream mismatch @%0d got=%02x want=%02x",
                             fst_got, fst_data, filebyte(fst_got));
                end
            end
            if (fst_eof) fst_eof_n = fst_eof_n + 1;
            fst_got = fst_got + 1;
        end
    end

    // bmp_unpack 输出像素逐点比对（RGB565）
    integer u_pix_n = 0, u_pix_bad = 0;
    integer u_pix_sof_n = 0;
    always @(posedge clk_mem) begin
        if (rst_n && bpu_valid) begin
            if (bpu_sof) u_pix_sof_n = u_pix_sof_n + 1;
            if (bpu_pixel !== exp565_n(u_pix_n)) begin
                u_pix_bad = u_pix_bad + 1;
                if (u_pix_bad <= 5)
                    $display("[INFO] unpack pixel mismatch @%0d (x=%0d y=%0d) got=%04x want=%04x",
                             u_pix_n, bpu_x, bpu_y, bpu_pixel, exp565_n(u_pix_n));
            end
            u_pix_n = u_pix_n + 1;
        end
    end

    // 单周期脉冲锁存
    reg idx_done_lat = 1'b0;
    reg bmp_cd_lat   = 1'b0;
    always @(posedge clk_mem) begin
        if (rst_n && idx_done)       idx_done_lat <= 1'b1;
        if (rst_n && bmp_check_done) bmp_cd_lat   <= 1'b1;
    end

    // ========================================================================
    // 显示侧断言：屏幕像素 == 源 BMP 像素
    //   A 的 core 内部有固定的图层延迟（最终 5 拍），但输出的 `x`/`y` **本身就是
    //   延迟后的扫描坐标**（rgb 与 x/y/de 同拍）⇒ 直接比对，不要再给期望加延迟。
    // ========================================================================
    integer pix_ok = 0, pix_bad = 0;
    integer frame_no = 0;
    reg        comparing = 1'b0;

    always @(posedge clk_pix) begin
        if (!rst_n) begin
            comparing <= 1'b0;
        end else begin
            if (pix_active_valid) comparing <= 1'b1;
            if (comparing && disp_de && (disp_x < W) && (disp_y < H)) begin
                if (disp_rgb[23:0] === expand565(px565(disp_x, disp_y))) pix_ok = pix_ok + 1;
                else begin
                    pix_bad = pix_bad + 1;
                    if (pix_bad <= 3)
                        $display("[INFO] pixel mismatch @(%0d,%0d) got=%h want=%h",
                                 disp_x, disp_y, disp_rgb[23:0],
                                 expand565(px565(disp_x, disp_y)));
                end
            end
            if (disp_frame_start) frame_no = frame_no + 1;
        end
    end

    // ========================================================================
    // 主流程
    // ========================================================================
    integer wait_cnt;
    initial begin
        errors = 0;
        rst_n = 1'b0;
        init_start = 1'b0; mp_start = 1'b0; bp_start = 1'b0;
        scan_en = 1'b0; idx_clear = 1'b0; idx_commit = 1'b0;
        fst_start = 1'b0; fst_first_clus = 32'd0; fst_file_size = 32'd0;
        phase = PH_MBR;

        // 卡模型 initial 块跑完后再构造卷
        #500;
        build_volume;
        #100;
        rst_n = 1'b1;
        repeat (10) @(posedge clk_mem);

        // ---- 前段 1) SD 初始化 -------------------------------------------
        @(posedge clk_mem); init_start = 1'b1;
        @(posedge clk_mem); init_start = 1'b0;
        wait_cnt = 0;
        while (!(init_done || init_error) && wait_cnt < 20_000_000) begin
            @(posedge clk_mem); wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk_mem);
        check(init_done === 1'b1, "F1) SD 初始化成功（CMD0/CMD8/ACMD41/CMD58）");

        // ---- 前段 2) MBR --------------------------------------------------
        phase = PH_MBR;
        @(posedge clk_mem); mp_start = 1'b1;
        @(posedge clk_mem); mp_start = 1'b0;
        wait_cnt = 0;
        while (!mp_done && wait_cnt < 20_000_000) begin @(posedge clk_mem); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk_mem);
        check(mp_done === 1'b1,           "F2) mbr_parser 完成");
        check(mp_ec   === `ERR_NONE,      "F3) mbr_parser 无错");
        check(mp_has  === 1'b1,           "F4) MBR 有效（分区表 + 签名）");
        check(mp_vol_base === VOL_BASE,   "F5) 卷基址 = 分区起始 LBA = 16");
        check(u_card.o_arg === 32'd0,     "F6) mbr_parser 读的是卡 0 号扇区");

        // ---- 前段 3) FAT32 挂载 ------------------------------------------
        phase = PH_BOOT;
        @(posedge clk_mem); bp_start = 1'b1;
        @(posedge clk_mem); bp_start = 1'b0;
        wait_cnt = 0;
        while (!(bp_done || bp_err) && wait_cnt < 20_000_000) begin @(posedge clk_mem); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk_mem);
        check(bp_done === 1'b1,           "F7) fat32_boot_parser 挂载完成");
        check(bp_err  === 1'b0,           "F8) 挂载无错");
        check(bp_bps  === 16'd512,        "F9) BPB BytsPerSec = 512");
        check(bp_spc  === SPC,            "F10) BPB SecPerClus = 32");
        check(bp_nfat === NFAT,           "F11) BPB NumFATs = 1");
        check(bp_fat_lba  === 32'd1,      "F12) FAT 起始（卷内 LBA）= 1");
        check(bp_data_lba === 32'd2,      "F13) 数据区起始 = 2");
        check(bp_root_lba === 32'd2,      "F14) 根目录起始 = 2（RootClus=2）");
        check(bp_tot_clus === 32'd63,     "F15) total_clus = (2048-2)/32 = 63");

        // ---- 前段 4) 根目录扫描 + file_index ------------------------------
        phase = PH_SCAN;
        @(posedge clk_mem); idx_clear = 1'b1;
        @(posedge clk_mem); idx_clear = 1'b0;
        @(posedge clk_mem); scan_en = 1'b1;
        @(posedge clk_mem); scan_en = 1'b0;
        wait_cnt = 0;
        while (!scan_done && wait_cnt < 40_000_000) begin @(posedge clk_mem); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk_mem);
        check(scan_done === 1'b1,         "F16) 根目录扫描完成");
        check(dir_bad   === 1'b0,         "F17) 目录结构正常");
        check(dn_ec     === `ERR_NONE,    "F18) 扫描无错");
        check(ent_count === 4,            "F19) 扫描抛出 4 条目录项");
        check(ent0_name === "SV0001  BMP","F20) 第 0 条名字 = SV0001.BMP");
        check(ent0_clus === FILE_CLUS,    "F21) 第 0 条首簇 = 3");
        check(ent0_size === FILE_BYTES,   "F22) 第 0 条文件大小 = 921654");

        @(posedge clk_mem); idx_commit = 1'b1;
        @(posedge clk_mem); idx_commit = 1'b0;
        wait_cnt = 0;
        while (!idx_done && wait_cnt < 1_000_000) begin @(posedge clk_mem); wait_cnt = wait_cnt + 1; end
        repeat (5) @(posedge clk_mem);
        check(idx_done_lat === 1'b1,      "F23) file_index 提交完成");
        check(file_cnt  === 4'd4,         "F24) 索引表里有 4 幅 BMP");
        check(sel_valid === 1'b1,         "F25) 槽 0 有效");
        check(sel_first_clus === FILE_CLUS, "F26) 槽 0 首簇 = 3");
        check(sel_size === FILE_BYTES,    "F27) 槽 0 大小 = 921654");

        // ---- 启动 frame_writer（它的 din_ready 要求 running）-------------
        repeat (4) @(posedge clk_mem);
        @(negedge clk_mem); fw_start = 1'b1;
        @(negedge clk_mem); fw_start = 1'b0;

        // ---- 前段 5) file_streamer -> bmp_parser -> bmp_unpack ------------
        phase = PH_STREAM;
        @(posedge clk_mem);
        fst_first_clus = sel_first_clus;
        fst_file_size  = sel_size;
        fst_start      = 1'b1;
        @(posedge clk_mem);
        fst_start      = 1'b0;

        wait_cnt = 0;
        while (!(bpu_done || bpu_error || fst_error || bmp_check_error || fw_wr_error)
               && wait_cnt < 400_000_000) begin
            @(posedge clk_mem); wait_cnt = wait_cnt + 1;
        end
        wait_cnt = 0;
        while (!(fw_slot_valid[1] || fw_wr_error) && wait_cnt < 200_000_000) begin
            @(posedge clk_mem); wait_cnt = wait_cnt + 1;
        end
        repeat (20) @(posedge clk_mem);

        // 前段字节流 / 像素
        check(fst_got  === FILE_BYTES,    "F28) file_streamer 恰好输出 921654 字节");
        check(fst_mism === 0,             "F29) ★ 921654 字节逐字节与卡上文件一致（0 错）");
        check(fst_sof_n === 1,            "F30) sof 恰好 1 次");
        check(fst_eof_n === 1,            "F31) eof 恰好 1 次");
        check(fst_error === 1'b0,         "F32) file_streamer 无错");
        check(bmp_cd_lat === 1'b1,        "F33) bmp_parser 头解析完成");
        check(bmp_check_error === 1'b0,   "F34) BMP 头校验通过");
        check(bmp_width  === 16'd640,     "F35) 解析宽度 = 640");
        check(bmp_height === 16'd480,     "F36) 解析高度 = 480（自底向上）");
        check(bmp_bpp === 8'd24,          "F37) 位深 = 24");
        check(u_pix_n === FRAME_PIX,      "F38) bmp_unpack 输出像素数 = 307200");
        check(u_pix_bad === 0,            "F39) ★ 307200 个 RGB565 像素逐个与卡上文件一致（0 错）");

        // ---- 后段（原有断言，逐条保留）-----------------------------------
        check(!bpu_error, "1) bmp_unpack 无错（BMP 头与像素段都被接受）");
        check(bmp_width  == 16'd640, "2) bmp_parser 解析出宽度 = 640");
        check(bmp_height == 16'd480, "3) bmp_parser 解析出高度 = 480");
        check(!bmp_check_error,      "4) BMP 头校验通过");
        check(!fw_wr_error, "5) frame_writer 写帧无错");
        check(fw_px_cnt == `SV_FRAME_PIXELS, "6) frame_writer 写满 307200 像素");
        check(fw_crc_ok == 1'b1, "7) frame_writer CRC 校验通过");
        check(fw_slot_valid[1] == 1'b1, "8) 槽 1 的 slot_valid 置位（A 才允许读）");

        // ---- 触发换帧握手 ------------------------------------------------
        @(negedge clk_sys);
        frame_ready = 1'b1;
        @(negedge clk_sys);
        frame_ready = 1'b0;

        // ★ 等**电平**信号 pix_active_valid，不要等单拍信号 active_commit。
        wait (pix_active_valid);
        // ★ 比对窗口：从"画面已激活"开始，再跨两整帧。
        repeat (2) @(posedge disp_frame_start);
        repeat (2000) @(posedge clk_pix);
        wait (frame_no >= 2);
        repeat (2000) @(posedge clk_pix);

        // ★ 这两条必须放在"跨两整帧之后"：
        //   A 的 core 从 mailbox 到达就激活画面（pix_active_valid），
        //   而 B 的 FSM 要等到下一个垂直消隐才提交（active_commit）——实测差约一帧。
        check(swap_error == 1'b0, "9) 换帧握手无超时");
        check(commits >= 1, "9b) 换帧确实提交了（active_commit 至少 1 次）");
        check(pix_ok > 200000, "10) 显示侧至少比对上 200000 个像素（画面真的出来了）");
        check(pix_bad == 0,    "11) ★ 显示像素与源 BMP 像素逐点一致（0 个不符）");
        check(pix_underflow == 0, "12) 无像素欠流（A 的 underflow 计数 = 0）");
        check(mem_overflow == 0,  "13) 无 FIFO 溢出");
        check(pix_frame_fault == 0, "14) 无帧故障标记");

        $display("[TB] tb_ab_frame_display done, errors=%0d (pix_ok=%0d pix_bad=%0d frames=%0d commits=%0d swap_err=%b stream=%0d stream_mism=%0d u_pix=%0d u_pix_bad=%0d)",
                 errors, pix_ok, pix_bad, frame_no, commits, swap_error,
                 fst_got, fst_mism, u_pix_n, u_pix_bad);
        $finish;
    end

    // ---- 换帧过程诊断（每 1 ms 打一行，只在 frame_ready 之后开始，避免刷屏）----
    reg diag_on = 1'b0;
    always @(posedge clk_sys) if (frame_ready) diag_on <= 1'b1;
    initial begin
        forever begin
            #1_000_000;
            if (diag_on)
                $display("[SWAP] t=%0t st=%0d req=%b fs_b=%b ack_b=%b reqa=%b commits=%0d err=%b | fsB=%0d ackB=%0d",
                         $time, swap_state_o, swap_req_b, fs_evt_b, ack_evt_b, req_evt_a,
                         commits, swap_error,
                         fs_b_pulses, ack_b_pulses);
        end
    end

    // 看门狗（前段 ~0.35 s 仿真 + 两帧扫描，给足 2 s；见 run 脚本说明）
    initial begin
        #2_000_000_000;
        $display("[FAIL] tb_ab_frame_display 看门狗超时（phase=%0d fst_got=%0d fw_px=%0d frames=%0d ok=%0d bad=%0d active=%b swapst=%0d swap_err=%b commits=%0d u_pix=%0d u_pix_bad=%0d）",
                 phase, fst_got, fw_px_cnt, frame_no, pix_ok, pix_bad, pix_active_valid, swap_state_o, swap_error, commits, u_pix_n, u_pix_bad);
        $finish;
    end

    // 进度（每 20 ms 仿真时间打一行，便于定位慢在哪一段）
    initial begin
        forever begin
            #20_000_000;
            $display("[PROG] t=%0t phase=%0d fst_got=%0d fst_mism=%0d u_pix=%0d u_pix_bad=%0d fw_px=%0d slotv=%b active=%b frames=%0d ok=%0d bad=%0d",
                     $time, phase, fst_got, fst_mism, u_pix_n, u_pix_bad, fw_px_cnt, fw_slot_valid,
                     pix_active_valid, frame_no, pix_ok, pix_bad);
        end
    end

endmodule
