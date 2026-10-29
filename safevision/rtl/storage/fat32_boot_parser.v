


`include "safevision_defs.vh"
module fat32_boot_parser (
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


    reg hdr_bps_matches;
    reg [15:0] hdr_rsvd;
    wire [7:0] rsvd_l=hdr_rsvd[0+:8];
    wire [7:0] rsvd_h=hdr_rsvd[8+:8];
    reg hdr_roote_matches;
    reg hdr_ts16_matches;
    reg hdr_fs16_matches;
    reg [31:0] hdr_ts32;
    wire [7:0] ts32_0=hdr_ts32[0+:8];
    wire [7:0] ts32_1=hdr_ts32[8+:8];
    wire [7:0] ts32_2=hdr_ts32[16+:8];
    wire [7:0] ts32_3=hdr_ts32[24+:8];
    reg [31:0] hdr_fs32;
    wire [7:0] fs32_0=hdr_fs32[0+:8];
    wire [7:0] fs32_1=hdr_fs32[8+:8];
    wire [7:0] fs32_2=hdr_fs32[16+:8];
    wire [7:0] fs32_3=hdr_fs32[24+:8];
    reg [31:0] hdr_root;
    wire [7:0] rc_0=hdr_root[0+:8];
    wire [7:0] rc_1=hdr_root[8+:8];
    wire [7:0] rc_2=hdr_root[16+:8];
    wire [7:0] rc_3=hdr_root[24+:8];
    reg hdr_sig_matches;
    reg[2:0] spc_log;reg spc_legal;
    wire[7:0] spc=spc_legal?(8'd1<<spc_log):8'd0;
    reg[1:0] nfat_class;
    wire[7:0] nfat={6'd0,nfat_class};
    reg[7:0] media;
    always @(posedge clk)begin
      if(rst_n && mstate==M_RECV && to_cnt!=`SD_TO_DATA && sd_data_valid)begin
        if(bcnt==11)hdr_bps_matches<=(sd_data==8'd0);
        if(bcnt==12)hdr_bps_matches<=hdr_bps_matches&&(sd_data==8'd2);
        if(bcnt>=14 && bcnt<=15)hdr_rsvd <= {sd_data,hdr_rsvd[15:8]};
        if(bcnt==17)hdr_roote_matches<=(sd_data==8'd0);
        if(bcnt==18)hdr_roote_matches<=hdr_roote_matches&&(sd_data==8'd0);
        if(bcnt==19)hdr_ts16_matches<=(sd_data==8'd0);
        if(bcnt==20)hdr_ts16_matches<=hdr_ts16_matches&&(sd_data==8'd0);
        if(bcnt==22)hdr_fs16_matches<=(sd_data==8'd0);
        if(bcnt==23)hdr_fs16_matches<=hdr_fs16_matches&&(sd_data==8'd0);
        if(bcnt>=32 && bcnt<=35)hdr_ts32 <= {sd_data,hdr_ts32[31:8]};
        if(bcnt>=36 && bcnt<=39)hdr_fs32 <= {sd_data,hdr_fs32[31:8]};
        if(bcnt>=44 && bcnt<=47)hdr_root <= {sd_data,hdr_root[31:8]};
        if(bcnt==510)hdr_sig_matches<=(sd_data==8'd85);
        if(bcnt==511)hdr_sig_matches<=hdr_sig_matches&&(sd_data==8'd170);
        if(bcnt==13)begin spc_legal<=sd_data!=0&&(sd_data&(sd_data-8'd1))==0;
          spc_log<=sd_data[7]?7:sd_data[6]?6:sd_data[5]?5:sd_data[4]?4:sd_data[3]?3:sd_data[2]?2:sd_data[1]?1:0;end
        if(bcnt==16)nfat_class<=sd_data==8'd1 ? 2'd1 : sd_data==8'd2 ? 2'd2 : 2'd0;
        if(bcnt==21)media<=sd_data;
      end
    end


    wire [15:0] w_bps   = hdr_bps_matches ? 16'd512 : 16'd0;
    wire [15:0] w_rsvd  = {rsvd_h, rsvd_l};
    wire [15:0] w_roote = hdr_roote_matches ? 16'd0 : 16'd1;
    wire [15:0] w_ts16  = hdr_ts16_matches ? 16'd0 : 16'd1;
    wire [15:0] w_fs16  = hdr_fs16_matches ? 16'd0 : 16'd1;
    wire [31:0] w_ts32  = {ts32_3, ts32_2, ts32_1, ts32_0};
    wire [31:0] w_fs32  = {fs32_3, fs32_2, fs32_1, fs32_0};
    wire [31:0] w_rc    = {rc_3,   rc_2,   rc_1,   rc_0};
    wire        w_sig_ok = hdr_sig_matches;

    wire is_fat32_fields = (w_roote == 16'h0000) &&
                           (w_fs16  == 16'h0000) &&
                           (w_ts16  == 16'h0000) &&
                           (w_fs32  != 32'h0000_0000);
    wire spc_ok = (spc != 8'd0) && (spc <= 8'd128) && ((spc & (spc - 8'd1)) == 8'd0);


    wire [2:0] w_log2_spc = spc_log;
    wire[31:0] base_value={16'd0,w_rsvd}+(nfat==8'd2 ? (w_fs32<<1):w_fs32);
    reg[31:0] staged_base,staged_payload;
    reg[7:0] staged_spc;
    reg[7:0] staged_inverse_spc;
    reg[25:0] root_low_product;
    reg[21:0] root_high_product;
    reg[39:0] staged_root_product;
    reg[25:0] count_low_product;
    reg[21:0] count_high_product;
    reg[39:0] staged_clus_product;
    (* dsp_style="yes" *) wire[25:0] root_low=w_rc[17:0]*staged_spc;
    (* dsp_style="yes" *) wire[21:0] root_high=w_rc[31:18]*staged_spc;
    (* dsp_style="yes" *) wire[25:0] count_low=staged_payload[17:0]*staged_inverse_spc;
    (* dsp_style="yes" *) wire[21:0] count_high=staged_payload[31:18]*staged_inverse_spc;


    always @(posedge clk)begin
      staged_base<=base_value;
      staged_payload<=w_ts32-staged_base;
      staged_spc<=spc;staged_inverse_spc<=8'd128>>spc_log;
      root_low_product<=root_low;
      root_high_product<=root_high;
      staged_root_product<={root_high_product,18'd0}+{14'd0,root_low_product};
      count_low_product<=count_low;count_high_product<=count_high;
      staged_clus_product<={count_high_product,18'd0}+{14'd0,count_low_product};
    end
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
                    data_start_lba <= staged_base;
                    root_dir_lba   <= staged_base
                                      + (staged_root_product[31:0]-{23'd0,spc,1'b0});
                    total_sec      <= w_ts32;


                    total_clus     <= staged_clus_product[38:7];
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
