// Read-only on-demand MEM snapshot. One outstanding query, tagged return.
// Request data remains fixed until acknowledged; the selected MEM word is
// sampled on the response acceptance edge. Reset abandons pending telemetry.
module v3_diag_query(
 input wire sys_clk,sys_rst_n,mem_clk,mem_rst_n,
 input wire request_valid,input wire[3:0] request_selector,
 output wire request_ready,output wire[3:0] mem_selector,
 input wire[31:0] mem_value,
 output wire reply_valid,reply_ok,output wire[31:0] reply_value);
 wire request_src_ready,mem_request,response_src_ready,response_valid;
 wire[35:0] response;reg pending;reg[3:0] expected_selector;
 assign request_ready=request_src_ready && !pending;
 video_cdc_mailbox #(.WIDTH(4)) requests(
 .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_valid(request_valid && request_ready),
 .src_ready(request_src_ready),.src_data(request_selector),
 .dst_clk(mem_clk),.dst_rst_n(mem_rst_n),.dst_valid(mem_request),
 .dst_ready(response_src_ready),.dst_data(mem_selector));
 video_cdc_mailbox #(.WIDTH(36)) responses(
 .src_clk(mem_clk),.src_rst_n(mem_rst_n),.src_valid(mem_request),
 .src_ready(response_src_ready),.src_data({mem_selector,mem_value}),
 .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_valid(response_valid),
 .dst_ready(1'b1),.dst_data(response));
 assign reply_valid=response_valid && pending;
 assign reply_ok=response[35:32]==expected_selector;
 assign reply_value=response[31:0];
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin pending<=0;expected_selector<=0;end
  else begin
   if(request_valid && request_ready)begin pending<=1;expected_selector<=request_selector;end
   if(reply_valid)pending<=0;
  end
 end
endmodule
