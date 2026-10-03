`timescale 1ns/1ps

// Every case is intentionally invalid. A specific RTL rejection is required.
module tb_clock_parameter_guards #(parameter integer CASE_ID = 0);
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;
    generate
        if (CASE_ID <= 2) begin : bad_reset_stages
            localparam integer STAGES = (CASE_ID == 0) ? 1 : (CASE_ID == 1) ? 0 : -1;
            reset_sync #(.STAGES(STAGES)) dut (.clk(clk),.async_rst_n(rst_n),.rst_n());
        end else if (CASE_ID == 3 || CASE_ID == 4 || CASE_ID == 8) begin : bad_clock_mode
            localparam integer MODE = (CASE_ID == 3) ? 2 : (CASE_ID == 4) ? -1 : 32'hxxxxxxxx;
            clock_gen #(.VIDEO_MODE_HD(MODE)) dut (.board_clk(clk),.board_rst_n(rst_n));
        end else begin : bad_subsystem_mode
            localparam integer MODE = (CASE_ID == 5) ? 2 : (CASE_ID == 6) ? -1 : 32'hxxxxxxxx;
            clock_video_subsystem #(.VIDEO_MODE_HD(MODE)) dut (
                .board_clk(clk),.board_rst_n(rst_n),.media_reset_req(1'b0),
                .memory_client_reset_req(1'b0),.hdmi_reinit_req(1'b0),.audio_reset_req(1'b0));
        end
    endgenerate
    initial begin
        #100;
        $fatal(1,"FAIL invalid clock/reset parameter accepted: CASE_ID=%0d",CASE_ID);
    end
endmodule
