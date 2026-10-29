


module clock_reset_ctrl (
    input  wire board_rst_n,
    input  wire sys_clk,
    input  wire mem_clk,
    input  wire pixel_clk,
    input  wire serial_clk,
    input  wire audio_clk,
    input  wire sys_pll_locked,
    input  wire mem_pll_locked,
    input  wire video_pll_locked,
    input  wire audio_pll_locked,
    input  wire media_reset_req,
    input  wire memory_client_reset_req,
    input  wire hdmi_reinit_req,
    input  wire audio_reset_req,
    output wire sys_rst_n,
    output wire mem_rst_n,
    output wire pixel_rst_n,
    output wire serial_rst_n,
    output wire audio_rst_n,
    output wire media_rst_n,
    output wire memory_client_rst_n,
    output wire hdmi_pixel_rst_n,
    output wire hdmi_serial_rst_n
);

    wire sys_async_rst_n;
    wire mem_async_rst_n;
    wire video_async_rst_n;
    wire audio_async_rst_n;

    assign sys_async_rst_n   = board_rst_n & sys_pll_locked;
    assign mem_async_rst_n   = board_rst_n & mem_pll_locked;
    assign video_async_rst_n = board_rst_n & video_pll_locked;
    assign audio_async_rst_n = board_rst_n & audio_pll_locked;


    reset_sync u_sys_reset (
        .clk(sys_clk), .async_rst_n(sys_async_rst_n), .rst_n(sys_rst_n)
    );
    reset_sync u_mem_reset (
        .clk(mem_clk), .async_rst_n(mem_async_rst_n), .rst_n(mem_rst_n)
    );
    reset_sync u_pixel_reset (
        .clk(pixel_clk), .async_rst_n(video_async_rst_n), .rst_n(pixel_rst_n)
    );
    reset_sync u_serial_reset (
        .clk(serial_clk), .async_rst_n(video_async_rst_n), .rst_n(serial_rst_n)
    );


    reset_sync u_audio_reset (
        .clk(audio_clk),
        .async_rst_n(audio_async_rst_n & ~audio_reset_req),
        .rst_n(audio_rst_n)
    );
    reset_sync u_media_reset (
        .clk(sys_clk),
        .async_rst_n(sys_async_rst_n & ~media_reset_req),
        .rst_n(media_rst_n)
    );
    reset_sync u_memory_client_reset (
        .clk(mem_clk),
        .async_rst_n(mem_async_rst_n & ~memory_client_reset_req),
        .rst_n(memory_client_rst_n)
    );
    reset_sync u_hdmi_pixel_reset (
        .clk(pixel_clk),
        .async_rst_n(video_async_rst_n & ~hdmi_reinit_req),
        .rst_n(hdmi_pixel_rst_n)
    );
    reset_sync u_hdmi_serial_reset (
        .clk(serial_clk),
        .async_rst_n(video_async_rst_n & ~hdmi_reinit_req),
        .rst_n(hdmi_serial_rst_n)
    );

endmodule
