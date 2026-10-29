


`include "safevision_defs.vh"

module spi_master #(
    parameter integer CLK_FREQ = 100_000_000,


    parameter integer MID_REF_SAMPLE = 0
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire [15:0] clk_div,


    input  wire        cs_n,


    input  wire        tx_valid,
    input  wire [7:0]  tx_data,
    output wire        tx_ready,
    output reg  [7:0]  rx_data,
    output reg         rx_valid,
    output wire        busy,


    output wire        sclk,
    output wire        mosi,
    input  wire        miso
);


    localparam [1:0] S_IDLE = 2'd0,
                     S_XFER = 2'd1,
                     S_DONE = 2'd2;

    reg  [1:0]  state;
    reg  [7:0]  div_r;
    reg  [7:0]  div_cnt;
    reg  [3:0]  half_cnt;
    reg  [7:0]  tx_sr;
    reg  [7:0]  rx_sr;
    reg         sclk_r;


    assign sclk     = sclk_r;
    assign mosi     = tx_sr[7];
    assign busy     = (state == S_XFER);
    assign tx_ready = (state == S_IDLE);

    wire sample_now = (state == S_XFER) && (div_cnt == div_r) && !sclk_r;
    reg sample_pending;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) sample_pending <= 1'b0;
        else sample_pending <= sample_now;
    generate if (MID_REF_SAMPLE) begin: delayed_miso
        always @(negedge clk or negedge rst_n)
            if (!rst_n) rx_sr <= 8'h00;
            else if (sample_pending) rx_sr <= {rx_sr[6:0], miso};
    end else begin: legacy_miso
        always @(posedge clk or negedge rst_n)
            if (!rst_n) rx_sr <= 8'h00;
            else if (sample_now) rx_sr <= {rx_sr[6:0], miso};
    end endgenerate


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            sclk_r   <= 1'b0;
            div_r    <= 8'd1;
            div_cnt  <= 8'd0;
            half_cnt <= 4'd0;
            tx_sr    <= 8'hFF;

            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin

            rx_valid <= (state == S_DONE);

            case (state)

                S_IDLE: begin
                    sclk_r   <= 1'b0;
                    div_cnt  <= 8'd0;
                    half_cnt <= 4'd0;
                    if (tx_valid) begin
                        tx_sr <= tx_data;
                        div_r <= (!MID_REF_SAMPLE && clk_div[7:0] == 8'd0) ? 8'd1 : clk_div[7:0];
                        state <= S_XFER;
                    end
                end

                S_XFER: begin
                    if (div_cnt == div_r) begin
                        div_cnt <= 8'd0;
                        if (!sclk_r) begin

                            sclk_r <= 1'b1;

                        end else begin

                            sclk_r <= 1'b0;
                            tx_sr  <= {tx_sr[6:0], 1'b1};


                            if (half_cnt == 4'd7) begin
                                state <= S_DONE;
                            end else begin
                                half_cnt <= half_cnt + 4'd1;
                            end
                        end
                    end else begin
                        div_cnt <= div_cnt + 8'd1;
                    end
                end

                S_DONE: begin
                    sclk_r  <= 1'b0;
                    rx_data <= rx_sr;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
