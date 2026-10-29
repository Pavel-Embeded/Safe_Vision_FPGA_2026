
module video_layer_delay #(parameter integer LATENCY=0)(
    input wire clk,rst_n,input wire [23:0] rgb_in,input wire valid_in,
    output wire [23:0] rgb_out,output wire valid_out
);
    generate if(LATENCY==0)begin : bypass
        assign rgb_out=rst_n?rgb_in:24'd0;assign valid_out=rst_n&&valid_in;
    end else begin : delay
        reg [24:0] data[0:LATENCY-1];integer i;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)for(i=0;i<LATENCY;i=i+1)data[i]<=0;
            else begin data[0]<={valid_in,rgb_in};for(i=1;i<LATENCY;i=i+1)data[i]<=data[i-1];end
        end
        assign {valid_out,rgb_out}=data[LATENCY-1];
    end endgenerate
endmodule
