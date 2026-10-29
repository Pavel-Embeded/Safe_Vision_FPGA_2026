


`include "safevision_defs.vh"
module mbr_parser (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    output reg         parse_done,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [3:0]  dbg_state,

    output reg         has_mbr,
    output reg  [31:0] vol_base_lba,
    output reg  [31:0] part_secs,

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


    localparam [2:0] M_IDLE = 3'd0,
                     M_REQ  = 3'd1,
                     M_RECV = 3'd2,
                     M_EVAL = 3'd3,
                     M_DONE = 3'd4,
                     M_ERR  = 3'd5;
    reg  [2:0]  mstate;
    reg  [9:0]  bcnt;


    localparam integer TO_W=$clog2(`SD_TO_DATA+32'd2);
    reg [TO_W-1:0] to_cnt;


    reg [31:0] hdr_base;
    wire [7:0] pb0=hdr_base[0+:8];
    wire [7:0] pb1=hdr_base[8+:8];
    wire [7:0] pb2=hdr_base[16+:8];
    wire [7:0] pb3=hdr_base[24+:8];
    reg [31:0] hdr_size;
    wire [7:0] ps0=hdr_size[0+:8];
    wire [7:0] ps1=hdr_size[8+:8];
    wire [7:0] ps2=hdr_size[16+:8];
    wire [7:0] ps3=hdr_size[24+:8];
    reg hdr_sig_matches;
    reg part_nonzero;
    always @(posedge clk)begin
      if(rst_n && mstate==M_RECV && to_cnt!=`SD_TO_DATA && sd_data_valid)begin
        if(bcnt>=454 && bcnt<=457)hdr_base <= {sd_data,hdr_base[31:8]};
        if(bcnt>=458 && bcnt<=461)hdr_size <= {sd_data,hdr_size[31:8]};
        if(bcnt==510)hdr_sig_matches<=sd_data==8'h55;
        if(bcnt==511)hdr_sig_matches<=hdr_sig_matches&&(sd_data==8'haa);
        if(bcnt==450)part_nonzero<=|sd_data;
      end
    end


    wire [31:0] w_start_lba = {pb3, pb2, pb1, pb0};
    wire [31:0] w_secs      = {ps3, ps2, ps1, ps0};
    wire        w_sig_ok    = hdr_sig_matches;


    wire        w_ok        = w_sig_ok && part_nonzero && (w_start_lba != 32'd0);
    assign sd_data_ready = (mstate == M_RECV);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate       <= M_IDLE;
            bcnt         <= 10'd0;
            to_cnt       <= 32'd0;
            sd_rd_addr   <= 32'd0;
            sd_rd_len    <= 16'd1;
            sd_rd_en     <= 1'b0;
            parse_done   <= 1'b0;
            has_mbr      <= 1'b0;
            vol_base_lba <= 32'd0;
            part_secs    <= 32'd0;
            err_code     <= `ERR_NONE;
            err_detail   <= `DET_NONE;
            dbg_state    <= M_IDLE;
        end else begin
            sd_rd_en  <= 1'b0;
            dbg_state <= mstate;
            case (mstate)

            M_IDLE: begin
                if (start) begin
                    parse_done   <= 1'b0;
                    has_mbr      <= 1'b0;
                    vol_base_lba <= 32'd0;
                    part_secs    <= 32'd0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    bcnt         <= 10'd0;
                    to_cnt       <= 32'd0;
                    sd_rd_addr   <= 32'd0;
                    sd_rd_len    <= 16'd1;
                    mstate       <= M_REQ;
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
                end else begin
                    has_mbr      <= w_ok;
                    vol_base_lba <= w_ok ? w_start_lba : 32'd0;
                    part_secs    <= w_ok ? w_secs      : 32'd0;
                    mstate       <= M_DONE;
                end
            end

            M_DONE: begin
                parse_done <= 1'b1;
                if (start) begin
                    parse_done   <= 1'b0;
                    has_mbr      <= 1'b0;
                    vol_base_lba <= 32'd0;
                    part_secs    <= 32'd0;
                    err_code     <= `ERR_NONE;
                    err_detail   <= `DET_NONE;
                    bcnt         <= 10'd0;
                    to_cnt       <= 32'd0;
                    sd_rd_addr   <= 32'd0;
                    sd_rd_len    <= 16'd1;
                    mstate       <= M_REQ;
                end
            end
            M_ERR: begin
                parse_done <= 1'b1;
                if (start) begin
                    parse_done <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    bcnt       <= 10'd0;
                    to_cnt     <= 32'd0;
                    sd_rd_addr <= 32'd0;
                    sd_rd_len  <= 16'd1;
                    mstate     <= M_REQ;
                end
            end
            default: mstate <= M_IDLE;
            endcase
        end
    end
endmodule
