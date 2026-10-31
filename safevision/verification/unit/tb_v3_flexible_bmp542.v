`timescale 1ns/1ps
module tb_v3_flexible_bmp542;
 reg clk=0,rst_n=0;always #5 clk=~clk;reg[7:0] data=0;reg valid=0,eof=0;wire ready;
 reg[31:0] file_size=0;wire cd,ce,td;wire[15:0] width,height;wire[7:0] bpp,ec,ed,bd;
 wire bv,br,bs,be;wire[15:0] pixel;wire pv,ps,pe,done,error;wire[9:0] x,y;reg pr=0;
 bmp_parser #(.VARIABLE_SIZE(1),.FLEX_PIXELS(1)) parser(.clk(clk),.rst_n(rst_n),.data(data),.valid(valid),.ready(ready),.eof(eof),.file_size(file_size),.check_done(cd),.check_error(ce),.err_code(),.err_detail(),.width(width),.height(height),.top_down(td),.bpp(bpp),.compression(),.pixel_off(),.file_size_o(),.dbg_state(),.out_data(bd),.out_valid(bv),.out_ready(br),.out_sof(bs),.out_eof(be));
 v3_bmp_normalizer #(.FLEX_PIXELS(1)) normal(.clk(clk),.rst_n(rst_n),.din(bd),.din_valid(bv),.din_ready(br),.din_sof(bs),.din_eof(be),.width(width),.height(height),.bpp(bpp),.top_down(td),.pixel(pixel),.pixel_valid(pv),.pixel_ready(pr),.x(x),.y(y),.img_sof(ps),.img_eof(pe),.done(done),.error(error),.err_code(ec),.err_detail(ed),.dbg_state());
 reg[15:0] expected[0:2457599];reg[63:0] cases[0:7];
 integer errors=0,comparisons=0,c=0,pos=0,pixels=0,cycle=0,w,h,top,bits,offset,stride,full_height;
 reg holding=0;reg[37:0] held;
 task check(input  ok,input [4095:0] message);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s case%0d pos%0d xy%0d,%0d",message,c,pos,x,y);end   end endtask
 function[7:0] byte_at;input integer n;integer u,row,col,channel,sx,sy,value;begin
  byte_at=0;
  if(n>=offset)begin
   u=n-offset;row=u/stride;col=u%stride;channel=col%(bits/8);sx=col/(bits/8);sy=top ? row:h-1-row;
   if(sx>=w)byte_at=8'hb7;
   else case(channel)
    0:byte_at=(sx*13+sy*5+101)&255;
    1:byte_at=(sx*7+sy*11+23)&255;
    2:byte_at=(sx*17+sy*3)&255;
    default:byte_at=8'h1d;
   endcase
  end else if(n>=54)byte_at=8'haa;
  else case(n)
   0:byte_at="B";1:byte_at="M";
   2,3,4,5:byte_at=file_size>>((n-2)*8);
   10,11,12,13:byte_at=offset>>((n-10)*8);
   14:byte_at=40;
   18,19,20,21:byte_at=w>>((n-18)*8);
   22,23,24,25:byte_at=full_height>>((n-22)*8);
   26:byte_at=1;28:byte_at=bits;
   default:byte_at=0;
  endcase
   end endfunction
 always @(negedge clk)begin cycle=cycle+1;pr=cycle%19>=5;end
 always @(posedge clk)if(rst_n)begin
  if(holding)check(pv&&{pixel,x,y,ps,pe}===held,"complete output word and coordinates stable under backpressure");
  holding<=pv&&!pr;held<={pixel,x,y,ps,pe};
  if(pv&&pr)begin
   check(x<640&&y<480&&pixel===expected[c*307200+y*640+x],"every normalized pixel vs independent source-coordinate oracle");
   check(ps==(pixels==0)&&pe==(pixels==307199),"exact frame boundary tags");pixels=pixels+1;
  end
 end else holding<=0;
 initial begin
  $readmemh("bmp542_expected.mem",expected);$readmemh("bmp542_cases.mem",cases);
  for(c=0;c<8;c=c+1)begin
   rst_n=0;valid=0;eof=0;repeat(5)@(negedge clk);
   w=cases[c][63:48];h=cases[c][47:32];top=cases[c][24];bits=cases[c][23:16];offset=cases[c][15:0];
   full_height=top ? -h:h;stride=((w*(bits/8)+3)/4)*4;file_size=offset+stride*h;pixels=0;pos=0;rst_n=1;
   while(pos<file_size)begin
    @(negedge clk);data=byte_at(pos);valid=cycle%11!=0;eof=pos==file_size-1;
    @(posedge clk);if(valid&&ready)pos=pos+1;
   end
   @(negedge clk);valid=0;eof=0;wait(done);@(negedge clk);
   check(!ce&&!error&&pixels==307200,"complete full image normal completion, including4K and portrait");
   $display("[PASS] BMP542 case%0d %0dx%0d %0dbpp top%0d full_pixels=%0d",c,w,h,bits,top,pixels);
  end
  $display("[TB] tb_v3_flexible_bmp542 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #(64'd5000000000);$display("[FAIL] timeout errors=1");$finish;end
endmodule
