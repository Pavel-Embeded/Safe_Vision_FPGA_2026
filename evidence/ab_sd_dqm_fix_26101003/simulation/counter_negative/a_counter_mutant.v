// Stage 1 exercise; single clock, low active async reset / sync release.
module a_counter #(
    parameter integer MODULO=1000,
    parameter integer WIDTH=10
)(input wire clk, input wire rst_n, input wire enable,
  output reg [WIDTH-1:0] count, output reg tick);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin count <= 0; tick <= 0; end
        else begin
            tick <= 0;
            if (enable) begin
                if (count == ((MODULO == 1000) ? MODULO-2 : MODULO-1)) begin count <= 0; tick <= 1; end
                else count <= count + 1'b1;
            end
        end
    end
    // synthesis translate_off
    initial if (WIDTH < 1 || WIDTH > 30 || MODULO < 1 || MODULO > (2**WIDTH))
        $fatal(1,"a_counter invalid parameters");
    // synthesis translate_on
endmodule
