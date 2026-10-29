


`include "safevision_defs.vh"

module fat32_directory_scanner #(parameter integer SV_MEDIA_ONLY=0) (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        scan_en,
    output reg         scan_done,
    output reg         dir_bad,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [3:0]  dbg_state,


    input  wire [7:0]  sec_per_clus,
    input  wire [31:0] root_clus,
    input  wire [31:0] root_dir_lba,
    input  wire [31:0] data_start_lba,


    output wire [87:0] ent_name,
    output reg  [7:0]  ent_attr,
    output reg  [31:0] ent_first_clus,
    output reg  [31:0] ent_size,
    output reg  [15:0] ent_index,
    output reg         ent_valid,
    input  wire        ent_ready,


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
    input  wire [7:0]  sd_err_detail,


    output reg  [31:0] wk_cur_clus,
    output reg         wk_start,
    output reg         wk_rst_walk,
    input  wire        wk_busy,
    input  wire        wk_done,
    input  wire [31:0] wk_next_clus,
    input  wire        wk_eoc,
    input  wire        wk_error,
    input  wire [7:0]  wk_err_code,
    input  wire [7:0]  wk_err_detail
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


    localparam [2:0] D_IDLE     = 3'd0,
                     D_SEC_REQ  = 3'd1,
                     D_SEC_RECV = 3'd2,
                     D_WALK     = 3'd3,
                     D_DONE     = 3'd5,
                     D_ERR      = 3'd6;

    reg  [2:0]  mstate;
    reg  [31:0] cur_clus;
    reg  [31:0] cur_lba;
    reg  [7:0]  sec_in_clus;
    reg  [8:0]  bcnt;
    reg  [31:0] to_cnt;


    reg [87:0] full_name;
    reg [15:0] media_digits;
    reg media_name_ok,media_bmp,media_wav;
    wire [87:0] media_name={16'h5356,
      4'h3,media_digits[15:12],4'h3,media_digits[11:8],
      4'h3,media_digits[7:4],4'h3,media_digits[3:0],16'h2020,
      (media_bmp?24'h424d50:24'h574156)};
    assign ent_name=SV_MEDIA_ONLY?media_name:full_name;
    wire [87:0] name_raw=ent_name;
    wire [7:0] attr_raw=ent_attr;
    wire [15:0] fc_h=ent_first_clus[31:16];
    wire [15:0] fc_l=ent_first_clus[15:0];
    wire [31:0] size_raw=ent_size;
    reg         skip_entry;
    reg         stop_pending;
    reg         wait_ent;
    reg  [15:0] slot_cnt;


    wire [4:0]  ent_off = bcnt[4:0];


    assign sd_data_ready = (mstate == D_SEC_RECV) && !wait_ent;
    assign sd_rd_len     = 16'd1;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= D_IDLE;
            scan_done    <= 1'b0;
            dir_bad      <= 1'b0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            dbg_state    <= D_IDLE;
            cur_clus     <= 32'd0;
            cur_lba      <= 32'd0;
            sec_in_clus  <= 8'd0;
            bcnt         <= 9'd0;
            to_cnt       <= 32'd0;


            skip_entry   <= 1'b0;
            stop_pending <= 1'b0;
            wait_ent     <= 1'b0;
            slot_cnt     <= 16'd0;
            full_name<=0;media_digits<=0;media_name_ok<=0;media_bmp<=0;media_wav<=0;
            ent_attr       <= 8'h0;
            ent_first_clus <= 32'h0;
            ent_size       <= 32'h0;
            ent_index      <= 16'h0;
            ent_valid      <= 1'b0;
            sd_rd_addr     <= 32'd0;
            sd_rd_en       <= 1'b0;
            wk_cur_clus    <= 32'd0;
            wk_start       <= 1'b0;
            wk_rst_walk    <= 1'b0;
        end else begin
            dbg_state   <= mstate;
            sd_rd_en    <= 1'b0;
            wk_start    <= 1'b0;
            wk_rst_walk <= 1'b0;


            if (wait_ent && ent_ready) begin
                wait_ent  <= 1'b0;
                ent_valid <= 1'b0;
            end

            case (mstate)

            D_IDLE: begin
                if (scan_en) begin
                    scan_done    <= 1'b0;
                    dir_bad      <= 1'b0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    cur_clus     <= root_clus;
                    cur_lba      <= root_dir_lba;
                    sec_in_clus  <= 8'd0;
                    bcnt         <= 9'd0;
                    to_cnt       <= 32'd0;


                    skip_entry   <= 1'b0;
                    stop_pending <= 1'b0;
                    wait_ent     <= 1'b0;
                    slot_cnt     <= 16'd0;
                    ent_valid    <= 1'b0;
                    wk_cur_clus  <= root_clus;
                    wk_rst_walk  <= 1'b1;
                    mstate       <= D_SEC_REQ;
                end
            end

            D_SEC_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= D_ERR;
                end else if (!wait_ent && (sd_timeout_err || sd_crc16_err)) begin

                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= D_ERR;
                end else if (!wait_ent && sd_rd_ready) begin
                    sd_rd_addr <= cur_lba;
                    sd_rd_en   <= 1'b1;
                    bcnt       <= 9'd0;
                    to_cnt     <= 32'd0;
                    mstate     <= D_SEC_RECV;
                end
            end

            D_SEC_RECV: begin

                if (!wait_ent) to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= D_ERR;
                end else if (sd_timeout_err || sd_crc16_err) begin
                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= D_ERR;
                end else if (sd_data_valid && sd_data_ready) begin
                    if(SV_MEDIA_ONLY)case(ent_off)
                      0:begin media_name_ok<=sd_data==8'h53;media_bmp<=0;media_wav<=0;end
                      1:if(sd_data!=8'h56)media_name_ok<=0;
                      2,3,4,5:begin
                        media_digits<={media_digits[11:0],sd_data[3:0]};
                        if(sd_data<8'h30||sd_data>8'h39)media_name_ok<=0;
                      end
                      6,7:if(sd_data!=8'h20)media_name_ok<=0;
                      8:begin media_bmp<=sd_data==8'h42;media_wav<=sd_data==8'h57;end
                      9:begin media_bmp<=media_bmp&&(sd_data==8'h4d);media_wav<=media_wav&&(sd_data==8'h41);end
                      10:begin media_bmp<=media_bmp&&(sd_data==8'h50);media_wav<=media_wav&&(sd_data==8'h56);end
                      default:;
                    endcase
                    case (ent_off)

                    5'd0: begin
                        skip_entry <= (sd_data == 8'hE5);
                        if (sd_data == 8'h00) begin
                            stop_pending <= 1'b1;
                            skip_entry   <= 1'b1;
                        end
                        if(!SV_MEDIA_ONLY)full_name <= {full_name[79:0], sd_data};
                    end

                    5'd1, 5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9, 5'd10:
                        if(!SV_MEDIA_ONLY)full_name <= {full_name[79:0], sd_data};
                    5'd11: ent_attr <= sd_data;


                    5'd20: ent_first_clus[23:16]  <= sd_data;
                    5'd21: ent_first_clus[31:24] <= sd_data;
                    5'd26: ent_first_clus[7:0]  <= sd_data;
                    5'd27: ent_first_clus[15:8] <= sd_data;
                    5'd28: ent_size[7:0]   <= sd_data;
                    5'd29: ent_size[15:8]  <= sd_data;
                    5'd30: ent_size[23:16] <= sd_data;

                    5'd31: begin
                        ent_size[31:24] <= sd_data;
                        if (!stop_pending && !skip_entry && (!SV_MEDIA_ONLY || (media_name_ok&&(media_bmp||media_wav)))) begin
                            if (attr_raw == 8'h0F) begin

                            end else if (attr_raw[3]) begin

                            end else if (attr_raw[4]) begin

                            end else begin

                                ent_size       <= {sd_data, ent_size[23:0]};
                                ent_index      <= slot_cnt;
                                ent_valid      <= 1'b1;
                                wait_ent       <= 1'b1;
                            end
                        end
                        slot_cnt <= slot_cnt + 16'd1;
                    end
                    default: ;
                    endcase

                    bcnt <= bcnt + 9'd1;

                    if (bcnt == 9'd511) begin
                        if (stop_pending) begin
                            mstate <= D_DONE;
                        end else if ((sec_in_clus + 8'd1) >= sec_per_clus) begin

                            wk_start <= 1'b1;
                            mstate   <= D_WALK;
                        end else begin
                            cur_lba     <= cur_lba + 32'd1;
                            sec_in_clus <= sec_in_clus + 8'd1;
                            to_cnt      <= 32'd0;
                            mstate      <= D_SEC_REQ;
                        end
                    end
                end
            end

            D_WALK: begin
                if (wk_done) begin
                    if (wk_eoc) begin
                        mstate <= D_DONE;
                    end else if (wk_error) begin
                        dir_bad    <= 1'b1;
                        err_code   <= wk_err_code;
                        err_detail <= wk_err_detail;
                        mstate     <= D_ERR;
                    end else begin
                        cur_clus    <= wk_next_clus;
                        wk_cur_clus <= wk_next_clus;
                        cur_lba     <= data_start_lba +
                                       cluster_sectors(wk_next_clus-32'd2,sec_per_clus);
                        sec_in_clus <= 8'd0;
                        to_cnt      <= 32'd0;
                        mstate      <= D_SEC_REQ;
                    end
                end
            end

            D_DONE: begin

                if (!wait_ent) begin
                    scan_done <= 1'b1;
                    mstate    <= D_IDLE;
                end
            end
            D_ERR: begin
                if (!wait_ent) begin
                    scan_done <= 1'b1;
                    mstate    <= D_IDLE;
                end
            end
            default: mstate <= D_IDLE;
            endcase
        end
    end

endmodule
