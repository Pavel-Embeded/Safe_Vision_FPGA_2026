


`include "safevision_defs.vh"

module fat32_boot_parser255_reference (
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    output reg         mount_done,
    output reg         mount_error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [3:0]  dbg_state,


    output reg  [15:0] bytes_per_sec,
    output reg  [7:0]  sec_per_clus,
    output reg  [7:0]  num_fats,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] root_clus,
    output reg  [31:0] root_dir_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] total_sec,
    output reg  [31:0] total_clus,


    output reg  [31:0] sd_rd_addr,
    output reg  [15:0] sd_rd_len,
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


    localparam [3:0] M_IDLE = 4'd0,
                     M_REQ  = 4'd1,
                     M_RECV = 4'd2,
                     M_EVAL = 4'd3,
                     M_DONE = 4'd4,
                     M_ERR  = 4'd5;

    reg  [3:0]  mstate;
    reg  [9:0]  bcnt;


    localparam integer TO_W=$clog2(`SD_TO_DATA+32'd2);
    reg [TO_W-1:0] to_cnt;


    reg  [7:0]  bps_l,  bps_h;
    reg  [7:0]  spc;
    reg  [7:0]  rsvd_l, rsvd_h;
    reg  [7:0]  nfat;
    reg  [7:0]  roote_l, roote_h;
    reg  [7:0]  ts16_l, ts16_h;
    reg  [7:0]  media;
    reg  [7:0]  fs16_l, fs16_h;
    reg  [7:0]  ts32_0, ts32_1, ts32_2, ts32_3;
    reg  [7:0]  fs32_0, fs32_1, fs32_2, fs32_3;
    reg  [7:0]  rc_0,   rc_1,   rc_2,   rc_3;
    reg  [7:0]  sig_l,  sig_h;


    wire [15:0] w_bps   = {bps_h,  bps_l};
    wire [15:0] w_rsvd  = {rsvd_h, rsvd_l};
    wire [15:0] w_roote = {roote_h, roote_l};
    wire [15:0] w_ts16  = {ts16_h, ts16_l};
    wire [15:0] w_fs16  = {fs16_h, fs16_l};
    wire [31:0] w_ts32  = {ts32_3, ts32_2, ts32_1, ts32_0};
    wire [31:0] w_fs32  = {fs32_3, fs32_2, fs32_1, fs32_0};
    wire [31:0] w_rc    = {rc_3,   rc_2,   rc_1,   rc_0};
    wire        w_sig_ok = (sig_l == 8'h55) && (sig_h == 8'hAA);


    wire is_fat32_fields = (w_roote == 16'h0000) &&
                           (w_fs16  == 16'h0000) &&
                           (w_ts16  == 16'h0000) &&
                           (w_fs32  != 32'h0000_0000);
    wire spc_ok = (spc != 8'd0) && (spc <= 8'd128) && ((spc & (spc - 8'd1)) == 8'd0);


    wire [2:0] w_log2_spc = (spc[7])  ?  3'd7 :
                            (spc[6])  ?  3'd6 :
                            (spc[5])  ?  3'd5 :
                            (spc[4])  ?  3'd4 :
                            (spc[3])  ?  3'd3 :
                            (spc[2])  ?  3'd2 :
                            (spc[1])  ?  3'd1 : 3'd0;
    wire nfat_ok = (nfat == 8'd1) || (nfat == 8'd2);


    reg [4:0] bpb_checks_q;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)bpb_checks_q<=0;
        else bpb_checks_q<={w_rc>=32'd2,nfat_ok,spc_ok,is_fat32_fields,w_bps==16'd512};
    end


    assign sd_data_ready = (mstate == M_RECV);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate        <= M_IDLE;
            bcnt          <= 10'd0;
            to_cnt        <= 32'd0;
            mount_done    <= 1'b0;
            mount_error   <= 1'b0;
            err_code      <= `ERR_NONE;
            err_detail    <= `DET_NONE;
            bytes_per_sec <= 16'd0;
            sec_per_clus  <= 8'd0;
            num_fats      <= 8'd0;
            fat_start_lba <= 32'd0;
            root_clus     <= 32'd0;
            root_dir_lba  <= 32'd0;
            data_start_lba<= 32'd0;
            total_sec     <= 32'd0;
            total_clus    <= 32'd0;
            sd_rd_addr    <= 32'd0;
            sd_rd_len     <= 16'd1;
            sd_rd_en      <= 1'b0;
            dbg_state     <= M_IDLE;
            bps_l <= 8'h0; bps_h <= 8'h0; spc <= 8'h0;
            rsvd_l <= 8'h0; rsvd_h <= 8'h0; nfat <= 8'h0;
            roote_l <= 8'h0; roote_h <= 8'h0; ts16_l <= 8'h0; ts16_h <= 8'h0;
            media <= 8'h0; fs16_l <= 8'h0; fs16_h <= 8'h0;
            ts32_0 <= 8'h0; ts32_1 <= 8'h0; ts32_2 <= 8'h0; ts32_3 <= 8'h0;
            fs32_0 <= 8'h0; fs32_1 <= 8'h0; fs32_2 <= 8'h0; fs32_3 <= 8'h0;
            rc_0 <= 8'h0; rc_1 <= 8'h0; rc_2 <= 8'h0; rc_3 <= 8'h0;
            sig_l <= 8'h0; sig_h <= 8'h0;
        end else begin
            dbg_state <= mstate;
            sd_rd_en  <= 1'b0;

            case (mstate)

            M_IDLE: begin
                mount_done <= 1'b0;
                if (start) begin
                    mount_error <= 1'b0;
                    err_code    <= `ERR_NONE;
                    err_detail  <= `DET_NONE;
                    bcnt        <= 10'd0;
                    to_cnt      <= 32'd0;
                    sd_rd_addr  <= 32'd0;
                    sd_rd_len   <= 16'd1;
                    mstate      <= M_REQ;
                end
            end

            M_REQ: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= M_ERR;
                end else if (sd_rd_ready) begin
                    sd_rd_en <= 1'b1;
                    mstate   <= M_RECV;
                end
            end

            M_RECV: begin
                to_cnt <= to_cnt + 32'd1;
                if (to_cnt == `SD_TO_DATA) begin
                    err_code   <= `ERR_SD_IO;
                    err_detail <= `DET_SD_TOKEN_TO;
                    mstate     <= M_ERR;
                end else if (sd_data_valid) begin

                    case (bcnt)
                        10'd11 : bps_l   <= sd_data;
                        10'd12 : bps_h   <= sd_data;
                        10'd13 : spc     <= sd_data;
                        10'd14 : rsvd_l  <= sd_data;
                        10'd15 : rsvd_h  <= sd_data;
                        10'd16 : nfat    <= sd_data;
                        10'd17 : roote_l <= sd_data;
                        10'd18 : roote_h <= sd_data;
                        10'd19 : ts16_l  <= sd_data;
                        10'd20 : ts16_h  <= sd_data;
                        10'd21 : media   <= sd_data;
                        10'd22 : fs16_l  <= sd_data;
                        10'd23 : fs16_h  <= sd_data;
                        10'd32 : ts32_0  <= sd_data;
                        10'd33 : ts32_1  <= sd_data;
                        10'd34 : ts32_2  <= sd_data;
                        10'd35 : ts32_3  <= sd_data;
                        10'd36 : fs32_0  <= sd_data;
                        10'd37 : fs32_1  <= sd_data;
                        10'd38 : fs32_2  <= sd_data;
                        10'd39 : fs32_3  <= sd_data;
                        10'd44 : rc_0    <= sd_data;
                        10'd45 : rc_1    <= sd_data;
                        10'd46 : rc_2    <= sd_data;
                        10'd47 : rc_3    <= sd_data;
                        10'd510: sig_l   <= sd_data;
                        10'd511: sig_h   <= sd_data;
                        default: ;
                    endcase
                    bcnt <= bcnt + 10'd1;

                    if (bcnt == 10'd511) mstate <= M_EVAL;
                end
            end

            M_EVAL: begin
                if (sd_timeout_err || sd_crc16_err) begin

                    err_code   <= sd_err_code;
                    err_detail <= sd_err_detail;
                    mstate     <= M_ERR;
                end else if (!w_sig_ok) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[0]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[1]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_NOT32;
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[2] || !bpb_checks_q[3]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;
                    mstate     <= M_ERR;
                end else if (!bpb_checks_q[4]) begin
                    err_code   <= `ERR_MEDIA_INVALID;
                    err_detail <= `DET_FAT_BPB;
                    mstate     <= M_ERR;
                end else begin

                    bytes_per_sec  <= w_bps;
                    sec_per_clus   <= spc;
                    num_fats       <= nfat;
                    fat_start_lba  <= {16'd0, w_rsvd};
                    root_clus      <= w_rc;
                    data_start_lba <= {16'd0, w_rsvd} + (nfat == 8'd2  ?  (w_fs32<<1) : w_fs32);
                    root_dir_lba   <= {16'd0, w_rsvd} + (nfat == 8'd2  ?  (w_fs32<<1) : w_fs32)
                                      + ((w_rc - 32'd2) << w_log2_spc);
                    total_sec      <= w_ts32;


                    total_clus     <= (w_ts32 - ({16'd0, w_rsvd} + (nfat == 8'd2  ?  (w_fs32<<1) : w_fs32))) >> w_log2_spc;
                    mstate         <= M_DONE;
                end
            end

            M_DONE: begin
                mount_done <= 1'b1;
                if (start) begin

                    mount_done <= 1'b0;
                    bcnt       <= 10'd0;
                    to_cnt     <= 32'd0;
                    sd_rd_addr <= 32'd0;
                    mstate     <= M_REQ;
                end
            end
            M_ERR: begin
                mount_error <= 1'b1;
                if (start) begin
                    mount_error <= 1'b0;
                    err_code    <= `ERR_NONE;
                    err_detail  <= `DET_NONE;
                    bcnt        <= 10'd0;
                    to_cnt      <= 32'd0;
                    mstate      <= M_REQ;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end

endmodule
