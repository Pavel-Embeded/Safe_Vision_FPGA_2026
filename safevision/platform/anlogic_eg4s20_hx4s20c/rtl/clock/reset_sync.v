


module reset_sync #(
    parameter integer STAGES = 2,
    parameter integer RELEASE_FALLING = 0
) (
    input  wire clk,
    input  wire async_rst_n,
    output wire rst_n
);

    localparam integer PIPE_STAGES = (STAGES < 2) ? 2 : STAGES;
    (* keep = "true" *) reg [PIPE_STAGES-1:0] release_pipe;
    // synthesis translate_off
    initial begin
        if (STAGES < 2) begin
            $display("[FAIL] reset_sync requires STAGES >= 2");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n)
            release_pipe <= {PIPE_STAGES{1'b0}};
        else
            release_pipe <= {release_pipe[PIPE_STAGES-2:0], 1'b1};
    end


    generate if (RELEASE_FALLING) begin : falling_release
        (* keep = "true" *) reg released;
        always @(negedge clk or negedge async_rst_n)
            if (!async_rst_n) released <= 1'b0;
            else released <= release_pipe[PIPE_STAGES-1];
        assign rst_n = released;
    end else begin : rising_release
        assign rst_n = release_pipe[PIPE_STAGES-1];
    end endgenerate

endmodule
