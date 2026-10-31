`timescale 1ns/1ps
`include "safevision_defs.vh"
module tb_v3_flexible_bmp_bounds551;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,valid=0,eof=0;reg[7:0] data=0;reg[31:0] file_size=0;
 wire ready,cd,ce;wire[7:0] ec,ed;wire[15:0] width,height;wire td;wire[7:0] bpp;
 wire[7:0] out_data;wire out_valid,out_sof,out_eof;
 bmp_parser #(.VARIABLE_SIZE(1),.FLEX_PIXELS(1)) parser(.clk(clk),.rst_n(rst_n),.data(data),.valid(valid),.ready(ready),.eof(eof),.file_size(file_size),.check_done(cd),.check_error(ce),.err_code(ec),.err_detail(ed),.width(width),.height(height),.top_down(td),.bpp(bpp),.compression(),.pixel_off(),.file_size_o(),.dbg_state(),.out_data(out_data),.out_valid(out_valid),.out_ready(1'b1),.out_sof(out_sof),.out_eof(out_eof));
 reg nrst_n=0,nvalid=0,nsof=0,neof=0;reg[7:0] ndata=0,nbpp=24;reg[15:0] nw=2,nh=-16'd1000;reg ntd=1;
 wire nready,npv,ndone,nerror;wire[7:0] nec,ned;wire[15:0] npixel;wire[9:0] nx,ny;
 v3_bmp_normalizer #(.FLEX_PIXELS(1)) norm(.clk(clk),.rst_n(nrst_n),.din(ndata),.din_valid(nvalid),.din_ready(nready),.din_sof(nsof),.din_eof(neof),.width(nw),.height(nh),.bpp(nbpp),.top_down(ntd),.pixel(npixel),.pixel_valid(npv),.pixel_ready(1'b1),.x(nx),.y(ny),.img_sof(),.img_eof(),.done(ndone),.error(nerror),.err_code(nec),.err_detail(ned),.dbg_state());
 reg[7:0] headers[0:2051];reg[47:0] cases[0:37];
 integer errors=0,comparisons=0,c=0,pos=0,got_checks=0,forwarded=0;
 integer pcount=0,ncount=0,stride=0,limit=0,rows=0,cycle=0;reg saw_done=0,saw_error=0;
 task check(input  ok,input [4095:0] message);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s case%0d pos%0d",message,c,pos);end   end endtask
 always @(posedge clk)begin
  if(rst_n&&cd)got_checks=got_checks+1;
  if(rst_n&&out_valid)forwarded=forwarded+1;
  if(nrst_n&&npv)pcount=pcount+1;
  if(nrst_n&&ndone)begin saw_done=1;saw_error=nerror;end
 end
 task normal_tail(input integer bits,input integer delivered_rows,input integer omit_bytes,input  want_error);begin
  want_error = (want_error === 1'b1); nrst_n=0;nvalid=0;nsof=0;neof=0;repeat(4)@(negedge clk);
  nw=2;nh=-16'd1000;ntd=1;nbpp=bits;stride=bits==24 ? 8:8;limit=delivered_rows*stride-omit_bytes;
  pcount=0;ncount=0;saw_done=0;saw_error=0;nrst_n=1;
  while(ncount<limit && !saw_done)begin
   @(negedge clk);nvalid=cycle%7!=0;nsof=ncount==0;neof=ncount==limit-1;ndata=(ncount*17+3)&255;cycle=cycle+1;
   @(posedge clk);if(nvalid&&nready)ncount=ncount+1;
  end
  @(negedge clk);nvalid=0;nsof=0;neof=0;
  repeat(10)@(negedge clk);
  check(saw_done,"normalizer terminates a complete or early-EOF stream");
  check(saw_error==want_error,"tail completeness distinguishes valid file and premature EOF");
  if(want_error)check(nec==`ERR_MEDIA_INVALID&&ned==`DET_BMP_TRUNC,"early-EOF has exact truncation diagnostics");
  else check(pcount==307200,"valid image emits one entire canonical frame");
  $display("[PASS] BOUNDS551 tail %0dbpp rows%0d omit%0d expected_error%0d output_pixels%0d",bits,delivered_rows,omit_bytes,want_error,pcount);
   end endtask
 initial begin
  $readmemh("headers.mem",headers);$readmemh("cases.mem",cases);
  for(c=0;c<38;c=c+1)begin
   rst_n=0;valid=0;eof=0;repeat(4)@(negedge clk);file_size=cases[c][47:16];got_checks=0;forwarded=0;rst_n=1;
   for(pos=0;pos<cases[c][15:8];pos=pos+1)begin
    @(negedge clk);data=headers[c*54+pos];valid=1;eof=cases[c][15:8]<54&&pos==cases[c][15:8]-1;
    @(posedge clk);check(ready,"header accepts every supplied byte");
   end
   @(negedge clk);valid=0;eof=0;repeat(4)@(negedge clk);
   check(got_checks==1,"one header publication");
   check(ce==(cases[c][7:0]!=0),"header result vs independent integer oracle");
   check(ed==cases[c][7:0],"precise malformed-header diagnostic");
   check(forwarded==0,"header bytes never escape as pixels");
   $display("[PASS] BOUNDS551 header case%0d detail%02x",c,ed);
  end
  rst_n=0;
  normal_tail(24,1000,0,0);normal_tail(32,1000,0,0);
  normal_tail(24,999,0,1);normal_tail(32,999,0,1);
  normal_tail(24,1000,1,1);normal_tail(32,1000,1,1);
  normal_tail(24,998,0,1);normal_tail(32,998,0,1);
  $display("[TB] tb_v3_flexible_bmp_bounds551 done, errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000000;$display("[FAIL] timeout errors=1");$finish;end
endmodule
