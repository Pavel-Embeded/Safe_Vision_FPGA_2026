`timescale 1ns/1ps
module tb_frame_swap_vblank_ack;
    reg clk_b=0,clk_a=0;
    always #4 clk_b=~clk_b;
    always #20 clk_a=~clk_a;
    reg rst_n=0,frame_ready=0,frame_start_a=0,ack_a=0,pending_a=0;
    wire req_b,fs_b,ack_b,req_a,mb_valid_a,swap_error,active_commit;
    wire frame_index_b,crc_ok_b;
    wire [1:0] slot_b;
    wire [7:0] generation_b;
    wire [2:0] state_o;
    frame_swap_ctrl #(.TIMEOUT_N(64)) dut(
        .clk(clk_b),.rst_n(rst_n),.frame_ready(frame_ready),
        .wr_frame_index(1'b1),.wr_slot_id(2'd2),.wr_generation(8'd7),.wr_crc_ok(1'b1),
        .frame_start(fs_b),.swap_ack(ack_b),.swap_req(req_b),
        .frame_index(frame_index_b),.slot_id(slot_b),.generation(generation_b),.crc_ok(crc_ok_b),
        .swap_error(swap_error),.active_commit(active_commit),.active_next(),
        .generation_next(),.frame_index_next(),.state_o(state_o));
    frame_swap_cdc cdc(
        .clk_b(clk_b),.rst_b_n(rst_n),.swap_req_b(req_b),
        .mb_frame_index_b(frame_index_b),.mb_slot_id_b(slot_b),
        .mb_generation_b(generation_b),.mb_crc_ok_b(crc_ok_b),
        .frame_start_evt_b(fs_b),.swap_ack_evt_b(ack_b),
        .clk_a(clk_a),.rst_a_n(rst_n),.swap_req_evt_a(req_a),.swap_req_lvl_a(),
        .mb_frame_index_a(),.mb_slot_id_a(),.mb_generation_a(),.mb_crc_ok_a(),
        .mb_valid_a(mb_valid_a),.frame_start_a(frame_start_a),.swap_ack_a(ack_a));

    always @(posedge clk_a or negedge rst_n) begin
        if(!rst_n) begin ack_a<=0; pending_a<=0; end
        else begin
            if(req_a) pending_a<=1;
            if(pending_a && mb_valid_a && frame_start_a) begin
                ack_a<=~ack_a; pending_a<=0;
                $display("A_SWITCH_AND_ACK_ON_VBLANK");
            end
        end
    end
    integer simultaneous=0,commits=0;
    always @(posedge clk_b) if(rst_n) begin
        if(fs_b&&ack_b) begin
            simultaneous=simultaneous+1;
            $display("B_FRAME_START_AND_ACK_SAME_EDGE state=%0d",dut.state);
        end
        if(active_commit) commits=commits+1;
    end
    initial begin
        repeat(8) @(negedge clk_b); rst_n=1;
        @(negedge clk_b); frame_ready=1;
        @(negedge clk_b); frame_ready=0;
        wait(req_a);
        repeat(2) @(negedge clk_a); frame_start_a=1;
        @(negedge clk_a); frame_start_a=0;
        repeat(80) @(negedge clk_b);
        if(simultaneous!=1 || commits!=1) $fatal(1,"AUDIT_BAD_STIMULUS");
        if(swap_error || dut.state!=0)
            $fatal(1,"SWAP_EARLY_ACK_LOST: ack arrived with frame_start, error=%b state=%0d",swap_error,dut.state);
        $display("PASS tb_frame_swap_vblank_ack: vblank acknowledgement completes frame swap"); $finish;
    end
    initial begin #2000; $fatal(1,"AUDIT_TIMEOUT"); end
endmodule
