


`include "safevision_defs.vh"

module sd_initializer #(


    parameter [15:0] CLK_DIV_INIT = `SD_DIV_INIT,


    parameter [2:0]  CMD0_RETRY_MAX = 3'd3
) (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    output reg         sdhc,
    output reg         init_done,
    output reg         init_error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [7:0]  retry_cnt,
    output reg  [3:0]  dbg_state,


    output wire [7:0]  dbg_r1,
    output wire [2:0]  dbg_seq,


    output reg         spi_cs_n,
    output reg  [15:0] spi_clk_div,
    output wire        spi_tx_valid,
    output wire [7:0]  spi_tx_data,
    input  wire        spi_tx_ready,
    input  wire [7:0]  spi_rx_data,
    input  wire        spi_rx_valid
);


    localparam [3:0] M_IDLE  = 4'd0,
                     M_POWER = 4'd1,
                     M_CSON  = 4'd2,
                     M_CMD   = 4'd3,
                     M_R1    = 4'd4,
                     M_EXTRA = 4'd5,
                     M_NEXT  = 4'd6,
                     M_DONE  = 4'd7,
                     M_ERR   = 4'd8;


    localparam [1:0] B_IDLE = 2'd0, B_SEND = 2'd1, B_WAIT = 2'd2;

    reg  [1:0]  bstate;
    reg         bstart;
    reg  [7:0]  bdata;
    reg  [7:0]  brdata;
    reg         bdone;

    assign spi_tx_valid = (bstate == B_SEND);
    assign spi_tx_data  = bdata;


    reg  [3:0]  mstate;
    reg  [2:0]  seq;
    reg  [7:0]  bcnt;
    reg  [47:0] cmd_sr;
    reg  [31:0] extra_sr;
    reg  [7:0]  extra_len;
    reg  [7:0]  r1;
    reg         ver2;
    reg  [31:0] acmd41_arg;
    reg  [31:0] to_resp;
    reg  [31:0] to_acmd41;
    reg  [2:0]  cmd0_try;


    assign dbg_r1  = r1;
    assign dbg_seq = seq;


    function [47:0] make_cmd;
        input [5:0]  idx;
        input [31:0] arg;
        input [7:0]  crc;
        begin
            make_cmd = {(`SD_CMD_PREFIX | {2'b00, idx}),
                        arg[31:24], arg[23:16], arg[15:8], arg[7:0],
                        crc};
        end
    endfunction

    wire [47:0] cmd_frame = (seq == 3'd0) ? make_cmd(`SD_CMD0,  32'h0000_0000,   `SD_CRC_CMD0) :
                            (seq == 3'd1) ? make_cmd(`SD_CMD8,  `SD_CMD8_ARG,     `SD_CRC_CMD8) :
                            (seq == 3'd2) ? make_cmd(`SD_CMD55, 32'h0000_0000,   `SD_CRC_DONT_CARE) :
                            (seq == 3'd3) ? make_cmd(`SD_ACMD41, acmd41_arg,     `SD_CRC_DONT_CARE) :
                                            make_cmd(`SD_CMD58, 32'h0000_0000,   `SD_CRC_DONT_CARE);


    wire [7:0] cmd_extra_len = (seq == 3'd1 || seq == 3'd4) ? 8'd4 : 8'd0;


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


    task do_soft_reset;
        begin
            seq        <= 3'd0;
            bcnt       <= 8'd0;
            cmd_sr     <= 48'h0;
            extra_sr   <= 32'h0;
            extra_len  <= 8'd0;
            r1         <= 8'hFF;
            ver2       <= 1'b0;
            acmd41_arg <= `SD_ACMD41_HCS;
            sdhc       <= 1'b0;
            init_done  <= 1'b0;
            init_error <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            retry_cnt  <= 8'd0;
            to_resp    <= 32'd0;
            to_acmd41  <= 32'd0;
            cmd0_try   <= 3'd0;
        end
    endtask


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= M_IDLE;
            seq         <= 3'd0;
            bcnt        <= 6'd0;
            cmd_sr      <= 48'h0;
            extra_sr    <= 32'h0;
            extra_len   <= 8'd0;
            r1          <= 8'hFF;
            ver2        <= 1'b0;
            acmd41_arg  <= `SD_ACMD41_HCS;
            sdhc        <= 1'b0;
            init_done   <= 1'b0;
            init_error  <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            retry_cnt   <= 8'd0;
            spi_cs_n    <= 1'b1;
            spi_clk_div <= CLK_DIV_INIT;
            to_resp     <= 32'd0;
            to_acmd41   <= 32'd0;
            dbg_state   <= M_IDLE;
            bstart      <= 1'b0;
            bdata       <= 8'hFF;
        end else begin
            dbg_state <= mstate;
            bstart    <= 1'b0;


            if (mstate == M_ERR) init_error <= 1'b1;


            if (seq >= 3'd2 && mstate != M_IDLE && mstate != M_DONE && mstate != M_ERR)
                to_acmd41 <= to_acmd41 + 32'd1;

            case (mstate)

            M_IDLE: begin
                spi_cs_n   <= 1'b1;
                spi_clk_div<= CLK_DIV_INIT;
                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end

            M_POWER: begin
                spi_cs_n <= 1'b1;
                if (bdone) begin
                    if (bcnt == (`SD_POWERUP_BYTES - 1)) begin
                        bcnt   <= 6'd0;
                        seq    <= 3'd0;
                        mstate <= M_CSON;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            M_CSON: begin
                spi_cs_n <= 1'b0;
                if (bdone) begin
                    cmd_sr  <= cmd_frame;
                    bdata   <= cmd_frame[47:40];
                    bstart  <= 1'b1;
                    bcnt    <= 8'd0;
                    to_resp <= 32'd0;
                    mstate  <= M_CMD;
                end else if (bstate == B_IDLE && !bstart) begin
                    bdata  <= 8'hFF;
                    bstart <= 1'b1;
                end
            end

            M_CMD: begin
                if (bdone) begin
                    if (bcnt == 6'd5) begin
                        bcnt    <= 6'd0;
                        to_resp <= 32'd0;
                        mstate  <= M_R1;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        cmd_sr <= {cmd_sr[39:0], 8'hFF};
                        bdata  <= cmd_sr[39:32];
                        bstart <= 1'b1;
                    end
                end
            end

            M_R1: begin
                to_resp <= to_resp + 32'd1;
                if (to_resp == `SD_TO_RESP) begin

                    err_code   <= `ERR_SD_INIT;
                    err_detail <= `DET_SD_RESP_TO;
                    mstate     <= M_ERR;
                end else if (bdone) begin
                    if (brdata[7] == 1'b0) begin
                        r1          <= brdata;
                        bcnt        <= 8'd0;
                        extra_sr    <= 32'h0;
                        extra_len   <= cmd_extra_len;
                        if (cmd_extra_len == 8'd0) begin
                            mstate <= M_NEXT;
                        end else begin
                            bdata  <= 8'hFF;
                            bstart <= 1'b1;
                            mstate <= M_EXTRA;
                        end
                    end else if (bcnt >= `SD_RESP_MAX_BYTES) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_RESP_TO;
                        mstate     <= M_ERR;
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

            M_EXTRA: begin
                if (bdone) begin
                    extra_sr <= {extra_sr[23:0], brdata};
                    if (bcnt == extra_len - 8'd1) begin
                        bcnt   <= 6'd0;
                        mstate <= M_NEXT;
                    end else begin
                        bcnt   <= bcnt + 6'd1;
                        bdata  <= 8'hFF;
                        bstart <= 1'b1;
                    end
                end
            end

            M_NEXT: begin
                case (seq)

                3'd0: begin


                    if (r1[`SD_R1_IDLE_STATE] && (r1[6:2] == 5'd0)) begin
                        seq    <= 3'd1;
                        mstate <= M_CSON;
                    end else if (cmd0_try < CMD0_RETRY_MAX) begin
                        cmd0_try <= cmd0_try + 3'd1;
                        mstate   <= M_POWER;
                    end else begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;
                        mstate     <= M_ERR;
                    end
                end

                3'd1: begin
                    if (r1[`SD_R1_ILLEGAL_CMD]) begin

                        ver2       <= 1'b0;
                        acmd41_arg <= 32'h0000_0000;
                        seq        <= 3'd2;
                        mstate     <= M_CSON;
                    end else if (extra_sr[7:0] == `SD_CMD8_CHECK) begin

                        ver2       <= 1'b1;
                        acmd41_arg <= `SD_ACMD41_HCS;
                        seq        <= 3'd2;
                        mstate     <= M_CSON;
                    end else begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;
                        mstate     <= M_ERR;
                    end
                end

                3'd2: begin
                    if (r1[`SD_R1_ILLEGAL_CMD]) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_INIT_CMD;
                        mstate     <= M_ERR;
                    end else begin
                        seq    <= 3'd3;
                        mstate <= M_CSON;
                    end
                end

                3'd3: begin
                    if (r1[`SD_R1_IDLE_STATE]) begin

                        if (to_acmd41 >= `SD_TO_ACMD41) begin

                            err_code   <= `ERR_SD_INIT;
                            err_detail <= `DET_SD_INIT_CMD;
                            mstate     <= M_ERR;
                        end else begin
                            retry_cnt <= retry_cnt + 8'd1;
                            seq       <= 3'd2;
                            mstate    <= M_CSON;
                        end
                    end else begin
                        seq    <= 3'd4;
                        mstate <= M_CSON;
                    end
                end

                3'd4: begin
                    if (extra_sr[31] == 1'b0) begin
                        err_code   <= `ERR_SD_INIT;
                        err_detail <= `DET_SD_NO_OCR;
                        mstate     <= M_ERR;
                    end else begin
                        sdhc       <= ver2 ? extra_sr[30] : 1'b0;
                        init_done  <= 1'b1;
                        mstate     <= M_DONE;
                    end
                end
                default: mstate <= M_ERR;
                endcase
            end

            M_DONE: begin
                spi_cs_n <= 1'b1;

                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end
            M_ERR: begin
                spi_cs_n <= 1'b1;


                if (start) begin
                    do_soft_reset;
                    mstate <= M_POWER;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end

    endmodule
