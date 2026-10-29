


`include "safevision_defs.vh"

module bmp_parser_frozen_extent #(parameter integer VARIABLE_SIZE=0,FLEX_PIXELS=0) (
    input  wire        clk,
    input  wire        rst_n,


    input  wire [7:0]  data,
    input  wire        valid,
    output wire        ready,
    input  wire        eof,
    input  wire [31:0] file_size,


    output reg         check_done,
    output reg         check_error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [15:0] width,
    output reg  [15:0] height,
    output reg         top_down,
    output reg  [7:0]  bpp,
    output reg  [31:0] compression,
    output reg  [31:0] pixel_off,
    output reg  [31:0] file_size_o,
    output reg  [3:0]  dbg_state,


    output reg  [7:0]  out_data,
    output reg         out_valid,
    input  wire        out_ready,
    output reg         out_sof,
    output reg         out_eof
);


    localparam [31:0] BMP_PIX_BYTES = 32'd921_600;
    localparam [31:0] BMP_HDR_BYTES = 32'd54;


    localparam [1:0] H_HEAD = 2'd0,
                     H_XFER = 2'd1,
                     H_DONE = 2'd2;

    reg  [1:0]  mstate;
    reg  [5:0] hcnt;
    reg  [31:0] legacy_skip_cnt;
    reg         hdr_ok;


    reg  [31:0] bfsize_r;
    reg  [31:0] offbits_r; wire[31:0] skip_cnt=FLEX_PIXELS?offbits_r:legacy_skip_cnt;
    reg         dib_ge40_r;
    reg         dib_within_offset_r;
    reg  [15:0] width_lo_r;
    reg         width_hi_zero_r;
    reg  [15:0] height_lo_r;
    reg         height_hi_match_r;
    reg         height_sign_r;
    reg         planes_one_r;
    reg  [7:0]  bpp_lo_r;
    reg         bpp_hi_zero_r;
    reg  [31:0] comp_r;
    reg         sig_match_r;


    wire sig_ok    = sig_match_r;


    wire[31:0] offbits_decrement = FLEX_PIXELS?((mstate==H_XFER)?32'd1:(hcnt==53)?32'd54:32'd14):32'd14;
    wire[31:0] offbits_delta=offbits_r-offbits_decrement;
    wire [31:0] dib_capacity = offbits_delta;
    wire dib_ok    = dib_ge40_r && (!FLEX_PIXELS || dib_within_offset_r);
    wire legacy_size_ok = (width_lo_r == 16'd640) && width_hi_zero_r &&
                     ((height_lo_r == 16'd480) || (height_lo_r == 16'hfe20)) &&
                     height_hi_match_r;
    wire[15:0] height_abs=height_sign_r?(~height_lo_r+16'd1):height_lo_r;
    wire size_ok=VARIABLE_SIZE?(width_lo_r!=0&&width_lo_r<=(FLEX_PIXELS?16384:1920)&&width_hi_zero_r&&height_abs!=0&&height_abs<=(FLEX_PIXELS?16384:1080)&&height_hi_match_r):legacy_size_ok;
    wire[16:0] dynamic_w3=FLEX_PIXELS&&bpp_lo_r==32?({1'b0,width_lo_r}<<2):({1'b0,width_lo_r}<<1)+{1'b0,width_lo_r};
    wire[16:0] dynamic_stride=((dynamic_w3+17'd3)>>2)<<2;


    reg[16:0] extent_stride_q;
    reg[15:0] extent_height_q;
    reg[31:0] dynamic_bytes_q;
    always @(posedge clk)begin
      extent_stride_q<=dynamic_stride;
      extent_height_q<=height_abs;
      dynamic_bytes_q<=extent_stride_q*extent_height_q;
    end
    wire[31:0] dynamic_bytes=dynamic_bytes_q;
    wire[31:0] required_bytes=VARIABLE_SIZE?dynamic_bytes:BMP_PIX_BYTES;


    wire[31:0] pixels_remaining=bfsize_r;
    wire fmt_ok    = planes_one_r && ((bpp_lo_r == 8'd24)||(FLEX_PIXELS&&bpp_lo_r==8'd32)) && bpp_hi_zero_r && (comp_r == 32'd0);
    wire trunc_ok  = (offbits_r >= BMP_HDR_BYTES) &&
                     (bfsize_r <= file_size) &&


                     (({1'b0,offbits_r} + {1'b0,required_bytes}) <= {1'b0,file_size}) &&
                     (!VARIABLE_SIZE || ({1'b0,offbits_r}+{1'b0,required_bytes}<={1'b0,bfsize_r}));


    reg[4:0] header_predicates_q;
    always @(posedge clk) header_predicates_q<={sig_ok,dib_ok,size_ok,fmt_ok,trunc_ok};
    wire final_sig=FLEX_PIXELS?header_predicates_q[4]:sig_ok;
    wire final_dib=FLEX_PIXELS?header_predicates_q[3]:dib_ok;
    wire final_size=FLEX_PIXELS?header_predicates_q[2]:size_ok;
    wire final_fmt=FLEX_PIXELS?header_predicates_q[1]:fmt_ok;
    wire final_trunc=FLEX_PIXELS?header_predicates_q[0]:trunc_ok;
    wire        check_ok = final_sig && final_dib && final_size && final_fmt && final_trunc;

    assign ready = (mstate == H_HEAD) ||
                   (mstate == H_XFER && (!hdr_ok || !out_valid));


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstate      <= H_HEAD;
            hcnt        <= 6'd0;
            if(!FLEX_PIXELS)legacy_skip_cnt <= 32'd0;

            hdr_ok      <= 1'b0;
            if(!FLEX_PIXELS)begin
            bfsize_r    <= 32'h0;
            offbits_r   <= 32'h0;
            dib_ge40_r <= 1'b0;
            dib_within_offset_r <= 1'b0;
            width_lo_r <= 16'h0;
            width_hi_zero_r <= 1'b0;
            height_lo_r <= 16'h0;
            height_hi_match_r <= 1'b0;
            height_sign_r <= 1'b0;
            planes_one_r <= 1'b0;
            bpp_lo_r <= 8'h0;
            bpp_hi_zero_r <= 1'b0;
            comp_r      <= 32'h0;
            sig_match_r <= 1'b0;
            end
            check_done  <= 1'b0;
            check_error <= 1'b0;
            err_code    <= `ERR_NONE;
            err_detail  <= `DET_NONE;
            width       <= 16'd0;
            height      <= 16'd0;
            top_down    <= 1'b0;
            bpp         <= 8'd0;
            compression <= 32'd0;
            pixel_off   <= 32'd0;
            file_size_o <= 32'd0;
            dbg_state   <= H_HEAD;
            out_data    <= 8'h00;
            out_valid   <= 1'b0;
            out_sof     <= 1'b0;
            out_eof     <= 1'b0;
        end else begin
            dbg_state  <= mstate;
            check_done <= 1'b0;

            case (mstate)

            H_HEAD: begin
                if (valid && ready) begin

                    case (hcnt)
                        6'd0 : sig_match_r <= (data == 8'h42);
                        6'd1 : sig_match_r <= sig_match_r && (data == 8'h4d);
                        6'd2, 6'd3, 6'd4, 6'd5  : bfsize_r  <= {data, bfsize_r[31:8]};
                        6'd10, 6'd11, 6'd12, 6'd13: offbits_r <= {data, offbits_r[31:8]};
                        6'd14: begin dib_ge40_r <= (data >= 8'd40); dib_within_offset_r <= data <= dib_capacity[7:0]; end
                        6'd15: begin dib_ge40_r <= dib_ge40_r || (data != 8'd0); if(data != dib_capacity[15:8])dib_within_offset_r <= data < dib_capacity[15:8]; end
                        6'd16: begin dib_ge40_r <= dib_ge40_r || (data != 8'd0); if(data != dib_capacity[23:16])dib_within_offset_r <= data < dib_capacity[23:16]; end
                        6'd17: begin dib_ge40_r <= dib_ge40_r || (data != 8'd0); if(data != dib_capacity[31:24])dib_within_offset_r <= data < dib_capacity[31:24]; end
                        6'd18: width_lo_r[7:0] <= data;
                        6'd19: width_lo_r[15:8] <= data;
                        6'd20: width_hi_zero_r <= (data == 8'd0);
                        6'd21: width_hi_zero_r <= width_hi_zero_r && (data == 8'd0);
                        6'd22: height_lo_r[7:0] <= data;
                        6'd23: height_lo_r[15:8] <= data;
                        6'd24: height_hi_match_r <= (data == ((VARIABLE_SIZE ? !height_lo_r[15] : height_lo_r == 16'd480) ? 8'h00 : 8'hff));
                        6'd25: begin
                            height_hi_match_r <= height_hi_match_r && (data == ((VARIABLE_SIZE ? !height_lo_r[15] : height_lo_r == 16'd480) ? 8'h00 : 8'hff));
                            height_sign_r <= data[7];
                        end
                        6'd26: planes_one_r <= (data == 8'd1);
                        6'd27: planes_one_r <= planes_one_r && (data == 8'd0);
                        6'd28: bpp_lo_r <= data;
                        6'd29: bpp_hi_zero_r <= (data == 8'd0);
                        6'd30, 6'd31, 6'd32, 6'd33: comp_r <= {data, comp_r[31:8]};
                        default: ;
                    endcase

                    hcnt <= hcnt + 6'd1;

                    if (eof && (hcnt != (BMP_HDR_BYTES - 32'd1))) begin

                        check_error <= 1'b1;
                        err_code    <= `ERR_MEDIA_INVALID;
                        err_detail  <= `DET_BMP_TRUNC;
                        check_done  <= 1'b1;
                        file_size_o <= file_size;
                        out_eof     <= 1'b1;
                        mstate      <= H_DONE;
                    end else if (hcnt == (BMP_HDR_BYTES - 32'd1)) begin


                        check_done  <= 1'b1;
                        file_size_o <= file_size;
                        pixel_off   <= offbits_r;
                        width       <= width_lo_r;
                        height      <= height_lo_r;
                        top_down    <= height_sign_r;
                        bpp         <= bpp_lo_r;
                        compression <= comp_r;
                        hdr_ok      <= check_ok;
                        if(VARIABLE_SIZE)bfsize_r<=required_bytes;
                        check_error <= !check_ok;
                        if (!check_ok) begin
                            err_code <= `ERR_MEDIA_INVALID;
                            if      (!final_sig)   err_detail <= `DET_BMP_SIG;
                            else if (!final_dib)   err_detail <= `DET_BMP_DIB;
                            else if (!final_size)  err_detail <= `DET_BMP_SIZE;
                            else if (!final_fmt)   err_detail <= `DET_BMP_FMT;
                            else                err_detail <= `DET_BMP_TRUNC;
                        end

                        if(FLEX_PIXELS)offbits_r <= (offbits_r > BMP_HDR_BYTES)?offbits_delta:32'd0;
                        else legacy_skip_cnt <= (offbits_r > BMP_HDR_BYTES)?(offbits_r-BMP_HDR_BYTES):32'd0;
                        out_eof  <= eof;

                        mstate   <= eof ? H_DONE : H_XFER;
                    end
                end
            end

            H_XFER: begin

                if (out_valid && out_ready) begin
                    out_valid <= 1'b0;
                    out_sof   <= 1'b0;
                    out_eof   <= 1'b0;
                end

                if (valid && ready) begin
                    if (skip_cnt != 32'd0) begin
                        if(FLEX_PIXELS)offbits_r<=offbits_delta;else legacy_skip_cnt<=skip_cnt-32'd1;
                    end else if (hdr_ok && (!VARIABLE_SIZE || pixels_remaining!=0)) begin
                        out_data  <= data;
                        out_valid <= 1'b1;
                        out_sof   <= 1'b1;
                        out_eof   <= VARIABLE_SIZE?(pixels_remaining==1||eof):eof;
                        if(VARIABLE_SIZE)bfsize_r<=pixels_remaining-1'b1;
                    end
                    if (eof) begin
                        if(!VARIABLE_SIZE||pixels_remaining!=0)out_eof <= 1'b1;
                        mstate  <= H_DONE;
                    end
                end
            end


            H_DONE: begin
                if (out_valid && out_ready) begin
                    out_valid <= 1'b0;
                    out_sof   <= 1'b0;
                    out_eof   <= 1'b0;
                end
                if (!out_valid) begin
                    hcnt      <= 6'd0;
                    if(!FLEX_PIXELS)legacy_skip_cnt <= 32'd0;
                    hdr_ok    <= 1'b0;
                    if(!FLEX_PIXELS)begin
                    sig_match_r <= 1'b0;
                    bfsize_r  <= 32'h0;
                    offbits_r <= 32'h0;
                    dib_ge40_r <= 1'b0;
                    dib_within_offset_r <= 1'b0;
                    width_lo_r <= 16'h0;
                    width_hi_zero_r <= 1'b0;
                    height_lo_r <= 16'h0;
                    height_hi_match_r <= 1'b0;
                    height_sign_r <= 1'b0;
                    planes_one_r <= 1'b0;
                    bpp_lo_r <= 8'h0;
                    bpp_hi_zero_r <= 1'b0;
                    comp_r    <= 32'h0;
                    end
                    mstate    <= H_HEAD;
                end
            end
            default: mstate <= H_HEAD;
            endcase
        end
    end

endmodule
