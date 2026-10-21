`timescale 1ns/1ps
module tb_v3_status_layers;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[11:0] x=0,y=0;reg de=0,fs=0;reg[95:0] cfg=0;
 reg[3:0] cache=15;reg[31:0] uf=32'h12345678;
 reg[1:0] slot=2;reg[7:0] gen=173;reg busy=0,safe=0;
 wire[15:0] osd,em,hud,srgb;wire[7:0] oa,ea,ha;
 v3_status_layers #(.FONT_FILE("font8x16.mem"),.COMPACT_FONT_FILE("font8x16_compact.mem"),
  .TEXT_FILE("v3_status_text.mem")) dut(
  .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(de),.frame_start(fs),
  .cfg_data(cfg),.cache_valid(cache),.underflows(uf),.active_slot(slot),.generation(gen),
  .busy(busy),.safety_active(safe),.osd_rgb565(osd),.emergency_rgb565(em),
  .hud_rgb565(hud),.safe_rgb565(srgb),.osd_alpha(oa),.emergency_alpha(ea),.hud_alpha(ha));
 reg[7:0] font[0:4095];integer errors=0,comparisons=0,c,r,b,k;
 reg[511:0] line_text;reg[7:0] ch;bit dot;
 task check(input bit good,input string message);begin
  comparisons++;if(!good)begin if(errors<8)$display("[FAIL] %s x=%0d y=%0d",message,x,y);errors++;end
 end endtask
 task point(input integer xx,yy);begin
  @(negedge clk);x=xx;y=yy;de=1;
  repeat(4)@(posedge clk);#1;
 end endtask
 initial begin
  $readmemh("font8x16.mem",font);cfg[86:79]=128;cfg[78:71]=160;
  cfg[54:48]=50;cfg[39:8]=32'h89abcdef;
  repeat(5)@(negedge clk);rst=1;
  line_text="SAFEVISION BASE SLOT 3 GEN 173 FPS 00                           ";
  for(c=0;c<37;c++)for(r=0;r<16;r+=3)for(b=0;b<8;b+=2)begin
   ch=line_text[(63-c)*8+:8];dot=font[ch*16+r][7-b];
   point(8+c*8+b,8+r);check(ha==(dot?224:0),"HUD glyph/slot/generation digits");
   check(oa==0&&ea==0,"transparent independent layers");
  end
  line_text="VIDEO UF 12345678 AUDIO UF 89ABCDEF ERR 00                      ";
  for(c=0;c<42;c++)begin
   ch=line_text[(63-c)*8+:8];
   for(b=0;b<8;b++)begin point(8+c*8+b,47);check(ha==(font[ch*16+7][7-b]?224:0),"both live underflow counters");end
  end
  point(100,464);check(ha==224&&hud==16'h07e0,"energy visible with menu closed");
  point(200,464);check(ha==0,"energy end reflects 50 percent");
  cfg[55]=1;cfg[58:56]=0;cfg[95:87]=-9'sd128;
  point(290,101);check(oa==160&&osd==16'h05bf,"current menu field highlight");
  point(290,121);check(oa==160&&osd==16'h1086,"other menu field panel");
  line_text="BRIGHTNESS  -128                                                ";
  for(c=0;c<16;c++)for(b=0;b<8;b++)begin
   ch=line_text[(63-c)*8+:8];dot=font[ch*16+7][7-b];
   point(8+c*8+b,107);check(oa==160&&osd==(dot?16'hffff:16'h05bf),"signed brightness text");
  end
  cfg[55]=0;cfg[47:40]=8'h3a;
  point(0,200);check(ea==224&&em==16'hf800,"warning border");
  point(400,200);check(ea==0,"warning interior transparent");
  line_text="WARNING CODE 3A | PRESS NEXT TO RECOVER                         ";
  for(c=0;c<39;c++)for(b=0;b<8;b++)begin
   ch=line_text[(63-c)*8+:8];point(8+c*8+b,423);
   check(ea==(font[ch*16+7][7-b]?224:0),"warning text and code");
  end
  safe=1;
  line_text="EMERGENCY                                                       ";
  for(c=0;c<9;c++)for(b=0;b<8;b++)begin
   ch=line_text[(63-c)*8+:8];point(248+c*16+b*2,134);
   check(srgb==(font[ch*16+7][7-b]?16'h07e0:16'h1800),"independent two-times SAFE text");
  end
  // A single input pixel must appear on the fourth edge, including de masking.
  @(negedge clk);de=0;repeat(4)@(posedge clk);#1;
  @(negedge clk);x=0;y=0;de=1;
  for(k=1;k<=4;k++)begin @(posedge clk);#1;check(ea==(k==4?224:0),"four-clock layer latency");end
  @(negedge clk);de=0;repeat(4)@(posedge clk);#1;
  check(oa==0&&ea==0&&ha==0&&srgb==0,"de masks every output");
  if(errors==0)$display("[PASS] telemetry, glyphs, menu, energy, warning, SAFE and alignment");
  $display("PASS tb_v3_status_layers errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #500000;$display("[FAIL] renderer timeout errors=1");$finish;end
endmodule
