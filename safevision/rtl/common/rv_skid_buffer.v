


module rv_skid_buffer #(
    parameter W = 8
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [W-1:0] in_data,
    input  wire         in_valid,
    output wire         in_ready,

    output wire [W-1:0] out_data,
    output wire         out_valid,
    input  wire         out_ready
);


    reg [W-1:0] b_data;
    reg         b_valid;


    reg [W-1:0] s_data;
    reg         s_valid;

    wire b_fire  = b_valid & out_ready;
    wire in_fire = in_valid & in_ready;


    assign in_ready  = ~s_valid;
    assign out_data  = b_data;
    assign out_valid = b_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_data  <= {W{1'b0}};
            b_valid <= 1'b0;
            s_data  <= {W{1'b0}};
            s_valid <= 1'b0;
        end else begin


            if (b_fire) begin

                if (s_valid) begin
                    b_data  <= s_data;
                    b_valid <= 1'b1;
                end else if (in_fire) begin
                    b_data  <= in_data;
                    b_valid <= 1'b1;
                end else begin
                    b_valid <= 1'b0;
                end
            end else if (!b_valid) begin

                if (in_fire) begin
                    b_data  <= in_data;
                    b_valid <= 1'b1;
                end else if (s_valid) begin
                    b_data  <= s_data;
                    b_valid <= 1'b1;
                end
            end


            if (b_fire) begin
                if (s_valid) begin

                    if (in_fire) begin
                        s_data  <= in_data;
                        s_valid <= 1'b1;
                    end else begin
                        s_valid <= 1'b0;
                    end
                end else begin
                    s_valid <= 1'b0;
                end
            end else if (b_valid) begin

                if (in_fire) begin
                    s_data  <= in_data;
                    s_valid <= 1'b1;
                end
            end else begin

                s_valid <= 1'b0;
            end
        end
    end

endmodule
