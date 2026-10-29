


module v3_mem_activity_tag(input wire clk,rst_n,activity,output wire[31:0] token);
 reg tag;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)tag<=0;else if(activity)tag<=~tag;
 assign token={31'd0,tag};
endmodule
