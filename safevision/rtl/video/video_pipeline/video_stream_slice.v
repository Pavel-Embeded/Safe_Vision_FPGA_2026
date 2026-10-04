// Elastic media stream only. Never put ready/stall in the fixed video scan.
// One cycle when unstalled, one transfer/clock; all payload/last bits held on stall.
module video_stream_slice #(parameter integer WIDTH=16)(
    input wire clk,rst_n,
    input wire [WIDTH-1:0] in_data,input wire in_last,in_valid,output wire in_ready,
    output wire [WIDTH-1:0] out_data,output wire out_last,out_valid,input wire out_ready
);
    rv_skid_buffer #(.W(WIDTH+1)) slice(.clk(clk),.rst_n(rst_n),
      .in_data({in_last,in_data}),.in_valid(in_valid),.in_ready(in_ready),
      .out_data({out_last,out_data}),.out_valid(out_valid),.out_ready(out_ready));
endmodule
