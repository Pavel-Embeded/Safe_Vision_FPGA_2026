


`include "safevision_defs.vh"

module bmp_unpack #(

    parameter ROUNDING = 1'b0
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire [7:0]  din,
    input  wire        din_valid,
    output wire        din_ready,
    input  wire        din_sof,
    input  wire        din_eof,


    input  wire [15:0] width,
    input  wire [15:0] height,
    input  wire        top_down,
    input  wire [31:0] pixel_off,


    output reg  [15:0] pixel,
    output reg         pixel_valid,
    input  wire        pixel_ready,
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    output reg         img_sof,
    output reg         img_eof,


    output reg         done,
    output reg         error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [3:0]  dbg_state
);


    localparam [1:0] U_IDLE = 2'd0,
                     U_RUN  = 2'd1,
                     U_DONE = 2'd2,
                     U_ERR  = 2'd3;

    reg  [1:0]  state;
    reg  [15:0] col;
    reg  [15:0] row_i;
    reg  [9:0]  px_in_row;
    reg  [1:0]  phase;
    reg  [7:0]  b_r, g_r;
    reg  [31:0] px_cnt;
    reg         full;
    reg         first_pix;


    wire [31:0] w3     = {16'd0, width} * 32'd3;
    wire [31:0] stride = ((w3 + 32'd3) >> 2) << 2;

    wire [15:0] w3_16     = w3[15:0];
    wire [15:0] stride_m1 = stride[15:0] - 16'd1;


    wire [15:0] h_abs    = top_down ? (~height + 16'd1) : height;
    wire [31:0] px_total = {16'd0, width} * {16'd0, h_abs};


    wire [15:0] y_calc = top_down ? row_i : (height - 16'd1 - row_i);

    wire        is_pix_byte = (col < w3_16);
    wire        is_row_last = (col == stride_m1);


    wire [7:0] cb = b_r;
    wire [7:0] cg = g_r;
    wire [7:0] cr = din;

    wire [4:0] r_trunc = cr[7:3];
    wire [5:0] g_trunc = cg[7:2];
    wire [4:0] b_trunc = cb[7:3];

    wire [5:0] r_round_sum = {1'b0, cr[7:3]} + {5'd0, cr[2]};
    wire [6:0] g_round_sum = {2'b00, cg[7:2]} + {6'd0, cg[1]};
    wire [5:0] b_round_sum = {1'b0, cb[7:3]} + {5'd0, cb[2]};

    wire [4:0] r_round = (r_round_sum > 6'd31) ? 5'd31 : r_round_sum[4:0];
    wire [5:0] g_round = (g_round_sum > 7'd63) ? 6'd63 : g_round_sum[5:0];
    wire [4:0] b_round = (b_round_sum > 6'd31) ? 5'd31 : b_round_sum[4:0];

    wire [4:0] r5 = ROUNDING ? r_round : r_trunc;
    wire [5:0] g6 = ROUNDING ? g_round : g_trunc;
    wire [4:0] b5 = ROUNDING ? b_round : b_trunc;


    wire [15:0] pix_calc = {r5, g6, b5};

    wire        byte_taken  = din_valid && din_ready;
    wire        pix_complete = is_pix_byte && (phase == 2'd2);
    wire        last_expected = (px_cnt + 32'd1 == px_total);
    wire        emit_now     = byte_taken && pix_complete && !full;
    wire        overflow_now = byte_taken && pix_complete && full;


    wire [31:0] px_next = px_cnt + (emit_now ? 32'd1 : 32'd0);


    assign din_ready = (state == U_RUN) && !pixel_valid;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= U_IDLE;
            col        <= 16'd0;
            row_i      <= 16'd0;
            px_in_row  <= 10'd0;
            phase      <= 2'd0;
            b_r        <= 8'h00;
            g_r        <= 8'h00;
            pixel      <= 16'h0000;
            pixel_valid<= 1'b0;
            x          <= 10'd0;
            y          <= 10'd0;
            img_sof    <= 1'b0;
            img_eof    <= 1'b0;
            px_cnt     <= 32'd0;
            full       <= 1'b0;
            first_pix  <= 1'b1;
            done       <= 1'b0;
            error      <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
            dbg_state  <= U_IDLE;
        end else begin
            dbg_state <= state;
            done      <= 1'b0;


            if (pixel_valid && pixel_ready) begin
                pixel_valid <= 1'b0;
                img_sof     <= 1'b0;
                img_eof     <= 1'b0;
            end

            case (state)


            U_IDLE: begin
                if (din_valid && din_sof) begin
                    state      <= U_RUN;
                    error      <= 1'b0;
                    err_code   <= `ERR_NONE;
                    err_detail <= `DET_NONE;
                    col        <= 16'd0;
                    row_i      <= 16'd0;
                    px_in_row  <= 10'd0;
                    phase      <= 2'd0;
                    b_r        <= 8'h00;
                    g_r        <= 8'h00;
                    px_cnt     <= 32'd0;
                    full       <= 1'b0;
                    first_pix  <= 1'b1;
                end
            end

            U_RUN: begin
                if (byte_taken) begin

                    if (is_row_last) begin
                        col       <= 16'd0;
                        row_i     <= row_i + 16'd1;
                        px_in_row <= 10'd0;
                    end else begin
                        col <= col + 16'd1;
                    end


                    if (is_pix_byte) begin
                        case (phase)
                        2'd0: begin b_r <= din; phase <= 2'd1; end
                        2'd1: begin g_r <= din; phase <= 2'd2; end
                        2'd2: begin
                            if (!full) begin
                                pixel       <= pix_calc;
                                pixel_valid <= 1'b1;
                                x           <= px_in_row;
                                y           <= y_calc[9:0];
                                img_sof     <= first_pix;
                                img_eof     <= last_expected;
                                px_cnt      <= px_cnt + 32'd1;
                                phase       <= 2'd0;
                                first_pix   <= 1'b0;
                                if (last_expected) full <= 1'b1;

                                if (!is_row_last) px_in_row <= px_in_row + 10'd1;
                            end
                        end
                        default: phase <= 2'd0;
                        endcase
                    end


                    if (overflow_now) begin
                        error      <= 1'b1;
                        err_code   <= `ERR_MEDIA_INVALID;
                        err_detail <= `DET_BMP_SIZE;
                        state      <= U_ERR;
                        done       <= 1'b1;
                    end else if (din_eof) begin
                        if (px_next == px_total) begin
                            state <= U_DONE;
                            done  <= 1'b1;
                        end else begin
                            error      <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_TRUNC;
                            state      <= U_ERR;
                            done       <= 1'b1;
                        end
                    end
                end
            end

            U_DONE: begin
                if (!pixel_valid) state <= U_IDLE;
            end

            U_ERR: begin
                error <= 1'b1;
                if (!pixel_valid) state <= U_IDLE;
            end
            default: state <= U_IDLE;
            endcase
        end
    end

endmodule
