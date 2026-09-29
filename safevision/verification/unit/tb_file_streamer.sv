// ============================================================================
// tb_file_streamer.sv — 阶段 7：簇链 -> 字节流
// ----------------------------------------------------------------------------
// 被测：rtl/storage/file_streamer.v + rtl/storage/fat32_cluster_walker.v
//       （挂在真实的 spi_master + sd_initializer + sd_sector_reader + 卡模型上）
//
// 测试卷（同 tb_fat32_directory_scanner）：
//   BytsPerSec=512, SecPerClus=4, RsvdSecCnt=1, NumFATs=1, FATSz32=1, RootClus=2
//     fat_start_lba = 1, data_start_lba = 2, root_dir_lba = 2
//     簇 N 的扇区 = 2 + (N-2)*4     簇2 = LBA 2..5，簇3 = LBA 6..9
//
// ★ 数据来源很省事：LBA 2 及以上都不显式写，卡模型会回落到默认图案
//   sector[k] = k + 0x11。所以"文件第 j 个字节的期望值"就是
//   ((j % 512) + 0x11) & 0xFF —— 与具体 LBA 无关，跨簇也成立。
//
// 验证内容：
//   T31 单簇文件（2048 B）：内容逐字节比对 + sof/eof 各一次
//   T32 跨簇文件（4096 B）：内容逐字节比对
//   T33 非整簇结尾（3000 B）：只发 3000 字节，一个不多
//   T34 文件比簇链长（要 5000 只有 4096）-> EOC 提前 -> DET_FS_SHORT
//   T35 簇链成环 -> DET_FS_LOOP
//   T36 簇号越界 -> DET_DIR_OOB
//   T37 下游反压：内容仍全对、bytes_rd 正确
//   T38 file_size = 0：一个字节都不发，也不发 sof/eof
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_file_streamer;

    localparam [31:0] TOTSEC_BIG  = 32'd65536;   // -> total_clus = 16383
    localparam [31:0] TOTSEC_TINY = 32'd18;      // -> total_clus = 4

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors;
    integer wait_cnt;
    integer i;

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
    // SPI 四线
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

    spi_master u_spi (
        .clk(clk), .rst_n(rst_n), .clk_div(spi_clk_div), .cs_n(spi_cs_n),
        .tx_valid(spi_tx_valid), .tx_data(spi_tx_data), .tx_ready(spi_tx_ready),
        .rx_data(spi_rx_data), .rx_valid(spi_rx_valid), .busy(),
        .sclk(sclk), .mosi(mosi), .miso(miso)
    );

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
    // sd_sector_reader：被 fat32_boot_parser / fat32_cluster_walker /
    //                   file_streamer 三者分时占用
    //   - mount 期间走 parser
    //   - file_streamer 在"查下一个簇"时会进 F_WALK，此时总线的使用权交给 walker
    //     用 walker 的 busy 做选择即可：walk 期间 file_streamer 不发读请求
    // ------------------------------------------------------------------------
    reg         rd_sel;               // 0 = parser, 1 = walker/file_streamer 侧

    wire        p_rd_en,  f_rd_en,  w_rd_en;
    wire [31:0] p_rd_addr, f_rd_addr, w_rd_addr;
    wire [15:0] p_rd_len,  f_rd_len,  w_rd_len;
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_to_err, rd_crc16_err;
    wire [7:0]  rd_ec, rd_ed;
    wire        p_data_ready, f_data_ready, w_data_ready;

    wire        wk_busy;

    // walker busy 时把总线给 walker，否则给 file_streamer；mount 期间给 parser
    wire        bus_wk = wk_busy && spi_sel;
    wire        fs_rd_en   = rd_sel ? (bus_wk ? w_rd_en   : f_rd_en)   : p_rd_en;
    wire [31:0] fs_rd_addr = rd_sel ? (bus_wk ? w_rd_addr : f_rd_addr) : p_rd_addr;
    wire [15:0] fs_rd_len  = rd_sel ? (bus_wk ? w_rd_len  : f_rd_len)  : p_rd_len;
    wire        rd_data_ready = rd_sel ? (bus_wk ? w_data_ready : f_data_ready) : p_data_ready;

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
    // fat32_boot_parser（只为了拿到 fat_start_lba / data_start_lba / total_clus）
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
        .sd_rd_addr(p_rd_addr), .sd_rd_len(p_rd_len), .sd_rd_en(p_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(p_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ------------------------------------------------------------------------
    // DUT: fat32_cluster_walker
    // ------------------------------------------------------------------------
    wire [31:0] wk_cur_clus, wk_next_clus, wk_hop;
    wire        wk_start, wk_rst_walk, wk_done, wk_eoc, wk_error;
    wire [7:0]  wk_ec, wk_ed;

    fat32_cluster_walker u_walker (
        .clk(clk), .rst_n(rst_n),
        .rst_walk(wk_rst_walk), .start(wk_start), .cur_clus(wk_cur_clus),
        .busy(wk_busy), .done(wk_done), .next_clus(wk_next_clus),
        .eoc(wk_eoc), .error(wk_error), .err_code(wk_ec), .err_detail(wk_ed),
        .hop_cnt(wk_hop), .dbg_state(),
        .fat_start_lba(o_fat_lba), .total_clus(o_tot_clus),
        .sd_rd_addr(w_rd_addr), .sd_rd_len(w_rd_len), .sd_rd_en(w_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(w_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ------------------------------------------------------------------------
    // DUT: file_streamer
    // ------------------------------------------------------------------------
    reg  fs_start;
    reg  [31:0] fs_first_clus, fs_file_size;
    reg  fs_ready;
    wire [7:0] fs_data;
    wire fs_valid, fs_sof, fs_eof, fs_busy, fs_done, fs_error;
    wire [7:0] fs_ec, fs_ed;
    wire [31:0] fs_bytes;
    wire [3:0] fs_dbg;

    file_streamer u_fs (
        .clk(clk), .rst_n(rst_n),
        .start(fs_start), .first_clus(fs_first_clus), .file_size(fs_file_size),
        .busy(fs_busy), .done(fs_done), .error(fs_error),
        .err_code(fs_ec), .err_detail(fs_ed), .bytes_rd(fs_bytes), .dbg_state(fs_dbg),
        .data(fs_data), .valid(fs_valid), .ready(fs_ready), .sof(fs_sof), .eof(fs_eof),
        .sec_per_clus(o_spc), .fat_start_lba(o_fat_lba),
        .data_start_lba(o_data_lba), .total_clus(o_tot_clus),
        .wk_cur_clus(wk_cur_clus), .wk_start(wk_start), .wk_rst_walk(wk_rst_walk),
        .wk_busy(wk_busy), .wk_done(wk_done), .wk_next_clus(wk_next_clus),
        .wk_eoc(wk_eoc), .wk_error(wk_error),
        .wk_err_code(wk_ec), .wk_err_detail(wk_ed),
        .sd_rd_addr(f_rd_addr), .sd_rd_len(f_rd_len), .sd_rd_en(f_rd_en),
        .sd_rd_ready(rd_ready), .sd_data(rd_data), .sd_data_valid(rd_data_valid),
        .sd_data_ready(f_data_ready), .sd_data_last(rd_data_last),
        .sd_rd_done(rd_done), .sd_timeout_err(rd_to_err), .sd_crc16_err(rd_crc16_err),
        .sd_err_code(rd_ec), .sd_err_detail(rd_ed)
    );

    // ------------------------------------------------------------------------
    // 字节流监视器：逐字节比对 + sof/eof 计数
    // ------------------------------------------------------------------------
    integer got_n;            // 收到的字节数
    integer mism;             // 内容不符个数
    integer sof_n, eof_n;     // sof / eof 出现次数
    integer eof_at;           // eof 出现时已收字节数

    always @(posedge clk) begin
        if (fs_valid === 1'b1 && fs_ready === 1'b1) begin
            if (fs_sof === 1'b1) sof_n = sof_n + 1;
            if (fs_data !== (((got_n % 512) + 17) & 255)) mism = mism + 1;
            got_n = got_n + 1;
            if (fs_eof === 1'b1) begin
                eof_n  = eof_n + 1;
                eof_at = got_n;
            end
        end
    end

    task clear_mon;
        begin
            got_n  = 0;
            mism   = 0;
            sof_n  = 0;
            eof_n  = 0;
            eof_at = 0;
        end
    endtask

    // ------------------------------------------------------------------------
    // 卡模型
    // ------------------------------------------------------------------------
    wire [31:0] card_arg;

    sd_spi_card_model u_card (
        .sclk(sclk), .cs_n(spi_cs_n), .mosi(mosi), .miso(miso),
        .i_dead(1'b0),
        .o_cmd(), .o_arg(card_arg), .o_acmd41_arg(),
        .o_cmd_cnt(), .o_acmd41_cnt(), .o_cmd_valid()
    );

    // ------------------------------------------------------------------------
    // 流程封装
    // ------------------------------------------------------------------------
    task mk_vol;
        input [31:0] totsec;
        input [31:0] fat2;
        input [31:0] fat3;
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

    task do_stream;
        input [31:0] clus;
        input [31:0] fsize;
        begin
            rd_sel       = 1'b1;
            clear_mon;
            @(posedge clk); fs_first_clus = clus; fs_file_size = fsize; fs_start = 1'b1;
            @(posedge clk); fs_start = 1'b0;
            repeat (10) @(posedge clk);
            wait_cnt = 0;
            while (!(fs_done === 1'b1) && wait_cnt < 8_000_000) begin
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
        errors = 0;
        spi_sel = 1'b0;
        init_start = 1'b0;
        mnt_start = 1'b0;
        fs_start = 1'b0;
        fs_ready = 1'b1;
        fs_first_clus = 32'd2;
        fs_file_size  = 32'd0;
        rd_sel = 1'b0;
        clear_mon;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---- 前置：SD 初始化 ----
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
        spi_sel = 1'b1;
        repeat (5) @(posedge clk);

        // ====================================================================
        // T31 单簇文件 2048 Byte
        // ====================================================================
        $display("\n==== T31: 单簇文件 2048 B ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);   // 簇2 -> EOC
        do_mount;
        check(mnt_done === 1'b1, "T31.1 挂载成功");
        do_stream(32'd2, 32'd2048);
        check(fs_done  === 1'b1,      "T31.2 读完了");
        check(fs_error === 1'b0,      "T31.3 无错误");
        check(got_n == 2048,          "T31.4 正好 2048 个字节");
        check(mism == 0,              "T31.5 2048 字节逐个比对全对");
        check(sof_n == 1,             "T31.6 sof 只出现 1 次");
        check(eof_n == 1,             "T31.7 eof 只出现 1 次");
        check(eof_at == 2048,         "T31.8 eof 与第 2048 个字节同拍");
        check(fs_bytes === 32'd2048,  "T31.9 bytes_rd = 2048");
        check(wk_hop === 32'd0,       "T31.10 单簇文件不需要跳簇");

        // ====================================================================
        // T32 跨簇文件 4096 Byte（簇2 -> 簇3）
        // ====================================================================
        $display("\n==== T32: 跨簇文件 4096 B ====");
        mk_vol(TOTSEC_BIG, 32'd3, 32'h0FFF_FFFF);           // FAT[2]=3, FAT[3]=EOC
        do_mount;
        do_stream(32'd2, 32'd4096);
        check(fs_done  === 1'b1,      "T32.1 读完了");
        check(fs_error === 1'b0,      "T32.2 无错误");
        check(got_n == 4096,          "T32.3 正好 4096 个字节");
        check(mism == 0,              "T32.4 跨簇后内容仍逐个对");
        check(sof_n == 1,             "T32.5 sof 只出现 1 次");
        check(eof_n == 1,             "T32.6 eof 只出现 1 次");
        check(fs_bytes === 32'd4096,  "T32.7 bytes_rd = 4096");
        check(wk_hop === 32'd1,       "T32.8 正好跳了 1 次簇");

        // ====================================================================
        // T33 非整簇结尾：只要前 3000 字节
        // ====================================================================
        $display("\n==== T33: 只取 3000 B（簇里还有货也不许多发）====");
        mk_vol(TOTSEC_BIG, 32'd3, 32'h0FFF_FFFF);
        do_mount;
        do_stream(32'd2, 32'd3000);
        check(fs_done  === 1'b1,     "T33.1 读完了");
        check(fs_error === 1'b0,     "T33.2 无错误");
        check(got_n == 3000,         "T33.3 一个字节不多、一个不少");
        check(mism == 0,             "T33.4 前 3000 字节内容全对");
        check(eof_at == 3000,        "T33.5 eof 落在第 3000 个字节");
        check(fs_bytes === 32'd3000, "T33.6 bytes_rd = 3000");

        // ====================================================================
        // T34 文件比簇链长：要 5000，链上只有 4096
        // ====================================================================
        $display("\n==== T34: 文件比簇链长 ====");
        mk_vol(TOTSEC_BIG, 32'd3, 32'h0FFF_FFFF);
        do_mount;
        do_stream(32'd2, 32'd5000);
        check(fs_done  === 1'b1,              "T34.1 出错也宣告结束");
        check(fs_error === 1'b1,              "T34.2 error 拉高");
        check(fs_ec    === `ERR_MEDIA_INVALID, "T34.3 主码 = 0x03");
        check(fs_ed    === `DET_FS_SHORT,     "T34.4 细分码 = 0x36(文件长度不足)");
        check(got_n == 4096,                  "T34.5 已经把链上的货都发完了");

        // ====================================================================
        // T35 簇链成环
        // ====================================================================
        $display("\n==== T35: 簇链成环 ====");
        mk_vol(TOTSEC_TINY, 32'd2, 32'h0FFF_FFFF);          // total_clus=4，FAT[2]=2 自环
        do_mount;
        check(o_tot_clus === 32'd4, "T35.1 小卷 total_clus = 4");
        do_stream(32'd2, 32'd100000);
        check(fs_error === 1'b1,           "T35.2 error 拉高");
        check(fs_ed    === `DET_FS_LOOP,   "T35.3 细分码 = 0x34(簇链成环)");
        check(fs_ec    === `ERR_MEDIA_INVALID, "T35.4 主码 = 0x03");

        // ====================================================================
        // T36 簇号越界
        // ====================================================================
        $display("\n==== T36: 簇号越界 ====");
        mk_vol(TOTSEC_TINY, 32'd6, 32'h0FFF_FFFF);          // total_clus=4 -> 合法 2..5
        do_mount;
        do_stream(32'd2, 32'd100000);
        check(fs_error === 1'b1,           "T36.1 error 拉高");
        check(fs_ed    === `DET_DIR_OOB,   "T36.2 细分码 = 0x33(簇号越界)");

        // ====================================================================
        // T37 下游反压
        // ====================================================================
        $display("\n==== T37: 下游反压 ====");
        mk_vol(TOTSEC_BIG, 32'h0FFF_FFFF, 32'h0FFF_FFFF);
        do_mount;
        fs_ready = 1'b0;                 // 先按住
        rd_sel   = 1'b1;
        clear_mon;
        @(posedge clk); fs_first_clus = 32'd2; fs_file_size = 32'd2048; fs_start = 1'b1;
        @(posedge clk); fs_start = 1'b0;
        // 等第一个字节出现，再按住一段时间
        wait_cnt = 0;
        while (!(fs_valid === 1'b1) && wait_cnt < 4_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (500) @(posedge clk);
        check(fs_valid === 1'b1,      "T37.1 反压期间 valid 保持");
        check(got_n == 0,             "T37.2 下游没收就不算送达");
        check(fs_sof === 1'b1,        "T37.3 反压期间 sof 保持");
        fs_ready = 1'b1;              // 放开
        wait_cnt = 0;
        while (!(fs_done === 1'b1) && wait_cnt < 8_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (10) @(posedge clk);
        check(fs_done === 1'b1,       "T37.4 放开后读完");
        check(got_n == 2048,          "T37.5 反压不会丢字节");
        check(mism == 0,              "T37.6 反压不会错字节");
        check(fs_bytes === 32'd2048,  "T37.7 bytes_rd 与实收一致");

        // ====================================================================
        // T38 空文件
        // ====================================================================
        $display("\n==== T38: file_size = 0 ====");
        do_stream(32'd2, 32'd0);
        check(fs_done === 1'b1,      "T38.1 空文件也能收工");
        check(fs_error === 1'b0,     "T38.2 不算错误");
        check(got_n == 0,            "T38.3 一个字节都不发");
        check(sof_n == 0,            "T38.4 不发 sof");
        check(eof_n == 0,            "T38.5 不发 eof");
        check(fs_bytes === 32'd0,    "T38.6 bytes_rd = 0");

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #400_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule