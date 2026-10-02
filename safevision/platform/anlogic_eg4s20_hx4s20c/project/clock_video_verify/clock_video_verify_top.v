// ============================================================================
// clock_video_verify_top.v - TD-only clock/reset/timing implementation check
// ----------------------------------------------------------------------------
// This is a verification top, not SafeVision's product top or a board image.
// SV_VERIFY_HD is a synthesis-time define (0=BASE, 1=HD). Four reset-request
// inputs and all probe outputs have no verified board pin assignments.
// ============================================================================
`ifndef SV_VERIFY_HD
`define SV_VERIFY_HD 0
`endif

module clock_video_verify_top (
    input  wire       board_clk,
    input  wire       board_rst_n,
    input  wire       media_reset_req,
    input  wire       memory_client_reset_req,
    input  wire       hdmi_reinit_req,
    input  wire       audio_reset_req,
    output wire [8:0] probe_domain,
    output wire [7:0] probe_video
);

    localparam integer VIDEO_MODE_HD = `SV_VERIFY_HD;
    wire sys_clk, mem_clk, pixel_clk, serial_clk, audio_clk;
    wire sys_pll_locked, mem_pll_locked, video_pll_locked;
    wire audio_pll_locked;
    wire sys_rst_n, mem_rst_n, pixel_rst_n, serial_rst_n, audio_rst_n;
    wire media_rst_n, memory_client_rst_n;
    wire hdmi_pixel_rst_n, hdmi_serial_rst_n;

    wire [11:0] scan_x, scan_y;
    wire hsync, vsync, de, line_start, frame_start;
    wire active_frame_start, hblank, vblank;
    clock_video_subsystem #(.VIDEO_MODE_HD(VIDEO_MODE_HD)) u_subsystem (
        .board_clk(board_clk), .board_rst_n(board_rst_n),
        .media_reset_req(media_reset_req),
        .memory_client_reset_req(memory_client_reset_req),
        .hdmi_reinit_req(hdmi_reinit_req),
        .audio_reset_req(audio_reset_req),
        .sys_clk(sys_clk), .mem_clk(mem_clk),
        .pixel_clk(pixel_clk), .serial_clk(serial_clk),
        .audio_clk(audio_clk),
        .sys_pll_locked(sys_pll_locked), .mem_pll_locked(mem_pll_locked),
        .video_pll_locked(video_pll_locked),
        .audio_pll_locked(audio_pll_locked),
        .sys_rst_n(sys_rst_n), .mem_rst_n(mem_rst_n),
        .pixel_rst_n(pixel_rst_n), .serial_rst_n(serial_rst_n),
        .audio_rst_n(audio_rst_n), .media_rst_n(media_rst_n),
        .memory_client_rst_n(memory_client_rst_n),
        .hdmi_pixel_rst_n(hdmi_pixel_rst_n),
        .hdmi_serial_rst_n(hdmi_serial_rst_n),
        .x(scan_x), .y(scan_y), .hsync(hsync), .vsync(vsync), .de(de),
        .line_start(line_start), .frame_start(frame_start),
        .active_frame_start(active_frame_start),
        .hblank(hblank), .vblank(vblank)
    );

    // Nine independently reset state elements keep all five generated clock
    // domains and all nine reset outputs observable in the mapped netlist.
    // Each probe stays in its own clock domain; no cross-domain sample is made.
    reg [3:0] sys_count, mem_count, pixel_count, audio_count;
    reg [3:0] media_count, memory_client_count, hdmi_pixel_count;
    reg serial_toggle, hdmi_serial_toggle;
    always @(posedge sys_clk or negedge sys_rst_n)
        if (!sys_rst_n) sys_count <= 4'd0;
        else sys_count <= sys_count + 4'd1;
    always @(posedge mem_clk or negedge mem_rst_n)
        if (!mem_rst_n) mem_count <= 4'd0;
        else mem_count <= mem_count + 4'd1;
    always @(posedge pixel_clk or negedge pixel_rst_n)
        if (!pixel_rst_n) pixel_count <= 4'd0;
        else pixel_count <= pixel_count + 4'd1;
    always @(posedge serial_clk or negedge serial_rst_n)
        if (!serial_rst_n) serial_toggle <= 1'b0;
        else serial_toggle <= ~serial_toggle;
    always @(posedge audio_clk or negedge audio_rst_n)
        if (!audio_rst_n) audio_count <= 4'd0;
        else audio_count <= audio_count + 4'd1;
    always @(posedge sys_clk or negedge media_rst_n)
        if (!media_rst_n) media_count <= 4'd0;
        else media_count <= media_count + 4'd1;
    always @(posedge mem_clk or negedge memory_client_rst_n)
        if (!memory_client_rst_n) memory_client_count <= 4'd0;
        else memory_client_count <= memory_client_count + 4'd1;
    always @(posedge pixel_clk or negedge hdmi_pixel_rst_n)
        if (!hdmi_pixel_rst_n) hdmi_pixel_count <= 4'd0;
        else hdmi_pixel_count <= hdmi_pixel_count + 4'd1;
    always @(posedge serial_clk or negedge hdmi_serial_rst_n)
        if (!hdmi_serial_rst_n) hdmi_serial_toggle <= 1'b0;
        else hdmi_serial_toggle <= ~hdmi_serial_toggle;

    assign probe_domain = {hdmi_serial_toggle, hdmi_pixel_count[3],
                           memory_client_count[3], media_count[3],
                           audio_count[3], serial_toggle, pixel_count[3],
                           mem_count[3], sys_count[3]};

    // A pixel-domain register exercises the scan coordinates and all timing
    // labels; probe_video is an unpinned logic probe, not an HDMI output.
    reg [7:0] pixel_sample;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) pixel_sample <= 8'd0;
        else if (de) pixel_sample <= scan_x[7:0] ^ scan_y[7:0] ^
                                     {7'd0, active_frame_start};
        else pixel_sample <= {hsync, vsync, line_start, frame_start,
                              hblank, vblank, scan_x[0], scan_y[0]};
    end
    assign probe_video = pixel_sample;

endmodule
