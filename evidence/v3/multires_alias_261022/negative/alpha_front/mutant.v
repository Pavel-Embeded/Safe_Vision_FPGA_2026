// Exact arithmetic identity: B + floor(((F-B)*a+127)/255). Bias 255*32
// (red/blue) or 255*64 (green) keeps the divider unsigned. The corresponding
// subtraction vanishes modulo the output channel width; true output stays
// in 0..31/63. Three clocks and invalid-cycle public output are preserved.
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
 reg[13:0] sr,sb;reg[14:0] sg;reg[4:0] br2,bb2;reg[5:0] bg2;reg v1,v2;
 function[6:0] div255;
  input[14:0] x;reg[15:0] t;
  begin t={1'b0,x}+16'd1;div255=(t+(t>>8))>>8;end
 endfunction
 wire[6:0] qr=div255({1'b0,sr}),qg=div255(sg),qb=div255({1'b0,sb});
 wire[4:0] rr=br2+qr[4:0],rb=bb2+qb[4:0];wire[5:0] rg=bg2+qg[5:0];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pr<=0;pg<=0;pb<=0;br<=0;bg<=0;bb<=0;
   sr<=0;sg<=0;sb<=0;br2<=0;bg2<=0;bb2<=0;v1<=0;v2<=0;pixel<=0;valid_out<=0;end
  else begin
   pr<=-dr*$signed({1'b0,alpha});pg<=dg*$signed({1'b0,alpha});pb<=db*$signed({1'b0,alpha});
   br<=back[15:11];bg<=back[10:5];bb<=back[4:0];v1<=valid_in;
   sr<=pr+14'd8287;br2<=br;
   sg<=pg+15'd16447;bg2<=bg;
   sb<=pb+14'd8287;bb2<=bb;v2<=v1;
   pixel<={rr,rg,rb};valid_out<=v2;
  end
 end
endmodule
