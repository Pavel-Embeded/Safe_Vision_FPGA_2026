


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


 reg[4:0] br2,bb2;reg[5:0] bg2;reg cr,cg,cb;reg v1,v2;
 wire[13:0] sr_next=pr+14'd8287,sb_next=pb+14'd8287;
 wire[14:0] sg_next=pg+15'd16447;
 wire[4:0] rr=br2+cr,rb=bb2+cb;wire[5:0] rg=bg2+cg;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin pr<=0;pg<=0;pb<=0;br<=0;bg<=0;bb<=0;
   br2<=0;bg2<=0;bb2<=0;cr<=0;cg<=0;cb<=0;v1<=0;v2<=0;pixel<=0;valid_out<=0;end
  else begin
   pr<=dr*$signed({1'b0,alpha});pg<=dg*$signed({1'b0,alpha});pb<=db*$signed({1'b0,alpha});
   br<=back[15:11];bg<=back[10:5];bb<=back[4:0];v1<=valid_in;
   br2<=br+sr_next[12:8];bg2<=bg+sg_next[13:8];bb2<=bb+sb_next[12:8];
   cr<=sr_next[7:0]>=~{2'b0,sr_next[13:8]};
   cg<=sg_next[7:0]>=~{1'b0,sg_next[14:8]};
   cb<=sb_next[7:0]>=~{2'b0,sb_next[13:8]};v2<=v1;
   pixel<={rr,rg,rb};valid_out<=v2;
  end
 end
endmodule
