


module a_hdmi_output #(
    parameter integer HD=0,QUEUE_AW=4,EDID_SETTLE_CYCLES=100000
)(
    input wire pixel_clk,serial_clk,rst_n,hpd,edid_reread,
    input wire [23:0] rgb,input wire de,input wire [11:0] x,y,
    input wire audio_valid,input wire [23:0] audio_left,audio_right,
    input wire acr_valid,input wire [19:0] acr_cts,acr_n,
    output wire tmds_d0_p,tmds_d1_p,tmds_d2_p,tmds_clk_p,
    output wire ddc_scl,inout wire ddc_sda,
    output wire video_locked,connected,overflow_sticky,
    output wire [31:0] dropped_frames,
    output wire edid_valid,output wire [7:0] edid_data,
    output wire [QUEUE_AW:0] queue_level
);
    wire prn,hpd_reset,edid_trig,resync;
    reset_sync reset_pixel(.clk(pixel_clk),.async_rst_n(rst_n),.rst_n(prn));
    hdmi_edid_control #(.SETTLE_CYCLES(EDID_SETTLE_CYCLES)) edid(
        .clk(pixel_clk),.rst_n(prn),.hpd(hpd),.reread(edid_reread||resync),
        .trigger(edid_trig),.connected(connected),.tx_reset(hpd_reset));
    wire valid,user,last,ready;wire [23:0] data;
    hdmi_video_bridge #(.HD(HD),.QUEUE_AW(QUEUE_AW)) input_queue(
        .clk(pixel_clk),.rst_n(prn&&!hpd_reset),.rgb(rgb),.de(de),.x(x),.y(y),
        .axis_valid(valid),.axis_user(user),.axis_last(last),.axis_data(data),
        .axis_ready(ready),.resync(resync),.overflow_sticky(overflow_sticky),
        .dropped_frames(dropped_frames),.queue_level(queue_level));
    wire tx_reset=!prn||hpd_reset||resync;


    wire serial_rst_n;
    reset_sync reset_serial(.clk(serial_clk),.async_rst_n(!tx_reset),.rst_n(serial_rst_n));
    wire [9:0] c0,c1,c2,cc;
    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"),.HTOTAL(HD?1650:800),.HSA(HD?40:96),
        .HFP(HD?110:16),.HBP(HD?220:48),.HACTIVE(HD?1280:640),
        .VTOTAL(HD?750:525),.VSA(HD?5:2),.VFP(HD?5:10),
        .VBP(HD?20:33),.VACTIVE(HD?720:480),.VIDEO_VIC(HD?4:1),
        .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
        .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
    ) transmitter(
        .I_pixel_clk(pixel_clk),.I_rst(tx_reset),.I_edid_read_trig(edid_trig),
        .O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
        .I_axis_s_user(user),.I_axis_s_valid(valid),.I_axis_s_last(last),.I_axis_s_data(data),
        .O_axis_s_ready(ready),.I_audio_valid(audio_valid),
        .I_audio_left_data(audio_left),.I_audio_right_data(audio_right),
        .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),
        .O_video_locked(video_locked),.O_ddc_scl(ddc_scl),.IO_ddc_sda(ddc_sda),
        .O_ch0_tmds_data(c0),.O_ch1_tmds_data(c1),.O_ch2_tmds_data(c2),.O_clk_tmds_data(cc));
    hdmi_phy_wrapper #(.DEVICE("EG")) phy(
        .I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(!serial_rst_n),
        .I_tmds_channel_0(c0),.I_tmds_channel_1(c1),.I_tmds_channel_2(c2),.I_tmds_channel_clk(cc),
        .O_tmds_ch0_p(tmds_d0_p),.O_tmds_ch1_p(tmds_d1_p),
        .O_tmds_ch2_p(tmds_d2_p),.O_tmds_clk_p(tmds_clk_p));
endmodule
