


module uart_tx #(
    parameter integer CLK_FREQ = 100_000_000,
    parameter integer BAUD     = 115200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    output wire       tx_ready,

    output reg        txd
);


    localparam integer DIV = CLK_FREQ / BAUD;

    localparam [1:0] U_IDLE  = 2'd0,
                     U_START = 2'd1,
                     U_DATA  = 2'd2,
                     U_STOP  = 2'd3;

    reg  [1:0]  state;

    localparam integer COUNTER_W=(DIV>=1&&DIV<=65536)?((DIV>1)?$clog2(DIV):1):16;
    reg [COUNTER_W-1:0] div_cnt;
    reg  [2:0]  bit_idx;
    reg  [7:0]  shifter;

    assign tx_ready = (state == U_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= U_IDLE;
            div_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shifter <= 8'h00;
            txd     <= 1'b1;
        end else begin
            case (state)

                U_IDLE: begin
                    txd     <= 1'b1;
                    div_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_valid) begin
                        shifter <= tx_data;
                        state   <= U_START;
                    end
                end

                U_START: begin
                    txd <= 1'b0;
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        state   <= U_DATA;
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end

                U_DATA: begin
                    txd <= shifter[0];
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        shifter <= {1'b1, shifter[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= U_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end

                U_STOP: begin
                    txd <= 1'b1;
                    if (div_cnt == DIV - 1) begin
                        div_cnt <= 16'd0;
                        state   <= U_IDLE;
                    end else begin
                        div_cnt <= div_cnt + 16'd1;
                    end
                end

                default: state <= U_IDLE;
            endcase
        end
    end

endmodule
