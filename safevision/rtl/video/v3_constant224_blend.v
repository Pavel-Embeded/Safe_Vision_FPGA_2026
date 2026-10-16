// Exact fixed-alpha RGB565 palette blend. The two production layers use
// alpha 0/224 only; configurable OSD keeps the generic alpha_blend module.
// foreground 0=white, 1=green, 2/3=gray; EMERGENCY selects constant red.
// Combinational truth tables cover every 5/6-bit background channel, with
// the same independent round((224*F+31*B)/255) result. Three clocks latency.
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
