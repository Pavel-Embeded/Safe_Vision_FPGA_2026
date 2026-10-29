`timescale 1ns/1ps
module tb_v3_keys_osd_hd194;
 reg clk=0,rst=0,power_rst=0,n=1,a=1,e=1;always #5 clk=~clk;
 wire signed[8:0] br;wire[6:0] pct,vol;wire[7:0] contrast,alpha;wire bilinear,fit,fade,menu,raw,auto_en;
 wire[1:0] period,scale;wire[2:0] field;
 wire[98:0] cfg={raw,scale,auto_en,br[7:0],contrast,alpha,bilinear,fit,fade,vol,period,field,menu,7'd20,8'd0,32'd0,8'd0};
 v3_user_controls #(.CLK_HZ(64),.DEBOUNCE(2),.HANDBOOK_PROFILE(1),.RETAIN_CONFIG(1)) keys(
  .clk(clk),.rst_n(rst),.config_rst_n(power_rst),.next_async(n),.auto_async(a),.emergency_async(e),
  .command_valid(1'b0),.command_target(8'd0),.command_name(96'd0),.command_value(32'd0),.command_query(1'b0),
  .cached(1'b1),.transition_busy(1'b0),.frame_commit(1'b0),.system_safe(1'b0),.catalog_id(7'd0),
  .auto_enabled(auto_en),.brightness(br),.brightness_pct(pct),.brightness_raw(raw),.contrast(contrast),.osd_alpha(alpha),
  .bilinear(bilinear),.fit(fit),.fade_enabled(fade),.volume(vol),.period_select(period),.menu(menu),.field(field),.scale_select(scale));
 reg[11:0] x=0,y=0;reg de=0;reg[31:0] uptime=32'h01234567;
 wire[15:0] hbase,hhd,sbase,shd;wire[7:0] abase,ahd;
 v3_status_layers #(.HD(1),.HANDBOOK_PROFILE(1),.USER_FEATURES(1),.TEXT_FILE("v3_handbook_status_text.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem")) base(
  .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(1'b0),.cfg_data(cfg),.cache_valid(4'hf),
  .underflows(32'd0),.active_slot(2'd0),.generation(8'd0),.busy(1'b0),.safety_active(1'b0),
  .uptime_bcd(uptime),.wave_pcm_valid(1'b0),.wave_pcm_left(24'd0),.hud_rgb565(hbase),.hud_alpha(abase),.safe_rgb565(sbase));
 reg[7:0] font[0:1023];integer errors=0,comparisons=0,c,r,col,expected;
 initial $readmemh("font8x16_compact.mem",font);
 task ck(input  ok,input [4095:0] m);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<10)$display("[FAIL] %s",m);end end  end endtask
 task glyph(input integer row,index,code);begin begin
  for(r=0;r<16;r = r + 1)for(col=0;col<8;col = col + 1)begin
   @(negedge clk);de=1;x=8+index*8+col;y=row+r;repeat(5)@(posedge clk);#1;
   expected=r!=0&&r!=15 ? ((font[{v_cast_s7(code),v_cast_s3((r-1)/2)}]>>(7-col))&1):0;
   ck(abase==224,"text window has constant dark backing alpha");
   ck(hbase==(expected ? 16'hffff:16'd0),"every lit/unlit glyph pixel matches external font and dark backing");
   if(expected)ck(hbase==16'hffff,"parameter/timestamp glyph white");
   if(row==696)ck(sbase==(expected ? 16'hffff:16'd0),"uptime white glyph and dark backing also visible in SAFE layer");
  end
 end  end endtask
 task tap_inc;begin begin @(negedge clk);n=0;repeat(12)@(negedge clk);n=1;repeat(100)@(negedge clk);end  end endtask
 initial begin
  repeat(5)@(negedge clk);power_rst=1;rst=1;repeat(100)@(negedge clk);
  ck(pct==80&&contrast==128,"defaults");glyph(56,4,"0");glyph(56,5,"8");glyph(56,6,"0");glyph(56,13,"1");glyph(56,14,"2");glyph(56,15,"8");
  @(negedge clk);n=0;a=0;repeat(160)@(negedge clk);n=1;a=1;repeat(100)@(negedge clk);ck(menu&&field==0,"physical KEY2+3 long chord enters brightness menu");
  tap_inc();ck(pct==85&&br==70,"KEY2 physical brightness increases");glyph(56,5,"8");glyph(56,6,"5");
  @(negedge clk);n=0;repeat(160)@(negedge clk);n=1;repeat(100)@(negedge clk);ck(field==1,"long KEY2 selects contrast");
  tap_inc();ck(contrast==136,"KEY2 physical contrast increases");glyph(56,13,"1");glyph(56,14,"3");glyph(56,15,"6");
  for(c=0;c<8;c = c + 1)glyph(696,3+c,48+c);
  rst=0;repeat(8)@(negedge clk);rst=1;repeat(100)@(negedge clk);ck(pct==85&&contrast==136,"warm reset retains settings");
  if(!errors)$display("[PASS] real key chord/menu/taps -> retained brightness/contrast -> actual parameter glyphs;8-digit seconds and SAFE timestamp");
  $display("[TB] tb_v3_keys_osd_hd194 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #10000000;$display("[FAIL] key OSD watchdog errors=1");$finish;end

function signed [2:0] v_cast_s3; input signed [2:0] value; begin begin v_cast_s3=value; end  end endfunction
function signed [6:0] v_cast_s7; input signed [6:0] value; begin begin v_cast_s7=value; end  end endfunction
endmodule
