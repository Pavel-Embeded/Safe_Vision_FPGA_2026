module v3_volume_column_reference67 #(parameter integer WIDTH=640,HEIGHT=480)(
 input wire clk,rst_n,frame_start,input wire[6:0] energy,volume,
 input wire[11:0] x,y,input wire de,
 output wire edge_pixel,fill_pixel,output wire[1:0] colour,
 output reg[6:0] level,output wire busy);
 reg[1:0] state;reg[3:0] bits_left;reg[6:0] multiplier,quotient;
 reg[13:0] term,acc;
 wire[13:0] added=acc+(multiplier[0] ? term:14'd0);
 assign busy=state!=0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;bits_left<=0;multiplier<=0;quotient<=0;term<=0;acc<=0;level<=0;end
  else if(frame_start)begin
   state<=1;bits_left<=7;multiplier<=volume>100 ? 7'd100:volume;
   term<={7'd0,energy>100 ? 7'd100:energy};acc<=0;quotient<=0;
  end else case(state)
   1:begin acc<=added;term<=term<<1;multiplier<=multiplier>>1;bits_left<=bits_left-1'b1;
    if(bits_left==1)state<=2;end
   2:if(acc>=100)begin acc<=acc-14'd100;quotient<=quotient+1'b1;end
     else begin level<=quotient;state<=0;end
   default:;
  endcase
 end
 wire box=de&&x>=WIDTH-49&&x<=WIDTH-23&&y>=HEIGHT-171&&y<=HEIGHT-69;
 assign edge_pixel=box&&(x==WIDTH-49||x==WIDTH-23||y==HEIGHT-171||y==HEIGHT-69);
 wire[11:0] rise=HEIGHT-70-y;
 wire gap=rise==10||rise==20||rise==30||rise==40||rise==50||rise==60||rise==70||rise==80||rise==90;
 assign fill_pixel=box&&!edge_pixel&&rise>=1&&rise<=100&&rise<=level&&!gap;
 assign colour=rise>80 ? 2'd2:rise>50 ? 2'd1:2'd0;
endmodule
