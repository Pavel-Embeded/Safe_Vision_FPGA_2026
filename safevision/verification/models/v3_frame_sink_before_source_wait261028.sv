


`include "pixel_format_defs.vh"

module v3_frame_sink_before_source_wait261028 #(
    parameter integer FIFO_AW     = 10,
    parameter [31:0]  GAP_TIMEOUT = 32'd500_000,
    parameter [31:0]  SWAP_TO_N   = 32'd12_500_000,


    parameter [31:0]  WRITE_TO_N  = 32'd50_000_000
    ,parameter integer REQUIRE_WRITE_DRAIN = 0, REQUIRE_READBACK = 0, RESIDENT_LOAD = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_clk,


    input  wire [31:0] px_word,
    input  wire        px_word_valid,
    output wire        px_word_ready,
    input  wire        frame_active,
    input  wire        top_down,
    input  wire [1:0]  slot,
    output reg         mem_ready,
    output reg         frame_done,
    output reg         last_frame_ok,


    output wire        wr_req,
    output wire [31:0] wr_addr,
    output wire [31:0] wr_data,
    output wire [15:0] wr_len,
    input  wire        wr_ready,


    output reg         swap_toggle,
    output reg  [1:0]  swap_slot,
    output reg  [7:0]  swap_generation,
    output reg         swap_crc_ok,
    input  wire        swap_busy,


    output reg  [3:0]  state_o,
    output reg  [7:0]  err_code,
    output reg  [7:0]  err_detail,
    output reg  [15:0] frame_cnt,
    output reg  [18:0] px_written,
    input wire write_drained,verify_done,verify_pass,
    output wire source_begin,output wire [1:0] source_slot,output wire source_top_down
);


    localparam [3:0] S_DRAIN = 4'd0,
                     S_WRITE = 4'd1,
                     S_SWAP  = 4'd2,
                     S_ERROR = 4'd3,
                     S_FLUSH = 4'd4;

    localparam [7:0] MY_TO_SWAP = 8'hF1,
                     MY_TO_FRAME= 8'hF2;


    reg [2:0] fa_sync;
    reg [1:0] td_sync;
    reg [3:0] sl_sync;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fa_sync <= 3'd0; td_sync <= 2'd0; sl_sync <= 4'd0;
        end else begin
            fa_sync <= {fa_sync[1:0], frame_active};
            td_sync <= {td_sync[0],    top_down};
            sl_sync <= {sl_sync[1:0],  slot};
        end
    end


    wire fa_rise = fa_sync[1] && !fa_sync[2];


    wire        fifo_full, fifo_afull, fifo_empty, fifo_aempty;
    wire [15:0] fifo_rd_data;
    wire        fifo_rd_valid;
    wire [FIFO_AW-1:0] fifo_wr_words;
    wire [FIFO_AW:0]   fifo_rd_pixels;
    wire        fifo_rd_en;
    wire        fifo_rst = ~rst_n;

    a_pixel_fifo #(.AW(FIFO_AW)) u_fifo (
        .rst(fifo_rst),
        .wr_clk(wr_clk), .wr_data(px_word), .wr_en(px_word_valid),
        .full(fifo_full), .almost_full(fifo_afull),
        .wr_words(fifo_wr_words), .wr_ready(px_word_ready),
        .rd_clk(clk), .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_rd_valid), .empty(fifo_empty), .almost_empty(fifo_aempty),
        .rd_pixels(fifo_rd_pixels)
    );


    reg         br_start;
    wire        br_start_ready, br_done, br_crc_ok, br_err;
    wire [3:0]  br_slot_valid;
    wire [15:0] br_crc_value;
    wire [18:0] br_px_cnt;
    wire [7:0]  br_ec, br_ed;

    reg  [1:0]  slot_lat;
    assign source_begin=br_start;assign source_slot=slot_lat;assign source_top_down=td_sync[1];
    wire [31:0] slot_base = `SV_SLOT_BASE(slot_lat);
    wire        br_din_ready;


    reg  [15:0] sk_data;
    reg         sk_valid;
    wire        sk_ready = br_din_ready;
    wire        sk_load  = fifo_rd_valid && (!sk_valid || sk_ready);
    wire        br_din_valid = sk_valid && (state_o == S_WRITE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sk_data <= 16'd0; sk_valid <= 1'b0;
        end else if (state_o != S_WRITE) begin
            sk_valid <= 1'b0;
        end else begin
            if (sk_load)                   sk_data  <= fifo_rd_data;
            if (sk_load)                   sk_valid <= 1'b1;
            else if (sk_valid && sk_ready) sk_valid <= 1'b0;
        end
    end


    bmp_frame_write_bridge #(
        .GAP_TIMEOUT(GAP_TIMEOUT),.EXACT_SAMPLE_COMPARE(RESIDENT_LOAD)
    ) u_bridge (
        .clk(clk), .rst_n(rst_n && !(RESIDENT_LOAD && state_o==S_ERROR)), .start(br_start), .top_down(td_sync[1]),
        .slot_sel(slot_lat), .slot_base(slot_base),
        .din(sk_data), .din_valid(br_din_valid), .din_ready(br_din_ready),
        .wr_req(wr_req), .start_ready(br_start_ready),
        .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ready),
        .wr_done(br_done), .slot_valid(br_slot_valid),
        .crc_ok(br_crc_ok), .crc_value(br_crc_value), .px_cnt(br_px_cnt),
        .wr_error(br_err), .err_code(br_ec), .err_detail(br_ed)
    );


    assign fifo_rd_en = (state_o == S_WRITE) ? sk_load : fifo_rd_valid;


    reg [31:0] to_cnt;
    reg        swap_seen;
    reg [2:0]  empty_settle;
    reg [18:0] px_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_o        <= S_DRAIN;
            br_start       <= 1'b0;
            mem_ready      <= 1'b0;
            frame_done     <= 1'b0;
            last_frame_ok  <= 1'b0;
            swap_toggle    <= 1'b0;
            swap_slot      <= 2'd0;
            swap_generation<= 8'd1;
            swap_crc_ok    <= 1'b0;
            slot_lat       <= 2'd1;
            to_cnt         <= 32'd0;
            swap_seen      <= 1'b0;
            empty_settle   <= 3'd0;
            err_code       <= 8'h00;
            err_detail     <= 8'h00;
            frame_cnt      <= 16'd0;
            px_written     <= 19'd0;
            px_d           <= 19'd0;
        end else begin
            br_start <= 1'b0;
            px_written <= br_px_cnt;
            px_d       <= br_px_cnt;

            case (state_o)


                S_DRAIN: begin
                    if (fifo_empty) begin
                        if (empty_settle != 3'd7) empty_settle <= empty_settle + 3'd1;
                    end else begin
                        empty_settle <= 3'd0;
                    end
                    mem_ready <= (empty_settle == 3'd7);

                    if (fa_rise) begin


                        slot_lat     <= sl_sync[3:2];
                        br_start     <= 1'b1;
                        mem_ready    <= 1'b0;
                        to_cnt       <= 32'd0;
                        swap_seen    <= 1'b0;
                        last_frame_ok<= 1'b0;
                        state_o      <= S_WRITE;
                    end
                end


                S_WRITE: begin


                    if (br_px_cnt != px_d) to_cnt <= 32'd0;
                    else                   to_cnt <= to_cnt + 32'd1;

                    if (br_done) begin
                        last_frame_ok  <= br_crc_ok;

                        err_code       <= 8'h00;
                        err_detail     <= 8'h00;

                        swap_crc_ok    <= br_crc_ok;
                        swap_slot      <= slot_lat;
                        swap_generation<= swap_generation + 8'd1;
                        if (!REQUIRE_WRITE_DRAIN && !REQUIRE_READBACK) swap_toggle <= ~swap_toggle;
                        to_cnt         <= 32'd0;
                        state_o        <= (REQUIRE_WRITE_DRAIN || REQUIRE_READBACK) ? S_FLUSH : S_SWAP;
                    end else if ((RESIDENT_LOAD && !fa_sync[2]) || br_err) begin
                        last_frame_ok<= 1'b0;
                        err_code   <= br_ec;
                        err_detail <= br_ed;
                        empty_settle<=0;
                        state_o    <= S_ERROR;
                    end else if (to_cnt >= WRITE_TO_N) begin
                        last_frame_ok<= 1'b0;
                        err_code   <= MY_TO_FRAME;
                        empty_settle<=0;
                        state_o    <= S_ERROR;
                    end
                end


                S_FLUSH: begin


                    to_cnt <= to_cnt + 32'd1;
                    if (REQUIRE_READBACK && verify_done && !verify_pass) begin
                        last_frame_ok<=0;swap_crc_ok<=0;err_code<=8'hF3;state_o<=S_ERROR;
                    end else if (write_drained && (!REQUIRE_READBACK || (verify_done && verify_pass))) begin
                        swap_toggle <= ~swap_toggle;
                        to_cnt <= 32'd0;
                        state_o <= S_SWAP;
                    end else if (to_cnt >= WRITE_TO_N) begin
                        last_frame_ok <= 1'b0;
                        err_code <= MY_TO_FRAME;
                        state_o <= S_ERROR;
                    end
                end

                S_SWAP: begin
                    to_cnt <= to_cnt + 32'd1;
                    if (swap_busy) swap_seen <= 1'b1;

                    if(RESIDENT_LOAD)begin


                        if(last_frame_ok)frame_cnt<=frame_cnt+1'b1;
                        frame_done<=~frame_done;to_cnt<=0;empty_settle<=0;state_o<=S_DRAIN;
                    end else if (to_cnt >= SWAP_TO_N) begin

                        swap_seen    <= 1'b0;
                        last_frame_ok<= 1'b0;
                        err_code     <= MY_TO_SWAP;
                        frame_done   <= ~frame_done;
                        to_cnt       <= 32'd0;
                        empty_settle <= 3'd0;
                        state_o      <= S_DRAIN;
                    end else if (swap_seen && !swap_busy) begin
                        if (last_frame_ok) frame_cnt <= frame_cnt + 16'd1;
                        swap_seen    <= 1'b0;
                        frame_done   <= ~frame_done;
                        to_cnt       <= 32'd0;
                        empty_settle <= 3'd0;
                        state_o      <= S_DRAIN;
                    end
                end


                S_ERROR: begin

                    last_frame_ok <= 1'b0;
                    mem_ready <= 1'b0;

                    if (fifo_empty) begin
                        if (empty_settle != 3'd7) empty_settle <= empty_settle + 3'd1;
                    end else begin
                        empty_settle <= 3'd0;
                    end


                    if (empty_settle == 3'd7) begin
                        frame_done <= ~frame_done;
                        empty_settle<=0;
                        state_o    <= S_DRAIN;
                    end
                end

                default: state_o <= S_DRAIN;
            endcase
        end
    end

endmodule
