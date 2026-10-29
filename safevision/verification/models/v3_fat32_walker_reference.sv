


`include "safevision_defs.vh"

module v3_fat32_walker_reference (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        rst_walk,
    input  wire        start,
    input  wire [31:0] cur_clus,
    output reg         busy,
    output reg         done,
    output reg  [31:0] next_clus,
    output reg         eoc,
    output reg         error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [31:0] hop_cnt,
    output reg  [3:0]  dbg_state,


    input  wire [31:0] fat_start_lba,
    input  wire [31:0] total_clus,


    output reg  [31:0] sd_rd_addr,
    output wire [15:0] sd_rd_len,
    output reg         sd_rd_en,
    input  wire        sd_rd_ready,
    input  wire [7:0]  sd_data,
    input  wire        sd_data_valid,
    output wire        sd_data_ready,
    input  wire        sd_data_last,
    input  wire        sd_rd_done,
    input  wire        sd_timeout_err,
    input  wire        sd_crc16_err,
    input  wire [7:0]  sd_err_code,
    input  wire [7:0]  sd_err_detail
);


    localparam [2:0] W_IDLE = 3'd0,
                     W_REQ  = 3'd1,
                     W_RECV = 3'd2,
                     W_DONE = 3'd3,
                     W_ERR  = 3'd4;

    reg  [2:0]  mstate;
    reg  [8:0]  bcnt;
    reg  [8:0]  fat_off;
    reg  [31:0] fat_val;
    reg  [31:0] to_cnt;


    wire [31:0] fat_byte_off = {cur_clus[29:0], 2'b00};
    wire [31:0] fat_lba      = fat_start_lba + (fat_byte_off >> 9);


    wire        fat_in_win = (bcnt >= fat_off) && (bcnt <= (fat_off + 9'd3));
    wire [31:0] fat_now    = fat_in_win ? {sd_data, fat_val[31:8]} : fat_val;
    wire [27:0] nxt_clus   = fat_now[27:0];
    wire        nxt_eoc    = (nxt_clus >= 28'h0FFF_FFF8);
    wire        nxt_oob    = (nxt_clus < 28'd2) ||
                             ({4'b0, nxt_clus} > (total_clus + 32'd1));
    wire        nxt_loop   = ((hop_cnt + 32'd1) > total_clus);

    assign sd_data_ready = (mstate == W_RECV);
    assign sd_rd_len     = 16'd1;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate     <= W_IDLE;
            bcnt       <= 9'd0;
            fat_off    <= 9'd0;
            fat_val    <= 32'h0;
            to_cnt     <= 32'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
            next_clus  <= 32'd0;
            eoc        <= 1'b0;
            error      <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            hop_cnt    <= 32'd0;
            dbg_state  <= W_IDLE;
            sd_rd_addr <= 32'd0;
            sd_rd_en   <= 1'b0;
        end else begin
            dbg_state <= mstate;
            done      <= 1'b0;
            sd_rd_en  <= 1'b0;
            busy      <= (mstate != W_IDLE);


            if (rst_walk) hop_cnt <= 32'd0;

            case (mstate)

            W_IDLE: begin
                if (start) begin
                    eoc        <= 1'b0;
                    error      <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    next_clus  <= 32'd0;
                    fat_off    <= {cur_clus[6:0], 2'b00};
                    fat_val    <= 32'h0;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= W_REQ;
                end
            end

            W_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= W_ERR;
                end else if (sd_rd_ready) begin
                    sd_rd_addr <= fat_lba;
                    sd_rd_en   <= 1'b1;
                    to_cnt     <= 32'd0;
                    mstate     <= W_RECV;
                end
            end

            W_RECV: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= W_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= W_ERR;
                end else if (sd_data_valid && sd_data_ready) begin
                    if (fat_in_win) fat_val <= {sd_data, fat_val[31:8]};

                    bcnt <= bcnt + 9'd1;
                    if (bcnt == 9'd511) begin
                        if (nxt_eoc) begin
                            eoc      <= 1'b1;
                            next_clus<= {4'b0, nxt_clus};
                            mstate   <= W_DONE;
                        end else if (nxt_oob) begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_DIR_OOB;
                            mstate     <= W_ERR;
                        end else if (nxt_loop) begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_FS_LOOP;
                            mstate     <= W_ERR;
                        end else begin
                            next_clus <= {4'b0, nxt_clus};
                            hop_cnt   <= hop_cnt + 32'd1;
                            mstate    <= W_DONE;
                        end
                    end
                end
            end

            W_DONE: begin
                done   <= 1'b1;
                mstate <= W_IDLE;
            end
            W_ERR: begin
                error  <= 1'b1;
                done   <= 1'b1;
                mstate <= W_IDLE;
            end
            default: mstate <= W_IDLE;
            endcase
        end
    end

endmodule
