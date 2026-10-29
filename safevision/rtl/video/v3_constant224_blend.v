


module v3_constant224_blend #(parameter integer EMERGENCY=0)(
 input wire clk,rst_n,valid_in,enabled,input wire[1:0] foreground,
 input wire[15:0] back,output reg[15:0] pixel,output reg valid_out
);
 function[4:0] map5;input[4:0] background;input[1:0] kind;reg[127:0] plane;begin
  plane=128'hf00ff807f00ff807f807f8071fe01fe0;map5[0]=plane[{kind,background}];
  plane=128'h000ffff8000ffff8fff800071fffe000;map5[1]=plane[{kind,background}];
  plane=128'h000fffff000ffffffffffff8e0000000;map5[2]=plane[{kind,background}];
  plane=128'h000fffff000fffffffffffff00000000;map5[3]=plane[{kind,background}];
  plane=128'hfff00000fff00000ffffffff00000000;map5[4]=plane[{kind,background}];
 end endfunction
 function[5:0] map6;input[5:0] background;input[1:0] kind;reg[255:0] plane;begin
  plane=256'hf00ff00ff807f807f00ff00ff807f807f807f807fc03fc033fc03fc01fe01fe0;map6[0]=plane[{kind,background}];
  plane=256'hfff0000ffff80007fff0000ffff80007fff80007fffc00033fffc0001fffe000;map6[1]=plane[{kind,background}];
  plane=256'h0000000ffffffff80000000ffffffff8fffffff8000000033fffffffe0000000;map6[2]=plane[{kind,background}];
  plane=256'h0000000fffffffff0000000ffffffffffffffffffffffffcc000000000000000;map6[3]=plane[{kind,background}];
  plane=256'h0000000fffffffff0000000fffffffffffffffffffffffff0000000000000000;map6[4]=plane[{kind,background}];
  plane=256'hfffffff000000000fffffff000000000ffffffffffffffff0000000000000000;map6[5]=plane[{kind,background}];
 end endfunction
 wire[1:0] kind_rb=foreground[1]?2'd2:foreground[0]?2'd0:2'd1;
 wire[1:0] kind_g=foreground[1]?2'd2:2'd1;
 wire[15:0] blended;
 generate if(EMERGENCY)begin:red
  assign blended={map5(back[15:11],2'd1),map6(back[10:5],2'd0),map5(back[4:0],2'd0)};
 end else begin:hud
  assign blended={map5(back[15:11],kind_rb),map6(back[10:5],kind_g),map5(back[4:0],kind_rb)};
 end endgenerate
 reg[15:0] p1,p2;reg v1,v2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin p1<=0;p2<=0;pixel<=0;v1<=0;v2<=0;valid_out<=0;end
  else begin p1<=enabled?blended:back;p2<=p1;pixel<=p2;v1<=valid_in;v2<=v1;valid_out<=v2;end
 end
endmodule


module v3_hud_palette224(input wire clk,rst_n,valid_in,enabled,
 input wire[15:0]foreground,back,output reg[15:0]pixel,output reg valid_out);
 function[4:0] map5;input[4:0] background;input[1:0] kind;reg[127:0] plane;begin
  plane=128'hf00ff807f00ff807f807f8071fe01fe0;map5[0]=plane[{kind,background}];
  plane=128'h000ffff8000ffff8fff800071fffe000;map5[1]=plane[{kind,background}];
  plane=128'h000fffff000ffffffffffff8e0000000;map5[2]=plane[{kind,background}];
  plane=128'h000fffff000fffffffffffff00000000;map5[3]=plane[{kind,background}];
  plane=128'hfff00000fff00000ffffffff00000000;map5[4]=plane[{kind,background}];
 end endfunction
 function[5:0] map6;input[5:0] background;input[1:0] kind;reg[255:0] plane;begin
  plane=256'hfc03fe01fe01ff00f00ff00ff807f807f807f807fc03fc033fc03fc01fe01fe0;map6[0]=plane[{kind,background}];
  plane=256'hfffc0001fffe0000fff0000ffff80007fff80007fffc00033fffc0001fffe000;map6[1]=plane[{kind,background}];
  plane=256'hfffffffe000000000000000ffffffff8fffffff8000000033fffffffe0000000;map6[2]=plane[{kind,background}];
  plane=256'hffffffffffffffff0000000ffffffffffffffffffffffffcc000000000000000;map6[3]=plane[{kind,background}];
  plane=256'h00000000000000000000000fffffffffffffffffffffffff0000000000000000;map6[4]=plane[{kind,background}];
  plane=256'hfffffffffffffffffffffff000000000ffffffffffffffff0000000000000000;map6[5]=plane[{kind,background}];
 end endfunction
 wire[1:0]r_kind=foreground[15] ? 2'd1 : foreground[14] ? 2'd2 : 2'd0;
 wire[1:0]b_kind=foreground[4] ? 2'd1 : foreground[3] ? 2'd2 : 2'd0;
 wire[1:0]g_kind={foreground[10]^foreground[9],foreground[10]};
 reg[15:0]back1,p2;reg[1:0]r1,g1,b1;reg enabled1,v1,v2;
 wire[15:0]blended={map5(back1[15:11],r1),map6(back1[10:5],g1),map5(back1[4:0],b1)};
 always@(posedge clk or negedge rst_n)begin
  if(!rst_n)begin back1<=0;r1<=0;g1<=0;b1<=0;enabled1<=0;p2<=0;pixel<=0;v1<=0;v2<=0;valid_out<=0;end
  else begin back1<=back;r1<=r_kind;g1<=g_kind;b1<=b_kind;enabled1<=enabled;v1<=valid_in;
   p2<=enabled1?blended:back1;v2<=v1;pixel<=p2;valid_out<=v2;end
 end
 // synthesis translate_off
 always@(posedge clk)if(rst_n&&enabled&&foreground!=16'hffff&&foreground!=16'h07e0&&foreground!=16'h7bef&&foreground!=16'h05bf&&foreground!=16'hffe0&&foreground!=16'hf800&&foreground!=0)$fatal(1,"unsupported HUD palette colour");
 // synthesis translate_on
endmodule
