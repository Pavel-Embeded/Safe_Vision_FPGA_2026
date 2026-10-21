// ============================================================================
// tb_sd_initializer.v — 阶段 4 验证：超时出口 + 卡变体分支
// ----------------------------------------------------------------------------
// 背景：tb_sd_sector_reader 用的是"理想卡"（ACMD41 立刻 ready、CMD8 一定回 0xAA、
//       CRC 恒对）。真实卡还有两条分支必须验证：
//         - 慢卡：上电后 ACMD41 会被拒绝很多次才 ready
//         - v1.x 卡：不认 CMD8，回 illegal command
//       以及最关键的鲁棒性行为：
//         - 拔卡 / 坏卡：必须有限时间内进错误态，**不能挂死**
//         - 插回后重新 start 必须能恢复
//
// 三个实例并行跑，共用 clk/rst_n，各自一套 spi_master + sd_initializer + 卡模型。
//
// 过关标准（手册 7.4）："拔卡上电，系统有限时间内进错误态而非卡死；
//                       插回后可恢复或提示。"
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_sd_initializer;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer   errors;
    integer   wait_cnt;
    reg       fin1, fin2, fin3;

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

    // ========================================================================
    // 实例 1：慢卡（ACMD41 前 3 次回 idle 态）
    // ========================================================================
    wire        s1_sclk, s1_mosi, s1_miso;
    wire        s1_cs, s1_txv, s1_txr, s1_rxv;
    wire [7:0]  s1_txd, s1_rxd;
    wire [15:0] s1_div;
    reg         s1_start;
    wire        s1_done, s1_err, s1_sdhc;
    wire [7:0]  s1_ec, s1_ed, s1_rc;
    wire [7:0]  s1_acmd41_cnt;

    spi_master u_spi1 (
        .clk(clk), .rst_n(rst_n), .clk_div(s1_div), .cs_n(s1_cs),
        .tx_valid(s1_txv), .tx_data(s1_txd), .tx_ready(s1_txr),
        .rx_data(s1_rxd), .rx_valid(s1_rxv), .busy(),
        .sclk(s1_sclk), .mosi(s1_mosi), .miso(s1_miso)
    );

    sd_initializer u_init1 (
        .clk(clk), .rst_n(rst_n), .start(s1_start),
        .sdhc(s1_sdhc), .init_done(s1_done), .init_error(s1_err),
        .err_code(s1_ec), .err_detail(s1_ed), .retry_cnt(s1_rc), .dbg_state(),
        .spi_cs_n(s1_cs), .spi_clk_div(s1_div),
        .spi_tx_valid(s1_txv), .spi_tx_data(s1_txd), .spi_tx_ready(s1_txr),
        .spi_rx_data(s1_rxd), .spi_rx_valid(s1_rxv)
    );

    // ★ 2026-10-06：这个"慢卡"实例同时兼守**缺陷 27 + 缺陷 28** ——
    //   前 2 次 CMD0 故意回 `0x02`（非 idle，模拟"卡被上次复位打断、残留字节被当成 R1"）
    //   ⇒ RTL 必须靠"重走 CS 高前导 + CMD0"重新同步（缺陷 28）；
    //   之后回 `0x03`（bit0 idle + bit1 erase reset，真卡实测值）⇒ 判据必须容忍 bit1（缺陷 27）。
    //   旧实现（等值判 0x01 / 不重同步）在这两处任一都会挂（T7.1/T7.2）。
    sd_spi_card_model #(.SLOW_INIT_POLLS(8'd3), .CMD0_R1(8'h03),
                        .CMD0_BAD_TRIES(3'd2)) u_card1 (
        .sclk(s1_sclk), .cs_n(s1_cs), .mosi(s1_mosi), .miso(s1_miso),
        .i_dead(1'b0),
        .o_cmd(), .o_arg(), .o_acmd41_arg(),
        .o_cmd_cnt(), .o_acmd41_cnt(s1_acmd41_cnt), .o_cmd_valid()
    );

    // ========================================================================
    // 实例 2：v1.x 卡（不认 CMD8）+ CCS = 0
    // ========================================================================
    wire        s2_sclk, s2_mosi, s2_miso;
    wire        s2_cs, s2_txv, s2_txr, s2_rxv;
    wire [7:0]  s2_txd, s2_rxd;
    wire [15:0] s2_div;
    reg         s2_start;
    wire        s2_done, s2_err, s2_sdhc;
    wire [7:0]  s2_ec, s2_ed, s2_rc;
    wire [31:0] s2_acmd41_arg;

    spi_master u_spi2 (
        .clk(clk), .rst_n(rst_n), .clk_div(s2_div), .cs_n(s2_cs),
        .tx_valid(s2_txv), .tx_data(s2_txd), .tx_ready(s2_txr),
        .rx_data(s2_rxd), .rx_valid(s2_rxv), .busy(),
        .sclk(s2_sclk), .mosi(s2_mosi), .miso(s2_miso)
    );

    sd_initializer u_init2 (
        .clk(clk), .rst_n(rst_n), .start(s2_start),
        .sdhc(s2_sdhc), .init_done(s2_done), .init_error(s2_err),
        .err_code(s2_ec), .err_detail(s2_ed), .retry_cnt(s2_rc), .dbg_state(),
        .spi_cs_n(s2_cs), .spi_clk_div(s2_div),
        .spi_tx_valid(s2_txv), .spi_tx_data(s2_txd), .spi_tx_ready(s2_txr),
        .spi_rx_data(s2_rxd), .spi_rx_valid(s2_rxv)
    );

    sd_spi_card_model #(
        .OCR_VALUE    (32'h80FF_8000),   // bit31=1 上电完成, bit30=0 -> 非 SDHC
        .CMD8_ILLEGAL (1'b1)             // 回 illegal command
    ) u_card2 (
        .sclk(s2_sclk), .cs_n(s2_cs), .mosi(s2_mosi), .miso(s2_miso),
        .i_dead(1'b0),
        .o_cmd(), .o_arg(), .o_acmd41_arg(s2_acmd41_arg),
        .o_cmd_cnt(), .o_acmd41_cnt(), .o_cmd_valid()
    );

    // ========================================================================
    // 实例 3：拔卡 / 坏卡（i_dead 可运行时切换，用于验证恢复）
    // ========================================================================
    wire        s3_sclk, s3_mosi, s3_miso;
    wire        s3_cs, s3_txv, s3_txr, s3_rxv;
    wire [7:0]  s3_txd, s3_rxd;
    wire [15:0] s3_div;
    reg         s3_start;
    wire        s3_done, s3_err, s3_sdhc;
    wire [7:0]  s3_ec, s3_ed, s3_rc;
    wire [3:0]  s3_dbg;          // 调试：初始化状态机当前状态
    wire [7:0]  s3_card_cnt;     // 调试：卡侧收到的命令条数
    reg         dead3;

    spi_master u_spi3 (
        .clk(clk), .rst_n(rst_n), .clk_div(s3_div), .cs_n(s3_cs),
        .tx_valid(s3_txv), .tx_data(s3_txd), .tx_ready(s3_txr),
        .rx_data(s3_rxd), .rx_valid(s3_rxv), .busy(),
        .sclk(s3_sclk), .mosi(s3_mosi), .miso(s3_miso)
    );

    sd_initializer u_init3 (
        .clk(clk), .rst_n(rst_n), .start(s3_start),
        .sdhc(s3_sdhc), .init_done(s3_done), .init_error(s3_err),
        .err_code(s3_ec), .err_detail(s3_ed), .retry_cnt(s3_rc), .dbg_state(s3_dbg),
        .spi_cs_n(s3_cs), .spi_clk_div(s3_div),
        .spi_tx_valid(s3_txv), .spi_tx_data(s3_txd), .spi_tx_ready(s3_txr),
        .spi_rx_data(s3_rxd), .spi_rx_valid(s3_rxv)
    );

    sd_spi_card_model u_card3 (
        .sclk(s3_sclk), .cs_n(s3_cs), .mosi(s3_mosi), .miso(s3_miso),
        .i_dead(dead3),
        .o_cmd(), .o_arg(), .o_acmd41_arg(),
        .o_cmd_cnt(s3_card_cnt), .o_acmd41_cnt(), .o_cmd_valid()
    );

    // ========================================================================
    // 激励
    // ========================================================================
    // ★ 踩坑记录（TB 侧竞态）：
    //   `@(posedge clk)` 在 active region 恢复执行，早于同一个沿上的
    //   非阻塞赋值更新。所以"发完 start 立刻读 DUT 输出"会读到旧值，
    //   导致等待循环在第一拍就误判退出。凡是"打完脉冲就查状态"的地方，
    //   都必须先 repeat(N) @(posedge clk) 让 NBA 结算。
    // ========================================================================
    initial begin
        errors   = 0;
        fin1     = 1'b0; fin2 = 1'b0; fin3 = 1'b0;
        s1_start = 1'b0; s2_start = 1'b0; s3_start = 1'b0;
        dead3    = 1'b1;                 // 实例 3 初始状态 = 拔卡

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        `ifdef SIM_FAST_TO
        $display("[INFO] 已定义 SIM_FAST_TO：超时使用仿真缩放值（非产品值）");
        `else
        $display("[INFO] 未定义 SIM_FAST_TO：超时使用产品值");
        `endif

        // ---- 三个实例同时启动 ----
        $display("\n==== T7~T9: 慢卡(CMD0 R1=0x03) / v1 卡 / 拔卡 并行验证 ====");
        @(posedge clk);
        s1_start = 1'b1; s2_start = 1'b1; s3_start = 1'b1;
        @(posedge clk);
        s1_start = 1'b0; s2_start = 1'b0; s3_start = 1'b0;

        // 等三者都进入终态（含硬超时，挂死即报错）
        wait_cnt = 0;
        while ((!fin1 || !fin2 || !fin3) && wait_cnt < 3_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
            if (s1_done === 1'b1 || s1_err === 1'b1) fin1 = 1'b1;
            if (s2_done === 1'b1 || s2_err === 1'b1) fin2 = 1'b1;
            if (s3_done === 1'b1 || s3_err === 1'b1) fin3 = 1'b1;
        end

        check(fin1 === 1'b1, "T7.0 慢卡实例有限时间内结束（未挂死）");
        check(fin2 === 1'b1, "T8.0 v1 卡实例有限时间内结束（未挂死）");
        check(fin3 === 1'b1, "T9.0 拔卡实例有限时间内结束（未挂死）");

        // ---- T7 慢卡 ----
        check(s1_done === 1'b1,      "T7.1 慢卡最终初始化成功");
        check(s1_err  === 1'b0,      "T7.2 慢卡无错误标志");
        check(s1_sdhc === 1'b1,      "T7.3 慢卡识别为 SDHC");
        check(s1_rc   === 8'd3,      "T7.4 retry_cnt = 3（确实轮询了 3 次 idle 态）");
        check(s1_acmd41_cnt >= 8'd4, "T7.5 卡侧收到 >=4 次 ACMD41");

        // ---- T8 v1.x 卡 ----
        check(s2_done === 1'b1,         "T8.1 v1 卡最终初始化成功（CMD8 失败不应中断流程）");
        check(s2_err  === 1'b0,         "T8.2 v1 卡无错误标志");
        check(s2_sdhc === 1'b0,         "T8.3 v1 卡判定为 SDSC（CCS=0，非 SDHC）");
        check(s2_acmd41_arg === 32'h0,  "T8.4 ACMD41 参数 = 0（v1 卡不应带 HCS 位）");

        // ---- T9 拔卡 ----
        check(s3_err  === 1'b1,          "T9.1 拔卡最终进入错误态");
        check(s3_done === 1'b0,          "T9.2 拔卡不会误报成功");
        check(s3_ec   === `ERR_SD_INIT,  "T9.3 对外错误码 = 0x01(SD 初始化失败)");
        check(s3_ed   === `DET_SD_RESP_TO,"T9.4 内部细分码 = 0x21(命令响应超时)");

        // ---- T10 插回后恢复 ----
        $display("\n==== T10: 插回后重新 start 恢复 ====");
        dead3 = 1'b0;
        repeat (5) @(posedge clk);
        @(posedge clk);
        s3_start = 1'b1;
        @(posedge clk);
        s3_start = 1'b0;
        repeat (10) @(posedge clk);      // 等 NBA 结算，见上方竞态说明

        fin3 = 1'b0;
        wait_cnt = 0;
        while ((s3_done !== 1'b1 && s3_err !== 1'b1) && wait_cnt < 3_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        repeat (5) @(posedge clk);
        $display("       恢复耗时 %0d 拍，末态 state=%0d，卡侧累计命令 %0d 条",
                 wait_cnt, s3_dbg, s3_card_cnt);

        check(s3_done === 1'b1, "T10.1 插回后重新 start 初始化成功");
        check(s3_err  === 1'b0, "T10.2 错误标志已被清除");
        check(s3_sdhc === 1'b1, "T10.3 恢复后正确识别为 SDHC");
        check(s3_ec   === `ERR_NONE, "T10.4 错误码已清零");

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