`timescale 1ns/1ps
module tb_v3_video_fraction_domain;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,de=0,fit=1;reg[11:0] x=0,y=0;
 wire hv,bv;wire[9:0] hx,hy,bx,by;wire[7:0] hf,hg,bf,bg;
 scaler_coords #(.HD(1)) hd(.clk(clk),.rst_n(rst),.de(de),.x(x),.y(y),.fit(fit),.scale_select(2'd0),.valid(hv),.sx(hx),.sy(hy),.fx(hf),.fy(hg));
 scaler_coords #(.HD(0)) base(.clk(clk),.rst_n(rst),.de(de),.x(x),.y(y),.fit(fit),.scale_select(2'd0),.valid(bv),.sx(bx),.sy(by),.fx(bf),.fy(bg));
 reg[36:0] eh0=0,eh1=0,eb0=0,eb1=0;integer a,b,errors=0,comparisons=0,pixels=0;
 function  legal_fraction(input[7:0] f);begin begin legal_fraction= ((f==0||f==85||f==170) === 1'b1);end  end endfunction
 always @(posedge clk)begin
  if(!rst)begin eh0=0;eh1=0;eb0=0;eb1=0;end
  else begin
   eh1=eh0;eb1=eb0;eh0=0;eb0=0;
   if(de&&x<640&&y<480)eb0={1'b1,v_cast_u10(x),v_cast_u10(y),8'd0,8'd0};
   if(de&&fit&&x>=160&&x<1120&&y<720)begin
    a=x-160;b=y;eh0={1'b1,v_cast_s10(a*2/3),v_cast_s10(b*2/3),v_cast_s8((a*2%3)*256/3),v_cast_s8((b*2%3)*256/3)};
   end
   if(de&&!fit&&x>=320&&x<960&&y>=120&&y<600)eh0={1'b1,v_cast_u10(x-320),v_cast_u10(y-120),8'd0,8'd0};
   #1;
   if(!legal_fraction(hf)||!legal_fraction(hg)||bf!==0||bg!==0)begin
    errors=errors+1;if(errors<8)$display("[FAIL] fraction domain including blanking");
   end
   if(hv!==eh1[36]||bv!==eb1[36])begin errors=errors+1;if(errors<8)$display("[FAIL] coordinate valid latency");end
   if(hv)begin
    pixels=pixels+1;
    if({hv,hx,hy,hf,hg}!==eh1)begin errors=errors+1;if(errors<8)$display("[FAIL] HD independent coordinate/fraction");end
   end
   if(bv&&{bv,bx,by,bf,bg}!==eb1)begin errors=errors+1;if(errors<8)$display("[FAIL] BASE independent coordinate/fraction");end
   comparisons=comparisons+1;
  end
 end
 task raster(input integer ha,va,ht,vt,input  mode);
  integer row,col;begin begin mode = (mode === 1'b1); fit=mode;
   for(row=0;row<vt;row=row+1)for(col=0;col<ht;col=col+1)begin
    x=col;y=row;de=col<ha&&row<va;@(negedge clk);
   end
  end
  end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;
  raster(640,480,800,525,1);raster(1280,720,1650,750,1);raster(1280,720,1650,750,0);
  de=0;repeat(4)@(negedge clk);
  if(errors==0)$display("[PASS] complete BASE and HD FIT/1:1 scans, exact fractions and valid/blanking domains");
  $display("[TB] tb_v3_video_fraction_domain done comparisons=%0d pixels=%0d errors=%0d",comparisons,pixels,errors);$finish;
 end
 initial begin #100000000;$display("[FAIL] timeout errors=1");$finish;end

function signed [7:0] v_cast_s8; input signed [7:0] value; begin begin v_cast_s8=value; end  end endfunction
function [9:0] v_cast_u10; input [9:0] value; begin begin v_cast_u10=value; end  end endfunction
function signed [9:0] v_cast_s10; input signed [9:0] value; begin begin v_cast_s10=value; end  end endfunction
endmodule
