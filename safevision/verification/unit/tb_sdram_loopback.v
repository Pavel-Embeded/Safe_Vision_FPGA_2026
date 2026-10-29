`timescale 1ns/1ps


module tb_sdram_loopback;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    wire [6:0] done;
    sv_loopback_case #(4096, 0, 0, 1, 0, 0,    0) contiguous(clk, rst_n, done[0]);
    sv_loopback_case #(1024,11, 1, 1, 0, 0,    1) sparse(clk, rst_n, done[1]);
    sv_loopback_case #(1024,11, 1, 1, 1, 1022, 2) address_alias(clk, rst_n, done[2]);
    sv_loopback_case #(256,  0, 0, 1, 2, 256,  3) high_dq_fault(clk, rst_n, done[3]);
    sv_loopback_case #(16,   0, 0, 1, 3, 0,    4) missing_read(clk, rst_n, done[4]);
    sv_loopback_case #(16,   0, 0, 1, 4, 0,    5) missing_init(clk, rst_n, done[5]);

    sv_loopback_case #(16,  11, 1, 1, 0, 0,    6, 115200) board_baud(clk, rst_n, done[6]);

    reg [20:0] proof_addr = 0;
    reg [2:0] proof_mode = 0;
    wire [31:0] proof_pat;
    sdr_pat_gen u_signature_proof(.addr(proof_addr), .mode(proof_mode), .pat(proof_pat));

    integer a;
    reg [20:0] old_addr;
    reg [31:0] pattern;
    reg [7:0] low_byte, mid_byte, high_byte;
    reg [20:0] recovered;
    reg [31:0] seen_zero = 0;
    reg [31:0] seen_one = 0;
    reg [31:0] old_patterns [0:1023];
    integer i, j, old_unique, duplicate;
    reg proof_done = 0;

    initial begin
        if (!$test$plusargs("SKIP_PATTERN_PROOF")) begin
            proof_addr = 21'd0; #1;
            if (proof_pat !== 32'hA55A3CC3) begin $display("[FAIL] SIGNATURE_GOLDEN_ZERO_FAILED"); $finish; end 
            proof_addr = 21'd1; #1;
            if (proof_pat !== 32'hA45B3DCB) begin $display("[FAIL] SIGNATURE_GOLDEN_ONE_FAILED"); $finish; end 
            proof_addr = 21'h001000; #1;
            if (proof_pat !== 32'hA5DA3CC3) begin $display("[FAIL] SIGNATURE_GOLDEN_HIGH_FAILED"); $finish; end 
            proof_addr = 21'h100000; #1;
            if (proof_pat !== 32'h255A3CC3) begin $display("[FAIL] SIGNATURE_GOLDEN_TOP_FAILED"); $finish; end 


            for (a = 0; a < 2097152; a = a + 1) begin
                proof_addr = a[20:0]; #1;
                pattern = proof_pat;
                low_byte  = pattern[15:8] ^ 8'h3C;
                mid_byte  = pattern[23:16] ^ 8'h5A ^ low_byte;
                high_byte = pattern[31:24] ^ 8'hA5 ^ low_byte;
                recovered = {high_byte, mid_byte, low_byte[4:0]};
                if (recovered !== a[20:0] || mid_byte[2:0] !== low_byte[7:5])
                    begin $display("[FAIL] SIGNATURE_NOT_INJECTIVE addr=%h", a); $finish; end 
                if (a < 256) begin
                    seen_zero = seen_zero | ~pattern;
                    seen_one  = seen_one  |  pattern;
                end
            end
            if (seen_zero !== 32'hFFFFFFFF || seen_one !== 32'hFFFFFFFF)
                begin $display("[FAIL] CONTIGUOUS_DQ_COVERAGE_FAILED"); $finish; end 


            old_unique = 0;
            for (i = 0; i < 1024; i = i + 1) begin
                old_addr = (i << 11) & 21'h1FFFFF;
                old_patterns[i] = {(8'hA5 ^ old_addr[11:4]), (8'h5A ^ old_addr[7:0]),
                                   old_addr[11:4], old_addr[3:0]};
            end
            for (i = 0; i < 1024; i = i + 1) begin
                duplicate = 0;
                for (j = 0; j < i; j = j + 1)
                    if (old_patterns[i] === old_patterns[j]) duplicate = 1;
                if (!duplicate) old_unique = old_unique + 1;
            end
            if (old_unique != 2) begin $display("[FAIL] OLD_PATTERN_NEGATIVE_CONTROL_FAILED unique=%0d", old_unique); $finish; end 
            $display("PASS old-pattern negative control finds exactly two aliases");
            $display("PASS all 2097152 signatures invert; all DQ bits toggle");
        end
        proof_done = 1'b1;
    end

    initial begin
        #200;
        rst_n = 1'b1;
        wait (&done && proof_done);
        $display("PASS tb_sdram_loopback: six application scenarios, board-baud UART and exhaustive address signature");
        $finish;
    end

    initial begin
        #100_000_000;
        begin $display("[FAIL] LOOPBACK_TEST_TIMEOUT done=%b", done); $finish; end 
    end
endmodule

module sv_loopback_case #(
    parameter integer WORDS = 16,
    parameter integer SHIFT = 0,
    parameter integer LOWSTEP = 0,
    parameter integer ROUNDS = 1,
    parameter integer FAULT_MODE = 0,
    parameter integer EXPECT_BAD = 0,
    parameter integer ID = 0,
    parameter integer UART_BAUD = 12500000
)(input wire clk, input wire rst_n, output reg done );
 initial begin done =  1'b0; end

    localparam integer BIT_NS = 8 * (125000000 / UART_BAUD);
    wire txd;
    wire [3:0] led;
    top_sdram_loopback #(
        .BAUD(UART_BAUD), .POWERUP_CYC(24'd16), .INIT_TO_CYC(24'd64),
        .BASE_ADDR(21'd0), .TEST_WORDS(WORDS), .ADDR_SHIFT(SHIFT),
        .ADDR_LOWSTEP(LOWSTEP), .ROUNDS(ROUNDS), .WR_DRAIN_CYC(16'd16),
        .RD_WAIT_TO_CYC(20'd64)
    ) dut(.clk(clk), .rst_n(rst_n), .uart_txd(txd), .led(led));

    defparam dut.u_sdram.MODEL_SHIFT = SHIFT;
    defparam dut.u_sdram.MODEL_WORDS = WORDS;
    defparam dut.u_sdram.FAULT_MODE = FAULT_MODE;

`ifndef SIM_MODEL_SIM_STUB


    initial begin
        #1; force dut.u_sys_pll.pll_inst.reset = 1'b1;
        #199; release dut.u_sys_pll.pll_inst.reset;
    end
