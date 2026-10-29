


`timescale 1ns / 1ps


module sv_video_vga_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg pix  = 1'b0;
    reg ser  = 1'b0;
    always #19.853 pix = ~pix;
    always #3.970  ser = ~ser;
    assign extlock  = 1'b1;
    assign clk0_out = ser;
    assign clk1_out = pix;
    assign clk2_out = ser;
endmodule


module sv_video_hd_pll (
    input  wire refclk,
    input  wire reset,
    output wire extlock,
    output wire clk0_out,
    output wire clk1_out,
    output wire clk2_out
);
    reg pix = 1'b0;
    reg ser = 1'b0;
    always #6.742 pix = ~pix;
    always #1.348 ser = ~ser;
    assign extlock  = 1'b1;
    assign clk0_out = ser;
    assign clk1_out = pix;
    assign clk2_out = ser;
endmodule


module hdmi_1_4b_transmitter_core_wrapper #(
    parameter DEVICE            = "EG",
    parameter HTOTAL            = 2200,
    parameter HSA               = 44,
    parameter HFP               = 88,
    parameter HBP               = 148,
    parameter HACTIVE           = 1920,
    parameter VTOTAL            = 1125,
    parameter VSA               = 5,
    parameter VFP               = 4,
    parameter VBP               = 36,
    parameter VACTIVE           = 1080,
    parameter VIDEO_TPG         = "Enable",
    parameter VIDEO_FORMAT      = "RGB",
    parameter VIDEO_VIC         = 16,
    parameter AUDIO_SAMPLE_RATE = "48K",
    parameter IIC_SCL_DIV       = 125
)(
    input  wire       I_pixel_clk,
    input  wire       I_rst,

    input  wire       I_edid_read_trig,
    output reg        O_edid_read_valid,
    output reg  [7:0] O_edid_read_data,

    input  wire       I_axis_s_user,
    input  wire       I_axis_s_valid,
    input  wire       I_axis_s_last,
    input  wire [23:0] I_axis_s_data,
    output wire       O_axis_s_ready,

    input  wire       I_audio_valid,
    input  wire [23:0] I_audio_left_data,
    input  wire [23:0] I_audio_right_data,

    input  wire       I_acr_valid,
    input  wire [19:0] I_acr_cts,
    input  wire [19:0] I_acr_n,

    output reg        O_video_locked,

    output wire       O_ddc_scl,
    inout  wire       IO_ddc_sda,

    output reg  [9:0] O_ch0_tmds_data,
    output reg  [9:0] O_ch1_tmds_data,
    output reg  [9:0] O_ch2_tmds_data,
    output reg  [9:0] O_clk_tmds_data
);

    integer axis_beats = 0;
    integer axis_lasts = 0;
    integer axis_bad   = 0;

    assign O_axis_s_ready = 1'b1;
    assign O_ddc_scl      = 1'b1;
    assign IO_ddc_sda     = 1'bz;

    reg [9:0] lock_cnt = 10'd0;
    reg [9:0] edid_cnt = 10'd0;

    always @(posedge I_pixel_clk) begin
        if (I_rst) begin
            O_video_locked    <= 1'b0;
            O_edid_read_valid <= 1'b0;
            O_ch0_tmds_data   <= 10'd0;
            O_ch1_tmds_data   <= 10'd0;
            O_ch2_tmds_data   <= 10'd0;
            O_clk_tmds_data   <= 10'd0;
            lock_cnt          <= 10'd0;
            edid_cnt          <= 10'd0;
            axis_beats        <= 0;
            axis_lasts        <= 0;
        end else begin

            if (lock_cnt != 10'h3FF) begin
                lock_cnt <= lock_cnt + 10'd1;
                if (lock_cnt == 10'd63) O_video_locked <= 1'b1;
            end

            if (I_edid_read_trig) begin edid_cnt <= 10'd8; O_edid_read_valid <= 1'b1; end
            else if (edid_cnt != 10'd0) begin
                edid_cnt <= edid_cnt - 10'd1;
                if (edid_cnt == 10'd1) O_edid_read_valid <= 1'b0;
            end
            O_edid_read_data <= 8'h00;


            if (I_axis_s_valid) begin
                axis_beats <= axis_beats + 1;
                if (I_axis_s_last) axis_lasts <= axis_lasts + 1;
                O_ch0_tmds_data <= {2'b00, I_axis_s_data[23:16]};
                O_ch1_tmds_data <= {2'b00, I_axis_s_data[15:8]};
                O_ch2_tmds_data <= {2'b00, I_axis_s_data[7:0]};
                O_clk_tmds_data <= 10'h155;
            end
        end
    end


    wire unused = |{ I_audio_valid, I_acr_valid, I_acr_cts, I_acr_n,
                     I_axis_s_user, I_audio_left_data, I_audio_right_data,
                     VIDEO_TPG, VIDEO_FORMAT, VIDEO_VIC, AUDIO_SAMPLE_RATE,
                     IIC_SCL_DIV, DEVICE, HTOTAL, HSA, HFP, HBP, HACTIVE,
                     VTOTAL, VSA, VFP, VBP, VACTIVE };
endmodule


module hdmi_phy_wrapper #(
    parameter DEVICE = "EG"
)(
    input  wire       I_pixel_clk,
    input  wire       I_serial_clk,
    input  wire       I_rst,
    input  wire [9:0] I_tmds_channel_0,
    input  wire [9:0] I_tmds_channel_1,
    input  wire [9:0] I_tmds_channel_2,
    input  wire [9:0] I_tmds_channel_clk,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p
);
    assign O_tmds_ch0_p = I_tmds_channel_0[0];
    assign O_tmds_ch1_p = I_tmds_channel_1[0];
    assign O_tmds_ch2_p = I_tmds_channel_2[0];
    assign O_tmds_clk_p = I_tmds_channel_clk[0];

    wire unused = |{ I_pixel_clk, I_serial_clk, I_rst, DEVICE,
                     I_tmds_channel_0[9:1], I_tmds_channel_1[9:1],
                     I_tmds_channel_2[9:1], I_tmds_channel_clk[9:1] };
endmodule
