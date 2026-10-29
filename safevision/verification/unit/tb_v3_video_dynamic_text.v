`timescale 1ns/1ps

module tb_v3_video_dynamic_text_model #(parameter HD=0)();
 reg clk=0;always #5 clk=~clk;reg rst=0;
 reg[11:0] x=0,y=0;reg[95:0] cfg=0;reg[3:0] cache=15;
 reg[31:0] uf=0;reg[1:0] slot=0;reg[7:0] gen=0;reg busy=0,safe=0;
 wire[15:0] osd,em,hud;wire[7:0] oa,ea,ha;
 v3_status_layers #(.HD(HD),.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_status_text.mem")) dut(
  .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(1'b1),.frame_start(1'b0),
  .cfg_data(cfg),.cache_valid(cache),.underflows(uf),.active_slot(slot),.generation(gen),.busy(busy),.safety_active(safe),
  .osd_rgb565(osd),.emergency_rgb565(em),.hud_rgb565(hud),.safe_rgb565(),.osd_alpha(oa),.emergency_alpha(ea),.hud_alpha(ha));
 reg[7:0] font[0:4095];integer errors=0,comparisons=0,n,i;
 function[7:0] hexchar(input integer value);begin begin hexchar=value<10 ? 48+value:55+value;end  end endfunction
 task character(input integer code,column,top,layer,input  selected);
  integer row,col;reg dot,good;begin begin
   selected = (selected === 1'b1); for(row=0;row<16;row=row+1)for(col=0;col<8;col=col+1)begin
    @(negedge clk);x=8+column*8+col;y=top+row;repeat(4)@(posedge clk);#1;
    dot= ((font[code*16+row][7-col]) === 1'b1);
    case(layer)
     0:good= ((oa===cfg[78:71]&&osd===(dot ? 16'hffff:selected ? 16'h05bf:16'h1086)) === 1'b1);
     1:good= ((ea===(dot ? 8'd224:8'd0)&&(!dot||em===16'hf800)) === 1'b1);
     2:good= ((ha===(dot ? 8'd224:8'd0)&&(!dot||hud===16'hffff)) === 1'b1);
    endcase
    comparisons=comparisons+1;
    if(!good)begin errors=errors+1;if(errors<8)$display("[FAIL] HD=%0d code=%h xy=%0d,%0d layer=%0d",HD,code,x,y,layer);end
   end
  end
  end endtask
 task word(input[63:0] text,input integer length,column,top,layer,input  selected);
  integer k;begin begin selected = (selected === 1'b1); for(k=0;k<length;k=k+1)character(text[(7-k)*8+:8],column+k,top,layer,selected);end
  end endtask
 initial begin
  $readmemh("font8x16.mem",font);cfg[55]=1;cfg[78:71]=200;cfg[69]=1;cfg[68]=1;
  repeat(5)@(negedge clk);rst=1;repeat(70)@(negedge clk);
  word(HD ? "HD      ":"BASE    ",4,11,8,2,0);
  for(n=0;n<4;n=n+1)begin slot=n;character(49+n,21,8,2,0);end
  for(n=0;n<16;n=n+1)begin
   cache=n;word(n==15 ? "READY   ":"LOAD    ",5,3,24,2,0);character(hexchar(n),15,24,2,0);
   uf=32'h11111111*n;cfg[39:8]=~uf;
   for(i=0;i<8;i=i+1)begin character(hexchar(n),9+i,40,2,0);character(hexchar(15-n),27+i,40,2,0);end
  end
  for(n=0;n<4;n=n+1)begin
   safe=n[1];busy=n[0];word(n[1] ? "SAFE    ":n[0] ? "WAIT    ":"PLAY    ",4,23,24,2,0);
  end
  safe=0;busy=0;
  for(n=0;n<256;n=n+1)begin
   cfg[47:40]=n;character(hexchar(n/16),40,40,2,0);character(hexchar(n%16),41,40,2,0);
   if(n!=0)begin character(hexchar(n/16),13,(HD ? 720:480)-64,1,0);character(hexchar(n%16),14,(HD ? 720:480)-64,1,0);end
   cfg[78:71]=n;repeat(70)@(negedge clk);
   character(48+n/100,12,240,0,0);character(48+(n/10)%10,13,240,0,0);character(48+n%10,14,240,0,0);
  end
  cfg[78:71]=200;
  for(n=0;n<2;n=n+1)begin
   cfg[70]=n;word(n ? "BILINEAR":"NEAREST ",8,12,140,0,0);
   cfg[69]=n;word(n ? "FIT     ":"1:1     ",3,12,160,0,0);
   cfg[68]=n;word(n ? "ON      ":"OFF     ",3,12,180,0,0);
   cfg[95:87]=n ? -9'sd1:9'sd1;character(n ? 45:43,12,100,0,1);
  end
  for(n=0;n<4;n=n+1)begin
   cfg[60:59]=n;word(n==0 ? "02      ":n==1 ? "05      ":n==2 ? "10      ":"30      ",2,12,220,0,0);
  end
  if(errors==0)$display("[PASS] dynamic mode/slot/cache/state/UF/fault/alpha/scaler/fit/fade/period/sign glyphs");
  if(HD)$display("[TB] tb_v3_video_dynamic_text_hd done comparisons=%0d errors=%0d",comparisons,errors);
  else $display("[TB] tb_v3_video_dynamic_text_base done comparisons=%0d errors=%0d",comparisons,errors);
  $finish;
 end
 initial begin #50000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
module tb_v3_video_dynamic_text_base;tb_v3_video_dynamic_text_model #(.HD(0)) model();endmodule
module tb_v3_video_dynamic_text_hd;tb_v3_video_dynamic_text_model #(.HD(1)) model();endmodule
