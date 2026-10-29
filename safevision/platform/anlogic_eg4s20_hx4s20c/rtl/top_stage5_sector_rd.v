


module top_stage5_sector_rd #(
    parameter integer CLK_FREQ    = 50_000_000,
    parameter integer BAUD        = 115200,
    parameter [31:0]  TARGET_LBA  = 32'd8192,
    parameter [23:0]  POWERUP_CYC = 24'd2_500_000
)(

    input  wire        clk,
    input  wire        rst_n,
    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        uart_txd,
    output wire [3:0]  led
);


    wire rst_sync_n;

    reset_sync u_reset_sync (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_sync_n)
    );


    localparam [2:0] ST_POWER  = 3'd0,
                     ST_INIT   = 3'd1,
                     ST_WAIT   = 3'd2,
                     ST_RD     = 3'd3,
                     ST_STREAM = 3'd4,
                     ST_OK     = 3'd5,
                     ST_ERR    = 3'd6;

    reg  [2:0]  st;
    reg  [23:0] pwr_cnt;


    wire        sdhc;
    wire        init_done;
    wire        init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n;
    wire [15:0] init_clk_div;
    wire        init_tx_valid;
    wire [7:0]  init_tx_data;


    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid;
    wire        rd_data_ready;
    wire        rd_data_last;
    wire        rd_done;
    wire        rd_busy;
    wire        rd_timeout;
    wire        rd_crc16_err;
    wire [7:0]  rd_err_code;
    wire        rd_cs_n;
    wire [15:0] rd_clk_div;
    wire        rd_tx_valid;
    wire [7:0]  rd_tx_data;
    wire [15:0] rd_crc_rx;
    wire [3:0]  rd_dbg_state;


    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;


    wire        uart_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;


    wire        spi_use_reader = init_done;

    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;


    assign sd_ncs = init_cs_n & rd_cs_n;


    assign uart_tx_valid = rd_data_valid & uart_ready;
    assign uart_tx_data  = rd_data;
    assign rd_data_ready = uart_tx_valid;


    wire init_start = (st == ST_INIT);

    wire rd_en      = (st == ST_RD) && rd_ready;


    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n)
            pwr_cnt <= 24'd0;
        else if (st == ST_POWER)
            pwr_cnt <= pwr_cnt + 24'd1;
    end


    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            st <= ST_POWER;
        end else begin
            case (st)

            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INIT;
            end

            ST_INIT: begin
                st <= ST_WAIT;
            end

            ST_WAIT: begin
                if (init_done)       st <= ST_RD;
                else if (init_error) st <= ST_ERR;
            end

            ST_RD: begin
                if (rd_ready) st <= ST_STREAM;
            end

            ST_STREAM: begin
                if (rd_done) begin
                    if (rd_timeout || rd_crc16_err || (rd_err_code != 8'h00))
                        st <= ST_ERR;
                    else
                        st <= ST_OK;
                end
            end
            ST_OK:  st <= ST_OK;
            ST_ERR: st <= ST_ERR;
            default: st <= ST_POWER;
            endcase
        end
    end


    wire [7:0] err_code_sel = (st == ST_WAIT) ? init_err_code : rd_err_code;

    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER : led_code = 4'h1;
            ST_INIT  : led_code = 4'h2;
            ST_WAIT  : led_code = 4'h3;
            ST_RD    : led_code = 4'h4;
            ST_STREAM: led_code = 4'h5;
            ST_OK    : led_code = 4'h8;
            default  : led_code = err_code_sel[3:0];
        endcase
    end

    assign led = led_code;


    sd_initializer u_sd_initializer (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .start         (init_start),
        .sdhc          (sdhc),
        .init_done     (init_done),
        .init_error    (init_error),
        .err_code      (init_err_code),
        .err_detail    (),
        .retry_cnt     (),
        .dbg_state     (),
        .spi_cs_n      (init_cs_n),
        .spi_clk_div   (init_clk_div),
        .spi_tx_valid  (init_tx_valid),
        .spi_tx_data   (init_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );


    sd_sector_reader u_sd_sector_reader (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .sdhc          (sdhc),
        .rd_en         (rd_en),
        .rd_addr       (TARGET_LBA),
        .rd_len        (16'd1),
        .rd_ready      (rd_ready),
        .data          (rd_data),
        .data_valid    (rd_data_valid),
        .data_ready    (rd_data_ready),
        .data_last     (rd_data_last),
        .rd_done       (rd_done),
        .busy          (rd_busy),
        .timeout_err   (rd_timeout),
        .crc16_err     (rd_crc16_err),
        .err_code      (rd_err_code),
        .err_detail    (),
        .crc_rx        (rd_crc_rx),
        .dbg_state     (rd_dbg_state),
        .spi_cs_n      (rd_cs_n),
        .spi_clk_div   (rd_clk_div),
        .spi_tx_valid  (rd_tx_valid),
        .spi_tx_data   (rd_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );


    spi_master #(
        .CLK_FREQ (CLK_FREQ)
    ) u_spi_master (
        .clk        (clk),
        .rst_n      (rst_sync_n),
        .clk_div    (spi_clk_div),
        .cs_n       (sd_ncs),
        .tx_valid   (spi_tx_valid),
        .tx_data    (spi_tx_data),
        .tx_ready   (spi_tx_ready),
        .rx_data    (spi_rx_data),
        .rx_valid   (spi_rx_valid),
        .busy       (spi_busy),
        .sclk       (sd_dclk),
        .mosi       (sd_mosi),
        .miso       (sd_miso)
    );


    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_sync_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_ready),
        .txd       (uart_txd)
    );

endmodule
