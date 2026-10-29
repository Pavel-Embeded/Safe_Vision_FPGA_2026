`timescale 1ns/1ps
module tb_v3_bmp_header199;
 reg clk=0,rst=0,valid=0,eof=0;reg[7:0] data=0;always #5 clk=~clk;
 reg[31:0] size=921654;wire ready,checked,bad;wire[7:0] detail;wire[15:0] width,height;wire td;
 bmp_parser #(.VARIABLE_SIZE(1)) dut(.clk(clk),.rst_n(rst),.data(data),.valid(valid),.ready(ready),.eof(eof),.file_size(size),
  .check_done(checked),.check_error(bad),.err_detail(detail),.width(width),.height(height),.top_down(td),.out_ready(1'b1));
 reg[7:0] header[0:53];integer errors=0,comparisons=0,i,c,w,h,sz;reg[7:0] expected;
 task le32(input integer off,input[31:0] n);begin for(integer k=0;k<4;k++)header[off+k]=n>>(8*k);end endtask
 task make(input integer wi,he);begin
  w=wi;h=he;sz=54+((wi*3+3)/4)*4*(he<0?-he:he);size=sz;
  for(i=0;i<54;i++)header[i]=0;header[0]="B";header[1]="M";header[26]=1;header[28]=24;
  le32(2,sz);le32(10,54);le32(14,40);le32(18,wi);le32(22,he);
 end endtask
 task run(input bit want_bad,input[7:0] code);begin
  rst=0;valid=0;repeat(4)@(negedge clk);rst=1;
  for(i=0;i<54;i++)begin @(negedge clk);data=header[i];valid=1;@(posedge clk);#1;
   if(i==53)begin comparisons+=2;if(!checked||bad!==want_bad||(want_bad&&detail!==code))begin errors++;$display("[FAIL] case%0d checked%b bad%b/%b detail%h/%h",c,checked,bad,want_bad,detail,code);end end
  end
  @(negedge clk);valid=0;
 end endtask
 initial begin
  for(c=0;c<14;c++)begin
   case(c/2)0:make(1,1);1:make(3,2);2:make(320,240);3:make(640,480);4:make(641,479);5:make(1280,720);default:make(1920,1080);endcase
   if(c%2)le32(22,-h);run(0,0);comparisons+=3;
   if(width!==16'(w)||height!==16'(c%2?-h:h)||td!==(c%2!=0))errors++;
  end
  for(c=0;c<19;c++)begin
   make(640,480);expected=8'h39;
   case(c)
    0:le32(18,0);1:le32(18,1921);2:le32(22,1081);3:le32(18,-1);4:le32(22,0);
    5:le32(18,32'h10000);6:le32(22,32'h101e0);
    7:begin header[28]=32;expected=8'h3a;end
    8:begin header[26]=2;expected=8'h3a;end
    9:begin le32(30,1);expected=8'h3a;end
    10:begin le32(14,39);expected=8'h38;end
    11:begin header[0]="X";expected=8'h37;end
    12:begin le32(10,53);expected=8'h3b;end
    13:begin le32(10,32'hfffffff0);expected=8'h3b;end
    14:begin le32(2,sz+1);expected=8'h3b;end
    15:begin le32(2,54);expected=8'h3b;end
    16:begin size=sz-1;expected=8'h3b;end
    17:begin le32(22,-1081);expected=8'h39;end
    18:begin le32(22,32'hffff01e0);expected=8'h39;end
   endcase
   run(1,expected);
  end
  if(!errors)$display("[PASS] legal geometry metadata and orientations;zero/negative/oversize/sign-extension rejection;BMP format,length and carry-safe overflow guards");
  $display("[TB] tb_v3_bmp_header199 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] BMP header watchdog errors=1");$finish;end
endmodule

