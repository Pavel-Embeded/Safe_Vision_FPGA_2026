`timescale 1ns/1ps

module tb_v3_video_decimal;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg[11:0] x=0,y=0;reg[95:0] cfg=0;reg[7:0] gen=0;
 wire[15:0] osd,hud;wire[7:0] oa,ha;
 v3_status_layers #(.COMPACT_FONT_FILE("font8x16_compact.mem"),.TEXT_FILE("v3_status_text.mem")) dut(
  .pixel_clk(clk),.pixel_rst_n(rst),.raw_x(x),.raw_y(y),.raw_de(1'b1),.frame_start(1'b0),
  .cfg_data(cfg),.cache_valid(4'hf),.underflows(32'd0),.active_slot(2'd0),.generation(gen),
  .busy(1'b0),.safety_active(1'b0),.osd_rgb565(osd),.emergency_rgb565(),.hud_rgb565(hud),
  .safe_rgb565(),.osd_alpha(oa),.emergency_alpha(),.hud_alpha(ha));
 reg[7:0] font[0:4095];integer errors=0,comparisons=0,value,place,row,bitno;
 task digits(input integer number,first_column,top,input  hud_layer,selected);
  integer digit,character,xx,yy;reg dot;begin
   hud_layer = (hud_layer === 1'b1); selected = (selected === 1'b1); for(place=0;place<3;place=place+1)begin
    digit=place==0 ? number/100:place==1 ? (number/10)%10:number%10;character=48+digit;

    for(yy=0;yy<16;yy=yy+1)for(xx=0;xx<8;xx=xx+1)begin
     @(negedge clk);x=8+(first_column+place)*8+xx;y=top+yy;
     repeat(4)@(posedge clk);#1;dot= ((font[character*16+yy][7-xx]) === 1'b1);
     if(hud_layer ? (ha!==(dot ? 8'd224:8'd0)):
       (oa!==cfg[78:71]||osd!==(dot ? 16'hffff:selected ? 16'h05bf:16'h1086)))begin
      if(errors<6)$display("[FAIL] decimal=%0d digit=%0d xy=%0d,%0d hud=%b osd=%h ha=%0d",number,digit,x,y,hud_layer,osd,ha);
      errors=errors+1;
     end
     comparisons=comparisons+1;
    end
   end
    end endtask
 initial begin
  $readmemh("font8x16.mem",font);cfg[55]=1;cfg[78:71]=200;
  repeat(5)@(negedge clk);rst=1;
  for(value=0;value<512;value=value+1)begin
   @(negedge clk);gen=value;cfg[95:87]=value-256;cfg[86:79]=value;
   cfg[67:61]=value%101;
   repeat(70)@(negedge clk);
   digits(value%256,27,8,1,0);
   digits(value<256 ? 256-value:value-256,13,100,0,1);
   digits(value%256,12,120,0,0);
   digits(value%101,12,200,0,0);
  end
  if(errors==0)$display("[PASS] every 9-bit signed brightness, 8-bit generation/contrast and volume as complete rendered decimal glyphs");
  $display("[TB] tb_v3_video_decimal done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #50000000;$display("[FAIL] decimal test timeout errors=1");$finish;end
endmodule
