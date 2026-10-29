


`include "safevision_defs.vh"

module frame_swap_ctrl #(


    parameter [31:0] TIMEOUT_N = 32'd5_000_000
)(
    input  wire       clk,
    input  wire       rst_n,


    input  wire       frame_ready,
    input  wire       wr_frame_index,
    input  wire [1:0] wr_slot_id,
    input  wire [7:0] wr_generation,
    input  wire       wr_crc_ok,


    input  wire       frame_start,
    input  wire       swap_ack,


    output reg        swap_req,
    output reg        frame_index,
    output reg [1:0]  slot_id,
    output reg [7:0]  generation,
    output reg        crc_ok,
    output reg        swap_error,


    output reg        active_commit,
    output reg [1:0]  active_next,
    output reg [7:0]  generation_next,
    output reg        frame_index_next,


    output reg [2:0]  state_o
);

    localparam [2:0] S_IDLE        = 3'd0,
                     S_REQ         = 3'd1,
                     S_WAIT_VBLANK = 3'd2,
                     S_COMMIT      = 3'd3,
                     S_WAIT_ACK    = 3'd4,
                     S_SAFE        = 3'd5;

    reg [2:0]  state;
    reg [31:0] to_cnt;
    reg        ack_seen;
    reg        fr_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            to_cnt           <= 32'd0;
            fr_d             <= 1'b0;
            ack_seen         <= 1'b0;
            swap_req         <= 1'b0;
            frame_index      <= 1'b0;
            slot_id          <= 2'd0;
            generation       <= 8'd0;
            crc_ok           <= 1'b0;
            swap_error       <= 1'b0;
            active_commit    <= 1'b0;
            active_next      <= 2'd0;
            generation_next  <= 8'd0;
            frame_index_next <= 1'b0;
            state_o          <= S_IDLE;
        end else begin

            active_commit <= 1'b0;
            state_o       <= state;
            fr_d          <= frame_ready;
            if ((state == S_WAIT_VBLANK || state == S_COMMIT || state == S_WAIT_ACK) && swap_ack)
                ack_seen <= 1'b1;

            case (state)

            S_IDLE: begin

                if (frame_ready && wr_crc_ok) begin
                    ack_seen         <= 1'b0;
                    frame_index      <= wr_frame_index;
                    slot_id          <= wr_slot_id;
                    generation_next  <= wr_generation;
                    frame_index_next <= wr_frame_index;
                    crc_ok           <= wr_crc_ok;
                    generation       <= wr_generation;
                    to_cnt           <= 32'd0;
                    state            <= S_REQ;
                end
            end

            S_REQ: begin
                swap_req <= ~swap_req;
                to_cnt   <= 32'd0;
                state    <= S_WAIT_VBLANK;
            end

            S_WAIT_VBLANK: begin
                if (frame_start) begin

                    active_next   <= slot_id;
                    active_commit <= 1'b1;
                    to_cnt        <= 32'd0;
                    state         <= S_COMMIT;
                end else if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                end
            end

            S_COMMIT: begin
                if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                    state  <= S_WAIT_ACK;
                end
            end

            S_WAIT_ACK: begin
                if (swap_ack || ack_seen) begin
                    ack_seen <= 1'b0;

                    state <= S_IDLE;
                end else if (to_cnt >= TIMEOUT_N) begin
                    swap_error <= 1'b1;
                    state      <= S_SAFE;
                end else begin
                    to_cnt <= to_cnt + 32'd1;
                end
            end

            S_SAFE: begin
                if (frame_ready && wr_crc_ok && !fr_d) begin
                    ack_seen         <= 1'b0;
                    swap_error       <= 1'b0;
                    frame_index      <= wr_frame_index;
                    slot_id          <= wr_slot_id;
                    generation_next  <= wr_generation;
                    frame_index_next <= wr_frame_index;
                    crc_ok           <= wr_crc_ok;
                    generation       <= wr_generation;
                    to_cnt           <= 32'd0;
                    state            <= S_REQ;
                end
            end
            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
