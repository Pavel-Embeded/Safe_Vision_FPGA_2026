`timescale 1ns/1ps
module setting_case88 #(parameter HD=0)(output reg done=0,output integer errors=0,comparisons=0);
 localparam W=HD?1280:640,H=HD?720:480;
 reg clk=0,rst=0,fs=0,de=0;always #5 clk=~clk;
 reg[11:0]x=0,y=0;reg[98:0]cfg=0;wire[15:0]rgb;wire[7:0]alpha;
 v3_status_layers #(.HD(HD),.HANDBOOK_PROFILE(1),.VOLUME_COLUMNS(1),.VOLUME_SETTING(1),.RASTER_PREDECODE(0),.PIXEL_HZ(1000000),.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) d(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),.cfg_data(cfg),.cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),.hud_rgb565(rgb),.hud_alpha(alpha));
 integer setting=0,vu=0,h,k,v,ix,iy,e;reg check_pixels=0;reg be,bf,ve,vf,caption;
 reg[15:0]cr[0:3];reg[7:0]ca[0:3];
 task ck(input bit ok,input string msg);begin comparisons++;if(!ok)begin errors++;if(errors<10)$display("[FAIL] setting HD=%0d %s x=%0d y=%0d level=%0d",HD,msg,x,y,setting);end end endtask

 function bit glyph(input byte ch,input integer row,col);
  string bitmap;begin
   case(ch)
    "V":bitmap="10001100011000110001100010101000100";
    "O":bitmap="01110100011000110001100011000101110";
    "L":bitmap="10000100001000010000100001000011111";
    "U":bitmap="10001100011000110001100011000101110";
    default:bitmap="00000000000000000000000000000000000";
   endcase
   glyph=row>=0&&row<7&&col>=0&&col<5&&bitmap[row*5+col]=="1";
  end
 endfunction
 function bit label_at(input integer px,py);
  integer row,col;begin row=py-(H-60);col=px-(W-81);
   label_at=glyph("V",row,col)||glyph("O",row,col-6)||glyph("L",row,col-12);
   col=px-(W-42);label_at=label_at||glyph("V",row,col)||glyph("U",row,col-6);
  end
 endfunction
 always @(posedge clk)begin
  for(integer q=3;q>0;q--)begin cr[q]=cr[q-1];ca[q]=ca[q-1];end
  h=H-70-y;
  be=de&&x>=W-86&&x<=W-60&&y>=H-171&&y<=H-69&&(x==W-86||x==W-60||y==H-171||y==H-69);
  bf=de&&x>W-86&&x<W-60&&h>=1&&h<=100&&h<=setting&&(h==100||h%10!=0);
  ve=de&&x>=W-49&&x<=W-23&&y>=H-171&&y<=H-69&&(x==W-49||x==W-23||y==H-171||y==H-69);
  vf=de&&x>W-49&&x<W-23&&h>=1&&h<=100&&h<=vu&&(h==100||h%10!=0);
  caption=de&&label_at(x,y);
  cr[0]=caption?16'hffff:bf?16'h05bf:vf?(h>80?16'hf800:h>50?16'hffe0:16'h07e0):16'h7bef;
  ca[0]=(caption||be||bf||ve||vf)?224:0;
  #1;if(check_pixels)begin ck(rgb===cr[3],"independent VOL+VU/caption RGB and four-clock alignment");ck(alpha===ca[3],"independent border/fill/text alpha");end
 end
 task capture(input integer gain,eng);begin
  check_pixels=0;@(negedge clk);de=0;x=0;y=0;cfg=0;cfg[67:61]=gain;cfg[54:48]=eng;fs=1;
  setting=gain>100?100:gain;vu=((eng>100?100:eng)*setting)/100;
  @(negedge clk);fs=0;cfg[67:61]=127-gain;cfg[54:48]=0;
  repeat(115)@(negedge clk);ck(d.setting_level==setting,"clamped frame snapshot persists despite mid-frame input changes");
  ck(d.volume_columns.column.level==vu,"original gain-dependent VU remains exact");
  check_pixels=1;
 end endtask
 task point(input integer px,py);begin @(negedge clk);x=px;y=py;de=1;end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  for(v=0;v<128;v++)begin
   capture(v,20);
   for(iy=H-174;iy<=H-66;iy++)begin point(W-73,iy);point(W-36,iy);end
   @(negedge clk);de=0;repeat(6)@(negedge clk);check_pixels=0;
  end
  for(k=0;k<8;k++)begin
   case(k)0:v=0;1:v=1;2:v=20;3:v=40;4:v=70;5:v=100;6:v=127;7:v=100;endcase
   e=k==7?0:20;capture(v,e);
   for(iy=H-175;iy<=H-50;iy++)for(ix=W-90;ix<=W-19;ix++)point(ix,iy);
   @(negedge clk);de=0;repeat(6)@(negedge clk);check_pixels=0;
  end
  rst=0;#1;ck(d.setting_level==0,"reset clears explicit setting column");done=1;
 end
endmodule
module setting_top88;
 wire a,b;wire integer ea,eb,ca,cb;
 setting_case88 #(.HD(0)) base(a,ea,ca);setting_case88 #(.HD(1)) hd(b,eb,cb);
 initial begin wait(a&&b);#2;
  if(ea+eb==0)$display("[PASS] all128 raw volumes,mute/full/quiet source,independent VOL/VU heights,mid-frame stability,BASE/HD RGB/alpha/captions and reset");
`ifdef HD_SETTING_SOURCE
  $display("PASS tb_v3_volume_setting_hd88 errors=%0d comparisons=%0d",ea+eb,ca+cb);
`else
  $display("PASS tb_v3_volume_setting_base88 errors=%0d comparisons=%0d",ea+eb,ca+cb);
`endif
  $finish;
 end
 initial begin #50000000;$display("[FAIL] setting88 watchdog errors=1");$finish;end
endmodule
module tb_v3_volume_setting_base88;setting_top88 t();endmodule
module tb_v3_volume_setting_hd88;setting_top88 t();endmodule