`endif

    function [7:0] hx;
        input [3:0] n;
        begin begin hx = (n < 10)  ?  (8'h30 + n) : (8'h37 + n); end
     end endfunction
    function [15:0] hex8;
        input [7:0] v;
        begin begin hex8 = {hx(v[7:4]),hx(v[3:0])}; end
     end endfunction
    function [47:0] hex24;
        input [23:0] v;
        begin begin hex24 = {hx(v[23:20]),hx(v[19:16]),hx(v[15:12]),hx(v[11:8]),hx(v[7:4]),hx(v[3:0])}; end
     end endfunction
    function [31:0] hex16;
        input [15:0] v;
        begin begin hex16 = {hx(v[15:12]),hx(v[11:8]),hx(v[7:4]),hx(v[3:0])}; end
     end endfunction
    function [63:0] hex32;
        input [31:0] v;
        begin begin
            hex32 = {hx(v[31:28]),hx(v[27:24]),hx(v[23:20]),hx(v[19:16]),
                     hx(v[15:12]),hx(v[11:8]),hx(v[7:4]),hx(v[3:0])};
        end
     end endfunction
    function [79:0] hex40;
        input [39:0] v;
        begin begin
            hex40 = {hx(v[39:36]),hx(v[35:32]),hx(v[31:28]),hx(v[27:24]),hx(v[23:20]),
                     hx(v[19:16]),hx(v[15:12]),hx(v[11:8]),hx(v[7:4]),hx(v[3:0])};
        end
     end endfunction
    function [20:0] addr_for;
        input integer index;
        begin begin addr_for = (index << SHIFT) + ((LOWSTEP != 0)  ?  index : 0); end
     end endfunction
    function [31:0] signature;
        input [20:0] address;
        reg [7:0] lo;
        begin begin
            lo = address[7:0];
            signature = {(8'hA5 ^ lo ^ address[20:13]),
                         (8'h5A ^ lo ^ address[12:5]),
                         (8'h3C ^ lo),
                         (8'hC3 ^ {address[4:0], address[7:5]})};
        end
     end endfunction

    reg [8*190-1:0] expected;
    reg [7:0] received;
    integer bytes_received = 0;
    integer handshakes = 0;
    integer bit_index;
    always @(posedge dut.ext_mem_clk) begin
        if (dut.rst_mem_n && dut.uart_tx_valid && dut.uart_tx_ready)
            handshakes <= handshakes + 1;
    end
    initial begin
        if (FAULT_MODE != 3 && FAULT_MODE != 4) begin
            wait(dut.st === 4'd6);
            repeat (1920 * (125000000 / UART_BAUD) + 1000) @(posedge dut.ext_mem_clk);
            if (dut.st === 4'd6 || bytes_received != 190 || handshakes != 190)
                begin $display("[FAIL] REPORT_STUCK case=%0d baud=%0d idx=%0d run=%b byte_valid=%b ready=%b handshakes=%0d bytes=%0d",
                       ID, UART_BAUD, dut.rpt_idx, dut.rpt_run, dut.rpt_byte_valid,
                       dut.uart_tx_ready, handshakes, bytes_received); $finish; end 
        end
    end
    reg [31:0] expected_bad_addr;
    reg [31:0] expected_bad_data;
    reg [31:0] expected_good_data;
    reg [31:0] seen_zero = 0;
    reg [31:0] seen_one = 0;
    reg [39:0] total_words;

    initial begin
        total_words = WORDS * ROUNDS;
        expected_bad_addr = 32'hFFFFFFFF;
        expected_good_data = 0;
        expected_bad_data = 0;
        if (EXPECT_BAD != 0) begin
            expected_bad_addr = {11'd0, addr_for(0)};
            expected_good_data = signature(addr_for(0));
            if (FAULT_MODE == 1)
                expected_bad_data = signature(addr_for(WORDS-2));
            else
                expected_bad_data = expected_good_data ^ 32'h80000000;
        end
        expected = {
            "SV-SDRAM-LOOP", 8'h0D, 8'h0A,
            "INIT=01 LOCK=01", 8'h0D, 8'h0A,
            "CFG=", hex8(SHIFT[7:0]), hx(LOWSTEP[3:0]), " BASE=000000 N=", hex24(WORDS[23:0]), 8'h0D, 8'h0A,
            "RND=", hex32(ROUNDS), "/", hex32(ROUNDS), " PAT=", hx((ROUNDS-1)%6), 8'h0D, 8'h0A,
            "W=", hex16(WORDS[15:0]), " R=", hex16(WORDS[15:0]),
            " CAP=", hex16((FAULT_MODE == 3)  ?  WORDS-1 : WORDS),
            " BAD=", hex16(EXPECT_BAD[15:0]), 8'h0D, 8'h0A,
            "TOT=", hex40(total_words), 8'h0D, 8'h0A,
            "BAD0=", hex32((EXPECT_BAD == 0)  ?  32'hFFFFFFFF : 32'd1), ":",
            hex24((EXPECT_BAD == 0)  ?  24'hFFFFFF : expected_bad_addr[23:0]),
            " E=", hex32(expected_good_data), " A=", hex32(expected_bad_data), 8'h0D, 8'h0A,
            "DONE", 8'h0D, 8'h0A
        };

        if (FAULT_MODE != 3 && FAULT_MODE != 4) begin
            wait(dut.rst_mem_n === 1'b1);
            for (bytes_received = 0; bytes_received < 190; bytes_received = bytes_received + 1) begin
                @(negedge txd);
                #(BIT_NS / 2);
                if (txd !== 1'b0) begin $display("[FAIL] UART_START_FAILED case=%0d", ID); $finish; end 
                #BIT_NS;
                for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                    received[bit_index] = txd;
                    #BIT_NS;
                end
                if (txd !== 1'b1) begin $display("[FAIL] UART_STOP_FAILED case=%0d", ID); $finish; end 
                if (received !== expected[8*(189-bytes_received) +: 8])
                    begin $display("[FAIL] UART_BYTE_FAILED case=%0d byte=%0d got=%h want=%h",
                           ID, bytes_received, received, expected[8*(189-bytes_received) +: 8]); $finish; end 
            end
        end
    end

    always @(posedge dut.ext_mem_clk) begin
        if (dut.rst_mem_n && dut.app_wr_en) begin
            if (dut.app_rd_en || !dut.sdr_init_done || dut.app_wr_dm !== 4'b0)
                begin $display("[FAIL] APPLICATION_WRITE_PROTOCOL_FAILED case=%0d", ID); $finish; end 
            seen_zero <= seen_zero | ~dut.app_wr_din;
            seen_one  <= seen_one  |  dut.app_wr_din;
        end
    end

    initial begin
        wait(dut.st === 4'd7 || dut.st === 4'd8);
        #1;
        if (FAULT_MODE == 4) begin
            if (led !== 4'd1 || dut.err_code !== 8'h01 || dut.wr_i !== 0 || dut.rd_i !== 0)
                begin $display("[FAIL] INIT_TIMEOUT_FAILED"); $finish; end 
        end else if (FAULT_MODE == 3) begin
            if (led !== 4'd2 || dut.err_code !== 8'h02 || dut.wr_i !== WORDS ||
                dut.rd_i !== WORDS || dut.cap_cnt !== WORDS-1)
                begin $display("[FAIL] READ_TIMEOUT_FAILED"); $finish; end 
        end else begin
            if (led !== ((EXPECT_BAD == 0)  ?  4'd8 : 4'd3) ||
                dut.err_code !== ((EXPECT_BAD == 0)  ?  8'h00 : 8'h03) ||
                dut.wr_i !== WORDS || dut.rd_i !== WORDS || dut.cap_cnt !== WORDS ||
                dut.checked_cnt !== WORDS || dut.bad_cnt !== EXPECT_BAD)
                begin $display("[FAIL] LOOPBACK_RESULT_FAILED case=%0d bad=%0d", ID, dut.bad_cnt); $finish; end 
            wait(bytes_received == 190);
            if (handshakes != 190)
                begin $display("[FAIL] UART_HANDSHAKE_COUNT_FAILED case=%0d accepted=%0d", ID, handshakes); $finish; end 
            if (FAULT_MODE == 0 && SHIFT == 0 && WORDS >= 256 &&
                (seen_zero !== 32'hFFFFFFFF || seen_one !== 32'hFFFFFFFF))
                begin $display("[FAIL] ACTUAL_WRITE_DQ_COVERAGE_FAILED case=%0d", ID); $finish; end 
        end
        repeat (20) @(posedge dut.ext_mem_clk);
        if ((FAULT_MODE == 3 || FAULT_MODE == 4) && bytes_received != 0)
            begin $display("[FAIL] UNEXPECTED_TIMEOUT_REPORT case=%0d", ID); $finish; end 
        $display("PASS loopback case=%0d words=%0d shift=%0d lowstep=%0d fault=%0d",
                 ID, WORDS, SHIFT, LOWSTEP, FAULT_MODE);
        done = 1'b1;
    end
endmodule

`ifdef SIM_MODEL_SIM_STUB
module sv_system_pll (
    input wire refclk, input wire reset, output wire extlock,
    output wire clk0_out, output wire clk1_out, output wire clk2_out
);
    reg mem_clk = 1'b0;
    always #4 mem_clk = ~mem_clk;
    assign extlock = 1'b1;
    assign clk0_out = mem_clk;
    assign clk1_out = mem_clk;
    assign clk2_out = mem_clk;
    wire unused = refclk | reset;
