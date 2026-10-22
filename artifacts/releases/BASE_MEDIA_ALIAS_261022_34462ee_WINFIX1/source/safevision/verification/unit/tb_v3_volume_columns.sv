`timescale 1ns/1ps
module volume_column_case #(parameter HD=0)(output reg done=0,output integer errors=0,comparisons=0);
 localparam W=HD?1280:640,H=HD?720:480;
 reg clk=0,rst=0,fs=0,de=0;always #5 clk=~clk;
 reg[6:0]en=0,vol=0;reg[11:0]x=0,y=0;
 wire ed,fl,busy;wire[1:0]colour;wire[6:0]lev;
 v3_volume_column #(.WIDTH(W),.HEIGHT(H)) dut(clk,rst,fs,en,vol,x,y,de,ed,fl,colour,lev,busy);
 reg[98:0]cfg=0;wire[15:0]rgb;wire[7:0]alpha;
 v3_status_layers #(.HD(HD),.HANDBOOK_PROFILE(1),.VOLUME_COLUMNS(1),
`ifdef HD_STATUS
 .RASTER_PREDECODE(0), // ROI coordinate jumps; exact raster recurrence is tested separately.
`endif
 .FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) hud(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),
 .cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.hud_rgb565(rgb),.hud_alpha(alpha));
 integer e,v,k,n,ix,iy,h,expected,stable;reg ee,ff;reg[1:0]cc;
 reg[15:0]cr[0:3];reg[7:0]ca[0:3];reg pipeline_checks=0;
 task ck(input bit ok,input string msg);begin comparisons++;if(!ok)begin errors++;if(errors<8)$display("[FAIL] HD=%0d %s",HD,msg);end end endtask
 task snapshot(input integer a,b);begin
  @(negedge clk);x=0;y=0;de=0;en=a;vol=b;cfg[54:48]=a;cfg[67:61]=b;fs=1;
  @(negedge clk);fs=0;en=0;vol=0; // Controls after snapshot must not change the result.
  n=0;while(busy&&n<112)begin @(negedge clk);n++;end
  expected=((a>100?100:a)*(b>100?100:b))/100;
  ck(!busy,"bounded serial gain/division completion");ck(lev===expected[6:0],"independent exact gain including input clamps");
 end endtask
 always@(posedge clk)begin
  for(integer q=3;q>0;q--)begin cr[q]=cr[q-1];ca[q]=ca[q-1];end
  h=H-70-y;
  ee=de&&x>=W-49&&x<=W-23&&y>=H-171&&y<=H-69&&(x==W-49||x==W-23||y==H-171||y==H-69);
  ff=de&&x>W-49&&x<W-23&&h>=1&&h<=100&&h<=expected&&(h==100||h%10!=0);
  cc=h>80?2:h>50?1:0;
  cr[0]=ff?(cc==2?16'hf800:cc==1?16'hffe0:16'h07e0):16'h7bef;ca[0]=ee||ff?224:0;
  #1;if(pipeline_checks)begin ck(rgb===cr[3],"four-clock RGB colour/position");ck(alpha===ca[3],"four-clock HUD alpha/edge/fill");end
 end
 initial begin
  repeat(4)@(negedge clk);rst=1;
  if(!HD)for(e=0;e<=100;e++)for(v=0;v<=100;v++)snapshot(e,v);
  for(k=0;k<9;k++)begin
   case(k)0:begin e=75;v=0;end 1:begin e=75;v=1;end 2:begin e=75;v=25;end
   3:begin e=75;v=50;end 4:begin e=75;v=70;end 5:begin e=75;v=100;end
   6:begin e=100;v=100;end 7:begin e=127;v=127;end 8:begin e=0;v=100;end endcase
   snapshot(e,v);repeat(5)@(negedge clk);pipeline_checks=1;stable=lev;
   for(iy=H-174;iy<=H-66;iy++)for(ix=W-52;ix<=W-20;ix++)begin
    @(negedge clk);x=ix;y=iy;de=1;#1;h=H-70-iy;
    ee=ix>=W-49&&ix<=W-23&&iy>=H-171&&iy<=H-69&&(ix==W-49||ix==W-23||iy==H-171||iy==H-69);
    ff=ix>W-49&&ix<W-23&&h>=1&&h<=100&&h<=expected&&(h==100||h%10!=0);
    ck(ed===ee&&fl===ff,"independent segmented column raster");ck(lev==stable,"no mid-frame level change");
   end
   @(negedge clk);de=0;repeat(6)@(negedge clk);pipeline_checks=0;
  end
  @(negedge clk);rst=0;#1;ck(lev==0&&!busy,"asynchronous reset clears level/calculation");done=1;
 end
endmodule
`ifdef HD_STATUS
module tb_v3_volume_columns_hd;
`else
module tb_v3_volume_columns_base;
`endif
 wire a,b;wire integer ea,eb,ca,cb;
 volume_column_case #(.HD(0)) base(a,ea,ca);
 volume_column_case #(.HD(1)) hd(b,eb,cb);
 initial begin wait(a&&b);#2;
  if(ea+eb==0)$display("[PASS] all10201 gains, muted/clamped inputs, immutable frame controls, independent BASE/HD colour raster and four-cycle HUD pipeline");
  `ifdef HD_STATUS
  $display("[TB] tb_v3_volume_columns_hd done errors=%0d comparisons=%0d",ea+eb,ca+cb);
`else
  $display("[TB] tb_v3_volume_columns_base done errors=%0d comparisons=%0d",ea+eb,ca+cb);
`endif
  $finish;end
 initial begin #30000000;$display("[FAIL] volume columns timeout");
`ifdef HD_STATUS
$display("[TB] tb_v3_volume_columns_hd done errors=1");
`else
$display("[TB] tb_v3_volume_columns_base done errors=1");
`endif
$finish;end
endmodule
