// Exact fractions0/85/170, RGB565, nearest/bilinear, latency THREE.
// Retiming: input capture -> horizontal -> vertical/output. The previous
// horizontal -> vertical -> output organization exposed ERAM clk2q plus
// interpolation on one edge. This preserves every output cycle and rounding.
module v3_scaler_bilinear_thirds(input wire clk,rst_n,valid_in,bilinear,
 input wire[15:0] p00,p10,p01,p11,input wire[7:0] fx,fy,
 output reg[15:0] pixel,output reg valid_out);
 function[5:0] lerp;
  input[5:0] a,b;input[7:0] f;
  reg[6:0] common_sum;reg[7:0] weighted;
  begin common_sum={1'b0,a}+{1'b0,b}+7'd0;
   weighted={1'b0,common_sum}+{2'b0,(f==85?a:b)};
   lerp=f==0?a:weighted/8'd3;end
 endfunction
 (* preserve="true" *) reg[15:0] a00,a10,a01,a11;
 reg[7:0] x1,y1,y2;reg m1,m2,v1,v2;
 reg[15:0] top,bottom,nearest;
 wire[5:0] tr=lerp({1'b0,a00[15:11]},{1'b0,a10[15:11]},x1);
 wire[5:0] tg=lerp(a00[10:5],a10[10:5],x1);
 wire[5:0] tb=lerp({1'b0,a00[4:0]},{1'b0,a10[4:0]},x1);
 wire[5:0] br=lerp({1'b0,a01[15:11]},{1'b0,a11[15:11]},x1);
 wire[5:0] bg=lerp(a01[10:5],a11[10:5],x1);
 wire[5:0] bb=lerp({1'b0,a01[4:0]},{1'b0,a11[4:0]},x1);
 wire[5:0] rr=lerp({1'b0,top[15:11]},{1'b0,bottom[15:11]},y2);
 wire[5:0] rg=lerp(top[10:5],bottom[10:5],y2);
 wire[5:0] rb=lerp({1'b0,top[4:0]},{1'b0,bottom[4:0]},y2);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin a00<=0;a10<=0;a01<=0;a11<=0;x1<=0;y1<=0;y2<=0;
   m1<=0;m2<=0;v1<=0;v2<=0;top<=0;bottom<=0;nearest<=0;pixel<=0;valid_out<=0;end
  else begin
   a00<=p00;a10<=p10;a01<=p01;a11<=p11;x1<=fx;y1<=fy;m1<=bilinear;v1<=valid_in;
   top<={tr[4:0],tg,tb[4:0]};bottom<={br[4:0],bg,bb[4:0]};
   y2<=y1;nearest<=a00;m2<=m1;v2<=v1;
   pixel<=m2?{rr[4:0],rg,rb[4:0]}:nearest;valid_out<=v2;
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(rst_n && !((fx==0||fx==85||fx==170)&&(fy==0||fy==85||fy==170)))
  $fatal(1,"production scaler fraction outside exact-thirds contract");
 // synthesis translate_on
endmodule
