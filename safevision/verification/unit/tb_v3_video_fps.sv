`timescale 1ns/1ps
module tb_v3_video_fps;
 reg clk=0,rst=0,fs=0,de=0;always #5 clk=~clk;
 reg[11:0] x=0,y=0;reg[95:0] cfg=0;
 wire[7:0] ha;wire[15:0] hud;
 v3_status_layers #(.PIXEL_HZ(10000),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_status_text.mem")) dut(
  .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),
  .cfg_data(cfg),.cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),
  .busy(1'b0),.safety_active(1'b0),.osd_rgb565(),.emergency_rgb565(),.hud_rgb565(hud),
  .safe_rgb565(),.osd_alpha(),.emergency_alpha(),.hud_alpha(ha));
 reg[7:0] font[0:4095];integer errors=0,comparisons=0,i,row,bitno,character,place;
 initial begin
  $readmemh("font8x16.mem",font);repeat(5)@(negedge clk);


  for(i=0;i<10000;i=i+1)begin
   rst=1;fs=(i%500==0)||(i==9999);@(posedge clk);#1;@(negedge clk);
  end
  fs=0;repeat(70)@(negedge clk);de=1;
  for(place=0;place<2;place=place+1)begin
   character=place==0?"2":"1";
   for(row=0;row<16;row=row+1)for(bitno=0;bitno<8;bitno=bitno+1)begin
    x=8+(35+place)*8+bitno;y=8+row;
    repeat(4)@(posedge clk);#1;
    if(ha!==(font[character*16+row][7-bitno]?8'd224:8'd0))begin
     if(errors<4)$display("[FAIL] measured FPS glyph not 21 xy=%0d,%0d",x,y);errors=errors+1;
    end
    comparisons=comparisons+1;@(negedge clk);
   end
  end
  if(!errors)$display("[PASS] FPS measured from real frame pulses including a frame on the second boundary");
  $display("[TB] tb_v3_video_fps done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #1000000;$display("[FAIL] fps timeout errors=1");$finish;end
endmodule
