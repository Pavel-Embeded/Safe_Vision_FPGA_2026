`timescale 1ns/1ps
module tb_v3_normalizer_miter203;
 reg clk=0,rst=0,valid=0,eof=0;always #5 clk=~clk;reg[7:0] data=0;
 reg[31:0] file_size=0;wire ready,checked,bad;wire[7:0] ec,ed,pdata;wire pv,pr,sof,peof;
 wire[15:0] w,h;wire td;wire[15:0] pixel;wire ov,done,error;reg outr=1;wire[9:0] ox,oy;
 integer errors=0,comparisons=0,pixels=0,iw,ih,sgn,sz,stride,p,xx,yy,dh,dw,l,t,sx,sy;
 integer last_done=0,byte_count=0;reg[15:0] want,held;reg stalled=0;
 bmp_parser #(.VARIABLE_SIZE(1)) parser(.clk(clk),.rst_n(rst),.data(data),.valid(valid),.ready(ready),.eof(eof),.file_size(file_size),
  .check_done(checked),.check_error(bad),.err_code(ec),.err_detail(ed),.width(w),.height(h),.top_down(td),
  .out_data(pdata),.out_valid(pv),.out_ready(pr),.out_sof(sof),.out_eof(peof));
 v3_bmp_normalizer dut(.clk(clk),.rst_n(rst),.din(pdata),.din_valid(pv),.din_ready(pr),.din_sof(sof),.din_eof(peof),
  .width(w),.height(h),.top_down(td),.pixel(pixel),.pixel_valid(ov),.pixel_ready(outr),.x(ox),.y(oy),.done(done),.error(error));
 wire rr,rv,rdone,rerror,rsof,reof;wire[15:0] rp;wire[9:0] rx,ry;wire[7:0] rec,red;
 v3_bmp_normalizer199_reference ref_dut(.clk(clk),.rst_n(rst),.din(pdata),.din_valid(pv),.din_ready(rr),.din_sof(sof),.din_eof(peof),
  .width(w),.height(h),.top_down(td),.pixel(rp),.pixel_valid(rv),.pixel_ready(outr),.x(rx),.y(ry),
  .done(rdone),.error(rerror),.img_sof(rsof),.img_eof(reof),.err_code(rec),.err_detail(red));
 integer public_cycles=0;
 always@(negedge clk)begin #0.001;
  if(rst)begin public_cycles = public_cycles + 1;
   if({pr,pixel,ov,ox,oy,done,error,dut.img_sof,dut.img_eof,dut.err_code,dut.err_detail}!==
      {rr,rp,rv,rx,ry,rdone,rerror,rsof,reof,rec,red})begin
    errors = errors + 1;if(errors<8)$display("[FAIL] original/optimized complete public-pin cycle differs state%0d/%0d",dut.state,ref_dut.state);
   end
  end
 end
 function[7:0] colour(input integer x,y,c);begin begin case(c)0:colour=(x*17+y*5+7)%256;1:colour=(x*3+y*29+31)%256;default:colour=(x*11+y*7+53)%256;endcase end  end endfunction
 function[7:0] file_byte(input integer n);integer z,row,col,c,hh;begin begin
  hh=sgn ? -ih:ih;file_byte=0;
  if(n<54)case(n)
   0:file_byte="B";1:file_byte="M";
   2,3,4,5:file_byte=(sz>>((n-2)*8))&255;
   10:file_byte=54;14:file_byte=40;
   18,19,20,21:file_byte=(iw>>((n-18)*8))&255;
   22,23,24,25:file_byte=(hh>>((n-22)*8))&255;
   26:file_byte=1;28:file_byte=24;default:file_byte=0;
  endcase
  else if(n<54+stride*ih)begin z=n-54;row=z/stride;col=z%stride;
   if(col<iw*3)begin c=col%3;file_byte=colour(col/3,sgn ? row:ih-1-row,c);end else file_byte=8'had;
  end else file_byte=8'hfa;
 end  end endfunction
 always@(negedge clk)if(rst)outr=($time/10)%11!=2&&($time/10)%17!=3;
 always@(posedge clk)if(rst)begin
  if(done)last_done=1;
  if(error||bad)begin errors = errors + 1;if(errors<5)$display("[FAIL] valid image rejected w%0d h%0d state=%0d ec=%h/%h",iw,ih,dut.state,ec,ed);end
  if(stalled)begin comparisons = comparisons + 1;if(!ov||pixel!==held)begin errors = errors + 1;if(errors<5)$display("[FAIL] output changed under backpressure");end end
  stalled=ov&&!outr;held=pixel;
  if(ov&&outr)begin
   xx=pixels%640;yy=sgn ? pixels/640:479-pixels/640;
   if(iw*480>=ih*640)begin dw=640;dh=ih*640/iw;if(dh==0)dh=1;end
   else begin dh=480;dw=iw*480/ih;if(dw==0)dw=1;end
   l=(640-dw)/2;t=(480-dh)/2;want=0;
   if(xx>=l&&xx<l+dw&&yy>=t&&yy<t+dh)begin
    sx=(xx-l)*iw/dw;sy=(yy-t)*ih/dh;
    want={v_cast_u5(colour(sx,sy,2)>>3),v_cast_u6(colour(sx,sy,1)>>2),v_cast_u5(colour(sx,sy,0)>>3)};
   end
   comparisons = comparisons + (3);
   if(pixel!==want||ox!==v_cast_s10(xx)||oy!==v_cast_s10(yy))begin errors = errors + 1;if(errors<9)$display("[FAIL] %0dx%0d td%0d pixel%0d xy%0d,%0d actual%h expected%h",iw,ih,sgn,pixels,ox,oy,pixel,want);end
   pixels = pixels + 1;
  end
 end
 task image(input integer wi,he,neg);begin begin
  @(negedge clk);rst=0;valid=0;eof=0;repeat(5)@(negedge clk);iw=wi;ih=he;sgn=neg;stride=((iw*3+3)/4)*4;sz=54+stride*ih+7;file_size=sz;pixels=0;last_done=0;stalled=0;rst=1;
  for(p=0;p<sz;p = p + 1)begin
   @(negedge clk);data=file_byte(p);valid=1;eof=p==sz-1;
   begin begin @(posedge clk); end while(!ready)begin @(posedge clk); end end 
   @(negedge clk);valid=0;eof=0;
   if(p%257==5)repeat(3)@(negedge clk);
  end
  wait(last_done);repeat(5)@(negedge clk);comparisons = comparisons + 1;
  if(pixels!=307200)begin errors = errors + 1;$display("[FAIL] image output size%0d",pixels);end
  $display("[CASE] %0dx%0d topdown%0d output%0d errors=%0d",iw,ih,sgn,pixels,errors);
 end  end endtask
 initial begin
  image(1,1,0);image(1,1,1);image(3,2,0);image(3,2,1);image(319,241,0);image(319,241,1);
  image(641,479,0);image(641,479,1);image(640,480,0);image(640,480,1);
  image(800,600,0);image(1280,720,1);image(1920,1080,0);image(1920,1,1);image(1,1080,0);
  if(!errors)$display("[PASS] complete frames vs independent rational reference,24bit,padding,both orientations,letterbox,up/downscale,backpressure,trailing bytes");
  comparisons=comparisons+public_cycles;
  $display("[TB] tb_v3_normalizer_miter203 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000000;$display("[FAIL] multires watchdog errors=1");$finish;end

function [4:0] v_cast_u5; input [4:0] value; begin begin v_cast_u5=value; end  end endfunction
function [5:0] v_cast_u6; input [5:0] value; begin begin v_cast_u6=value; end  end endfunction
function signed [9:0] v_cast_s10; input signed [9:0] value; begin begin v_cast_s10=value; end  end endfunction
endmodule
