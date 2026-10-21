`timescale 1ns/1ps
module tb_v3_phy_lane_equivalence;
 reg pixel=0,serial=0,ar=0;always #10 pixel=~pixel;always #2 serial=~serial;
 reg[39:0] data=40'habcde12345;reg[31:0] rng=32'h724ac319;
 wire ref_n;wire[3:0] lane_n,actual,expected;integer i,errors=0,comparisons=0;
 reset_sync reference_reset(.clk(serial),.async_rst_n(ar),.rst_n(ref_n));
 v3_phy_reset_fanout new_reset(.clk(serial),.async_rst_n(ar),.lane_rst_n(lane_n));
 hdmi_phy_wrapper #(.DEVICE("EG")) original(.I_pixel_clk(pixel),.I_serial_clk(serial),.I_rst(!ref_n),
 .I_tmds_channel_0(data[9:0]),.I_tmds_channel_1(data[19:10]),.I_tmds_channel_2(data[29:20]),.I_tmds_channel_clk(data[39:30]),
 .O_tmds_ch0_p(expected[0]),.O_tmds_ch1_p(expected[1]),.O_tmds_ch2_p(expected[2]),.O_tmds_clk_p(expected[3]));
 v3_hdmi_phy_wrapper #(.DEVICE("EG")) revised(.I_pixel_clk(pixel),.I_serial_clk(serial),.I_rst(~lane_n),
 .I_tmds_channel_0(data[9:0]),.I_tmds_channel_1(data[19:10]),.I_tmds_channel_2(data[29:20]),.I_tmds_channel_clk(data[39:30]),
 .O_tmds_ch0_p(actual[0]),.O_tmds_ch1_p(actual[1]),.O_tmds_ch2_p(actual[2]),.O_tmds_clk_p(actual[3]));
 always @(negedge pixel)begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);data<={rng,rng[7:0]};end
 initial begin
  repeat(10)@(negedge serial);ar=1;
  for(i=0;i<100000;i=i+1)begin
   @(serial);#0.001;comparisons=comparisons+4;
   if(actual!==expected)begin errors=errors+1;if(errors<10)$display("[FAIL] original vendor serial stream differs edge=%0d expected=%b actual=%b",i,expected,actual);end
   if(i>20 && (^actual===1'bx))begin errors=errors+1;if(errors<10)$display("[FAIL] unknown live serial stream");end
   if(i%997==996)begin ar=0;#0.123;ar=1;end
  end
  if(errors==0)$display("[PASS] all four vendor serial streams cycle/edge exact across resets");
  $display("[TB] tb_v3_phy_lane_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] serial equivalence watchdog errors=1");$finish;end
endmodule
