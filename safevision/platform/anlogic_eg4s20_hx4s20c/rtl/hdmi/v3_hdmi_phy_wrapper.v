// Keep the original vendor bit reversal, serializer and DDR implementation.
// Only each connected lane is synthesized from its wrapper instance; three
// unused outputs are open. No vendor source bytes are edited.
module v3_hdmi_phy_wrapper #(parameter DEVICE="EG")(input wire I_pixel_clk,I_serial_clk,input wire[3:0] I_rst,
 input wire[9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output wire O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 hdmi_phy_wrapper #(.DEVICE(DEVICE)) lane0(.I_pixel_clk(I_pixel_clk),.I_serial_clk(I_serial_clk),.I_rst(I_rst[0]),
 .I_tmds_channel_0(I_tmds_channel_0),.I_tmds_channel_1(I_tmds_channel_1),.I_tmds_channel_2(I_tmds_channel_2),.I_tmds_channel_clk(I_tmds_channel_clk),
 .O_tmds_ch0_p(O_tmds_ch0_p),.O_tmds_ch1_p(),.O_tmds_ch2_p(),.O_tmds_clk_p());
 hdmi_phy_wrapper #(.DEVICE(DEVICE)) lane1(.I_pixel_clk(I_pixel_clk),.I_serial_clk(I_serial_clk),.I_rst(I_rst[1]),
 .I_tmds_channel_0(I_tmds_channel_0),.I_tmds_channel_1(I_tmds_channel_1),.I_tmds_channel_2(I_tmds_channel_2),.I_tmds_channel_clk(I_tmds_channel_clk),
 .O_tmds_ch0_p(),.O_tmds_ch1_p(O_tmds_ch1_p),.O_tmds_ch2_p(),.O_tmds_clk_p());
 hdmi_phy_wrapper #(.DEVICE(DEVICE)) lane2(.I_pixel_clk(I_pixel_clk),.I_serial_clk(I_serial_clk),.I_rst(I_rst[2]),
 .I_tmds_channel_0(I_tmds_channel_0),.I_tmds_channel_1(I_tmds_channel_1),.I_tmds_channel_2(I_tmds_channel_2),.I_tmds_channel_clk(I_tmds_channel_clk),
 .O_tmds_ch0_p(),.O_tmds_ch1_p(),.O_tmds_ch2_p(O_tmds_ch2_p),.O_tmds_clk_p());
 hdmi_phy_wrapper #(.DEVICE(DEVICE)) lane3(.I_pixel_clk(I_pixel_clk),.I_serial_clk(I_serial_clk),.I_rst(I_rst[3]),
 .I_tmds_channel_0(I_tmds_channel_0),.I_tmds_channel_1(I_tmds_channel_1),.I_tmds_channel_2(I_tmds_channel_2),.I_tmds_channel_clk(I_tmds_channel_clk),
 .O_tmds_ch0_p(),.O_tmds_ch1_p(),.O_tmds_ch2_p(),.O_tmds_clk_p(O_tmds_clk_p));
endmodule
