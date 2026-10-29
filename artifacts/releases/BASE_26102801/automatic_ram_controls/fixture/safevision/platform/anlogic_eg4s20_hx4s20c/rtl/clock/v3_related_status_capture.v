// Board-only status capture between clocks with a common reference.
// REF50 and MEM50 -> SYS50(BASE)/SYS100(HD) use the same reference PLL.
// BASE control and memory use the same50MHz output; all real paths stay timed.
// Every source field is launched by a REF/MEM register. Ordinary clocked
// setup AND hold, including coincident edges, must pass native routed STA.
// No synchronizer attribute, false path, or datapath-only waiver is permitted
// on this payload. Not suitable for independent/asynchronous clock sources.
// The continuously published snapshot has one SYS-register latency; reset
// abandons the old media epoch. No payload hold/ACK copy is needed here.
module v3_related_status_capture #(parameter integer WIDTH=32)(
 input wire clk,rst_n,input wire[WIDTH-1:0] source_data,
 output reg[WIDTH-1:0] data,output reg valid);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin data<=0;valid<=0;end
  else begin data<=source_data;valid<=1;end
 end
endmodule
