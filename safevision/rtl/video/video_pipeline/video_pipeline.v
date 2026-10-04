// ============================================================================
// video_pipeline.v - A stage 10: fixed-rate pixel/tag latency alignment
// Verilog-2001. All ports use clk (pixel_clk), never sys_clk/mem_clk.
// latency = LATENCY cycles; throughput = one complete bundle per clock.
// LATENCY=0 is a combinational bypass. No enable/ready/stall is permitted.
//
// Count convention: a bundle stable before edge E appears after edge
// E+LATENCY-1 for LATENCY>=1. A source register launched after E is sampled
// at E+1 and appears after E+LATENCY. Cascaded latencies therefore add.
// pixel_valid is media availability, de is scan timing: keep them separate.
// Invalid/blank pixels still advance every tag. This module neither replaces
// missing pixels nor performs CDC, frame swaps, OSD or HDMI serialization.
// rst_n asserts asynchronously; caller releases it synchronously to clk.
// Reset flushes all stages: black pixel, zero coordinates/events/valid/de,
// inactive hsync/vsync, hblank=vblank=1. LATENCY=0 uses the same reset bundle.
// ============================================================================
module video_pipeline #(
    parameter integer PIXEL_WIDTH = 24, // use 16 for B's RGB565, no conversion
    parameter integer XY_WIDTH = 12,    // video_timing outputs are 12 bits
    parameter integer LATENCY = 1,      // number of registers per signal
    parameter [0:0] HSYNC_ACTIVE = 1'b0,
    parameter [0:0] VSYNC_ACTIVE = 1'b0
)(
    input wire clk,
    input wire rst_n,
    input wire [PIXEL_WIDTH-1:0] pixel_in,
    input wire [XY_WIDTH-1:0] x_in,
    input wire [XY_WIDTH-1:0] y_in,
    input wire hsync_in,
    input wire vsync_in,
    input wire de_in,
    input wire pixel_valid_in,
    input wire line_start_in,
    input wire frame_start_in,        // vertical-blank event from video_timing
    input wire active_frame_start_in, // first visible pixel, a distinct event
    input wire hblank_in,
    input wire vblank_in,
    // Every output has latency = LATENCY cycles, including all event tags.
    output wire [PIXEL_WIDTH-1:0] pixel_out,
    output wire [XY_WIDTH-1:0] x_out,
    output wire [XY_WIDTH-1:0] y_out,
    output wire hsync_out,
    output wire vsync_out,
    output wire de_out,
    output wire pixel_valid_out,
    output wire line_start_out,
    output wire frame_start_out,
    output wire active_frame_start_out,
    output wire hblank_out,
    output wire vblank_out
);
    localparam integer BUNDLE_WIDTH = PIXEL_WIDTH + 2*XY_WIDTH + 9;
    localparam [BUNDLE_WIDTH-1:0] RESET_BUNDLE = {
        {PIXEL_WIDTH{1'b0}}, {XY_WIDTH{1'b0}}, {XY_WIDTH{1'b0}},
        ~HSYNC_ACTIVE, ~VSYNC_ACTIVE, 5'b00000, 2'b11
    };
    wire [BUNDLE_WIDTH-1:0] bundle_in = {
        pixel_in, x_in, y_in, hsync_in, vsync_in, de_in, pixel_valid_in,
        line_start_in, frame_start_in, active_frame_start_in, hblank_in, vblank_in
    };
    wire [BUNDLE_WIDTH-1:0] bundle_out;
    assign {pixel_out, x_out, y_out, hsync_out, vsync_out, de_out,
            pixel_valid_out, line_start_out, frame_start_out,
            active_frame_start_out, hblank_out, vblank_out} = bundle_out;

    generate
        if (LATENCY == 0) begin : bypass
            assign bundle_out = rst_n ? bundle_in : RESET_BUNDLE;
        end else if (LATENCY > 0) begin : registered
            reg [BUNDLE_WIDTH-1:0] stages [0:LATENCY-1];
            integer i;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (i=0; i<LATENCY; i=i+1)
                        stages[i] <= RESET_BUNDLE;
                end else begin
                    stages[0] <= bundle_in;
                    for (i=1; i<LATENCY; i=i+1)
                        stages[i] <= stages[i-1];
                end
            end
            assign bundle_out = stages[LATENCY-1];
        end else begin : invalid_latency
            assign bundle_out = RESET_BUNDLE;
        end
        // synthesis translate_off
`ifndef SYNTHESIS
        if ((^LATENCY === 1'bx) || LATENCY < 0 ||
            (^PIXEL_WIDTH === 1'bx) || PIXEL_WIDTH <= 0 ||
            (^XY_WIDTH === 1'bx) || XY_WIDTH <= 0 ||
            (HSYNC_ACTIVE !== 1'b0 && HSYNC_ACTIVE !== 1'b1) ||
            (VSYNC_ACTIVE !== 1'b0 && VSYNC_ACTIVE !== 1'b1)) begin : bad_parameters
            initial begin
                $display("FATAL video_pipeline: invalid width, latency or polarity");
                $stop;
            end
        end
`endif
        // synthesis translate_on
    endgenerate
endmodule
