`timescale 1ns/1ps
module paired_rows_case275 #(parameter PHASE=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg mem=0,wr=0,pix=0,rst=0;always #10 mem=~mem;always #7 pix=~pix;
 initial begin #(PHASE);forever #5 wr=~wr;end
 reg valid=0,cv=0,prepare=0;reg[2:0] bank=0;reg[8:0] column=0;reg[31:0] data=0;
 reg[9:0]sx=0,sy=0,prepared=0;reg[1:0]mode=0;
 wire[130:0]actual,expected;
 v3_packed_row_store #(.HANDBOOK_PROFILE(1)) dut(mem,rst,wr,rst,pix,rst,valid,bank,column,data,actual[128],actual[129],cv,sx,sy,mode,prepare,prepared,actual[127:112],actual[111:96],actual[95:80],actual[79:64],actual[63:48],actual[47:32],actual[31:16],actual[15:0],actual[130]);
 v3_packed_row_store216_reference #(.HANDBOOK_PROFILE(1)) oracle(mem,rst,wr,rst,pix,rst,valid,bank,column,data,expected[128],expected[129],cv,sx,sy,mode,prepare,prepared,expected[127:112],expected[111:96],expected[95:80],expected[79:64],expected[63:48],expected[47:32],expected[31:16],expected[15:0],expected[130]);
 reg check=0;integer b,c,m,r,x;reg[2:0] reset_settled=0;


 always @(posedge pix)if(!rst)reset_settled<=0;else reset_settled<={reset_settled[1:0],1'b1};

 always@(negedge pix)if(check)begin comparisons++;
  if(actual[130:128]!==expected[130:128] || ((&reset_settled)&&rst&&actual[127:0]!==expected[127:0]))begin errors++;if(errors<8)$display("[FAIL] mux public edge phase=%0d mode=%0d sx=%0d sy=%0d got=%h want=%h",PHASE,mode,sx,sy,actual,expected);end
  if(rst&&(&reset_settled)&&$isunknown(actual[127:0]))begin errors++;if(errors<8)$display("[FAIL] unknown after complete memory initialization");end
 end
 initial begin
  #100;rst=1;
  for(b=0;b<8;b++)begin
   for(c=0;c<320;c++)begin @(negedge mem);valid=1;bank=b;column=c;data=32'((b*32'h10203041)^(c*32'h9e3779b9));end
   @(negedge mem);valid=0;repeat(8)@(negedge mem);
  end
  @(posedge pix);#1;check=1;


  for(m=0;m<4;m++)begin mode=m;
   for(r=0;r<1024;r++)begin
    @(posedge pix);#1;cv=0;prepare=1;prepared=r;repeat(8)begin @(posedge pix);#1;end
    prepare=0;cv=1;sy=r;
    for(x=0;x<1024;x++)begin sx=x;@(posedge pix);#1;end
   end
  end
  cv=0;repeat(8)begin @(posedge pix);#1;end
  rst=0;repeat(8)begin @(posedge pix);#1;end
  rst=1;repeat(8)begin @(posedge pix);#1;end
  if(!errors)$display("[PASS] paired physical row banks vs frozen216, all controls including reset and all valid-preload pixel edges, all4*1024*1024 coordinates, phase=%0d",PHASE);
  done=1;
 end
endmodule
module tb_v3_paired_rows_miter275;
 wire d0,d1;wire integer e0,e1,c0,c1;
 paired_rows_case275 #(.PHASE(0)) a(d0,e0,c0);paired_rows_case275 #(.PHASE(5)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_paired_rows_miter275 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
 initial begin #100000000;$display("[FAIL] miter watchdog");$display("[TB] tb_v3_paired_rows_miter275 done errors=1 comparisons=0");$finish;end
endmodule
