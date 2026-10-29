`timescale 1ns/1ps
module volume_column_vblank_case #(parameter HD=0)(output reg done,output integer errors,comparisons);
 initial begin done = 0; errors = 0; comparisons = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480,HT=HD ? 1650:800,VT=HD ? 750:525;
 reg clk=0,rst=0;always #5 clk=~clk;reg[11:0]x=0,y=0;
 wire de=x<W&&y<H,fs=x==0&&y==H;
 reg[98:0]cfg=0;wire[15:0]rgb,oldrgb;wire[7:0]alpha,oldalpha;
 v3_status_layers #(.HD(HD),.HANDBOOK_PROFILE(1),.VOLUME_COLUMNS(1),
`ifdef HD_STATUS
 .RASTER_PREDECODE(HD),
`endif

 .FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) hud(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),
 .cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.hud_rgb565(rgb),.hud_alpha(alpha));
 v3_status_layers #(.HD(HD),.HANDBOOK_PROFILE(1),.VOLUME_COLUMNS(0),
`ifdef HD_STATUS
 .RASTER_PREDECODE(HD),
`endif

 .FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) legacy(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),
 .cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.hud_rgb565(oldrgb),.hud_alpha(oldalpha));
 always@(posedge clk or negedge rst)if(!rst)begin x<=0;y<=0;end
 else if(x==HT-1)begin x<=0;y<=y==VT-1 ? 0:y+1'b1;end else x<=x+1'b1;
 integer frame=-1,expected=0,h,i;reg ee,ff;reg[3:0]roi;
 reg[15:0]cr[0:3];reg[7:0]ca[0:3];reg valid_compare=0;
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<6)$display("[FAIL] actual raster HD=%0d %s x=%0d y=%0d",HD,msg,x,y);end end  end endtask
 always@(negedge clk)if(rst&&frame>=0&&x==1&&y==H/2)begin cfg[67:61]=100;cfg[54:48]=100;end
 always@(posedge clk)begin
  if(rst&&fs)begin
   expected=(cfg[67:61]*cfg[54:48])/100;frame = frame + 1;
  end
  for(i=3;i>0;i = i - 1)begin cr[i]=cr[i-1];ca[i]=ca[i-1];end
  h=H-70-y;
  roi={roi[2:0],de&&x>=W-49&&x<=W-23&&y>=H-171&&y<=H-69};
  ee=de&&x>=W-49&&x<=W-23&&y>=H-171&&y<=H-69&&(x==W-49||x==W-23||y==H-171||y==H-69);
  ff=de&&x>W-49&&x<W-23&&h>=1&&h<=100&&h<=expected&&(h==100||h%10!=0);
  cr[0]=ff ? (h>80 ? 16'hf800:h>50 ? 16'hffe0:16'h07e0):16'h7bef;ca[0]=ee||ff ? 224:0;
  #1;if(rst&&valid_compare)begin
   if(roi[3])begin ck(rgb===cr[3],"column colour and frame snapshot");ck(alpha===ca[3],"column edge/height/alpha");end
   else ck({rgb,alpha}==={oldrgb,oldalpha},"all existing HUD pixels preserved outside column");
  end
 end
 initial begin
  cfg[54:48]=75;cfg[67:61]=50;
  #41;rst=1;repeat(6)@(negedge clk);valid_compare=1;
  wait(frame>=3);repeat(8)@(negedge clk);valid_compare=0;done=1;
 end
endmodule
module tb_v3_volume_columns_vblank_hd;
 wire a,b;wire signed [31:0] ea,eb,ca,cb;
 volume_column_vblank_case #(.HD(0)) base(a,ea,ca);volume_column_vblank_case #(.HD(1)) hd(b,eb,cb);
 initial begin wait(a&&b);#2;
  if(ea+eb==0)$display("[PASS] actual production first-vertical-blank snapshot; four BASE/HD rasters; immutable column and preserved HUD");
  $display("[TB] tb_v3_volume_columns_vblank_hd done errors=%0d comparisons=%0d",ea+eb,ca+cb);$finish;end
 initial begin #60000000;$display("[FAIL] vblank watchdog");$display("[TB] tb_v3_volume_columns_vblank_hd done errors=1");$finish;end
endmodule
