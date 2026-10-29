`timescale 1ns/1ps
module emergency_graphics_case #(parameter integer HD=0)(output reg done);
 initial begin done = 0; end

 localparam W=HD ? 1280:640,H=HD ? 720:480;
 reg clk=0,rst=0,de=0,fs=0,active=0;reg [11:0] x=0,y=0;
 reg [1:0] dir=0,level=0;wire [23:0] rgb;wire valid;
 always #5 clk=~clk;
 emergency_graphics #(.HD(HD),.FLASH_FRAMES(3),.FONT_FILE("font8x16.mem")) dut(
  .clk(clk),.rst_n(rst),.de(de),.frame_start(fs),.x(x),.y(y),
  .active(active),.direction(dir),.warning_level(level),.rgb(rgb),.valid(valid));
 reg [7:0] font[0:4095];initial $readmemh("font8x16.mem",font);
 integer flash_count=0;reg on=1;
 reg [23:0] golden[0:3];reg gv[0:3];integer checks=0,lit=0,i;
 function automatic [23:0] reference(input integer xx,yy,dd,ll,input  blink);
  integer z,dy,code,column,row;reg body,border_hit,dot;reg [23:0] fg,bg;
  begin begin
   blink = (blink === 1'b1); dy=yy>H/2 ? yy-H/2:H/2-yy;
   body= ((0) === 1'b1);
   if(dd==0||dd>=2)begin
    z=xx-(W/2-96);if(z>=0&&z<=64&&2*dy<=z)body= ((1) === 1'b1);
    if(dd==0&&xx>=W/2-32&&xx<=W/2+96&&dy<=12)body= ((1) === 1'b1);
   end
   if(dd==1||dd>=2)begin
    z=W/2+96-xx;if(z>=0&&z<=64&&2*dy<=z)body= ((1) === 1'b1);
    if(dd==1&&xx>=W/2-96&&xx<=W/2+32&&dy<=12)body= ((1) === 1'b1);
   end
   if(dd>=2&&xx>=W/2-32&&xx<=W/2+32&&dy<=12)body= ((1) === 1'b1);
   border_hit= ((xx<=3||xx>=W-4||yy<=3||yy>=H-4) === 1'b1);
   fg=(ll==0) ? 24'h00ff00:(ll==1) ? 24'hffff00:24'hff3030;
   bg=(ll<2) ? 24'h001008:24'h180000;
   dot= ((0) === 1'b1);
   if(xx>=W/2-16&&xx<W/2+16&&yy>=H/4&&yy<H/4+16)begin
    column=(xx-(W/2-16))/8;row=yy-H/4;
    case(column)0:code=69;1:code=88;2:code=73;3:code=84;default:code=32;endcase
    dot= ((font[code*16+row][7-((xx-(W/2-16))%8)]) === 1'b1);
   end
   reference=(dot||border_hit||(body&&blink)) ? fg:bg;
  end
  end endfunction
 integer period;
 always @(posedge clk or negedge rst)begin
  if(!rst)begin
   for(i=0;i<4;i=i+1)begin golden[i]=0;gv[i]=0;end
   flash_count=0;on=1;
  end else begin
   for(i=3;i>0;i=i-1)begin golden[i]=golden[i-1];gv[i]=gv[i-1];end
   gv[0]=active&&de;golden[0]=gv[0] ? reference(x,y,dir,level,on):0;
   if(!active||level==0)begin flash_count=0;on=1;end
   else if(fs)begin
    period=(level==1) ? 3:1;
    if(flash_count>=period-1)begin flash_count=0;on=!on;end
    else flash_count=flash_count+1;
   end
   #0.1;
   if(valid!==gv[3]||rgb!==golden[3])begin $display("[FAIL] graphics HD=%0d x=%0d y=%0d rgb=%h expected=%h",HD,x,y,rgb,golden[3]); $finish; end 
   checks=checks+1;if(valid&&rgb!=0)lit=lit+1;
  end
 end
 integer f,xx,yy;
 initial begin
  #33;rst=1;repeat(5)@(negedge clk);
  for(f=0;f<5;f=f+1)begin
   @(negedge clk);de=0;fs=1;active=(f!=0);dir=f-1;level=f%4;
   @(negedge clk);fs=0;
   for(yy=0;yy<H;yy=yy+1)begin
    for(xx=0;xx<W;xx=xx+1)begin
     @(negedge clk);de=1;x=xx;y=yy;level=((yy/30)+f)%4;
    end
    @(negedge clk);de=0;
    @(negedge clk);
   end
  end
  @(negedge clk);de=0;active=0;repeat(8)@(negedge clk);
  if(lit!=4*W*H)begin $display("[FAIL] graphics did not cover complete emergency DE"); $finish; end 
  $display("PASS emergency graphics HD=%0d checks=%0d active_pixels=%0d BRAM font/4 directions/4 levels/blank/latency4",HD,checks,lit);done=1;
 end
endmodule
module tb_emergency_graphics;
 wire [1:0] done;
 emergency_graphics_case #(.HD(0)) a(done[0]);emergency_graphics_case #(.HD(1)) b(done[1]);
 initial begin wait(&done);$display("PASS tb_emergency_graphics");$finish;end
 initial begin #100000000;begin $display("[FAIL] graphics watchdog"); $finish; end end
endmodule
