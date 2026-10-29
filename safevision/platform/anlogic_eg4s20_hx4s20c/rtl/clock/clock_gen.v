


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


    assign pll_reset = ~board_rst_n;


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


    sv_audio_pll u_audio_pll (
        .refclk(board_clk),
        .reset(pll_reset),
        .extlock(audio_pll_locked),
        .clk0_out(audio_feedback_clk),
        .clk1_out(audio_clk)
    );

endmodule
