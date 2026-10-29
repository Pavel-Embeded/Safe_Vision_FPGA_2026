


module v3_related_status_capture #(parameter integer WIDTH=32)(
 input wire clk,rst_n,input wire[WIDTH-1:0] source_data,
 output reg[WIDTH-1:0] data,output reg valid);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin data<=0;valid<=0;end
  else begin data<=source_data;valid<=1;end
 end
endmodule
