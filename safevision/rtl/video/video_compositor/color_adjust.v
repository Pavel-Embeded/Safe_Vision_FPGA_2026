

module color_adjust(input wire clk,rst_n,valid_in,input wire [15:0] pixel_in,
 input wire signed [8:0] brightness,input wire [7:0] contrast,
 output reg [15:0] pixel_out,output reg valid_out);
 reg signed [18:0] r,g,b;reg v;
 function [7:0] clamp;
  input signed [18:0] x;reg signed [18:0] y;
  begin y=x>>>7;if(y<0)clamp=0;else if(y>255)clamp=255;else clamp=y[7:0];end
 endfunction
 wire [7:0] cr=clamp(r),cg=clamp(g),cb=clamp(b);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin r<=0;g<=0;b<=0;v<=0;valid_out<=0;pixel_out<=0;end
  else begin
   r<=($signed({1'b0,pixel_in[15:11],pixel_in[15:13]})-19'sd128)*$signed({1'b0,contrast})+19'sd16384+($signed(brightness)<<<7);
   g<=($signed({1'b0,pixel_in[10:5],pixel_in[10:9]})-19'sd128)*$signed({1'b0,contrast})+19'sd16384+($signed(brightness)<<<7);
   b<=($signed({1'b0,pixel_in[4:0],pixel_in[4:2]})-19'sd128)*$signed({1'b0,contrast})+19'sd16384+($signed(brightness)<<<7);
   v<=valid_in;pixel_out<={cr[7:3],cg[7:2],cb[7:3]};valid_out<=v;
  end
 end
endmodule
