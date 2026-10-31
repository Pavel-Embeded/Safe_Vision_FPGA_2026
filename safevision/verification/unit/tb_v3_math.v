`timescale 1ns/1ps
module tb_v3_math;
 reg clk=0;always #5 clk=~clk;reg rst=0,v=0;reg [15:0] f,b;reg [7:0] a;
 wire [15:0] q;wire qv;
 alpha_blend ab(clk,rst,v,f,b,a,q,qv);
 reg [55:0] vectors[0:3327];reg [95:0] scales[0:2047];
 reg [15:0] p00,p10,p01,p11;reg [7:0] fx,fy;reg sv=0;
 wire [15:0] sq;wire sqv;
 scaler_bilinear si(clk,rst,sv,1'b1,p00,p10,p01,p11,fx,fy,sq,sqv);
 reg [15:0] e0,e1,e2,se0,se1,se2;reg ev0=0,ev1=0,ev2=0;
 reg sev0=0,sev1=0,sev2=0;integer i,errors=0,checks=0;
 function integer distance;input [15:0] x,y;integer r,g,b;begin
  r=$signed({1'b0,x[15:11]})-$signed({1'b0,y[15:11]});if(r<0)r=-r;
  g=$signed({1'b0,x[10:5]})-$signed({1'b0,y[10:5]});if(g<0)g=-g;
  b=$signed({1'b0,x[4:0]})-$signed({1'b0,y[4:0]});if(b<0)b=-b;
  distance=(r>g) ? r:g;if(b>distance)distance=b;  end endfunction
 always @(posedge clk)begin
  e2=e1;e1=e0;e0=vectors[i][15:0];ev2=ev1;ev1=ev0;ev0=v;
  se2=se1;se1=se0;se0=scales[i<2048 ? i:0][15:0];sev2=sev1;sev1=sev0;sev0=sv;
  #1;
  if(rst && qv)begin checks=checks+1;if(q!==e2)begin errors=errors+1;$display("[FAIL] alpha i=%0d q=%h expected=%h",i,q,e2);end end
  if(rst && sqv)begin checks=checks+1;if(distance(sq,se2)>1)begin errors=errors+1;$display("[FAIL] scaler q=%h expected=%h",sq,se2);end end
 end
 initial begin
  $readmemh("alpha_golden.mem",vectors);$readmemh("scaler_golden.mem",scales);i=0;
  repeat(3)@(negedge clk);rst=1;
  for(i=0;i<3328;i=i+1)begin
   v=1;{a,f,b}=vectors[i][55:16];sv=(i<2048);
   if(sv){p00,p10,p01,p11,fx,fy}=scales[i][95:16];
   @(negedge clk);
  end
  v=0;sv=0;repeat(4)@(negedge clk);
  if(checks!=5376)begin errors=errors+1;$display("[FAIL] coverage count %d",checks);end
  if(errors==0)$display("[PASS] 3328 alpha / 2048 independent bilinear vectors");
  $display("PASS tb_v3_math errors=%0d",errors);$finish;
 end
endmodule
