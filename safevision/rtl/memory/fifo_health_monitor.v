


module fifo_health_monitor (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        clr,
    input  wire [15:0] data_count,
    input  wire        empty,
    input  wire        full,
    input  wire        rd_en,
    input  wire        wr_en,

    output reg  [15:0] min_level,
    output reg  [15:0] underflow_cnt,
    output reg  [15:0] overflow_cnt,
    output wire [15:0] cur_level
);


    reg min_started;

    assign cur_level = data_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            min_level     <= 16'hFFFF;
            min_started   <= 1'b0;
            underflow_cnt <= 16'd0;
            overflow_cnt  <= 16'd0;
        end else if (clr) begin
            min_level   <= 16'hFFFF;
            min_started <= 1'b0;
        end else begin

            if (!min_started) begin
                min_level   <= data_count;
                min_started <= 1'b1;
            end else if (data_count < min_level) begin
                min_level <= data_count;
            end


            if (rd_en && empty) begin
                underflow_cnt <= underflow_cnt + 16'd1;
            end


            if (wr_en && full) begin
                overflow_cnt <= overflow_cnt + 16'd1;
            end
        end
    end

endmodule
