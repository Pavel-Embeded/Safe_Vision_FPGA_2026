`timescale 1ns/1ps
`include "safevision_defs.vh"


module tb_frame_swap_real_frame;
    localparam [31:0] A_INTEGRATION_TIMEOUT_N = 32'd5_000_000;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg frame_ready = 1'b0;
    reg wr_frame_index = 1'b0;
    reg [1:0] wr_slot_id = 2'd0;
    reg [7:0] wr_generation = 8'd0;
    reg wr_crc_ok = 1'b1;
    reg frame_start = 1'b0;
    reg swap_ack = 1'b0;

    wire swap_req, frame_index, crc_ok, swap_error, active_commit;
    wire [1:0] slot_id, active_next;
    wire [7:0] generation, generation_next;
    wire frame_index_next;
    wire [2:0] state_o;

    frame_swap_ctrl #(.TIMEOUT_N(A_INTEGRATION_TIMEOUT_N)) dut (
        .clk(clk), .rst_n(rst_n),
        .frame_ready(frame_ready), .wr_frame_index(wr_frame_index),
        .wr_slot_id(wr_slot_id), .wr_generation(wr_generation),
        .wr_crc_ok(wr_crc_ok), .frame_start(frame_start),
        .swap_ack(swap_ack), .swap_req(swap_req),
        .frame_index(frame_index), .slot_id(slot_id),
        .generation(generation), .crc_ok(crc_ok),
        .swap_error(swap_error), .active_commit(active_commit),
        .active_next(active_next), .generation_next(generation_next),
        .frame_index_next(frame_index_next), .state_o(state_o)
    );

    integer tick = 0;
    integer frames = 0;
    integer commits = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tick <= 0;
        else tick <= tick + 1;
    end


    always @(negedge clk) begin
        if (!rst_n) frame_start = 1'b0;
        else frame_start = (tick == 1_666_666 || tick == 3_333_333);
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_start) frames = frames + 1;
            if (active_commit) begin
                if (commits >= frames ||
                    !(tick == 1_666_667 || tick == 3_333_334))
                    $fatal(1, "FAIL commit outside real frame boundary at tick %0d", tick);
                commits = commits + 1;
            end
            if (swap_error === 1'b1)
                $fatal(1, "FAIL explicit integration timeout fired before two real frame events, tick %0d", tick);
        end
    end

    task automatic check(input reg condition, input [8*80-1:0] description);
        if (condition !== 1'b1) $fatal(1, "FAIL %0s at tick %0d", description, tick);
    endtask

    initial begin
        check(A_INTEGRATION_TIMEOUT_N == 32'd5_000_000,
              "explicit A integration timeout must equal five million sys_clk periods");

        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (100) @(negedge clk);
        wr_slot_id = 2'd1;
        wr_generation = 8'd1;
        wr_frame_index = 1'b1;
        frame_ready = 1'b1;
        @(negedge clk) frame_ready = 1'b0;

        wait (tick == 1_666_660);
        check(state_o == 3'd2 && commits == 0 && frames == 0 && !swap_error,
              "first request remains pending until 16.67 ms boundary");
        wait (active_commit === 1'b1);
        #1;
        check(active_next == 2'd1 && generation_next == 8'd1 &&
              frame_index_next == 1'b1 && !swap_error,
              "first frame commits intended payload");
        wait (state_o == 3'd4);
        @(negedge clk) swap_ack = 1'b1;
        @(negedge clk) swap_ack = 1'b0;
        wait (state_o == 3'd0);

        @(negedge clk);
        wr_slot_id = 2'd2;
        wr_generation = 8'd2;
        wr_frame_index = 1'b0;
        frame_ready = 1'b1;
        @(negedge clk) frame_ready = 1'b0;

        wait (tick == 3_333_327);
        check(state_o == 3'd2 && commits == 1 && frames == 1 && !swap_error,
              "second request remains pending until next 16.67 ms boundary");
        wait (active_commit === 1'b1);
        #1;
        check(active_next == 2'd2 && generation_next == 8'd2 &&
              frame_index_next == 1'b0 && !swap_error,
              "second frame commits intended payload");
        wait (state_o == 3'd4);
        @(negedge clk) swap_ack = 1'b1;
        @(negedge clk) swap_ack = 1'b0;
        wait (state_o == 3'd0);
        repeat (3) @(negedge clk);
        check(frames == 2 && commits == 2 && !swap_error,
              "two frame events and two commits complete without timeout");
        $display("PASS tb_frame_swap_real_frame: 2 events spaced 1666667 sys_clk cycles; explicit TIMEOUT_N 5000000 (B default unchanged); 2 commits; 0 errors");
        $finish;
    end

    initial begin
        #40_000_000;
        $fatal(1, "FAIL watchdog before two real frame events complete");
    end
endmodule
