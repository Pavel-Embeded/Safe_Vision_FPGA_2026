


`include "fault_code_defs.vh"

module fault_manager #(
    parameter integer CLK_HZ = 100000000
)(
    input  wire        clk,
    input  wire        rst_n,


    input  wire        err_push,
    input  wire [7:0]  err_code,
    input  wire [2:0]  err_level,
    input  wire        wdt_timeout,
    input  wire [7:0]  wdt_reason,
    input  wire        media_fatal,


    input  wire        recover_ack,


    output reg  [7:0]  fault_code,
    output reg  [2:0]  fault_level,
    output reg         fault_valid,
    output reg         fatal,
    output reg  [31:0] fault_ts,
    output reg         media_rst_req
);
    localparam integer MS_DIV = (CLK_HZ >= 1000) ? (CLK_HZ/1000) : 1;


    localparam [2:0] LV_INFO     = 3'd0;
    localparam [2:0] LV_WARNING  = 3'd1;
    localparam [2:0] LV_DEGRADED = 3'd2;
    localparam [2:0] LV_SAFE     = 3'd3;
    localparam [2:0] LV_FATAL    = 3'd4;

    reg [31:0] ms_cnt;
    reg [31:0] ts_now;


    wire can_clear = recover_ack & ~fatal & ~media_fatal & ~err_push;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_cnt <= 32'd0; ts_now <= 32'd0; end
        else if (ms_cnt == MS_DIV-1) begin ms_cnt <= 32'd0; ts_now <= ts_now + 32'd1; end
        else ms_cnt <= ms_cnt + 32'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_code <= 8'h00; fault_level <= LV_INFO; fault_valid <= 1'b0;
            fatal <= 1'b0; fault_ts <= 32'd0; media_rst_req <= 1'b0;
        end else begin
            media_rst_req <= 1'b0;
            if (media_fatal) fatal <= 1'b1;
            if (err_push && err_level==LV_FATAL) fatal <= 1'b1;

            if (can_clear) begin

                fault_code <= 8'h00; fault_level <= LV_INFO; fault_valid <= 1'b0;
                fault_ts <= 32'd0; media_rst_req <= 1'b1;
            end else if (!fault_valid) begin

                if (err_push) begin
                    fault_code <= err_code; fault_level <= err_level;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end else if (wdt_timeout) begin
                    fault_code <= wdt_reason; fault_level <= LV_SAFE;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end else if (media_fatal) begin
                    fault_code <= 8'h00; fault_level <= LV_FATAL;
                    fault_valid <= 1'b1; fault_ts <= ts_now;
                end
            end else if (media_fatal) begin
                fault_level <= LV_FATAL;
            end else if (wdt_timeout && fault_level<LV_SAFE) begin
                fault_level<=LV_SAFE;
            end else if (err_push && err_level>fault_level) begin
                fault_level<=err_level;
            end
        end
    end

endmodule
