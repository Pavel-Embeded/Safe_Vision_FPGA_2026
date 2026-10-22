// Board-only progress encoding, not an absolute transaction counter.
// At most one activity event per MEM50 edge. SYS100 continuously samples
// the token through a fully timed related-clock register, without stalls;
// therefore at least one SYS snapshot sees each source change. Comparing
// successive snapshots preserves every activity pulse, even at full rate.
// Common media reset cancels the previous epoch. Do not use this encoding
// with a slower/stalled/asynchronous consumer. No timing waiver is allowed.
module v3_mem_activity_tag(input wire clk,rst_n,activity,output wire[31:0] token);
 reg tag;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)tag<=0;else if(activity)tag<=~tag;
 assign token={31'd0,tag};
endmodule
