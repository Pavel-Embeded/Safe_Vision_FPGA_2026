`timescale 1ns/1ps
module tb_v3_bmp_bounds;
 reg clk=0,rst=0,valid=0,eof=0;always #5 clk=~clk;
 reg[7:0] data=0;reg[31:0] file_size=0;wire ready,checked,bad,out_valid;
 wire[7:0] code,detail;
 bmp_parser dut(.clk(clk),.rst_n(rst),.data(data),.valid(valid),.ready(ready),.eof(eof),.file_size(file_size),
 .check_done(checked),.check_error(bad),.err_code(code),.err_detail(detail),.width(),.height(),.top_down(),
 .bpp(),.compression(),.pixel_off(),.file_size_o(),.dbg_state(),.out_data(),.out_valid(out_valid),.out_ready(1'b1),.out_sof(),.out_eof());
 reg[7:0] header[0:59];integer errors=0,comparisons=0,seen=0,output_bytes=0,i,j;
 reg observed_bad;reg[31:0] seed=32'h917b2ac5,offset,length;reg expected;
 always @(posedge clk)if(rst)begin
  if(checked)begin observed_bad=bad;seen=seen+1;end
  if(out_valid)output_bytes=output_bytes+1;
 end
 task put32(input integer addr,input[31:0] value);begin
  for(integer k=0;k<4;k=k+1)header[addr+k]=value[k*8+:8];
 end endtask
 task check(input bit condition,input string label);begin
  comparisons++;if(!condition)begin errors++;if(errors<6)$display("[FAIL] %s offset=%h file_size=%h got_bad=%b expected_bad=%b",label,offset,length,observed_bad,!expected);end
 end endtask
 task run_case(input[31:0] off,sz);begin
  offset=off;length=sz;file_size=sz;
  expected=off>=54&&({32'd0,off}+64'd921600)<={32'd0,sz};
  @(negedge clk);rst=0;valid=0;eof=0;repeat(3)@(negedge clk);
  for(i=0;i<60;i=i+1)header[i]=0;
  header[0]="B";header[1]="M";put32(2,sz);put32(10,off);put32(14,40);put32(18,640);put32(22,480);
  header[26]=1;header[28]=24;seen=0;output_bytes=0;observed_bad=1'bx;rst=1;
  for(i=0;i<60;i=i+1)begin
   while(!ready)@(negedge clk);
   data=header[i];valid=1;eof=i==59;@(negedge clk);valid=0;eof=0;
  end
  repeat(5)@(negedge clk);
  check(seen==1,"header produces exactly one validation event");
  check(observed_bad===!expected,"32bit file fields checked against independent 64bit extent oracle");
  if(!expected)check(output_bytes==0,"invalid wrapped or short extent publishes no bytes");
 end endtask
 initial begin
  run_case(54,921654);run_case(54,921653);run_case(53,921654);
  run_case(32'hfffffff0,921654);run_case(32'hffffffff,32'hffffffff);
  run_case(32'hfff1efff,32'hffffffff);run_case(32'hfff1f000,32'hffffffff);
  run_case(1000,922600);run_case(54,0);
  for(j=0;j<256;j=j+1)begin
   seed=seed*32'd1664525+32'd1013904223;offset=seed;
   seed=seed*32'd1664525+32'd1013904223;length=seed;
   run_case(offset,length);
  end
  if(!errors)$display("[PASS] BMP extent boundaries, overflow rejection and zero-byte bad-header publication");
  $display("[TB] tb_v3_bmp_bounds done comparisons=%0d errors=%0d",comparisons,errors);
  if(!errors)$display("PASS tb_v3_bmp_bounds");$finish;
 end
 initial begin #10000000;$display("[FAIL] BMP extent timeout errors=1");$finish;end
endmodule
