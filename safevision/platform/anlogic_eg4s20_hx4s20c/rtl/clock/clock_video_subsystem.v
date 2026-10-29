


`include "video_mode_defs.vh"

module clock_video_subsystem #(
    parameter integer VIDEO_MODE_HD = 0
) (
    input  wire        board_clk,
    input  wire        board_rst_n,
    input  wire        media_reset_req,
    input  wire        memory_client_reset_req,
    input  wire        hdmi_reinit_req,
    input  wire        audio_reset_req,
    output wire        sys_clk,
    output wire        mem_clk,
    output wire        pixel_clk,
    output wire        serial_clk,
    output wire        audio_clk,
    output wire        sys_pll_locked,
    output wire        mem_pll_locked,
    output wire        video_pll_locked,
    output wire        audio_pll_locked,
    output wire        sys_rst_n,
    output wire        mem_rst_n,
    output wire        pixel_rst_n,
    output wire        serial_rst_n,
    output wire        audio_rst_n,
    output wire        media_rst_n,
    output wire        memory_client_rst_n,
    output wire        hdmi_pixel_rst_n,
    output wire        hdmi_serial_rst_n,
    output wire [11:0] x,
    output wire [11:0] y,
    output wire        hsync,
    output wire        vsync,
    output wire        de,
    output wire        line_start,
    output wire        frame_start,
    output wire        active_frame_start,
    output wire        hblank,
    output wire        vblank
);

    localparam integer H_ACTIVE = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_H_ACTIVE : `SV_VIDEO_BASE_H_ACTIVE;
    localparam integer H_FRONT  = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_H_FRONT : `SV_VIDEO_BASE_H_FRONT;
    localparam integer H_SYNC   = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_H_SYNC : `SV_VIDEO_BASE_H_SYNC;
    localparam integer H_BACK   = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_H_BACK : `SV_VIDEO_BASE_H_BACK;
    localparam integer V_ACTIVE = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_V_ACTIVE : `SV_VIDEO_BASE_V_ACTIVE;
    localparam integer V_FRONT  = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_V_FRONT : `SV_VIDEO_BASE_V_FRONT;
    localparam integer V_SYNC   = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_V_SYNC : `SV_VIDEO_BASE_V_SYNC;
    localparam integer V_BACK   = (VIDEO_MODE_HD == 1) ?
                                  `SV_VIDEO_HD_V_BACK : `SV_VIDEO_BASE_V_BACK;
    localparam HSYNC_ACTIVE = (VIDEO_MODE_HD == 1) ?
                               `SV_VIDEO_HD_HSYNC_ACTIVE : `SV_VIDEO_BASE_HSYNC_ACTIVE;
    localparam VSYNC_ACTIVE = (VIDEO_MODE_HD == 1) ?
                               `SV_VIDEO_HD_VSYNC_ACTIVE : `SV_VIDEO_BASE_VSYNC_ACTIVE;

    // synthesis translate_off
    initial begin
        if (VIDEO_MODE_HD !== 0 && VIDEO_MODE_HD !== 1) begin
            $display("[FAIL] clock_video_subsystem VIDEO_MODE_HD must be 0 or 1");
            $stop;
        end
    end
    // synthesis translate_on

    clock_gen #(
        .VIDEO_MODE_HD(VIDEO_MODE_HD)
    ) u_clock_gen (
        .board_clk(board_clk),
        .board_rst_n(board_rst_n),
        .sys_clk(sys_clk),
        .mem_clk(mem_clk),
        .pixel_clk(pixel_clk),
        .serial_clk(serial_clk),
        .audio_clk(audio_clk),
        .sys_pll_locked(sys_pll_locked),
        .mem_pll_locked(mem_pll_locked),
        .video_pll_locked(video_pll_locked),
        .audio_pll_locked(audio_pll_locked)
    );

    clock_reset_ctrl u_clock_reset_ctrl (
        .board_rst_n(board_rst_n),
        .sys_clk(sys_clk),
        .mem_clk(mem_clk),
        .pixel_clk(pixel_clk),
        .serial_clk(serial_clk),
        .audio_clk(audio_clk),
        .sys_pll_locked(sys_pll_locked),
        .mem_pll_locked(mem_pll_locked),
        .video_pll_locked(video_pll_locked),
        .audio_pll_locked(audio_pll_locked),
        .media_reset_req(media_reset_req),
        .memory_client_reset_req(memory_client_reset_req),
        .hdmi_reinit_req(hdmi_reinit_req),
        .audio_reset_req(audio_reset_req),
        .sys_rst_n(sys_rst_n),
        .mem_rst_n(mem_rst_n),
        .pixel_rst_n(pixel_rst_n),
        .serial_rst_n(serial_rst_n),
        .audio_rst_n(audio_rst_n),
        .media_rst_n(media_rst_n),
        .memory_client_rst_n(memory_client_rst_n),
        .hdmi_pixel_rst_n(hdmi_pixel_rst_n),
        .hdmi_serial_rst_n(hdmi_serial_rst_n)
    );

    video_timing #(
        .H_ACTIVE(H_ACTIVE),
        .H_FRONT(H_FRONT),
        .H_SYNC(H_SYNC),
        .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE),
        .V_FRONT(V_FRONT),
        .V_SYNC(V_SYNC),
        .V_BACK(V_BACK),
        .HSYNC_ACTIVE(HSYNC_ACTIVE),
        .VSYNC_ACTIVE(VSYNC_ACTIVE)
    ) u_video_timing (
        .clk(pixel_clk),
        .rst_n(pixel_rst_n),
        .x(x),
        .y(y),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .line_start(line_start),
        .frame_start(frame_start),
        .active_frame_start(active_frame_start),
        .hblank(hblank),
        .vblank(vblank)
    );

endmodule
