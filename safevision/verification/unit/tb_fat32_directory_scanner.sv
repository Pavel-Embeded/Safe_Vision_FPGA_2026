// ============================================================================
// tb_fat32_directory_scanner.v — 阶段 6 第二块：根目录遍历 fat32_directory_scanner
// ----------------------------------------------------------------------------
// 测试卷（刻意做小，卡模型只支持 LBA 0..63）：
//   BytsPerSec=512, SecPerClus=4, RsvdSecCnt=1, NumFATs=1, FATSz32=1,
//   RootClus=2
//     fat_start_lba  = 1
//     data_start_lba = 1 + 1*1 = 2
//     root_dir_lba   = 2 + (2-2)*4 = 2      <- 根目录就在 2 号扇区
//     簇 N 占用的扇区 = 2 + (N-2)*4          <- 簇2 = LBA 2..5，簇3 = LBA 6..9
//   大卷：TotSec32=65536 -> total_clus = (65536-2)/4 = 16383
//   小卷：TotSec32=18    -> total_clus = (18-2)/4    = 4      （判环/越界用）
//
// 验证内容：
//   T21 单扇区正常扫描 + 四类跳过规则（LFN / 卷标 / 删除项 / 子目录）
//   T22 空目录（首槽就是 0x00）
//   T23 簇内无 0x00 -> 去 FAT 查到 EOC 正常收工（跨扇区背靠背，64 条）
//   T24 根目录跨簇（簇2 满 + 簇3 有货），验证簇链跟随与槽位号连续
//   T25 簇链成环 -> DET_FS_LOOP
//   T26 簇号越界 -> DET_DIR_OOB
//   T27 下游反压（ent_ready 按住不放）不丢项、不乱序
//   T28 恢复合法卷后重扫成功（错误可恢复）
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_fat32_directory_scanner;

    localparam [31:0] TOTSEC_BIG  = 32'd65536;   // -> total_clus = 16383
    localparam [31:0] TOTSEC_TINY = 32'd18;      // -> total_clus = 4

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer wait_cnt;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // SPI 四线 + 总线复用（与 tb_fat32_boot_parser 同构）
    // ------------------------------------------------------------------------
    wire sclk, mosi, miso;
    reg  spi_sel;                     // 0 = sd_initializer, 1 = sd_sector_reader

    wire        init_cs_n, init_tx_valid;
    wire [7:0]  init_tx_data;
    wire [15:0] init_clk_div;
    wire        rd_cs_n, rd_tx_valid;
    wire [7:0]  rd_tx_data;
    wire [15:0] rd_clk_div;

    wire        spi_cs_n    = spi_sel ? rd_cs_n    : init_cs_n;
    wire [15:0] spi_clk_div = spi_sel ? rd_clk_div : init_clk_div;
    wire        spi_tx_valid= spi_sel ? rd_tx_valid: init_tx_valid;
    wire [7:0]  spi_tx_data = spi_sel ? rd_tx_data : init_tx_data;

    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;

    spi_master u_spi (
        .clk(clk), .rst_n(rst_n), .clk_div(spi_clk_div), .cs_n(spi_cs_n),
        .tx_valid(spi_tx_valid), .tx_data(spi_tx_data), .tx_ready(spi_tx_ready),
        .rx_data(spi_rx_data), .rx_valid(spi_rx_valid), .busy(spi_busy),
        .sclk(sclk), .mosi(mosi), .miso(miso)
    );

    // ------------------------------------------------------------------------
    // sd_initializer
    // ------------------------------------------------------------------------
    reg  init_start;
    wire init_done, init_error, sdhc;
    wire [7:0] init_ec, init_ed, init_rc;

    sd_initializer u_init (
        .clk(clk), .rst_n(rst_n), .start(init_start),
        .sdhc(sdhc), .init_done(init_done), .init_error(init_error),
        .err_code(init_ec), .err_detail(init_ed), .retry_cnt(init_rc), .dbg_state(),
        .spi_cs_n(init_cs_n), .spi_clk_div(init_clk_div),
        .spi_tx_valid(init_tx_valid), .spi_tx_data(init_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // sd_sector_reader ← 由 fat32_boot_parser / fat32_directory_scanner 分时占用
    //   注：两者共用一个读口会互相打架，本 TB 里让 fat32_directory_scanner 独占、
    //       fat32_boot_parser 只在 do_mount 期间用——两者不会同时发请求。
    //       真实顶层会加一个 rd 仲裁器，那是后续阶段的事。
    // ------------------------------------------------------------------------
    reg         rd_sel;               // 0 = fat32_boot_parser 发起, 1 = 目录遍历侧

    wire        m_rd_en,  d_rd_en,  w_rd_en;
    wire [31:0] m_rd_addr, d_rd_addr, w_rd_addr;
    wire [15:0] m_rd_len,  d_rd_len,  w_rd_len;
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to_err, rd_crc16_err;
    wire [7:0]  rd_ec, rd_ed;
    wire        mnt_data_ready, dir_data_ready, wk_data_ready;

    // ---- fat32_cluster_walker：跳簇逻辑与 file_streamer 共用同一个模块 ----
    wire [31:0] wk_cur_clus, wk_next_clus;
    wire        wk_start, wk_rst_walk, wk_busy, wk_done, wk_eoc, wk_error;
    wire [7:0]  wk_ec, wk_ed;

    // walker busy 时把总线让给它；遍历目录的 scanner 这时不发读请求
    wire        bus_wk = wk_busy && rd_sel;

    wire        fs_rd_en   = rd_sel ? (bus_wk ? w_rd_en   : d_rd_en)   : m_rd_en;
    wire [31:0] fs_rd_addr = rd_sel ? (bus_wk ? w_rd_addr : d_rd_addr) : m_rd_addr;
    wire [15:0] fs_rd_len  = rd_sel ? (bus_wk ? w_rd_len  : d_rd_len)  : m_rd_len;

    // 数据选择：谁在收就听谁的 data_ready
    wire rd_data_ready = rd_sel ? (bus_wk ? wk_data_ready : dir_data_ready) : mnt_data_ready;

    // fat32_directory_scanner 的候选目录项输出
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid;
    wire        scan_done, dir_bad;
    wire [7:0]  dir_ec, dir_ed;
    wire [3:0]  dir_dbg;

    sd_sector_reader u_rd (
        .clk(clk), .rst_n(rst_n), .sdhc(sdhc),
        .rd_en(fs_rd_en), .rd_addr(fs_rd_addr), .rd_len(fs_rd_len), .rd_ready(rd_ready),
        .data(rd_data), .data_valid(rd_data_valid), .data_ready(rd_data_ready),
        .data_last(rd_data_last),
        .rd_done(rd_done), .busy(), .timeout_err(rd_to_err), .crc16_err(rd_crc16_err),
        .err_code(rd_ec), .err_detail(rd_ed), .crc_rx(), .dbg_state(),
        .spi_cs_n(rd_cs_n), .spi_clk_div(rd_clk_div),
        .spi_tx_valid(rd_tx_valid), .spi_tx_data(rd_tx_data),
        .spi_tx_ready(spi_tx_ready), .spi_rx_data(spi_rx_data), .spi_rx_valid(spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // DUT: fat32_boot_parser
    // ------------------------------------------------------------------------
    reg  mnt_start;
    wire mnt_done, mnt_err;
    wire [7:0] mnt_ec, mnt_ed;
    wire [15:0] o_bps;
    wire [7:0]  o_spc, o_nfat;
    wire [31:0] o_fat_lba, o_root_clus, o_root_lba, o_data_lba, o_tot_sec, o_tot_clus;

    fat32_boot_parser u_mnt (
        .clk(clk), .rst_n(rst_n), .start(mnt_start),
        .mount_done(mnt_done), .mount_error(mnt_err),
        .err_code(mnt_ec), .err_detail(mnt_ed), .dbg_state(),
        .bytes_per_sec(o_bps), .sec_per_clus(o_spc), .num_fats(o_nfat),
        .fat_start_lba(o_fat_lba), .root_clus(o_root_clus),
        .root_dir_lba(o_root_lba), .data_start_lba(o_data_lba),
        .total_sec(o_tot_sec), .total_clus(o_tot_clus),
        .sd_rd_addr(m_rd_addr), .sd_rd_len(m_rd_len), .sd_rd_en(m_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(mnt_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ------------------------------------------------------------------------
    // DUT: fat32_directory_scanner
    // ------------------------------------------------------------------------
    reg  scan_start;
    reg  ent_ready;

    fat32_directory_scanner u_dir (
        .clk(clk), .rst_n(rst_n),
        .scan_en(scan_start), .scan_done(scan_done), .dir_bad(dir_bad),
        .err_code(dir_ec), .err_detail(dir_ed), .dbg_state(dir_dbg),
        .sec_per_clus(o_spc), .root_clus(o_root_clus),
        .root_dir_lba(o_root_lba), .data_start_lba(o_data_lba),
        .ent_name(ent_name), .ent_attr(ent_attr), .ent_first_clus(ent_first_clus),
        .ent_size(ent_size), .ent_index(ent_index),
        .ent_valid(ent_valid), .ent_ready(ent_ready),
        .sd_rd_addr(d_rd_addr), .sd_rd_len(d_rd_len), .sd_rd_en(d_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(dir_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed),
        .wk_cur_clus(wk_cur_clus), .wk_start(wk_start), .wk_rst_walk(wk_rst_walk),
        .wk_busy(wk_busy), .wk_done(wk_done), .wk_next_clus(wk_next_clus),
        .wk_eoc(wk_eoc), .wk_error(wk_error),
        .wk_err_code(wk_ec), .wk_err_detail(wk_ed)
    );

    fat32_cluster_walker u_walker (
        .clk(clk), .rst_n(rst_n),
        .rst_walk(wk_rst_walk), .start(wk_start), .cur_clus(wk_cur_clus),
        .busy(wk_busy), .done(wk_done), .next_clus(wk_next_clus),
        .eoc(wk_eoc), .error(wk_error), .err_code(wk_ec), .err_detail(wk_ed),
        .hop_cnt(), .dbg_state(),
        .fat_start_lba(o_fat_lba), .total_clus(o_tot_clus),
        .sd_rd_addr(w_rd_addr), .sd_rd_len(w_rd_len), .sd_rd_en(w_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(wk_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ------------------------------------------------------------------------
    // 目录项收集（模拟 file_index 侧：下游一直 ready）
    // ------------------------------------------------------------------------
    reg [87:0] got_name [0:127];
    reg [15:0] got_idx  [0:127];
    reg [31:0] got_clus [0:127];
    reg [31:0] got_size [0:127];
    reg [7:0]  got_attr [0:127];
    integer    got_n;

    always @(posedge clk) begin
        if (ent_valid === 1'b1 && ent_ready === 1'b1) begin
            if (got_n < 128) begin
                got_name[got_n] = ent_name;
                got_idx [got_n] = ent_index;
                got_clus[got_n] = ent_first_clus;
                got_size[got_n] = ent_size;
                got_attr[got_n] = ent_attr;
            end
            got_n = got_n + 1;
        end
    end

    // ------------------------------------------------------------------------
    // 卡模型
    // ------------------------------------------------------------------------
    wire [5:0]  card_cmd;
    wire [31:0] card_arg;

    sd_spi_card_model u_card (
        .sclk(sclk), .cs_n(spi_cs_n), .mosi(mosi), .miso(miso),
        .i_dead(1'b0),
        .o_cmd(card_cmd), .o_arg(card_arg), .o_acmd41_arg(),
        .o_cmd_cnt(), .o_acmd41_cnt(), .o_cmd_valid()
    );

    wire [31:0] last_lba = card_arg;       // 最近一条命令的块号

    // ------------------------------------------------------------------------
    // 建卷 / 流程封装
    // ------------------------------------------------------------------------
    // 一份"微型 FAT32 卷"：DBR(0) + FAT 表(1) + 数据区从 2 开始
    task mk_vol;
        input [31:0] totsec;
        input [31:0] fat2;          // FAT[2] 的值
        input [31:0] fat3;          // FAT[3] 的值
        begin
            u_card.mk_fat32_dbr(16'd512, 8'd4, 16'd1, 8'd1,
                                32'd1, 32'd2, totsec, 1'b1);
            u_card.vol_zero(32'd1);
            u_card.vol_set_le(32'd1, 16'd8,  fat2, 3'd4);
            u_card.vol_set_le(32'd1, 16'd12, fat3, 3'd4);
        end
    endtask

    task do_mount;
        begin
            rd_sel = 1'b0;
            @(posedge clk); mnt_start = 1'b1;
            @(posedge clk); mnt_start = 1'b0;
            repeat (10) @(posedge clk);
            wait_cnt = 0;
            while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            repeat (5) @(posedge clk);
        end
    endtask

    task do_scan;
        begin
            rd_sel = 1'b1;
            got_n  = 0;
            @(posedge clk); scan_start = 1'b1;
            @(posedge clk); scan_start = 1'b0;
            repeat (10) @(posedge clk);      // 等 scan_done 被清零
            wait_cnt = 0;
            while (!(scan_done === 1'b1) && wait_cnt < 4_000_000) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end
            repeat (10) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // 激励
    // ------------------------------------------------------------------------
    initial begin
        errors     = 0;
        spi_sel    = 1'b0;
        init_start = 1'b0;
        mnt_start  = 1'b0;
        scan_start = 1'b0;
        ent_ready  = 1'b1;
        rd_sel     = 1'b0;
        got_n      = 0;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ====================================================================
        // 前置：SD 初始化（卡模型用默认"理想卡"）
        // ====================================================================
        $display("\n==== 前置：SD 初始化 ====");
        @(posedge clk);
        init_start = 1'b1;
        @(posedge clk);
        init_start = 1'b0;
        wait_cnt = 0;
        while (!(init_done === 1'b1 || init_error === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);
        check(init_done === 1'b1, "P1 SD 初始化成功");
        check(sdhc === 1'b1,      "P2 识别为 SDHC");
        spi_sel = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        // T21 单扇区扫描 + 四类跳过规则
        // ====================================================================
        $display("\n==== T21: 正常扫描 + 跳过规则 ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);   // 簇2 -> EOC
        // 根目录簇2 = LBA 2..5；只在 2 号扇区放货，其余清零（首字节 0x00 收工）
        u_card.vol_zero(32'd2);
        u_card.vol_zero(32'd3);
        u_card.vol_zero(32'd4);
        u_card.vol_zero(32'd5);
        u_card.mk_dir_entry(32'd2, 16'd0,   "LONGFILEBMP", 8'h0F, 32'd0,   32'd0);
        u_card.mk_dir_entry(32'd2, 16'd32,  "SV0001  BMP", 8'h20, 32'd100, 32'd307266);
        u_card.mk_dir_entry(32'd2, 16'd64,  "MYLABEL    ", 8'h08, 32'd0,   32'd0);
        u_card.mk_dir_entry(32'd2, 16'd96,  "SV0009  BMP", 8'h20, 32'd900, 32'd307266);
        u_card.vol_set(32'd2, 16'd96, 8'hE5);                       // 该槽改成"已删除"
        u_card.mk_dir_entry(32'd2, 16'd128, "SUBDIR     ", 8'h10, 32'd50,  32'd0);
        u_card.mk_dir_entry(32'd2, 16'd160, "SV0002  BMP", 8'h20, 32'd200, 32'd307266);

        do_mount;
        check(mnt_done === 1'b1,   "T21.1 挂载成功");
        check(o_data_lba === 32'd2, "T21.2 data_start_lba = 2");
        check(o_root_lba === 32'd2, "T21.3 root_dir_lba = 2");

        do_scan;
        check(scan_done === 1'b1,          "T21.4 scan_done 拉高");
        check(dir_bad  === 1'b0,           "T21.5 目录结构无异常");
        check(dir_ec   === `ERR_NONE,      "T21.6 无错误码");
        check(got_n == 2,                  "T21.7 只抛出 2 条（四类跳过项全被滤掉）");
        check(got_name[0] === "SV0001  BMP", "T21.8 第1条名字 = SV0001.BMP");
        check(got_attr[0] === 8'h20,       "T21.9 第1条属性 = 0x20(归档)");
        check(got_clus[0] === 32'd100,     "T21.10 第1条首簇 = 100");
        check(got_size[0] === 32'd307266,  "T21.11 第1条大小 = 307266");
        check(got_idx [0] === 16'd1,       "T21.12 第1条槽位 = 1（槽0 是 LFN）");
        check(got_name[1] === "SV0002  BMP", "T21.13 第2条名字 = SV0002.BMP");
        check(got_clus[1] === 32'd200,     "T21.14 第2条首簇 = 200");
        check(got_idx [1] === 16'd5,       "T21.15 第2条槽位 = 5（中间跳过3条）");
        check(last_lba === 32'd2,          "T21.16 见到 0x00 后没有再读后面的扇区");

        // ====================================================================
        // T22 空目录
        // ====================================================================
        $display("\n==== T22: 空目录 ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);
        u_card.vol_zero(32'd2);
        u_card.vol_zero(32'd3);
        u_card.vol_zero(32'd4);
        u_card.vol_zero(32'd5);
        do_mount;
        do_scan;
        check(scan_done === 1'b1,     "T22.1 空目录也能正常收工");
        check(got_n == 0,             "T22.2 一条都不抛");
        check(dir_bad === 1'b0,       "T22.3 不算异常");
        check(dir_ec  === `ERR_NONE,  "T22.4 无错误码");

        // ====================================================================
        // T23 簇内没有 0x00 -> 查 FAT 得 EOC（跨扇区背靠背 + 高 16 位首簇）
        // ====================================================================
        $display("\n==== T23: 簇满 + FAT=EOC ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);
        u_card.mk_dir_fill(32'd2, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd3, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd4, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd5, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        do_mount;
        do_scan;
        check(scan_done === 1'b1,              "T23.1 走完4个扇区后正常收工");
        check(dir_bad === 1'b0,                "T23.2 无结构异常");
        check(got_n == 64,                     "T23.3 一个簇 4 扇区 = 64 条全抛出");
        check(got_name[63] === "DUMMY0  BMP",  "T23.4 最后一条来自第4个扇区");
        check(got_idx[63] === 16'd63,          "T23.5 槽位号跨扇区连续");
        check(got_clus[0] === 32'h0001_0002,   "T23.6 首簇高16位(0x0001)拼装正确");
        check(got_size[0] === 32'd512,         "T23.7 文件大小拼装正确");

        // ====================================================================
        // T24 根目录跨簇：簇2(64条) -> FAT 指到簇3 -> 簇3 第2槽 0x00
        // ====================================================================
        $display("\n==== T24: 根目录跨簇 ====");
        mk_vol(TOTSEC_BIG, 32'd3, 32'h0FFF_FFFF);   // FAT[2]=3, FAT[3]=EOC
        u_card.mk_dir_fill(32'd2, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd3, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd4, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd5, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.vol_zero(32'd6);                      // 簇3 起始扇区
        u_card.mk_dir_entry(32'd6, 16'd0, "SV0007  BMP", 8'h20, 32'd700, 32'd307266);
        do_mount;
        do_scan;
        check(scan_done === 1'b1,               "T24.1 跨簇遍历正常收工");
        check(dir_bad === 1'b0,                 "T24.2 无结构异常");
        check(got_n == 65,                      "T24.3 64(簇2) + 1(簇3) = 65 条");
        check(got_name[64] === "SV0007  BMP",   "T24.4 跨簇那一条被抛出来了");
        check(got_clus[64] === 32'd700,         "T24.5 跨簇那一条首簇正确");
        check(got_idx [64] === 16'd64,          "T24.6 槽位号跨簇继续累加");
        check(last_lba === 32'd6,               "T24.7 卡侧确实读到簇3首个扇区(LBA 6)");

        // ====================================================================
        // T25 簇链成环
        // ====================================================================
        $display("\n==== T25: 簇链成环 ====");
        mk_vol(TOTSEC_TINY, 32'd2, 32'h0FFF_FFFF);   // total_clus=4；FAT[2]=2 自环
        u_card.mk_dir_fill(32'd2, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd3, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd4, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd5, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        do_mount;
        check(o_tot_clus === 32'd4, "T25.1 小卷 total_clus = 4");
        do_scan;
        check(scan_done === 1'b1,             "T25.2 出错时也算遍历结束");
        check(dir_bad   === 1'b1,             "T25.3 dir_bad 拉高");
        check(dir_ec    === `ERR_MEDIA_INVALID, "T25.4 主码 = 0x03(媒体文件非法)");
        check(dir_ed    === `DET_FS_LOOP,     "T25.5 细分码 = 0x34(簇链成环)");

        // ====================================================================
        // T26 簇号越界
        // ====================================================================
        $display("\n==== T26: 簇号越界 ====");
        mk_vol(TOTSEC_TINY, 32'd6, 32'h0FFF_FFFF);   // total_clus=4 -> 合法簇 2..5
        u_card.mk_dir_fill(32'd2, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd3, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd4, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        u_card.mk_dir_fill(32'd5, "DUMMY0  BMP", 8'h20, 32'h0001_0002, 32'd512);
        do_mount;
        do_scan;
        check(dir_bad === 1'b1,               "T26.1 dir_bad 拉高");
        check(dir_ed  === `DET_DIR_OOB,       "T26.2 细分码 = 0x33(目录项越界)");
        check(dir_ec  === `ERR_MEDIA_INVALID, "T26.3 主码 = 0x03");

        // ====================================================================
        // T27 下游反压：ent_ready 按住不放
        // ====================================================================
        $display("\n==== T27: 下游反压 ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);
        u_card.vol_zero(32'd2);
        u_card.mk_dir_entry(32'd2, 16'd0, "SV0001  BMP", 8'h20, 32'd100, 32'd307266);
        u_card.mk_dir_entry(32'd2, 16'd32,"SV0002  BMP", 8'h20, 32'd200, 32'd307266);
        do_mount;

        rd_sel   = 1'b1;
        got_n    = 0;
        ent_ready = 1'b0;                 // 按住下游
        @(posedge clk); scan_start = 1'b1;
        @(posedge clk); scan_start = 1'b0;
        wait_cnt = 0;
        while (!(ent_valid === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (200) @(posedge clk);
        check(ent_valid === 1'b1,        "T27.1 反压期间 ent_valid 一直保持");
        check(ent_index === 16'd0,       "T27.2 反压期间数据不乱（槽位号稳定）");
        check(got_n == 0,                "T27.3 下游没确认就不算送达");
        check(ent_name === "SV0001  BMP","T27.4 反压期间名字不变");

        @(negedge clk); // Change ready away from DUT/monitor sampling edge.
        ent_ready = 1'b1;                 // 放开
        wait_cnt = 0;
        while (!(scan_done === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (10) @(posedge clk);
        check(scan_done === 1'b1,        "T27.5 放开反压后能跑完");
        check(got_n == 2,                "T27.6 两条一条不少");
        check(got_name[0] === "SV0001  BMP", "T27.7 顺序没乱：第1条");
        check(got_name[1] === "SV0002  BMP", "T27.8 顺序没乱：第2条");

        // ====================================================================
        // T28 恢复合法卷后重扫成功
        // ====================================================================
        $display("\n==== T28: 恢复后重扫 ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);
        u_card.vol_zero(32'd2);
        u_card.mk_dir_entry(32'd2, 16'd0, "SV0003  BMP", 8'h20, 32'd300, 32'd307266);
        do_mount;
        do_scan;
        check(scan_done === 1'b1,       "T28.1 重扫成功");
        check(dir_bad === 1'b0,         "T28.2 dir_bad 已清零");
        check(dir_ec  === `ERR_NONE,    "T28.3 错误码已清零");
        check(got_n == 1,               "T28.4 抛出 1 条");
        check(got_clus[0] === 32'd300,  "T28.5 首簇正确");

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #300_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule
