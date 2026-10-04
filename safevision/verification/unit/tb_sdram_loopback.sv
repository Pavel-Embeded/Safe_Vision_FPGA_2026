`timescale 1ns/1ps
// Compile only with run_sdram_loopback_sim.ps1. The local sdram module below
// replaces the encrypted controller ONLY for application-level verification.
// It does not model the physical SDRAM, refresh, CAS, DQ delay or STA corners.
module tb_sdram_loopback;
    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;
    initial begin #200; rst_n = 1; end
    wire [5:0] done;
    sv_loopback_case #(4096, 0, 0, 0, 0) contiguous(clk, rst_n, done[0]);
    sv_loopback_case #(1024, 11, 0, 0, 1) sparse(clk, rst_n, done[1]);
    sv_loopback_case #(1024, 11, 1, 1022, 2) alias_fault(clk, rst_n, done[2]);
    sv_loopback_case #(256, 0, 2, 256, 3) high_dq_fault(clk, rst_n, done[3]);
    sv_loopback_case #(16, 0, 3, 0, 4) missing_read(clk, rst_n, done[4]);
    sv_loopback_case #(16, 0, 4, 0, 5) missing_init(clk, rst_n, done[5]);

    integer a;
    reg [31:0] p;
    reg [7:0] lo, mid, hi;
    reg [20:0] recovered;
    reg [31:0] seen_zero = 0, seen_one = 0;
    reg proof_done = 0;
    initial begin
        if (!$test$plusargs("SKIP_PATTERN_PROOF")) begin
            if (contiguous.dut.pat_of(21'd0) !== 32'hA55A3CC3 ||
                contiguous.dut.pat_of(21'd1) !== 32'hA45B3DCB ||
                contiguous.dut.pat_of(21'd4096) !== 32'hA5DA3CC3 ||
                contiguous.dut.pat_of(21'h100000) !== 32'h255A3CC3)
                $fatal(1, "PATTERN_GOLDEN_VECTOR_FAILED");
            // Independent inverse proves injectivity over every legal address;
            // do not calculate expectations using the RTL's forward formula.
            for (a = 0; a < 2097152; a = a + 1) begin
                p = contiguous.dut.pat_of(a[20:0]);
                lo = p[15:8] ^ 8'h3C;
                mid = p[23:16] ^ 8'h5A ^ lo;
                hi = p[31:24] ^ 8'hA5 ^ lo;
                recovered = {hi, mid, lo[4:0]};
                if (recovered !== a[20:0] || mid[2:0] !== lo[7:5])
                    $fatal(1, "ADDRESS_SIGNATURE_NOT_INJECTIVE addr=%h", a);
                if (a < 256) begin
                    seen_zero = seen_zero | ~p;
                    seen_one = seen_one | p;
                end
            end
            if (seen_zero !== 32'hFFFFFFFF || seen_one !== 32'hFFFFFFFF)
                $fatal(1, "DQ_PATTERN_BIT_COVERAGE_FAILED");
            $display("PASS all 2097152 address signatures and 32 DQ bit values");
        end
        proof_done = 1;
    end
    initial begin
        wait (&done && proof_done);
        $display("PASS tb_sdram_loopback: 6 scenarios, real UART, address alias detection");
        $finish;
    end
    initial begin #1000000; $fatal(1, "LOOPBACK_TEST_TIMEOUT done=%b", done); end
endmodule

module sv_loopback_case #(
    parameter integer WORDS = 4096,
    parameter integer SHIFT = 0,
    parameter integer FAULT = 0,
    parameter integer BAD = 0,
    parameter integer ID = 0
)(input wire clk, input wire rst_n, output reg done = 0);
    wire txd;
    wire [3:0] led;
    top_sdram_loopback #(
        .BAUD(12500000), .POWERUP_CYC(24'd16), .INIT_TO_CYC(24'd64),
        .TEST_WORDS(WORDS), .ADDR_SHIFT(SHIFT), .WR_DRAIN_CYC(16'd16),
        .RD_WAIT_TO_CYC(20'd64)
    ) dut(.clk(clk), .rst_n(rst_n), .uart_txd(txd), .led(led));
    defparam dut.u_sdram.MODEL_SHIFT = SHIFT;
    defparam dut.u_sdram.MODEL_WORDS = WORDS;
    defparam dut.u_sdram.FAULT_MODE = FAULT;

    // The TD functional model has uninitialized lock counters unless reset is
    // pulsed. Supply that simulation initial condition; the real top ties PLL
    // reset low and relies on chip power-up. This does not verify power-up AC.
    initial begin
        #1; force dut.u_sys_pll.pll_inst.reset = 1'b1;
        #199; release dut.u_sys_pll.pll_inst.reset;
    end

    function [31:0] hex16(input [15:0] value);
        reg [127:0] digits;
        integer i;
        begin
            digits = "0123456789ABCDEF";
            for (i = 0; i < 4; i = i + 1)
                hex16[8*i +: 8] = digits[8*(15-value[4*i +: 4]) +: 8];
        end
    endfunction
    reg [567:0] expected;
    reg [7:0] received;
    integer bytes_received = 0;
    integer bit_index;
    initial begin
        expected = {"SV-SDRAM-LOOP", 8'h0D, 8'h0A,
                    "INIT=01 LOCK=01", 8'h0D, 8'h0A,
                    "W=", hex16(WORDS), " R=", hex16(WORDS),
                    " CAP=", hex16(WORDS), " BAD=", hex16(BAD), 8'h0D, 8'h0A,
                    "DONE", 8'h0D, 8'h0A};
        if (FAULT != 3 && FAULT != 4) begin
            wait(dut.rst_mem_n === 1'b1);
            for (bytes_received = 0; bytes_received < 71; bytes_received = bytes_received + 1) begin
                @(negedge txd);
                #40;
                if (txd !== 0) $fatal(1, "UART_START_FAILED case=%0d", ID);
                #80;
                for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                    received[bit_index] = txd;
                    #80;
                end
                if (txd !== 1) $fatal(1, "UART_STOP_FAILED case=%0d", ID);
                if (received !== expected[8*(70-bytes_received) +: 8]) begin
                    if (FAULT == 1 && bytes_received >= 59 && bytes_received <= 62)
                        $fatal(1, "ADDRESS_ALIAS_ESCAPED: bad count byte=%0d got=%h", bytes_received, received);
                    $fatal(1, "UART_BYTE_FAILED case=%0d byte=%0d got=%h want=%h",
                           ID, bytes_received, received, expected[8*(70-bytes_received) +: 8]);
                end
            end
        end
    end
    reg [31:0] seen_zero = 0, seen_one = 0;
    always @(posedge dut.ext_mem_clk) begin
        if (dut.rst_mem_n && dut.app_wr_en) begin
            if (dut.app_rd_en || !dut.sdr_init_done || dut.app_wr_dm !== 4'b0)
                $fatal(1, "APPLICATION_WRITE_PROTOCOL_FAILED case=%0d", ID);
            seen_zero <= seen_zero | ~dut.app_wr_din;
            seen_one <= seen_one | dut.app_wr_din;
        end
    end
    initial begin
        wait(dut.st === 4'd7 || dut.st === 4'd8);
        #1;
        if (FAULT == 1 && dut.bad_cnt == 0)
            $fatal(1, "ADDRESS_ALIAS_ESCAPED: high-address decoder fault reported success");
        if (FAULT == 4) begin
            if (led !== 4'd1 || dut.err_code !== 8'h01 || dut.wr_i !== 0 || dut.rd_i !== 0)
                $fatal(1, "INIT_TIMEOUT_FAILED");
        end else if (FAULT == 3) begin
            if (led !== 4'd2 || dut.err_code !== 8'h02 || dut.wr_i !== WORDS ||
                dut.rd_i !== WORDS || dut.cap_cnt !== WORDS-1)
                $fatal(1, "READ_TIMEOUT_FAILED");
        end else begin
            if (led !== (BAD == 0 ? 4'd8 : 4'd3) ||
                dut.err_code !== (BAD == 0 ? 8'h00 : 8'h03) ||
                dut.wr_i !== WORDS || dut.rd_i !== WORDS || dut.cap_cnt !== WORDS || dut.bad_cnt !== BAD)
                $fatal(1, "LOOPBACK_RESULT_FAILED case=%0d bad=%0d", ID, dut.bad_cnt);
            wait(bytes_received == 71);
            if (SHIFT == 0 && WORDS >= 256 && !$test$plusargs("SKIP_PATTERN_PROOF") &&
                (seen_zero !== 32'hFFFFFFFF || seen_one !== 32'hFFFFFFFF))
                $fatal(1, "ACTUAL_WRITE_DQ_COVERAGE_FAILED case=%0d", ID);
        end
        repeat (20) @(posedge dut.ext_mem_clk);
        if ((FAULT == 3 || FAULT == 4) && bytes_received != 0)
            $fatal(1, "UNEXPECTED_TIMEOUT_REPORT case=%0d", ID);
        $display("PASS loopback case=%0d words=%0d shift=%0d fault=%0d", ID, WORDS, SHIFT, FAULT);
        done = 1;
    end
endmodule

// Simulation-only substitute with the same application ports as sdram.v.
// Ordered, seven-cycle read responses; explicit faults exercise the checker.
module sdram #(
    parameter integer MODEL_SHIFT = 0,
    parameter integer MODEL_WORDS = 4096,
    parameter integer FAULT_MODE = 0
)(input wire Clk, Clk_sft, Rst,
  output reg Sdr_init_done = 0, output wire Sdr_init_ref_vld, Sdr_busy,
  input wire App_wr_en, input wire [20:0] App_wr_addr,
  input wire [3:0] App_wr_dm, input wire [31:0] App_wr_din,
  input wire App_rd_en, input wire [20:0] App_rd_addr,
  output reg Sdr_rd_en = 0, output reg [31:0] Sdr_rd_dout = 0);
    reg [31:0] memory [0:4095];
    reg [6:0] valid_pipe = 0;
    reg [31:0] data_pipe [0:6];
    integer init_count = 0;
    integer i, windex, rindex;
    assign Sdr_init_ref_vld = 1'b0;
    assign Sdr_busy = !Sdr_init_done;
    always @(posedge Clk or posedge Rst) begin
        if (Rst) begin
            init_count <= 0;
            Sdr_init_done <= 0;
            Sdr_rd_en <= 0;
            Sdr_rd_dout <= 0;
            valid_pipe <= 0;
            for (i = 0; i < 7; i = i + 1) data_pipe[i] <= 0;
        end else begin
            if (init_count < 8) init_count <= init_count + 1;
            if (init_count == 7 && FAULT_MODE != 4) Sdr_init_done <= 1;
            if ((App_wr_en || App_rd_en) && !Sdr_init_done)
                $fatal(1, "COMMAND_BEFORE_INIT");
            if (App_wr_en && App_rd_en) $fatal(1, "OVERLAPPING_COMMANDS");
            windex = (FAULT_MODE == 1 ? (App_wr_addr & 21'hFFF) : App_wr_addr) >> MODEL_SHIFT;
            rindex = (FAULT_MODE == 1 ? (App_rd_addr & 21'hFFF) : App_rd_addr) >> MODEL_SHIFT;
            if (App_wr_en) begin
                if (windex >= 4096 || App_wr_dm !== 4'b0) $fatal(1, "MODEL_WRITE_RANGE_OR_MASK");
                memory[windex] <= App_wr_din;
            end
            valid_pipe[0] <= App_rd_en && !(FAULT_MODE == 3 &&
                                           App_rd_addr == ((MODEL_WORDS-1) << MODEL_SHIFT));
            if (App_rd_en) begin
                if (rindex >= 4096) $fatal(1, "MODEL_READ_RANGE");
                data_pipe[0] <= memory[rindex] ^ (FAULT_MODE == 2 ? 32'h80000000 : 32'd0);
            end
            for (i = 1; i < 7; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                data_pipe[i] <= data_pipe[i-1];
            end
            Sdr_rd_en <= valid_pipe[6];
            Sdr_rd_dout <= data_pipe[6];
        end
    end
endmodule
