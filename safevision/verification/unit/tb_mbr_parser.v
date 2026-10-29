


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_mbr_parser;


    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;


    wire sclk, mosi, miso;
    reg  spi_sel;

    wire        init_cs_n, init_tx_valid;
    wire [7:0]  init_tx_data;
    wire [15:0] init_clk_div;
    wire        mbr_cs_n, mbr_tx_valid;
    wire [7:0]  mbr_tx_data;
    wire [15:0] mbr_clk_div;

    wire        spi_cs_n     = spi_sel  ?  mbr_cs_n     : init_cs_n;
    wire [15:0] spi_clk_div  = spi_sel  ?  mbr_clk_div  : init_clk_div;
    wire        spi_tx_valid = spi_sel  ?  mbr_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_sel  ?  mbr_tx_data  : init_tx_data;

    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;


    spi_master u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .clk_div  (spi_clk_div),
        .cs_n     (spi_cs_n),
        .tx_valid (spi_tx_valid),
        .tx_data  (spi_tx_data),
        .tx_ready (spi_tx_ready),
        .rx_data  (spi_rx_data),
        .rx_valid (spi_rx_valid),
        .busy     (spi_busy),
        .sclk     (sclk),
        .mosi     (mosi),
        .miso     (miso)
    );


    reg  init_start;
    wire init_done, init_error, sdhc;
    wire [7:0] init_err_code, init_err_detail, init_retry;
    wire [3:0] init_dbg;

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


    wire        mbr_rd_en, mbr_rd_ready;
    wire [31:0] mbr_rd_addr;
    wire [15:0] mbr_rd_len;
    wire        rd_busy, rd_done, rd_timeout, rd_crc16_err;
    wire [7:0]  mbr_rd_data;
    wire        mbr_rd_data_valid, mbr_rd_data_ready, mbr_rd_data_last;
    wire [7:0]  rd_err_code, rd_err_detail;
    wire [15:0] rd_crc_rx;
    wire [3:0]  rd_dbg;

    sd_sector_reader u_reader (
        .clk          (clk),
        .rst_n        (rst_n),
        .sdhc         (sdhc),
        .rd_en        (mbr_rd_en),
        .rd_addr      (mbr_rd_addr),
        .rd_len       (mbr_rd_len),
        .rd_ready     (mbr_rd_ready),
        .data         (mbr_rd_data),
        .data_valid   (mbr_rd_data_valid),
        .data_ready   (mbr_rd_data_ready),
        .data_last    (mbr_rd_data_last),
        .rd_done      (rd_done),
        .busy         (rd_busy),
        .timeout_err  (rd_timeout),
        .crc16_err    (rd_crc16_err),
        .err_code     (rd_err_code),
        .err_detail   (rd_err_detail),
        .crc_rx       (rd_crc_rx),
        .dbg_state    (rd_dbg),
        .spi_cs_n     (mbr_cs_n),
        .spi_clk_div  (mbr_clk_div),
        .spi_tx_valid (mbr_tx_valid),
        .spi_tx_data  (mbr_tx_data),
        .spi_tx_ready (spi_tx_ready),
        .spi_rx_data  (spi_rx_data),
        .spi_rx_valid (spi_rx_valid)
    );


    reg         mbr_start;
    wire        parse_done, has_mbr;
    wire [31:0] vol_base_lba, part_secs;
    wire [7:0]  mbr_err_code, mbr_err_detail;
    wire [3:0]  mbr_dbg;

    mbr_parser u_mbr (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (mbr_start),
        .parse_done    (parse_done),
        .err_code      (mbr_err_code),
        .err_detail    (mbr_err_detail),
        .dbg_state     (mbr_dbg),
        .has_mbr       (has_mbr),
        .vol_base_lba  (vol_base_lba),
        .part_secs     (part_secs),
        .sd_rd_addr    (mbr_rd_addr),
        .sd_rd_len     (mbr_rd_len),
        .sd_rd_en      (mbr_rd_en),
        .sd_rd_ready   (mbr_rd_ready),
        .sd_data       (mbr_rd_data),
        .sd_data_valid (mbr_rd_data_valid),
        .sd_data_ready (mbr_rd_data_ready),
        .sd_data_last  (mbr_rd_data_last),
        .sd_rd_done    (rd_done),
        .sd_timeout_err(rd_timeout),
        .sd_crc16_err  (rd_crc16_err),
        .sd_err_code   (rd_err_code),
        .sd_err_detail (rd_err_detail)
    );


    wire [5:0]  card_cmd;
    wire [31:0] card_arg, card_acmd41_arg;
    wire [7:0]  card_cmd_cnt, card_acmd41_cnt;
    wire        card_cmd_valid;

    sd_spi_card_model u_card (
        .sclk         (sclk),
        .cs_n         (spi_cs_n),
        .mosi         (mosi),
        .miso         (miso),
        .i_dead       (1'b0),
        .o_cmd        (card_cmd),
        .o_arg        (card_arg),
        .o_acmd41_arg (card_acmd41_arg),
        .o_cmd_cnt    (card_cmd_cnt),
        .o_acmd41_cnt (card_acmd41_cnt),
        .o_cmd_valid  (card_cmd_valid)
    );


    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin begin
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
     end endtask


    task mk_mbr;
        input        sig_ok;
        input [7:0]  ptype;
        input [31:0] start_lba;
        input [31:0] secs;
        begin begin
            u_card.vol_zero(32'd0);
            if (sig_ok) begin
                u_card.vol_set(32'd0, 16'd510, 8'h55);
                u_card.vol_set(32'd0, 16'd511, 8'hAA);
            end
            u_card.vol_set(32'd0, 16'd450, ptype);
            u_card.vol_set_le(32'd0, 16'd454, start_lba, 3'd4);
            u_card.vol_set_le(32'd0, 16'd458, secs,      3'd4);
        end
     end endtask


    task run_mbr;
        begin begin
            mbr_start = 1'b1;
            @(posedge clk);
            #1;
            mbr_start = 1'b0;
            wait (parse_done === 1'b0);
            wait (parse_done === 1'b1);
            #1;
        end
     end endtask


    initial begin
        #20_000_000;
        $display("[FAIL] tb_mbr_parser 看门狗超时");
        $finish;
    end


    initial begin
        init_start = 1'b0;
        mbr_start  = 1'b0;
        spi_sel    = 1'b0;


        mk_mbr(1'b1, 8'h0B, 32'd8192, 32'd15515648);

        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;


        init_start = 1'b1;
        @(posedge clk);
        #1;
        init_start = 1'b0;
        wait (init_done === 1'b1);
        spi_sel = 1'b1;


        run_mbr;
        check(has_mbr === 1'b1,           "T1.1 有效 MBR -> has_mbr=1");
        check(vol_base_lba === 32'd8192,  "T1.2 卷基址 = 分区0 起始 LBA 8192（小端拼装正确）");
        check(part_secs === 32'd15515648, "T1.3 分区扇区数正确（小端）");
        check(card_arg === 32'd0,         "T1.4 读的是卡的第 0 号扇区（MBR）");


        mk_mbr(1'b0, 8'h0B, 32'd8192, 32'd15515648);
        run_mbr;
        check(has_mbr === 1'b0 && vol_base_lba === 32'd0 && mbr_err_code === `ERR_NONE,
              "T2 无 0x55AA 签名 -> has_mbr=0、卷基址回退 0，且不报错");


        mk_mbr(1'b1, 8'h00, 32'd8192, 32'd15515648);
        run_mbr;
        check(has_mbr === 1'b0 && vol_base_lba === 32'd0,
              "T3 分区类型=0（空表项）-> has_mbr=0、卷基址 0");


        mk_mbr(1'b1, 8'h0B, 32'd0, 32'd15515648);
        run_mbr;
        check(has_mbr === 1'b0 && vol_base_lba === 32'd0,
              "T4 分区起始 LBA=0 -> has_mbr=0（不把 MBR 当卷）");

        $display("[TB] tb_mbr_parser done, errors=%0d", errors);
        $finish;
    end

endmodule
