


`timescale 1ns/1ps
module tb_fullgeom;
    localparam integer WORDS      = 153600;
    localparam integer ROW_WORDS  = 320;
    localparam integer BLOCK_WORDS= 64;
    localparam [31:0]  SLOT1      = 32'h000A_0000;

    reg clk = 0; always #12.5 clk = ~clk;
    reg rst_n = 0;
    reg        frame_begin = 0;
    reg [1:0]  frame_slot  = 0;
    reg        top_down    = 0;
    reg        accepted    = 0;
    reg [31:0] write_addr  = 0, write_data = 0;
    reg        verify_start= 0, verify_allow = 1;
    wire       verify_done, verify_pass, fault;
    wire       rd_req;  wire [31:0] rd_addr;  wire [15:0] rd_len;
    reg        rd_ack = 0, rd_busy = 0, rd_valid = 0;
    reg [31:0] rd_data = 0;
    wire [31:0] bad_addr, bad_expected, bad_actual, source_words;
    wire [15:0] checked_blocks;

    frame_integrity_guard #(.WORDS(WORDS), .ROW_WORDS(ROW_WORDS),
                            .BLOCK_WORDS(BLOCK_WORDS), .TIMEOUT(32'd4000)) dut (
        .clk(clk), .rst_n(rst_n), .frame_begin(frame_begin), .frame_slot(frame_slot),
        .top_down(top_down), .accepted(accepted), .write_addr(write_addr), .write_data(write_data),
        .verify_start(verify_start), .verify_allow(verify_allow),
        .verify_done(verify_done), .verify_pass(verify_pass), .fault(fault),
        .rd_req(rd_req), .rd_addr(rd_addr), .rd_len(rd_len),
        .rd_ack(rd_ack), .rd_busy(rd_busy), .rd_data(rd_data), .rd_valid(rd_valid),
        .lookup_addr(32'd0), .lookup_crc(), .lookup_valid(),
        .bad_addr(bad_addr), .bad_expected(bad_expected), .bad_actual(bad_actual),
        .source_words(source_words), .checked_blocks(checked_blocks));


    reg [31:0] mem [0:600000];
    wire [31:0] rd_word = rd_addr >> 2;

    integer wcount, col, r;
    reg [31:0] cur_addr;
    function [31:0] pixdata(input [31:0] a);
        pixdata = a ^ 32'h5A5A_1234;
    endfunction


    task drive_frame;
        begin
            @(posedge clk);
            frame_slot <= 1; frame_begin <= 1; @(posedge clk); frame_begin <= 0;
            cur_addr = SLOT1 + (top_down ? 0 : (WORDS-ROW_WORDS)*4);
            col = 0;
            for (wcount = 0; wcount < WORDS; wcount = wcount + 1) begin
                @(posedge clk);
                write_addr <= cur_addr; write_data <= pixdata(cur_addr); accepted <= 1;
                mem[cur_addr >> 2] <= pixdata(cur_addr);
                if (col == ROW_WORDS-1) begin
                    col = 0;

                    cur_addr = top_down ? (cur_addr + 4)
                                        : (cur_addr - ROW_WORDS*8 + 4);
                end else begin
                    col = col + 1;
                    cur_addr = cur_addr + 4;
                end
            end
            @(posedge clk); accepted <= 0;
            repeat (4) @(posedge clk);
        end
    endtask


    always @(posedge clk) begin
        rd_ack   <= 1'b0;
        rd_valid <= 1'b0;
        if (rd_req && !rd_ack && !rd_valid) begin
            rd_ack <= 1'b1;
        end else if (rd_ack) begin
            for (r = 0; r < BLOCK_WORDS; r = r + 1) begin
                @(posedge clk);
                rd_valid <= 1'b1; rd_data <= mem[rd_word + r];
            end
            @(posedge clk); rd_valid <= 1'b0;
        end
    end

    integer errors = 0;

    task do_pass(input integer dir);
        begin
            top_down = dir[0];
            rst_n = 0; repeat (5) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
            drive_frame;
            @(posedge clk); verify_start <= 1; @(posedge clk); verify_start <= 0;
            fork : waitdone
                begin : w1  wait (verify_done == 1'b1); end
                begin : w2  #60_000_000; end
            join_any
            disable waitdone;
            repeat (4) @(posedge clk);

            $display("");
            $display("=================================================");
            $display("  REAL GEOMETRY  WORDS=%0d ROW_WORDS=%0d BLOCKS=%0d  top_down=%0d",
                     WORDS, ROW_WORDS, WORDS/BLOCK_WORDS, top_down);
            $display("  verify_done   = %0d", verify_done);
            $display("  verify_pass   = %0d   (expect 1)", verify_pass);
            $display("  fault         = %0d   (expect 0)", fault);
            $display("  source_words  = %0d  (expect %0d)", source_words, WORDS);
            $display("  checked_blocks= %0d  (expect %0d)", checked_blocks, WORDS/BLOCK_WORDS);
            $display("  bad_addr      = %08X", bad_addr);
            $display("  bad_expected  = %08X", bad_expected);
            $display("  bad_actual    = %08X", bad_actual);
            if (!verify_done)       begin errors=errors+1; $display("  [FAIL] verify never finished"); end
            if (!verify_pass)       begin errors=errors+1; $display("  [FAIL] verify_pass=0 (guard rejected an ideal memory)"); end
            if (fault)              begin errors=errors+1; $display("  [FAIL] fault asserted"); end
            if (source_words!=WORDS)begin errors=errors+1; $display("  [FAIL] source_words mismatch"); end
        end
    endtask

    initial begin
        do_pass(0);
        do_pass(1);
        $display("");
        $display("  TOTAL RESULT: %0d error(s) over both row orders", errors);
        $display("=================================================");
        $finish;
    end
endmodule
