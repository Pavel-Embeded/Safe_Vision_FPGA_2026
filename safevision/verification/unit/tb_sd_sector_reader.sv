// ============================================================================
// tb_sd_sector_reader.v — 阶段 5 验证：CMD17 单扇区读 + 逐字节比对
// ----------------------------------------------------------------------------
// 过关标准（手册 7.5）："512 Byte 一个字节都不能差"
//
// 验证内容：
//   T1  初始化序列走通（CMD0 -> CMD8 -> CMD55+ACMD41 -> CMD58），sdhc = 1
//   T2  CMD17 参数正确（LBA = 1000 原样送出）
//   T3  512 Byte 逐字节与卡模型一致
//   T4  CRC16 比对通过（crc16_err == 0）
//   T5  反压（data_ready 周期拉低）下不丢字节
//   T6  rd_len != 1（CMD18 未实现）被明确拒绝，不静默错读
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_sd_sector_reader;

    // ------------------------------------------------------------------------
    // 时钟与复位
    // ------------------------------------------------------------------------
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;          // 100 MHz

    // ------------------------------------------------------------------------
    // SPI 四线
    // ------------------------------------------------------------------------
    wire sclk, mosi, miso;

    // 总线复用：初始化阶段归 sd_initializer，读阶段归 sd_sector_reader
    reg  spi_sel;                  // 0 = sd_initializer, 1 = sd_sector_reader

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

    // ------------------------------------------------------------------------
    // DUT: spi_master
    // ------------------------------------------------------------------------
    spi_master u_spi (
        .clk        (clk),
        .rst_n      (rst_n),
        .clk_div    (spi_clk_div),
        .cs_n       (spi_cs_n),
        .tx_valid   (spi_tx_valid),
        .tx_data    (spi_tx_data),
        .tx_ready   (spi_tx_ready),
        .rx_data    (spi_rx_data),
        .rx_valid   (spi_rx_valid),
        .busy       (spi_busy),
        .sclk       (sclk),
        .mosi       (mosi),
        .miso       (miso)
    );

    // ------------------------------------------------------------------------
    // DUT: sd_initializer
    // ------------------------------------------------------------------------
    reg  init_start;
    wire init_done, init_error, sdhc;
    wire [7:0]  init_err_code, init_err_detail, init_retry;
    wire [3:0]  init_dbg;

    sd_initializer u_init (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (init_start),
        .sdhc         (sdhc),
        .init_done    (init_done),
        .init_error   (init_error),
        .err_code     (init_err_code),
        .err_detail   (init_err_detail),
        .retry_cnt    (init_retry),
        .dbg_state    (init_dbg),
        .spi_cs_n     (init_cs_n),
        .spi_clk_div  (init_clk_div),
        .spi_tx_valid (init_tx_valid),
        .spi_tx_data  (init_tx_data),
        .spi_tx_ready (spi_tx_ready),
        .spi_rx_data  (spi_rx_data),
        .spi_rx_valid (spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // DUT: sd_sector_reader
    // ------------------------------------------------------------------------
    reg         rd_en;
    reg  [31:0] rd_addr;
    reg  [15:0] rd_len;
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_timeout_err, rd_crc16_err;
    wire [7:0]  rd_err_code, rd_err_detail;
    wire [15:0] rd_crc_rx;
    wire [3:0]  rd_dbg;

    reg         data_ready;

    sd_sector_reader u_rd (
        .clk          (clk),
        .rst_n        (rst_n),
        .sdhc         (sdhc),
        .rd_en        (rd_en),
        .rd_addr      (rd_addr),
        .rd_len       (rd_len),
        .rd_ready     (rd_ready),
        .data         (rd_data),
        .data_valid   (rd_data_valid),
        .data_ready   (data_ready),
        .data_last    (rd_data_last),
        .rd_done      (rd_done),
        .busy         (),
        .timeout_err  (rd_timeout_err),
        .crc16_err    (rd_crc16_err),
        .err_code     (rd_err_code),
        .err_detail   (rd_err_detail),
        .crc_rx       (rd_crc_rx),
        .dbg_state    (rd_dbg),
        .spi_cs_n     (rd_cs_n),
        .spi_clk_div  (rd_clk_div),
        .spi_tx_valid (rd_tx_valid),
        .spi_tx_data  (rd_tx_data),
        .spi_tx_ready (spi_tx_ready),
        .spi_rx_data  (spi_rx_data),
        .spi_rx_valid (spi_rx_valid)
    );

    // ------------------------------------------------------------------------
    // 卡模型
    // ------------------------------------------------------------------------
    wire [5:0]  card_cmd;
    wire [31:0] card_arg;
    wire [7:0]  card_cmd_cnt;
    wire        card_cmd_valid;

    sd_spi_card_model u_card (
        .sclk         (sclk),
        .cs_n         (spi_cs_n),
        .mosi         (mosi),
        .miso         (miso),
        .i_dead       (1'b0),            // 理想卡：正常响应
        .o_cmd        (card_cmd),
        .o_arg        (card_arg),
        .o_acmd41_arg (),
        .o_cmd_cnt    (card_cmd_cnt),
        .o_acmd41_cnt (),
        .o_cmd_valid  (card_cmd_valid)
    );

    // ------------------------------------------------------------------------
    // 数据收集
    // ------------------------------------------------------------------------
    reg [7:0] rx_buf [0:511];
    integer   got;

    // 反压：每 16 拍拉低 1 拍，验证 data_ready 低时 DUT 保持数据不丢
    reg [3:0] stall_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stall_cnt <= 4'd0;
        else        stall_cnt <= stall_cnt + 4'd1;
    end
    always @(*) data_ready = (stall_cnt != 4'd0);

    always @(posedge clk) begin
        if (rst_n && rd_data_valid && data_ready) begin
            if (got < 512) rx_buf[got] = rd_data;
            got = got + 1;
        end
    end

    // ------------------------------------------------------------------------
    // 主激励
    // ------------------------------------------------------------------------
    integer errors;
    integer k;
    integer wait_cnt;

    task check;
        input        cond;
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

    initial begin
        $dumpfile("tb_sd_sector_reader.vcd");
        $dumpvars(0, tb_sd_sector_reader);

        errors     = 0;
        got        = 0;
        spi_sel    = 1'b0;
        init_start = 1'b0;
        rd_en      = 1'b0;
        rd_addr    = 32'd1000;
        rd_len     = 16'd1;

        // ---- 复位 ----
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ====================================================================
        // T1 初始化
        // ====================================================================
        $display("\n==== T1: SD 初始化序列 ====");
        @(posedge clk);
        init_start = 1'b1;
        @(posedge clk);
        init_start = 1'b0;

        // 等初始化完成（轮询 + 硬超时，防止状态机挂死导致仿真永不到头）
        wait_cnt = 0;
        while (!(init_done === 1'b1 || init_error === 1'b1) && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        if (!(init_done === 1'b1 || init_error === 1'b1)) begin
            $display("[FAIL] 初始化超时未结束（疑似状态机挂死）");
            errors = errors + 1;
        end

        check(init_done === 1'b1,  "T1.1 init_done 拉高");
        check(init_error === 1'b0, "T1.2 无初始化错误");
        check(sdhc === 1'b1,       "T1.3 识别为 SDHC (CCS=1)");
        check(u_card.o_cmd_cnt == 8'd5, "T1.4 卡侧共收到 5 条命令");
        $display("       err_code=0x%02x err_detail=0x%02x retry=%0d",
                 init_err_code, init_err_detail, init_retry);

        // ====================================================================
        // T2/T3/T4 单扇区读
        // ====================================================================
        $display("\n==== T2~T4: CMD17 读 LBA=1000 ====");
        spi_sel = 1'b1;                            // 总线交给 sd_sector_reader
        repeat (5) @(posedge clk);

        @(posedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        rd_en = 1'b0;

        wait_cnt = 0;
        while (rd_done !== 1'b1 && wait_cnt < 2_000_000) begin
            @(posedge clk);
            wait_cnt = wait_cnt + 1;
        end
        if (rd_done !== 1'b1) begin
            $display("[FAIL] 扇区读超时未结束（疑似状态机挂死）");
            errors = errors + 1;
        end

        repeat (10) @(posedge clk);

        check(u_card.o_arg === 32'd1000, "T2.1 CMD17 参数 = LBA 1000（字节序正确）");
        check(u_card.o_cmd === `SD_CMD17,  "T2.2 卡侧收到的命令是 CMD17");
        check(got == 512,                "T3.1 收到 512 Byte");
        check(rd_timeout_err === 1'b0,   "T3.2 无超时");
        // 注意：必须同时要求 got==512，否则"读失败但 crc16_err 未被置位"会假阳性通过
        check(rd_crc16_err === 1'b0 && got == 512, "T4.1 CRC16 比对通过");

        // 逐字节比对
        begin : byte_cmp
            integer bad;
            bad = 0;
            for (k = 0; k < 512; k = k + 1) begin
                if (rx_buf[k] !== u_card.sector[k]) begin
                    if (bad < 5)
                        $display("       第 %0d 字节不符：DUT=0x%02x 卡=0x%02x",
                                 k, rx_buf[k], u_card.sector[k]);
                    bad = bad + 1;
                end
            end
            check(bad == 0, "T3.3 512 Byte 逐字节完全一致");
            if (bad != 0) $display("       共 %0d 个字节不符", bad);
        end

        // ====================================================================
        // T5 连续多次读（验证状态机每次都能干净回到 IDLE，无残留状态）
        //    对应手册 7.5 过关自测："同一 LBA 连读 100 次，全部比对通过且无一次超时"
        //    仿真里取 3 次即可暴露状态残留问题
        // ====================================================================
        $display("\n==== T5: 连续多次读 ====");
        begin : repeat_rd
            integer r;
            integer bad_r;
            integer tgt;
            bad_r = 0;
            for (r = 1; r <= 3; r = r + 1) begin
                tgt     = 1000 + r * 1000;
                got     = 0;
                rd_addr = tgt;
                @(posedge clk);
                rd_en = 1'b1;
                @(posedge clk);
                rd_en = 1'b0;

                wait_cnt = 0;
                while (rd_done !== 1'b1 && wait_cnt < 2_000_000) begin
                    @(posedge clk);
                    wait_cnt = wait_cnt + 1;
                end
                repeat (5) @(posedge clk);

                if (got != 512 || rd_timeout_err !== 1'b0 || rd_crc16_err !== 1'b0
                    || u_card.o_arg !== tgt)
                    bad_r = bad_r + 1;
            end
            check(bad_r == 0, "T5.1 连续 3 次读全部成功且 LBA 参数正确");
        end

        // ====================================================================
        // T6 rd_len != 1 必须被明确拒绝
        // ====================================================================
        $display("\n==== T6: CMD18 未实现时的拒绝行为 ====");
        rd_addr = 32'd1000;
        rd_len = 16'd2;
        got    = 0;
        @(posedge clk);
        rd_en = 1'b1;
        @(posedge clk);
        rd_en = 1'b0;
        wait (rd_done === 1'b1);
        repeat (5) @(posedge clk);
        check(rd_err_code === `ERR_SD_IO, "T6.1 rd_len=2 被拒绝并给出错误码");
        check(got == 0,                   "T6.2 拒绝时不产生任何数据字节");
        rd_len = 16'd1;

        // ====================================================================
        $display("\n============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

    // 全局兜底超时
    initial begin
        #60_000_000;
        $display("[FAIL] 全局超时，仿真未正常结束");
        $finish;
    end

endmodule