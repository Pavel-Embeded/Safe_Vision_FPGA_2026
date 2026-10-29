


module scaler_bilinear #(parameter RASTER_THIRDS=0)(input wire clk,rst_n,valid_in,bilinear,
 input wire [15:0] p00,p10,p01,p11,input wire [7:0] fx,fy,
 output reg [15:0] pixel,output reg valid_out);
 function[5:0] divide_third;
  input[7:0] n;reg[1:0] remainder;reg[7:0] quotient;integer k;
  begin begin remainder=0;quotient=0;
   for(k=7;k>=0;k=k-1)begin
    quotient[k]=remainder[1]|(remainder[0]&n[k]);
    remainder={(remainder[0]&~n[k])|(remainder[1]&n[k]),
      (~remainder[1]&~remainder[0]&n[k])|(remainder[1]&~n[k])};
   end
   divide_third=quotient[5:0];
  end
  end endfunction
 function[5:0] lerp;
  input[5:0] a,b;input[7:0] f;
  reg signed[6:0] delta;reg signed[15:0] product,numerator;
  reg[7:0] weighted;
  begin begin
   if(RASTER_THIRDS)begin


    weighted=f==85 ? {1'b0,a,1'b0}+{2'b0,b}+8'd1:
                           {2'b0,a}+{1'b0,b,1'b0}+8'd1;
    lerp=f==0 ? a:divide_third(weighted);
   end else begin
    delta=$signed({1'b0,b})-$signed({1'b0,a});
    product=delta*$signed({1'b0,f});
    numerator=$signed({2'b0,a,8'b0})+product+16'sd128;
    lerp=numerator[13:8];
   end
  end
  end endfunction
 reg[15:0] top,bottom,vertical,n1,n2;reg[7:0] y1;reg m1,m2,v1,v2;
 wire[5:0] tr=lerp({1'b0,p00[15:11]},{1'b0,p10[15:11]},fx);
 wire[5:0] tg=lerp(p00[10:5],p10[10:5],fx);
 wire[5:0] tb=lerp({1'b0,p00[4:0]},{1'b0,p10[4:0]},fx);
 wire[5:0] br=lerp({1'b0,p01[15:11]},{1'b0,p11[15:11]},fx);
 wire[5:0] bg=lerp(p01[10:5],p11[10:5],fx);
 wire[5:0] bb=lerp({1'b0,p01[4:0]},{1'b0,p11[4:0]},fx);
 wire[5:0] rr=lerp({1'b0,top[15:11]},{1'b0,bottom[15:11]},y1);
 wire[5:0] rg=lerp(top[10:5],bottom[10:5],y1);
 wire[5:0] rb=lerp({1'b0,top[4:0]},{1'b0,bottom[4:0]},y1);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin top<=0;bottom<=0;vertical<=0;y1<=0;n1<=0;n2<=0;
   m1<=0;m2<=0;v1<=0;v2<=0;pixel<=0;valid_out<=0;end
  else begin
   top<={tr[4:0],tg,tb[4:0]};bottom<={br[4:0],bg,bb[4:0]};
   y1<=fy;n1<=p00;m1<=bilinear;v1<=valid_in;
   vertical<={rr[4:0],rg,rb[4:0]};n2<=n1;m2<=m1;v2<=v1;
   pixel<=m2 ? vertical:n2;valid_out<=v2;
  end
 end
endmodule
