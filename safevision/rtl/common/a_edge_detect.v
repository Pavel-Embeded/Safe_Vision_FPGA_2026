
module a_edge_detect(input wire clk, input wire rst_n, input wire sig,
                     output reg rise, output reg fall);
    reg previous;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin previous<=0; rise<=0; fall<=0; end
        else begin
            previous<=sig;
            rise<=sig && !previous;
            fall<=!sig && previous;
        end
    end
endmodule
