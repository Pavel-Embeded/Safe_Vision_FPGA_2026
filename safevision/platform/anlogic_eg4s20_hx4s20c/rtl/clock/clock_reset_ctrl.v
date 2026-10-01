// ============================================================================
// clock_reset_ctrl.v — PLL 锁定许可与分域复位（SafeVision A · 板级平台）
// ----------------------------------------------------------------------------
// 依据：手册 V2.0 §6.3/§6.4/§10；docs/interface_spec.md v1.9。
//
// 本模块不产生、分频或切换时钟。sys/mem/video/audio 时钟必须来自经过
// TD 配置、约束与 STA 验证的安路 PLL IP。一个 PLL 同时提供多个时钟时，
// 对应的 locked 输入可连接同一个锁定信号。
//
// 局部复位隔离：
//   media_reset_req         仅重启 sys_clk 域媒体业务；
//   memory_client_reset_req 仅重启 mem_clk 域内存客户端，保留 SDRAM IP；
//   hdmi_reinit_req         仅重启 HDMI 前级/串行路径，保留视频时序；
//   audio_reset_req         仅重启音频消费链，保留视频与故障通道。
// 请求为保持电平。跨域发起请求须先按接口规范完成 CDC，不能直接接单拍。
// ============================================================================
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

    // 基础域复位：业务局部请求不得破坏时钟域基础设施。
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

    // 局部请求重新断言复位；audio_rst_n 是音频消费域的唯一复位输出。
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
