`timescale 1ns/1ps
module tb_v3_handbook_hud;
 reg clk=0,rst=0;always #5 clk=~clk;reg[11:0]x=0,y=0;reg[98:0]cfg=0;reg busy=0,safe=0;
 wire[15:0]osd,em,hud,srgb;wire[7:0]oa,ea,ha;
 v3_status_layers #(.HANDBOOK_PROFILE(1),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_handbook_status_text.mem")) dut(
 .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(1'b1),.frame_start(1'b0),
 .cfg_data(cfg),.cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(8'd1),.busy(busy),.safety_active(safe),
 .osd_rgb565(osd),.emergency_rgb565(em),.hud_rgb565(hud),.safe_rgb565(srgb),.osd_alpha(oa),.emergency_alpha(ea),.hud_alpha(ha));
 reg[7:0]font[0:4095];reg[511:0]text;reg[7:0]ch;integer errors=0,comparisons=0,c,b,r,m;bit dot;
 task line(input integer yy,length,input bit is_menu,input[511:0]content);begin
  // Decimal converter runs independently; wait a full seven-value refresh.
  repeat(100)@(negedge clk);
  for(c=0;c<length;c++)for(r=1;r<15;r+=3)for(b=0;b<8;b++)begin
   ch=content[(63-c)*8+:8];dot=font[ch*16+r][7-b];
   @(negedge clk);x=8+c*8+b;y=yy+r;repeat(4)@(posedge clk);#1;comparisons++;
   if(is_menu?(oa!=160||osd!=(dot?16'hffff:16'h05bf)):(ha!=(dot?224:0)))begin
    errors++;if(errors<10)$display("[FAIL] handbook glyph row=%0d char=%0d code=%h bit=%0d",yy,c,ch,b);end
  end
 end endtask
 initial begin
  $readmemh("font8x16.mem",font);cfg[95]=1;cfg[94:87]=60;cfg[86:79]=128;cfg[78:71]=160;cfg[67:61]=70;cfg[7:0]=37;
  repeat(5)@(negedge clk);rst=1;
  line(24,47,0,"SD READY CACHE F MODE AUTO   LAT 037 MS BR 080%                 ");
  cfg[95]=0;cfg[7:0]=255;
  line(24,47,0,"SD READY CACHE F MODE NORMAL LAT 255+MS BR 080%                 ");
  safe=1;line(24,47,0,"SD READY CACHE F MODE SAFE   LAT 255+MS BR 080%                 ");safe=0;busy=1;
  line(24,47,0,"SD READY CACHE F MODE WAIT   LAT 255+MS BR 080%                 ");busy=0;
  cfg[55]=1;cfg[58:56]=0;line(100,18,1,"BRIGHTNESS   080 %                                              ");
  cfg[98]=1;cfg[94:87]=-128;
  line(100,18,1,"OFFSET      -128                                                ");
  cfg[98]=0;cfg[94:87]=-100;line(100,18,1,"BRIGHTNESS   000 %                                              ");
  cfg[94:87]=100;line(100,18,1,"BRIGHTNESS   100 %                                              ");
  cfg[58:56]=3;
  for(m=0;m<4;m++)begin cfg[97:96]=m;
   case(m)0:text="SCALE       1:1                                                 ";1:text="SCALE       FIT                                                 ";
    2:text="SCALE       1/2                                                 ";3:text="SCALE       1/4                                                 ";endcase
   line(160,15,1,text);
  end
  if(errors==0)$display("[PASS] literal glyph oracle for AUTO/NORMAL/SAFE/WAIT, actual milliseconds, percent/raw brightness and four geometries");
  $display("[TB] tb_v3_handbook_hud done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
