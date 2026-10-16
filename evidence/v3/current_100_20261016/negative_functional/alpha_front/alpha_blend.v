// RGB565, foreground alpha 0..255. Exact rounded division by 255.
// Fixed latency 3, throughput one pixel/clock. Difference form uses ONE signed
// multiplier/channel: B*255 + (F-B)*alpha equals F*alpha+B*(255-alpha).
module alpha_blend(
 input wire clk,rst_n,valid_in,
 input wire [15:0] front,back,input wire [7:0] alpha,
 output reg [15:0] pixel,output reg valid_out
);
 wire signed[5:0] dr=$signed({1'b0,front[15:11]})-$signed({1'b0,back[15:11]});
 wire signed[6:0] dg=$signed({1'b0,front[10:5]})-$signed({1'b0,back[10:5]});
 wire signed[5:0] db=$signed({1'b0,front[4:0]})-$signed({1'b0,back[4:0]});
 reg signed[13:0] pr,pb;reg signed[14:0] pg;
 reg[4:0] br,bb;reg[5:0] bg;
 reg[12:0] sr,sb;reg[13:0] sg;reg v1,v2;
 function[5:0] div255;
  input[13:0] x;reg[14:0] t;
  begin t={1'b0,x}+15'd1;div255=(t+(t>>8))>>8;end
 endfunction
 wire[5:0] qr=div255({1'b0,sr}),qg=div255(sg),qb=div255({1'b0,sb});
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pr<=0;pg<=0;pb<=0;br<=0;bg<=0;bb<=0;
   sr<=0;sg<=0;sb<=0;v1<=0;v2<=0;pixel<=0;valid_out<=0;end
  else begin
   pr<=-dr*$signed({1'b0,alpha});pg<=dg*$signed({1'b0,alpha});pb<=db*$signed({1'b0,alpha});
   br<=back[15:11];bg<=back[10:5];bb<=back[4:0];v1<=valid_in;
   sr<=$signed({1'b0,br,8'd0})-$signed({9'd0,br})+pr+14'sd127;
   sg<=$signed({1'b0,bg,8'd0})-$signed({9'd0,bg})+pg+15'sd127;
   sb<=$signed({1'b0,bb,8'd0})-$signed({9'd0,bb})+pb+14'sd127;v2<=v1;
   pixel<={qr[4:0],qg,qb[4:0]};valid_out<=v2;
  end
 end
endmodule
