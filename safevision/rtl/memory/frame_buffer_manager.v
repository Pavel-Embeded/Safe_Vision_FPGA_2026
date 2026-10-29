


`include "safevision_defs.vh"

module frame_buffer_manager (
    input  wire        clk,
    input  wire        rst_n,


    input  wire [1:0]  wr_slot_sel,
    input  wire        wr_slot_set,
    input  wire        slot_valid_set,
    input  wire [1:0]  slot_valid_id,
    input  wire        slot_valid_clr,


    input  wire        active_commit,
    input  wire [1:0]  active_next,
    input  wire [7:0]  generation_in,
    input  wire        frame_index_in,


    input  wire [1:0]  sel_slot,
    output reg  [31:0] slot_base_o,


    output reg  [1:0]  active_slot,
    output reg  [1:0]  write_slot,
    output reg  [3:0]  slot_valid,
    output reg        frame_index,
    output reg  [7:0]  generation,
    output reg  [31:0] active_slot_base,


    output wire [31:0] slot_base0,
    output wire [31:0] slot_base1,
    output wire [31:0] slot_base2,
    output wire [31:0] slot_base3,
    output wire [31:0] line_stride,
    output wire [31:0] frame_bytes
);


    localparam [31:0] IMG0_BASE       = `SV_IMG0_BASE;
    localparam [31:0] IMG1_BASE       = `SV_IMG1_BASE;
    localparam [31:0] IMG2_BASE       = `SV_IMG2_BASE;
    localparam [31:0] IMG3_BASE       = `SV_IMG3_BASE;
    localparam [31:0] AUDIO_RING_BASE = `SV_AUDIO_RING_BASE;
    localparam [31:0] WORK_BASE       = `SV_WORK_BASE;

    localparam [31:0] SLOT_STRIDE     = `SV_IMG_ALIGN_BYTES;
    localparam [31:0] LINE_STRIDE     = `SV_FRAME_STRIDE_BYTES;
    localparam [31:0] FRAME_BYTES     = `SV_FRAME_BYTES;


    function [31:0] slot_base_of;
        input [1:0] s;
        begin
            case (s)
                2'd0:    slot_base_of = IMG0_BASE;
                2'd1:    slot_base_of = IMG1_BASE;
                2'd2:    slot_base_of = IMG2_BASE;
                default: slot_base_of = IMG3_BASE;
            endcase
        end
    endfunction

    assign slot_base0  = IMG0_BASE;
    assign slot_base1  = IMG1_BASE;
    assign slot_base2  = IMG2_BASE;
    assign slot_base3  = IMG3_BASE;
    assign line_stride = LINE_STRIDE;
    assign frame_bytes = FRAME_BYTES;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_slot      <= 2'd0;
            write_slot       <= 2'd0;
            slot_valid       <= 4'b0000;
            frame_index      <= 1'b0;
            generation       <= 8'd0;
            active_slot_base <= IMG0_BASE;
        end else begin

            if (slot_valid_clr) begin
                slot_valid <= 4'b0000;
            end
            if (wr_slot_set) begin
                write_slot <= wr_slot_sel;
            end
            if (slot_valid_set) begin
                slot_valid[slot_valid_id] <= 1'b1;
            end


            if (active_commit) begin
                active_slot      <= active_next;
                active_slot_base <= slot_base_of(active_next);
                generation       <= generation_in;
                frame_index      <= frame_index_in;
            end
        end
    end


    always @(*) begin
        slot_base_o = slot_base_of(sel_slot);
    end

endmodule
