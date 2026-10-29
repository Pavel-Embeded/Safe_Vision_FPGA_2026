


module shift_reg #(
    parameter integer WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,

    input  wire             load_en,
    input  wire [WIDTH-1:0] load_data,
    input  wire             shift_en,
    input  wire             ser_in,

    output reg  [WIDTH-1:0] data_out,
    output wire             ser_out
);

    assign ser_out = data_out[WIDTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= {WIDTH{1'b0}};
        end else if (load_en) begin
            data_out <= load_data;
        end else if (shift_en) begin
            data_out <= {data_out[WIDTH-2:0], ser_in};
        end
    end

endmodule
