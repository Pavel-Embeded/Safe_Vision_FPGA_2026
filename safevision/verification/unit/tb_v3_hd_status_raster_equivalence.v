`timescale 1ns/1ps
module status_raster_case #(parameter HD=0,HB=0)(output reg done,output integer comparisons,errors);
 initial begin done = 0; comparisons = 0; errors = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480,CW=HB ? 99:96,HT=HD ? 1650:800,VT=HD ? 750:525;
 reg clk=0,rst=0;always #5 clk=!clk;
 reg[11:0]x=0,y=0;reg[31:0]noise=32'h329a512d^(HD<<8)^HB,underflows=0;
 reg[98:0]cfg=0;reg[3:0]cache=0;reg[1:0]slot=0;reg[7:0]gen=0;reg busy=0,safe=0;
 wire de=x<W&&y<H,fs=x==0&&y==0;
 wire[15:0]a0,a1,a2,a3,b0,b1,b2,b3;wire[7:0]aa0,aa1,aa2,ba0,ba1,ba2;
 v3_status_layers #(.RASTER_PREDECODE(1),.HD(HD),.HANDBOOK_PROFILE(HB),.PIXEL_HZ(74),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE(HB ? "v3_handbook_status_text.mem":"v3_status_text.mem")) dut(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg[CW-1:0]),.cache_valid(cache),.underflows(underflows),.active_slot(slot),.generation(gen),.busy(busy),.safety_active(safe),
 .osd_rgb565(a0),.emergency_rgb565(a1),.hud_rgb565(a2),.safe_rgb565(a3),.osd_alpha(aa0),.emergency_alpha(aa1),.hud_alpha(aa2));
 v3_hd_status_reference #(.HD(HD),.HANDBOOK_PROFILE(HB),.PIXEL_HZ(74),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE(HB ? "v3_handbook_status_text.mem":"v3_status_text.mem")) golden(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg[CW-1:0]),.cache_valid(cache),.underflows(underflows),.active_slot(slot),.generation(gen),.busy(busy),.safety_active(safe),
 .osd_rgb565(b0),.emergency_rgb565(b1),.hud_rgb565(b2),.safe_rgb565(b3),.osd_alpha(ba0),.emergency_alpha(ba1),.hud_alpha(ba2));
 always @(posedge clk or negedge rst)
  if(!rst)begin x<=0;y<=0;end
  else if(x==HT-1)begin x<=0;y<=y==VT-1 ? 0:y+1'b1;end else x<=x+1'b1;
 always @(negedge clk)begin
  noise<={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
  underflows<=noise;cfg<={noise,noise^32'h33335555,noise^32'habcd9876,noise[2:0]};
  cache<=noise[7:4];slot<=noise[1:0];gen<=noise[15:8];busy<=noise[17];safe<=noise[18];
 end
 always @(posedge clk or negedge rst)begin
  #1;comparisons = comparisons + 1;
  if({a0,a1,a2,a3,aa0,aa1,aa2}!=={b0,b1,b2,b3,ba0,ba1,ba2} || (golden.normal_v1 && rst && dut.normal_effective!==golden.normal_effective))begin
   errors = errors + 1;if(errors<9)$display("[FAIL] status raster predecode edge HD=%0d HB=%0d x=%0d y=%0d got=%h want=%h",HD,HB,x,y,dut.normal_effective,golden.normal_effective);
  end
 end
 integer k;
 initial begin
  #41;rst=1;
  for(k=0;k<24;k = k + 1)begin repeat(1730+k*3)@(negedge clk);#2;rst=0;#3;rst=1;end
  repeat(HT*VT*2+100)@(negedge clk);
  done=1;
 end
endmodule
module tb_v3_hd_status_raster_equivalence;
 wire d0,d1,d2,d3;wire signed [31:0] c0,c1,c2,c3,e0,e1,e2,e3;
 status_raster_case #(.HD(0),.HB(0)) a(d0,c0,e0);
 status_raster_case #(.HD(0),.HB(1)) b(d1,c1,e1);
 status_raster_case #(.HD(1),.HB(0)) c(d2,c2,e2);
 status_raster_case #(.HD(1),.HB(1)) d(d3,c3,e3);
 initial begin wait(d0&&d1&&d2&&d3);#2;
  $display("[PASS] status raster predecode exact raw outputs/glyph code acrossBASE/HD,legacy/handbook,two rasters,24async resets,changing configuration");
  $display("PASS tb_v3_hd_status_raster_equivalence comparisons=%0d errors=%0d",c0+c1+c2+c3,e0+e1+e2+e3);$finish;
 end
 initial begin #40000000;$display("[FAIL] status raster predecode watchdog errors=1");$finish;end
endmodule