endmodule
`endif


module sdram #(
    parameter integer MODEL_SHIFT = 0,
    parameter integer MODEL_WORDS = 16,
    parameter integer FAULT_MODE = 0
)(input wire Clk, Clk_sft, Rst,
  output reg Sdr_init_done , output wire Sdr_init_ref_vld, Sdr_busy,
  input wire App_wr_en, input wire [20:0] App_wr_addr,
  input wire [3:0] App_wr_dm, input wire [31:0] App_wr_din,
  input wire App_rd_en, input wire [20:0] App_rd_addr,
  output reg Sdr_rd_en , output reg [31:0] Sdr_rd_dout );
 initial begin Sdr_init_done =  0; Sdr_rd_en =  0; Sdr_rd_dout =  0; end

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
                begin $display("[FAIL] COMMAND_BEFORE_INIT"); $finish; end 
            if (App_wr_en && App_rd_en) begin $display("[FAIL] OVERLAPPING_COMMANDS"); $finish; end 
            windex = (FAULT_MODE == 1  ?  (App_wr_addr & 21'h000FFF) : App_wr_addr) >> MODEL_SHIFT;
            rindex = (FAULT_MODE == 1  ?  (App_rd_addr & 21'h000FFF) : App_rd_addr) >> MODEL_SHIFT;
            if (App_wr_en) begin
                if (windex >= 4096 || App_wr_dm !== 4'b0) begin $display("[FAIL] MODEL_WRITE_RANGE_OR_MASK"); $finish; end 
                memory[windex] <= App_wr_din;
            end
            valid_pipe[0] <= App_rd_en && !(FAULT_MODE == 3 &&
                App_rd_addr == (((MODEL_WORDS-1) << MODEL_SHIFT) + ((MODEL_SHIFT != 0)  ?  MODEL_WORDS-1 : 0)));
            if (App_rd_en) begin
                if (rindex >= 4096) begin $display("[FAIL] MODEL_READ_RANGE"); $finish; end 
                data_pipe[0] <= memory[rindex] ^ ((FAULT_MODE == 2)  ?  32'h80000000 : 32'd0);
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
