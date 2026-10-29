


`include "safevision_defs.vh"

module frame_writer #(
    parameter [9:0]  FRAME_WIDTH     = `SV_FRAME_WIDTH,
    parameter [9:0]  FRAME_HEIGHT    = `SV_FRAME_HEIGHT,
    parameter [31:0] BYTES_PER_PIXEL = `SV_RGB565_BYTES_PER_PX,
    parameter [18:0] PIX_PER_FRAME   = `SV_FRAME_PIXELS,
    parameter integer SAMPLE_STRIDE  = 1024,
    parameter [31:0] GAP_TIMEOUT     = 32'd512,
    parameter [31:0] SLOT_SPAN       = `SV_IMG_ALIGN_BYTES,
    parameter [31:0] MEM_VISIBLE     = `SV_MEM_VISIBLE_BYTES,
    parameter integer EXACT_SAMPLE_COMPARE=0,
    parameter integer SOURCE_PROGRESS_AWARE=0
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire        start,
    input  wire [1:0]  slot_sel,
    input  wire [31:0] slot_base,


    input  wire [15:0] din,
    input  wire        din_valid,
    output wire        din_ready,


    output wire        wr_req,
    output wire [31:0] wr_addr,
    output wire [31:0] wr_data,
    output wire [15:0] wr_len,
    input  wire        wr_ready,
    output reg         wr_done,


    output reg  [3:0]  slot_valid,
    output reg         crc_ok,
    output reg  [15:0] crc_value,
    output reg  [18:0] px_cnt,
    output reg         wr_error,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    input wire source_progress
);


    localparam S_IDLE = 1'b0,
               S_RUN  = 1'b1;


    localparam [7:0] ERR_SDRAM_XFER   = 8'h04;
    localparam [7:0] DET_SDRAM_VERIFY = 8'h42;

    reg        state;


    reg        frame_full;
    reg [31:0] base_reg;
    reg [1:0]  slot_sel_q;
    reg        have_lo;
    reg [15:0] lo_pix;
    reg [9:0]  x_cnt;
    reg [9:0]  y_cnt;
    reg [31:0] src_idx;
    reg [31:0] bus_idx;
    (* preserve="true",keep="true" *)reg sample_mismatch;
    reg [15:0] crc_src;
    reg [15:0] crc_bus;
    reg        wr_pending;
    reg [31:0] wr_addr_r;
    (* preserve="true",keep="true" *)reg [31:0] wr_data_r;
    reg        crc_src_pend;
    (* preserve="true",keep="true" *)reg [31:0] crc_pair_q;
    localparam integer GAP_W = (GAP_TIMEOUT < 2) ? 1 : $clog2({1'b0,GAP_TIMEOUT}+33'd1);
    reg [GAP_W-1:0] gap_cnt;


    wire [31:0] cur_byte_addr;
    wire [31:0] cur_offset;
    wire [29:0] cur_word_addr;
    wire        cur_word_phase;

    frame_address_gen #(
        .FRAME_WIDTH     (FRAME_WIDTH),
        .BYTES_PER_PIXEL (BYTES_PER_PIXEL)
    ) u_addr_gen (
        .slot_base (32'd0),
        .x         (x_cnt),
        .y         (y_cnt),
        .byte_addr (cur_offset),
        .word_addr (cur_word_addr),
        .word_phase(cur_word_phase)
    );
    assign cur_byte_addr = base_reg + cur_offset;


    wire running    = (state == S_RUN);


    assign din_ready = running && !wr_pending && !frame_full;
    assign wr_req    = running && wr_pending;
    assign wr_addr   = wr_addr_r;
    assign wr_data   = wr_data_r;
    assign wr_len    = 16'd1;

    wire wr_accept = wr_req && wr_ready;
    wire px_accept = din_valid && din_ready;


    wire [31:0] px_pair = {din, lo_pix};

    wire [15:0] crc_bus_w1, crc_bus_w2, crc_bus_w3;
    wire [15:0] crc_bus_next;
    crc16_ccitt u_crc_bus_0 (.crc_in(crc_bus),    .data(wr_data_r[31:24]), .crc_out(crc_bus_w1));
    crc16_ccitt u_crc_bus_1 (.crc_in(crc_bus_w1), .data(wr_data_r[23:16]), .crc_out(crc_bus_w2));
    crc16_ccitt u_crc_bus_2 (.crc_in(crc_bus_w2), .data(wr_data_r[15:8]),  .crc_out(crc_bus_w3));
    crc16_ccitt u_crc_bus_3 (.crc_in(crc_bus_w3), .data(wr_data_r[7:0]),   .crc_out(crc_bus_next));

    wire [15:0] crc_src_w1, crc_src_w2, crc_src_w3;
    wire [15:0] crc_src_next;


    generate if(!EXACT_SAMPLE_COMPARE)begin:legacy_source_crc
    crc16_ccitt u_crc_src_0 (.crc_in(crc_src),    .data(crc_pair_q[31:24]), .crc_out(crc_src_w1));
    crc16_ccitt u_crc_src_1 (.crc_in(crc_src_w1), .data(crc_pair_q[23:16]), .crc_out(crc_src_w2));
    crc16_ccitt u_crc_src_2 (.crc_in(crc_src_w2), .data(crc_pair_q[15:8]),  .crc_out(crc_src_w3));
    crc16_ccitt u_crc_src_3 (.crc_in(crc_src_w3), .data(crc_pair_q[7:0]),   .crc_out(crc_src_next));
    end else begin:exact_source_sample
      assign crc_src_next=16'd0;
    end endgenerate
    wire sample_check_ok=EXACT_SAMPLE_COMPARE?!sample_mismatch:(crc_src==crc_bus);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            base_reg   <= 32'd0;
            slot_sel_q <= 2'd0;
            have_lo    <= 1'b0;
            lo_pix     <= 16'd0;
            x_cnt      <= 10'd0;
            y_cnt      <= 10'd0;
            src_idx    <= 32'd0;
            bus_idx    <= 32'd0;
            crc_src    <= 16'd0;sample_mismatch<=0;
            crc_bus    <= 16'd0;
            wr_pending <= 1'b0;
            wr_addr_r  <= 32'd0;
            wr_data_r  <= 32'd0;
            crc_src_pend <= 1'b0;
            crc_pair_q   <= 32'd0;
            gap_cnt    <= 16'd0;
            wr_done    <= 1'b0;
            slot_valid <= 4'b0000;
            crc_ok     <= 1'b0;
            crc_value  <= 16'd0;
            px_cnt     <= 19'd0;
            frame_full <= (PIX_PER_FRAME == 19'd0);
            wr_error   <= 1'b0;
            err_code   <= `ERR_NONE;
            err_detail <= `DET_NONE;
        end else begin

            wr_done <= 1'b0;


            if (!EXACT_SAMPLE_COMPARE && crc_src_pend) begin
                crc_src      <= crc_src_next;
                crc_src_pend <= 1'b0;
            end

            case (state)

                S_IDLE: begin
                    if (start) begin


                        if ((slot_base[1:0] != 2'b00) || (SLOT_SPAN > MEM_VISIBLE) ||
                            (slot_base > (MEM_VISIBLE - SLOT_SPAN))) begin

                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_TRUNC;
                            crc_ok     <= 1'b0;
                        end else begin
                            base_reg   <= slot_base;
                            slot_sel_q <= slot_sel;
                            have_lo    <= 1'b0;
                            x_cnt      <= 10'd0;
                            y_cnt      <= 10'd0;
                            src_idx    <= 32'd0;
                            bus_idx    <= 32'd0;
                            crc_src    <= 16'd0;sample_mismatch<=0;
                            crc_bus    <= 16'd0;
                            wr_pending <= 1'b0;
                            gap_cnt    <= 16'd0;
                            px_cnt     <= 19'd0;
                            frame_full <= (PIX_PER_FRAME == 19'd0);
                            wr_error   <= 1'b0;
                            err_code   <= `ERR_NONE;
                            err_detail <= `DET_NONE;

                            state      <= S_RUN;
                        end
                    end
                end


                S_RUN: begin


                    if (wr_accept) begin
                        wr_pending <= 1'b0;
                        if ((bus_idx % SAMPLE_STRIDE) == 0)begin
                            crc_bus <= crc_bus_next;
                            if(EXACT_SAMPLE_COMPARE && wr_data_r!==crc_pair_q)sample_mismatch<=1;
                        end
                        bus_idx <= bus_idx + 32'd1;
                    end


                    if (px_accept) begin
                        px_cnt <= px_cnt + 19'd1;
                        if (px_cnt == (PIX_PER_FRAME - 19'd1)) frame_full <= 1'b1;
                        if (!have_lo) begin

                            have_lo <= 1'b1;
                            lo_pix  <= din;
                        end else begin

                            have_lo <= 1'b0;


                            if (cur_offset >= SLOT_SPAN) begin
                                wr_error   <= 1'b1;
                                err_code   <= `ERR_MEDIA_INVALID;
                                err_detail <= `DET_BMP_TRUNC;
                                crc_ok     <= 1'b0;
                                state      <= S_IDLE;
                            end else begin
                                wr_pending <= 1'b1;
                                wr_addr_r  <= cur_byte_addr;
                                wr_data_r  <= px_pair;


                                if (((EXACT_SAMPLE_COMPARE?bus_idx:src_idx) % SAMPLE_STRIDE) == 0) begin
                                    crc_src_pend <= 1'b1;
                                    crc_pair_q   <= px_pair;
                                end
                                src_idx <= src_idx + 32'd1;

                                if (x_cnt == (FRAME_WIDTH - 10'd2)) begin
                                    x_cnt <= 10'd0;
                                    y_cnt <= y_cnt + 10'd1;
                                end else begin
                                    x_cnt <= x_cnt + 10'd2;
                                end
                            end
                        end
                    end


                    if (frame_full && !wr_pending) begin
                        if (din_valid) begin

                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_BMP_SIZE;
                            crc_ok     <= 1'b0;
                            state      <= S_IDLE;
                        end else begin

                            crc_value <= crc_bus;
                            crc_ok    <= sample_check_ok;
                            if (sample_check_ok) begin

                                slot_valid[slot_sel_q] <= 1'b1;
                                wr_done   <= 1'b1;
                            end else begin

                                wr_error   <= 1'b1;
                                err_code   <= ERR_SDRAM_XFER;
                                err_detail <= DET_SDRAM_VERIFY;
                            end
                            state     <= S_IDLE;
                        end
                    end

                    else if (!frame_full) begin
                        if (px_accept || wr_accept) begin
                            gap_cnt <= 16'd0;
                        end else if (SOURCE_PROGRESS_AWARE && source_progress && !wr_pending && !din_valid) begin


                            gap_cnt <= 16'd0;
                        end else if (gap_cnt >= GAP_TIMEOUT) begin
                            wr_error   <= 1'b1;
                            err_code   <= `ERR_MEDIA_INVALID;
                            err_detail <= `DET_FS_SHORT;
                            crc_ok     <= 1'b0;
                            state      <= S_IDLE;
                        end else begin
                            gap_cnt <= gap_cnt + 16'd1;
                        end
                    end

                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
