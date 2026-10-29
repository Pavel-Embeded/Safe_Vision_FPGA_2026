


`include "safevision_defs.vh"


module v3_file_streamer_compact_ctx (
    input wire context_load,
    input wire [135:0] context_in,
    output wire [135:0] context_out,
    input wire context_enable,
    input wire stream_enable,
    output wire idle_between_sectors,
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    input  wire [31:0] first_clus,
    input  wire [31:0] file_size,
    output reg         busy,
    output reg         done,
    output reg         error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output wire [31:0] bytes_rd,
    output reg  [3:0]  dbg_state,


    output reg  [7:0]  data,
    output reg         valid,
    input  wire        ready,
    output reg         sof,
    output reg         eof,


    input  wire [7:0]  sec_per_clus,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] total_clus,


    output reg  [31:0] wk_cur_clus,
    output reg         wk_start,
    output reg         wk_rst_walk,
    input  wire        wk_busy,
    input  wire        wk_done,
    input  wire [31:0] wk_next_clus,
    input  wire        wk_eoc,
    input  wire        wk_error,
    input  wire [7:0]  wk_err_code,
    input  wire [7:0]  wk_err_detail,


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


    function [31:0] cluster_sectors;
      input [31:0] delta;input [7:0] spc;
      begin case(spc)
       1:cluster_sectors=delta;2:cluster_sectors=delta<<1;4:cluster_sectors=delta<<2;
       8:cluster_sectors=delta<<3;16:cluster_sectors=delta<<4;32:cluster_sectors=delta<<5;
       64:cluster_sectors=delta<<6;128:cluster_sectors=delta<<7;
       default:cluster_sectors=0;
      endcase end
    endfunction


    localparam [2:0] F_IDLE     = 3'd0,
                     F_SEC_REQ  = 3'd1,
                     F_SEC_RECV = 3'd2,
                     F_WALK     = 3'd3,
                     F_DONE     = 3'd4,
                     F_ERR      = 3'd5;

    reg  [2:0]  mstate;

    reg  [31:0] cur_lba;
    reg  [7:0]  sec_in_clus;
    reg  [8:0]  bcnt;
    reg  [31:0] cnt;
    reg  [31:0] fsize;
    reg         stop_pending;
    reg  [31:0] to_cnt;

    assign idle_between_sectors = (mstate == F_SEC_REQ) && !valid;
    assign sd_data_ready = (mstate == F_SEC_RECV) && !valid;
    assign sd_rd_len     = 16'd1;


    assign context_out={wk_cur_clus,cur_lba,sec_in_clus,cnt,fsize};
    assign bytes_rd=cnt;
    wire [31:0] next_count=cnt+32'd1;
    wire last_file_byte=next_count==fsize;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= F_IDLE;

            cur_lba      <= 32'd0;
            sec_in_clus  <= 8'd0;
            bcnt         <= 9'd0;
            cnt          <= 32'd0;
            fsize        <= 32'd0;
            stop_pending <= 1'b0;
            to_cnt       <= 32'd0;
            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;

            dbg_state    <= F_IDLE;
            data         <= 8'h00;
            valid        <= 1'b0;
            sof          <= 1'b0;
            eof          <= 1'b0;
            wk_cur_clus  <= 32'd0;
            wk_start     <= 1'b0;
            wk_rst_walk  <= 1'b0;
            sd_rd_addr   <= 32'd0;
            sd_rd_en     <= 1'b0;
        end else if(context_load)begin
            {wk_cur_clus,cur_lba,sec_in_clus,cnt,fsize} <= context_in;
            mstate<=F_SEC_REQ;bcnt<=0;to_cnt<=0;stop_pending<=0;
            busy<=1;done<=0;error<=0;err_code<=0;err_detail<=0;
            data<=0;valid<=0;sof<=0;eof<=0;dbg_state<=F_SEC_REQ;
            sd_rd_addr<=0;sd_rd_en<=0;wk_start<=0;wk_rst_walk<=0;
        end else if (stream_enable && context_enable) begin
            dbg_state   <= mstate;
            sd_rd_en    <= 1'b0;
            wk_start    <= 1'b0;
            wk_rst_walk <= 1'b0;
            busy        <= (mstate != F_IDLE);


            if (valid && ready) begin
                valid <= 1'b0;
                sof   <= 1'b0;
                eof   <= 1'b0;
            end

            case (mstate)

            F_IDLE: begin
                if (start) begin
                    done         <= 1'b0;
                    error        <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    valid        <= 1'b0;
                    sof          <= 1'b0;
                    eof          <= 1'b0;
                    cnt          <= 32'd0;

                    fsize        <= file_size;

                    cur_lba      <= data_start_lba + cluster_sectors(first_clus-32'd2,sec_per_clus);
                    sec_in_clus  <= 8'd0;
                    bcnt         <= 9'd0;
                    stop_pending <= 1'b0;
                    to_cnt       <= 32'd0;
                    wk_cur_clus  <= first_clus;
                    wk_rst_walk  <= 1'b1;
                    if (file_size == 32'd0) begin

                        mstate <= F_DONE;
                    end else begin
                        mstate <= F_SEC_REQ;
                    end
                end
            end

            F_SEC_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= F_ERR;
                end else if (!valid && sd_rd_ready) begin
                    sd_rd_addr <= cur_lba;
                    sd_rd_en   <= 1'b1;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= F_SEC_RECV;
                end
            end

            F_SEC_RECV: begin

                if (!valid) to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= F_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= F_ERR;
                end else begin


                    if (!valid && sd_data_valid && sd_data_ready) begin
                        bcnt <= bcnt + 9'd1;

                        if (!stop_pending) begin
                            data  <= sd_data;
                            valid <= 1'b1;
                            sof   <= (cnt == 32'd0);
                            eof   <= (last_file_byte);
                            cnt   <= next_count;


                            if (last_file_byte) stop_pending <= 1'b1;
                        end


                        if (bcnt == 9'd511) begin


                            if (stop_pending || (last_file_byte)) begin
                                mstate <= F_DONE;
                            end else if ((sec_in_clus + 8'd1) >= sec_per_clus) begin
                                wk_start <= 1'b1;
                                mstate   <= F_WALK;
                            end else begin
                                cur_lba     <= cur_lba + 32'd1;
                                sec_in_clus <= sec_in_clus + 8'd1;
                                to_cnt      <= 32'd0;
                                mstate      <= F_SEC_REQ;
                            end
                        end
                    end
                end
            end

            F_WALK: begin
                if (wk_done) begin
                    if (wk_eoc) begin

                        err_code   <= `ERR_MEDIA_INVALID;
                        err_detail <= `DET_FS_SHORT;
                        mstate     <= F_ERR;
                    end else if (wk_error) begin
                        err_code   <= wk_err_code;
                        err_detail <= wk_err_detail;
                        mstate     <= F_ERR;
                    end else begin

                        wk_cur_clus <= wk_next_clus;
                        cur_lba     <= data_start_lba +
                                       cluster_sectors(wk_next_clus-32'd2,sec_per_clus);
                        sec_in_clus <= 8'd0;
                        to_cnt      <= 32'd0;
                        mstate      <= F_SEC_REQ;
                    end
                end
            end

            F_DONE: begin

                if (!valid) begin
                    done   <= 1'b1;
                    mstate <= F_IDLE;
                end
            end
            F_ERR: begin
                error  <= 1'b1;
                done   <= 1'b1;
                mstate <= F_IDLE;
            end
            default: mstate <= F_IDLE;
            endcase
        end
    end

endmodule
