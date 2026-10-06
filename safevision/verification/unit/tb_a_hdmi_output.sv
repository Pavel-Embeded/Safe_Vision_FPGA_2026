// A wrapper wiring/stream test; encoder is explicitly a CONTRACT model.
// Serializer and ODDR are the actual vendor sources, not that model.
`timescale 1ns/1ps
module hdmi_output_case #(parameter integer HD=0)(output reg done=0);
 localparam integer WIDTH=HD?1280:640,HEIGHT=HD?720:480,HT=HD?1650:800;
 localparam real SH=HD?1.347:3.972;
 reg pc=0,sc=0;always #(5*SH)pc=~pc;always #SH sc=~sc;
 reg rn=0,hpd=0,reread=0,de=0;reg [11:0] x=0,y=0;reg [23:0] rgb=0;
 wire connected,overflow,locked,edid_valid;wire [31:0] drops;wire [7:0] edid_data;
 wire [4:0] level;wire [3:0] q;wire scl;tri1 sda;
 reg av=0,acrv=0;reg [23:0] left=0,right=0;reg [19:0] cts=0,n=0;
 integer acount=0,acr_count=0;
 a_hdmi_output #(.HD(HD),.EDID_SETTLE_CYCLES(4)) dut(
  .pixel_clk(pc),.serial_clk(sc),.rst_n(rn),.hpd(hpd),.edid_reread(reread),
  .rgb(rgb),.de(de),.x(x),.y(y),.audio_valid(av),.audio_left(left),.audio_right(right),
  .acr_valid(acrv),.acr_cts(cts),.acr_n(n),.tmds_d0_p(q[0]),.tmds_d1_p(q[1]),
  .tmds_d2_p(q[2]),.tmds_clk_p(q[3]),.ddc_scl(scl),.ddc_sda(sda),
  .video_locked(locked),.connected(connected),.overflow_sticky(overflow),
  .dropped_frames(drops),.edid_valid(edid_valid),.edid_data(edid_data),.queue_level(level));
 integer cyc=0;
 always @(negedge pc)begin
  cyc=cyc+1;av=(cyc%50==0);acrv=(cyc%61==0);
  left=cyc*17;right=~left;cts=cyc*3;n=6144;
 end
 always @(posedge pc)if(rn&&!dut.tx_reset)begin
  if({dut.transmitter.I_audio_valid,dut.transmitter.I_audio_left_data,dut.transmitter.I_audio_right_data}
    !=={av,left,right})$fatal(1,"PCM24 port connection");
  if({dut.transmitter.I_acr_valid,dut.transmitter.I_acr_cts,dut.transmitter.I_acr_n}
    !=={acrv,cts,n})$fatal(1,"ACR20 port connection");
  if(av)acount=acount+1;if(acrv)acr_count=acr_count+1;
 end
 task raster(input integer lines);
  integer xx,yy;
  begin
   for(yy=0;yy<lines;yy=yy+1)for(xx=0;xx<HT;xx=xx+1)begin
    @(negedge pc);x=xx;y=yy;de=(xx<WIDTH);rgb={8'(xx),8'(yy),8'(xx+yy)};
   end
   @(negedge pc);de=0;
  end
 endtask
 initial begin
  repeat(10)@(negedge pc);rn=1;hpd=1;repeat(200)@(negedge pc);
  raster(3);hpd=0;repeat(15)@(negedge pc);
  if(connected||!dut.tx_reset||dut.serial_rst_n)$fatal(1,"HPD reset did not propagate");
  hpd=1;repeat(200)@(negedge pc);raster(HEIGHT);
  wait(dut.transmitter.completed==1);repeat(20)@(negedge pc);
  if(overflow||drops!=0||!locked||acount<10||acr_count<10)$fatal(1,"wrapper completion/fault/audio");
  if(dut.transmitter.accepted!=WIDTH*HEIGHT)$fatal(1,"full frame count");
  $display("PASS HDMI wrapper contract HD=%0d pixels=%0d PCM=%0d ACR=%0d HPD/reset actualPHY",HD,WIDTH*HEIGHT,acount,acr_count);
  done=1;
 end
endmodule
module tb_a_hdmi_output;
 wire a,b;hdmi_output_case #(.HD(0)) base(a);hdmi_output_case #(.HD(1)) hd(b);
 initial begin wait(a&&b);$display("PASS tb_a_hdmi_output CONTRACT ONLY; encrypted encoding unverified");$finish;end
 initial begin #50000000;$fatal(1,"HDMI wrapper watchdog");end
endmodule
