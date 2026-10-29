`timescale 1ns/1ps
module tb_frame_swap_default_timeout;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,frame_ready=0,frame_start=0,swap_ack=0;
    wire swap_error,active_commit;
    wire [2:0] state_o;
    frame_swap_ctrl dut(
        .clk(clk),.rst_n(rst_n),.frame_ready(frame_ready),
        .wr_frame_index(1'b1),.wr_slot_id(2'd1),.wr_generation(8'd1),.wr_crc_ok(1'b1),
        .frame_start(frame_start),.swap_ack(swap_ack),.swap_req(),
        .frame_index(),.slot_id(),.generation(),.crc_ok(),.swap_error(swap_error),
        .active_commit(active_commit),.active_next(),.generation_next(),
        .frame_index_next(),.state_o(state_o));
    integer tick=0;
    always @(posedge clk) if(rst_n) begin
        tick=tick+1;
        if(swap_error)
            $fatal(1,"SWAP_DEFAULT_TIMEOUT_BEFORE_VBLANK: tick=%0d next_vblank=1666667 default=%0d",tick,dut.TIMEOUT_N);
    end
    initial begin
        repeat(8) @(negedge clk); rst_n=1;
        repeat(100) @(negedge clk); frame_ready=1;
        @(negedge clk); frame_ready=0;

        wait(tick==1666667);
        @(negedge clk); frame_start=1;
        @(negedge clk); frame_start=0;
        wait(state_o==4);
        @(negedge clk); swap_ack=1;
        @(negedge clk); swap_ack=0;
        repeat(5) @(negedge clk);
        $display("PASS tb_frame_swap_default_timeout: default timeout accommodates full 60 Hz frame wait"); $finish;
    end
    initial begin #18000000; $fatal(1,"AUDIT_TIMEOUT"); end
endmodule
