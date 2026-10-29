


`include "video_mode_defs.vh"

module video_timing #(
    parameter integer H_ACTIVE = `SV_VIDEO_BASE_H_ACTIVE,
    parameter integer H_FRONT  = `SV_VIDEO_BASE_H_FRONT,
    parameter integer H_SYNC   = `SV_VIDEO_BASE_H_SYNC,
    parameter integer H_BACK   = `SV_VIDEO_BASE_H_BACK,
    parameter integer V_ACTIVE = `SV_VIDEO_BASE_V_ACTIVE,
    parameter integer V_FRONT  = `SV_VIDEO_BASE_V_FRONT,
    parameter integer V_SYNC   = `SV_VIDEO_BASE_V_SYNC,
    parameter integer V_BACK   = `SV_VIDEO_BASE_V_BACK,
    parameter         HSYNC_ACTIVE = `SV_VIDEO_BASE_HSYNC_ACTIVE,
    parameter         VSYNC_ACTIVE = `SV_VIDEO_BASE_VSYNC_ACTIVE
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg  [11:0] x,
    output reg  [11:0] y,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire        line_start,
    output wire        frame_start,
    output wire        active_frame_start,
    output wire        hblank,
    output wire        vblank
);

    localparam integer H_TOTAL      = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL      = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam integer H_SYNC_BEGIN = H_ACTIVE + H_FRONT;
    localparam integer H_SYNC_END   = H_SYNC_BEGIN + H_SYNC;
    localparam integer V_SYNC_BEGIN = V_ACTIVE + V_FRONT;
    localparam integer V_SYNC_END   = V_SYNC_BEGIN + V_SYNC;


    generate
        if ((^H_ACTIVE === 1'bx) || (^H_FRONT === 1'bx) ||
            (^H_SYNC === 1'bx) || (^H_BACK === 1'bx) ||
            (^V_ACTIVE === 1'bx) || (^V_FRONT === 1'bx) ||
            (^V_SYNC === 1'bx) || (^V_BACK === 1'bx) ||
            H_ACTIVE <= 0 || V_ACTIVE <= 0 || H_SYNC <= 0 || V_SYNC <= 0 ||
            H_FRONT < 0 || H_BACK < 0 || V_FRONT < 0 || V_BACK < 0 ||

            H_ACTIVE > 4096 || H_FRONT > 4096 || H_SYNC > 4096 || H_BACK > 4096 ||
            V_ACTIVE > 4096 || V_FRONT > 4096 || V_SYNC > 4096 || V_BACK > 4096 ||
            H_TOTAL <= 0 || V_TOTAL <= 0 ||
            H_TOTAL > 4096 || V_TOTAL > 4096 ||
            (HSYNC_ACTIVE !== 1'b0 && HSYNC_ACTIVE !== 1'b1) ||
            (VSYNC_ACTIVE !== 1'b0 && VSYNC_ACTIVE !== 1'b1)) begin : invalid_parameters
`ifndef SYNTHESIS
          initial begin
            $display("FATAL video_timing: invalid geometry or sync polarity");
            $stop;
          end
`endif
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 12'd0;
            y <= 12'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 12'd0;
            if (y == V_TOTAL - 1)
                y <= 12'd0;
            else
                y <= y + 12'd1;
        end else begin
            x <= x + 12'd1;
        end
    end

    wire hsync_window = (x >= H_SYNC_BEGIN) && (x < H_SYNC_END);
    wire vsync_window = (y >= V_SYNC_BEGIN) && (y < V_SYNC_END);

    assign hblank = !rst_n || (x >= H_ACTIVE);
    assign vblank = !rst_n || (y >= V_ACTIVE);
    assign de = !hblank && !vblank;
    assign hsync = (rst_n && hsync_window) ? HSYNC_ACTIVE : ~HSYNC_ACTIVE;
    assign vsync = (rst_n && vsync_window) ? VSYNC_ACTIVE : ~VSYNC_ACTIVE;

    assign line_start         = rst_n && (x == 12'd0);
    assign frame_start        = rst_n && (x == 12'd0) && (y == V_ACTIVE);
    assign active_frame_start = rst_n && (x == 12'd0) && (y == 12'd0);

endmodule
