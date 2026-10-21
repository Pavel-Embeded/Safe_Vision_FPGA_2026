// ============================================================================
// tb_fat32_boot_parser.v — 阶段 6 第一块：FAT32 挂载与 BPB 解析
// ----------------------------------------------------------------------------
// 验证内容：
//   T11 正常挂载：读 0 号扇区、校验 BPB、算出 data_start_lba / root_dir_lba /
//        total_clus 等全部派生地址
//   T12 签名不是 0x55AA        -> 明确报错，不是硬着头皮解析
//   T13 不是 FAT32（判别位不成立）-> 报 DET_FAT_NOT32
//   T14 每扇区字节数不是 512     -> 报 DET_FAT_BPB
//   T15 修复卷内容后重新 start 能挂载成功（错误可恢复）
//
// 计算基准（测试用卷参数）：
//   BytsPerSec=512, SecPerClus=8, RsvdSecCnt=32, NumFATs=2, FATSz32=1024,
//   RootClus=2, TotSec32=0x10000(65536)
//     data_start_lba = 32 + 2*1024            = 2080
//     root_dir_lba   = 2080 + (2-2)*8         = 2080
//     total_clus     = (65536 - 2080) / 8     = 7932
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_fat32_boot_parser;

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
    // SPI 四线 + 总线复用
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
    // sd_sector_reader ← 由 fat32_boot_parser 驱动
    // ------------------------------------------------------------------------
    wire        fs_rd_en;
    wire [31:0] fs_rd_addr;
    wire [15:0] fs_rd_len;
    wire        fs_rd_ready;
    wire [7:0]  fs_data;
    wire        fs_data_valid, fs_data_ready, fs_data_last;
    wire        fs_rd_done, fs_to_err, fs_crc16_err;
    wire [7:0]  fs_rd_ec, fs_rd_ed;

    sd_sector_reader u_rd (
        .clk(clk), .rst_n(rst_n), .sdhc(sdhc),
        .rd_en(fs_rd_en), .rd_addr(fs_rd_addr), .rd_len(fs_rd_len), .rd_ready(fs_rd_ready),
        .data(fs_data), .data_valid(fs_data_valid), .data_ready(fs_data_ready),
        .data_last(fs_data_last),
        .rd_done(fs_rd_done), .busy(), .timeout_err(fs_to_err), .crc16_err(fs_crc16_err),
        .err_code(fs_rd_ec), .err_detail(fs_rd_ed), .crc_rx(), .dbg_state(),
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
    wire [3:0]  mnt_dbg;

    fat32_boot_parser u_mnt (
        .clk(clk), .rst_n(rst_n), .start(mnt_start),
        .mount_done(mnt_done), .mount_error(mnt_err),
        .err_code(mnt_ec), .err_detail(mnt_ed), .dbg_state(mnt_dbg),
        .bytes_per_sec(o_bps), .sec_per_clus(o_spc), .num_fats(o_nfat),
        .fat_start_lba(o_fat_lba), .root_clus(o_root_clus),
        .root_dir_lba(o_root_lba), .data_start_lba(o_data_lba),
        .total_sec(o_tot_sec), .total_clus(o_tot_clus),
        .sd_rd_addr(fs_rd_addr), .sd_rd_len(fs_rd_len), .sd_rd_en(fs_rd_en),
        .sd_rd_ready(fs_rd_ready), .sd_data(fs_data), .sd_data_valid(fs_data_valid),
        .sd_data_ready(fs_data_ready), .sd_data_last(fs_data_last),
        .sd_rd_done(fs_rd_done), .sd_timeout_err(fs_to_err), .sd_crc16_err(fs_crc16_err),
        .sd_err_code(fs_rd_ec), .sd_err_detail(fs_rd_ed)
    );

    // ------------------------------------------------------------------------
    // 卡模型
    // ------------------------------------------------------------------------
    wire [5:0]  card_cmd;
    wire [31:0] card_arg;
    wire [7:0]  card_cmd_cnt;

    sd_spi_card_model u_card (
        .sclk(sclk), .cs_n(spi_cs_n), .mosi(mosi), .miso(miso),
        .i_dead(1'b0),
        .o_cmd(card_cmd), .o_arg(card_arg), .o_acmd41_arg(),
        .o_cmd_cnt(card_cmd_cnt), .o_acmd41_cnt(), .o_cmd_valid()
    );

    // ------------------------------------------------------------------------
    // 激励
    // ------------------------------------------------------------------------
    initial begin
        errors    = 0;
        spi_sel   = 1'b0;
        init_start= 1'b0;
        mnt_start = 1'b0;

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---- 先在卡上造一个合法 FAT32 卷 ----
        u_card.mk_fat32_dbr(16'd512, 8'd8, 16'd32, 8'd2,
                            32'd1024, 32'd2, 32'd65536, 1'b1);

        // ====================================================================
        // 初始化 SD 卡
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
        check(sdhc === 1'b1,      "P2 识别为 SDHC（块寻址）");

        spi_sel = 1'b1;          // 总线交给 sd_sector_reader
        repeat (5) @(posedge clk);

        // ====================================================================
        // T11 正常挂载
        // ====================================================================
        $display("\n==== T11: 正常 FAT32 挂载 ====");
        @(posedge clk);
        mnt_start = 1'b1;
        @(posedge clk);
        mnt_start = 1'b0;
        repeat (10) @(posedge clk);          // 等 NBA 结算

        wait_cnt = 0;
        while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);

        check(mnt_done === 1'b1,      "T11.1 mount_done 拉高");
        check(mnt_err  === 1'b0,      "T11.2 无挂载错误");
        check(u_card.o_arg === 32'd0, "T11.3 挂载读的是 0 号扇区（DBR）");
        check(o_bps   === 16'd512,    "T11.4 BytsPerSec = 512");
        check(o_spc   === 8'd8,       "T11.5 SecPerClus = 8");
        check(o_nfat  === 8'd2,       "T11.6 NumFATs = 2");
        check(o_fat_lba  === 32'd32,       "T11.7 fat_start_lba = RsvdSecCnt = 32");
        check(o_root_clus=== 32'd2,        "T11.8 root_clus = 2");
        check(o_data_lba === 32'd2080,     "T11.9 data_start_lba = 32 + 2*1024 = 2080");
        check(o_root_lba === 32'd2080,     "T11.10 root_dir_lba = 2080 + (2-2)*8 = 2080");
        check(o_tot_sec  === 32'd65536,    "T11.11 total_sec = 65536");
        check(o_tot_clus === 32'd7932,     "T11.12 total_clus = (65536-2080)/8 = 7932");
        if (mnt_err) $display("       (意外) err_code=0x%02x err_detail=0x%02x", mnt_ec, mnt_ed);

        // ====================================================================
        // T12 签名被破坏
        // ====================================================================
        $display("\n==== T12: 签名不是 0x55AA ====");
        u_card.vol_set(32'd0, 16'd511, 8'h00);          // 破坏签名的第二个字节
        @(posedge clk);
        mnt_start = 1'b1;
        @(posedge clk);
        mnt_start = 1'b0;
        repeat (10) @(posedge clk);
        wait_cnt = 0;
        while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);

        check(mnt_err === 1'b1,                 "T12.1 挂载失败并置错误");
        check(mnt_done === 1'b0,                "T12.2 不会误报成功");
        check(mnt_ec === `ERR_MEDIA_INVALID,    "T12.3 对外主码 = 0x03(媒体文件非法)");
        check(mnt_ed === `DET_FAT_BPB,          "T12.4 内部细分码 = 0x31(BPB 非法)");

        // ====================================================================
        // T13 不是 FAT32（判别位不成立）
        // ====================================================================
        $display("\n==== T13: 不是 FAT32 ====");
        u_card.mk_fat32_dbr(16'd512, 8'd8, 16'd32, 8'd2,
                            32'd1024, 32'd2, 32'd65536, 1'b0);   // as_fat32=0
        @(posedge clk);
        mnt_start = 1'b1;
        @(posedge clk);
        mnt_start = 1'b0;
        repeat (10) @(posedge clk);
        wait_cnt = 0;
        while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);

        check(mnt_err === 1'b1,              "T13.1 非 FAT32 被拒绝");
        check(mnt_ed === `DET_FAT_NOT32,     "T13.2 内部细分码 = 0x32(非 FAT32)");

        // ====================================================================
        // T14 每扇区字节数不是 512
        // ====================================================================
        $display("\n==== T14: BytsPerSec != 512 ====");
        u_card.mk_fat32_dbr(16'd1024, 8'd8, 16'd32, 8'd2,
                            32'd1024, 32'd2, 32'd65536, 1'b1);
        @(posedge clk);
        mnt_start = 1'b1;
        @(posedge clk);
        mnt_start = 1'b0;
        repeat (10) @(posedge clk);
        wait_cnt = 0;
        while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);

        check(mnt_err === 1'b1,         "T14.1 BytsPerSec=1024 被拒绝");
        check(mnt_ed === `DET_FAT_BPB,  "T14.2 内部细分码 = 0x31(BPB 非法)");

        // ====================================================================
        // T15 修复后重新挂载成功（错误可恢复）
        // ====================================================================
        $display("\n==== T15: 修复卷内容后重新挂载 ====");
        u_card.mk_fat32_dbr(16'd512, 8'd8, 16'd32, 8'd2,
                            32'd1024, 32'd2, 32'd65536, 1'b1);
        @(posedge clk);
        mnt_start = 1'b1;
        @(posedge clk);
        mnt_start = 1'b0;
        repeat (10) @(posedge clk);
        wait_cnt = 0;
        while (!(mnt_done === 1'b1 || mnt_err === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);

        check(mnt_done === 1'b1,        "T15.1 重新挂载成功");
        check(mnt_err  === 1'b0,        "T15.2 错误标志已清除");
        check(mnt_ec   === `ERR_NONE,   "T15.3 错误码已清零");
        check(o_data_lba === 32'd2080,  "T15.4 派生地址再次算对");

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    initial begin
        #60_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule