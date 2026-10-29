


`include "safevision_defs.vh"

module sd_sector_reader #(

    parameter [15:0] CLK_DIV_FAST = `SD_DIV_FAST
) (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        sdhc,


    input  wire        rd_en,
    input  wire [31:0] rd_addr,
    input  wire [15:0] rd_len,
    output wire        rd_ready,


    output wire [7:0]  data,
    output wire        data_valid,
    input  wire        data_ready,
    output wire        data_last,


    output reg         rd_done,
    output reg         busy,
    output reg         timeout_err,
    output reg         crc16_err,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [15:0] crc_rx,
    output reg  [3:0]  dbg_state,


    output reg         spi_cs_n,
    output reg  [15:0] spi_clk_div,
    output wire        spi_tx_valid,
    output wire [7:0]  spi_tx_data,
    input  wire        spi_tx_ready,
    input  wire [7:0]  spi_rx_data,
    input  wire        spi_rx_valid
);


    localparam [3:0] S_IDLE  = 4'd0,
                     S_CSON  = 4'd1,
                     S_CMD   = 4'd2,
                     S_R1    = 4'd3,
                     S_TOKEN = 4'd4,
                     S_DATA  = 4'd5,
                     S_CRC   = 4'd6,
                     S_DONE  = 4'd7,
                     S_ERR   = 4'd8;


    localparam [1:0] B_IDLE = 2'd0, B_SEND = 2'd1, B_WAIT = 2'd2;

    reg  [1:0]  bstate;
    reg         bstart;
    reg  [7:0]  bdata;
    reg  [7:0]  brdata;
    reg         bdone;

    assign spi_tx_valid = (bstate == B_SEND);
    assign spi_tx_data  = bdata;


    reg  [3:0]  mstate;
    reg  [7:0]  bcnt;
    reg  [47:0] cmd_sr;
    reg  [9:0]  byte_cnt;
    reg  [15:0] crc_acc;
    reg  [7:0]  dbyte;
    reg         dvalid;
    reg  [31:0] to_resp;
    reg  [31:0] to_data;

    wire [15:0] crc_rx_next = {crc_rx[7:0], brdata};


    wire [15:0] crc_next_val;
    crc16_ccitt u_crc16 (
        .crc_in  (crc_acc),
        .data    (brdata),
        .crc_out (crc_next_val)
    );

    assign rd_ready   = (mstate == S_IDLE);
    assign data       = dbyte;
    assign data_valid = dvalid;
    assign data_last  = dvalid && (byte_cnt == `SD_SECTOR_BYTES);


    wire [31:0] cmd_arg = sdhc ? rd_addr : {rd_addr[22:0], 9'b0};
    wire [47:0] cmd_frame = {(`SD_CMD_PREFIX | {2'b00, `SD_CMD17}),
                             cmd_arg[31:24], cmd_arg[23:16], cmd_arg[15:8], cmd_arg[7:0],
                             `SD_CRC_DONT_CARE};


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bstate <= B_IDLE;
            brdata <= 8'h00;
            bdone  <= 1'b0;
        end else begin


            bdone  <= 1'b0;
            case (bstate)
                B_IDLE : if (bstart) bstate <= B_SEND;
                B_SEND : if (spi_tx_ready) bstate <= B_WAIT;
                B_WAIT : if (spi_rx_valid) begin
                             brdata <= spi_rx_data;
                             bdone  <= 1'b1;
                             bstate <= B_IDLE;
                         end
                default: bstate <= B_IDLE;
            endcase
        end
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= S_IDLE;
            bcnt        <= 6'd0;
            cmd_sr      <= 48'h0;
            byte_cnt    <= 10'd0;
            crc_acc     <= 16'h0;
            crc_rx      <= 16'h0;
            dbyte       <= 8'h00;
            dvalid      <= 1'b0;
            rd_done     <= 1'b0;
            busy        <= 1'b0;
            timeout_err <= 1'b0;
            crc16_err   <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            spi_cs_n    <= 1'b1;
            spi_clk_div <= CLK_DIV_FAST;
            to_resp     <= 32'd0;
            to_data     <= 32'd0;
            dbg_state   <= S_IDLE;
            bstart      <= 1'b0;
            bdata       <= 8'hFF;
        end else begin
            rd_done   <= 1'b0;
            dbg_state <= mstate;
            bstart    <= 1'b0;
            busy      <= (mstate != S_IDLE);

            case (mstate)

            S_IDLE: begin
                spi_cs_n    <= 1'b1;
                spi_clk_div <= CLK_DIV_FAST;
                dvalid      <= 1'b0;
                if (rd_en) begin
                    if (rd_len != 16'd1) begin

                        err_code   <= `ERR_SD_IO;
                        err_detail <= `DET_SD_TOKEN_TO;
                        rd_done    <= 1'b1;
                    end else begin
                        timeout_err <= 1'b0;
                        crc16_err   <= 1'b0;
                        err_code    <= `ERR_NONE;
                        err_detail  <= `DET_NONE;
                        crc_acc     <= 16'h0;
                        crc_rx      <= 16'h0;
                        byte_cnt    <= 10'd0;
                        bcnt        <= 6'd0;
                        to_resp     <= 32'd0;
                        to_data     <= 32'd0;
                        mstate      <= S_CSON;
                    end
                end
            end

            S_CSON: begin
                spi_cs_n <= 1'b0;
                if (bdone) begin
                    cmd_sr <= cmd_frame;
                    bdata  <= cmd_frame[47:40];
                    bstart <= 1'b1;
                    bcnt   <= 8'd0;
                    mstate <= S_CMD;
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            S_CMD: begin
                if (bdone) begin
                    if (bcnt == 6'd5) begin
                        bcnt    <= 6'd0;
                        to_resp <= 32'd0;
                        mstate  <= S_R1;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        cmd_sr <= {cmd_sr[39:0], 8'hFF};
                        bdata  <= cmd_sr[39:32];
                        bstart <= 1'b1;
                    end
                end
            end

            S_R1: begin
                to_resp <= to_resp + 32'd1;
                if (to_resp == `SD_TO_RESP) begin
                    timeout_err <= 1'b1;
                    err_code    <= `ERR_SD_IO;
                    err_detail  <= `DET_SD_RESP_TO;
                    mstate      <= S_ERR;
                end else if (bdone) begin
                    if (brdata[7] == 1'b0) begin
                        if (brdata != 8'h00) begin

                            err_code    <= `ERR_SD_IO;
                            err_detail  <= `DET_SD_RESP_TO;
                            timeout_err <= 1'b1;
                            mstate      <= S_ERR;
                        end else begin
                            to_data <= 32'd0;
                            mstate  <= S_TOKEN;
                        end
                    end else if (bcnt >= `SD_RESP_MAX_BYTES) begin
                        timeout_err <= 1'b1;
                        err_code    <= `ERR_SD_IO;
                        err_detail  <= `DET_SD_RESP_TO;
                        mstate      <= S_ERR;
                    end else begin
                        bcnt   <= bcnt + 8'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin

                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            S_TOKEN: begin
                to_data <= to_data + 32'd1;
                if (to_data == `SD_TO_DATA) begin
                    timeout_err <= 1'b1;
                    err_code    <= `ERR_SD_IO;
                    err_detail  <= `DET_SD_TOKEN_TO;
                    mstate      <= S_ERR;
                end else if (bdone) begin
                    if (brdata == `SD_TOKEN_DATA_START) begin
                        mstate <= S_DATA;
                    end else if (brdata[7:5] == 3'b000) begin

                        timeout_err <= 1'b1;
                        err_code    <= `ERR_SD_IO;
                        err_detail  <= `DET_SD_TOKEN_TO;
                        mstate      <= S_ERR;
                    end else begin
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin

                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            S_DATA: begin
                if (dvalid) begin
                    if (data_ready) begin
                        dvalid <= 1'b0;
                        if (byte_cnt == `SD_SECTOR_BYTES) begin
                            bcnt   <= 6'd0;
                            bdata  <= 8'hFF;
                            bstart <= 1'b1;
                            mstate <= S_CRC;
                        end
                    end
                end else if (bdone) begin
                    dbyte    <= brdata;
                    dvalid   <= 1'b1;
                    crc_acc  <= crc_next_val;
                    byte_cnt <= byte_cnt + 10'd1;
                end else if (bstate == B_IDLE) begin

                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            S_CRC: begin
                if (bdone) begin
                    crc_rx <= crc_rx_next;
                    if (bcnt == 6'd1) begin
                        if (crc_rx_next != crc_acc) begin
                            crc16_err <= 1'b1;
                            err_code <= `ERR_SD_IO;
                            err_detail <= `DET_SD_DATA_CRC;
                        end
                        mstate <= S_DONE;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end
            end

            S_DONE: begin
                spi_cs_n <= 1'b1;
                rd_done  <= 1'b1;
                mstate   <= S_IDLE;
            end
            S_ERR: begin
                spi_cs_n <= 1'b1;
                rd_done  <= 1'b1;
                mstate   <= S_IDLE;
            end
            default: mstate <= S_IDLE;
            endcase
        end
    end

endmodule
