// ============================================================================
// clock_gen.v - SafeVision A 板级 PLL 时钟适配
// ----------------------------------------------------------------------------
// 50 MHz 板级参考时钟进入安路 TD 生成的 PLL IP。本模块只连线，不用逻辑
// 分频、门控或多路选择器形成时钟。VIDEO_MODE_HD 在编译时只例化一套视频 PLL。
//
// 目标与本版 TD PLL 配置的实际频率（MHz）：
//   sys 100，mem 125；BASE pixel 25.185185185、serial 125.925925926；
//   HD pixel 74.166666667、serial 370.833333333；audio 12.288135593。
// 视频串行时钟与像素时钟来自同一 PLL VCO，严格保持 5:1。
// 生成文件、约束和 STA 应核对这些频率；锁定信号不证明频率正确。
// ============================================================================
module clock_gen #(
    parameter integer VIDEO_MODE_HD = 0
) (
    input  wire board_clk,
    input  wire board_rst_n,
    output wire sys_clk,
    output wire mem_clk,
    output wire pixel_clk,
    output wire serial_clk,
    output wire audio_clk,
    output wire sys_pll_locked,
    output wire mem_pll_locked,
    output wire video_pll_locked,
    output wire audio_pll_locked
);

    wire pll_reset;
    wire system_locked;
    wire audio_feedback_clk;

    // 安路 PLL reset 高有效；板级 board_rst_n 低有效。
    assign pll_reset = ~board_rst_n;

    // 一颗 PLL 同时给系统与 SDRAM 域，两个许可共用同一 extlock。
    sv_system_pll u_system_pll (
        .refclk(board_clk),
        .reset(pll_reset),
        .extlock(system_locked),
        .clk0_out(sys_clk),
        .clk1_out(mem_clk)
    );
    assign sys_pll_locked = system_locked;
    assign mem_pll_locked = system_locked;

    generate
        if (VIDEO_MODE_HD == 0) begin : gen_video_base
            wire video_feedback_clk;
            // C0 是 PLL 正常反馈路径，不能删除；C1/C2 才是业务时钟。
            sv_video_vga_pll u_video_pll (
                .refclk(board_clk),
                .reset(pll_reset),
                .extlock(video_pll_locked),
                .clk0_out(video_feedback_clk),
                .clk1_out(pixel_clk),
                .clk2_out(serial_clk)
            );
        end else if (VIDEO_MODE_HD == 1) begin : gen_video_hd
            wire video_feedback_clk;
            sv_video_hd_pll u_video_pll (
                .refclk(board_clk),
                .reset(pll_reset),
                .extlock(video_pll_locked),
                .clk0_out(video_feedback_clk),
                .clk1_out(pixel_clk),
                .clk2_out(serial_clk)
            );
        end else begin : gen_invalid_video_mode
            assign pixel_clk = 1'b0;
            assign serial_clk = 1'b0;
            assign video_pll_locked = 1'b0;
            // synthesis translate_off
            initial begin
                $display("[FAIL] clock_gen VIDEO_MODE_HD must be 0 or 1");
                $stop;
            end
            // synthesis translate_on
        end
    endgenerate

    // C0 是音频 PLL 正常反馈路径；业务音频 MCLK 从 C1 引出。
    sv_audio_pll u_audio_pll (
        .refclk(board_clk),
        .reset(pll_reset),
        .extlock(audio_pll_locked),
        .clk0_out(audio_feedback_clk),
        .clk1_out(audio_clk)
    );

endmodule
