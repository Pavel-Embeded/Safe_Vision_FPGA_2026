


module v3_response_timer #(parameter integer CLK_HZ=100000000)(
 input wire clk,rst_n,start,finish,cancel,output reg[15:0] latency_ms);
 localparam integer TICKS=CLK_HZ/1000>0?CLK_HZ/1000:1;
 localparam integer CW=TICKS>1?$clog2(TICKS):1;
 reg[CW-1:0] cycles;reg[15:0] milliseconds;reg active;
 wire tick=cycles==TICKS-1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cycles<=0;milliseconds<=0;latency_ms<=0;active<=0;end
  else if(cancel)begin active<=0;cycles<=0;milliseconds<=0;end
  else if(start)begin active<=1;cycles<=0;milliseconds<=0;end
  else if(active)begin
   if(tick)begin cycles<=0;if(milliseconds!=65535)milliseconds<=milliseconds+1'b1;end
   else cycles<=cycles+1'b1;
   if(finish)begin active<=0;latency_ms<=milliseconds+((tick&&milliseconds!=65535)?16'd1:16'd0);end
  end
 end
endmodule
