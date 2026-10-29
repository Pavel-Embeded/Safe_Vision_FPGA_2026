


`include "fault_code_defs.vh"

module watchdog #(
    parameter integer CLK_HZ       = 100000000,
    parameter integer TO_FRAME_CYC = 10000000,
    parameter integer TO_MEM_CYC   = 20000000,
    parameter integer TO_PROG_CYC  = 50000000,
    parameter [7:0]   CODE_FRAME   = `ERR_MEDIA_INVALID,
    parameter [7:0]   CODE_MEM     = `ERR_SD_IO,
    parameter [7:0]   CODE_PROG    = `ERR_MEDIA_INVALID
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        recover_ack,


    input  wire        frame_heartbeat,
    input  wire        mem_heartbeat,
    input  wire        progress_token,


    output reg         wdt_timeout,
    output reg  [1:0]  wdt_channel,
    output reg  [7:0]  wdt_reason,
    output reg  [31:0] wdt_ts
);

    function integer counter_width;
        input integer n;
        integer v;
        begin
            counter_width = 1;
            for (v = n-1; v > 1; v = v >> 1) counter_width = counter_width + 1;
        end
    endfunction
    localparam integer MS_DIV = (CLK_HZ >= 1000) ? (CLK_HZ/1000) : 1;

    localparam integer TW_F = counter_width(TO_FRAME_CYC);
    localparam integer TW_M = counter_width(TO_MEM_CYC);
    localparam integer TW_P = counter_width(TO_PROG_CYC);

    reg [31:0]      ms_cnt;
    reg [31:0]      ts_now;
    reg [TW_F-1:0]  t_frame;
    reg [TW_M-1:0]  t_mem;
    reg [TW_P-1:0]  t_prog;
    reg             f_frame, f_mem, f_prog;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin ms_cnt <= 32'd0; ts_now <= 32'd0; end
        else if (ms_cnt == MS_DIV-1) begin ms_cnt <= 32'd0; ts_now <= ts_now + 32'd1; end
        else ms_cnt <= ms_cnt + 32'd1;
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_frame <= 0; f_frame <= 1'b0;
        end else if (recover_ack) begin
            t_frame <= 0; f_frame <= 1'b0;
        end else if (frame_heartbeat) begin
            t_frame <= 0;
        end else if (f_frame) begin
            t_frame <= t_frame;
        end else if (t_frame == TO_FRAME_CYC-1) begin
            f_frame <= 1'b1;
        end else t_frame <= t_frame + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_mem <= 0; f_mem <= 1'b0;
        end else if (recover_ack) begin
            t_mem <= 0; f_mem <= 1'b0;
        end else if (mem_heartbeat) begin
            t_mem <= 0;
        end else if (f_mem) begin
            t_mem <= t_mem;
        end else if (t_mem == TO_MEM_CYC-1) begin
            f_mem <= 1'b1;
        end else t_mem <= t_mem + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t_prog <= 0; f_prog <= 1'b0;
        end else if (recover_ack) begin
            t_prog <= 0; f_prog <= 1'b0;
        end else if (progress_token) begin
            t_prog <= 0;
        end else if (f_prog) begin
            t_prog <= t_prog;
        end else if (t_prog == TO_PROG_CYC-1) begin
            f_prog <= 1'b1;
        end else t_prog <= t_prog + 1'b1;
    end

    wire any_to = f_frame | f_mem | f_prog;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdt_timeout <= 1'b0; wdt_channel <= 2'd0; wdt_reason <= 8'h00; wdt_ts <= 32'd0;
        end else if (recover_ack) begin
            wdt_timeout <= 1'b0; wdt_channel <= 2'd0; wdt_reason <= 8'h00; wdt_ts <= 32'd0;
        end else if (any_to && !wdt_timeout) begin
            wdt_timeout <= 1'b1;
            if (f_frame)      begin wdt_channel <= 2'd0; wdt_reason <= CODE_FRAME; end
            else if (f_mem)   begin wdt_channel <= 2'd1; wdt_reason <= CODE_MEM;   end
            else              begin wdt_channel <= 2'd2; wdt_reason <= CODE_PROG;  end
            wdt_ts <= ts_now;
        end
    end

    // synthesis translate_off
    initial if (TO_FRAME_CYC < 1 || TO_MEM_CYC < 1 || TO_PROG_CYC < 1 ||
                TO_FRAME_CYC == TO_MEM_CYC || TO_MEM_CYC == TO_PROG_CYC ||
                TO_FRAME_CYC == TO_PROG_CYC)
        begin $display("[FAIL] watchdog invalid thresholds (must be >=1 and mutually distinct)"); $finish; end 
    // synthesis translate_on

endmodule
