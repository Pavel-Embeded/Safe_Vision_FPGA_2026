// One common first sample prevents independent first-stage decisions.
// Each located second-stage copy releases on the SAME second SERIAL edge.
// This is a physical fanout change, not an extra reset pipeline stage.
module v3_phy_reset_fanout(input wire clk,async_rst_n,output wire[3:0] lane_rst_n);
 (* keep="true",async_reg="true" *) reg sampled;
 (* keep="true",preserve="true",max_fanout=12 *) reg[3:0] released;
 always @(posedge clk or negedge async_rst_n)begin
  if(!async_rst_n)begin sampled<=0;released<=0;end
  else begin sampled<=1;released<={4{sampled}};end
 end
 assign lane_rst_n=released;
endmodule
