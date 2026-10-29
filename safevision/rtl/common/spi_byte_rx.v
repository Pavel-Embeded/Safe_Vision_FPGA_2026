


module spi_byte_rx (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       sclk,
    input  wire       miso,

    input  wire       clear,

    output reg  [7:0] rx_byte,
    output reg        rx_valid
);

    reg       sclk_d;
    reg [2:0] bit_cnt;
    reg [7:0] sreg;

    wire sclk_rise = sclk & ~sclk_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_d   <= 1'b0;
            bit_cnt  <= 3'd0;
            sreg     <= 8'h00;
            rx_byte  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            sclk_d   <= sclk;
            rx_valid <= 1'b0;

            if (clear) begin
                bit_cnt <= 3'd0;
                sreg    <= 8'h00;
            end else if (sclk_rise) begin
                sreg <= {sreg[6:0], miso};
                if (bit_cnt == 3'd7) begin
                    bit_cnt  <= 3'd0;
                    rx_byte  <= {sreg[6:0], miso};
                    rx_valid <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 3'd1;
                end
            end
        end
    end

endmodule
