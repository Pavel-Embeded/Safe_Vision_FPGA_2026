


`timescale 1ns/1ps
`include "safevision_defs.vh"

module tb_mem_roundtrip;
    localparam integer WORDS     = 153600;
    localparam integer ROW_WORDS = 320;
    localparam integer BLOCK     = 64;
    localparam integer BLOCKS    = WORDS/BLOCK;
    localparam [31:0]  SLOT1     = 32'h000A_0000;

    reg clk = 0; always #12.5 clk = ~clk;
    reg rst_n = 0;


    wire        mem_req, mem_wr, mem_ready, mem_rvalid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;
    wire        wr_ack, wr_busy, rd_ack, rd_busy, rd_data_valid;
    wire [31:0] rd_data;
    wire        sd_ack, sd_busy, sd_rdata_valid;
    wire [31:0] sd_rdata;
    reg  [15:0] video_level = 16'd3500;

    reg         wr_req = 0; reg [31:0] wr_addr = 0, wr_data = 0;
    wire [15:0] wr_len = 16'd1;
    reg         sd_req = 0; wire sd_wr = 1'b0;
    reg  [31:0] sd_addr = 0; reg [15:0] sd_len = BLOCK; wire [31:0] sd_wdata = 0;


    localparam [31:0] SLOT0 = 32'h0000_0000;
    reg         d_req = 0; reg [31:0] d_addr = 0;
    wire [15:0] d_len = BLOCK;
    integer     dblk = 0, dk;
    initial begin
        @(posedge rst_n);
        forever begin
            @(posedge clk);
            d_addr = SLOT0 + dblk*BLOCK*4; d_req = 1'b1;
            while (!rd_ack) @(posedge clk);
            d_req = 1'b0;
            for (dk = 0; dk < BLOCK; dk = dk + 1) begin
                @(posedge clk);
                while (!rd_data_valid) @(posedge clk);
            end
            while (rd_busy) @(posedge clk);
            dblk = (dblk + 1) % BLOCKS;
            repeat (200) @(posedge clk);
        end
    end

    memory_arbiter #(.MAX_BURSTS(4),.STARVE_LIMIT(64),.COMPACT_CONSEC_COUNTER(1),
                     .HIGH_WATER(16'd3600),.CRITICAL_WATER(16'd3000)) arb(
        .clk(clk), .rst_n(rst_n), .video_fifo_level(video_level),
        .rd_req(d_req), .rd_addr(d_addr), .rd_len(d_len),
        .rd_ack(rd_ack), .rd_busy(rd_busy), .rd_data(rd_data), .rd_data_valid(rd_data_valid),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ack(wr_ack), .wr_busy(wr_busy),
        .sd_req(sd_req), .sd_wr(sd_wr), .sd_addr(sd_addr), .sd_wdata(sd_wdata), .sd_len(sd_len),
        .sd_ack(sd_ack), .sd_busy(sd_busy), .sd_rdata(sd_rdata), .sd_rdata_valid(sd_rdata_valid),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb), .mem_ready(mem_ready), .mem_rdata(mem_rdata),
        .mem_rdata_valid(mem_rvalid), .wr_starve_cnt(), .rd_starve_cnt());


    wire        a_req, a_wr, a_ready, a_rvalid, a_init, mem_error;
    wire [31:0] a_addr, a_wdata, a_rdata;
    wire [3:0]  a_wstrb;
    mem_ctrl memory(.clk(clk), .rst_n(rst_n), .init_done(),
        .req(mem_req), .wr(mem_wr), .addr(mem_addr), .wdata(mem_wdata), .wstrb(mem_wstrb),
        .rdata(mem_rdata), .rdata_valid(mem_rvalid), .ready(mem_ready), .mem_error(mem_error),
        .sdram_req(a_req), .sdram_wr(a_wr), .sdram_addr(a_addr), .sdram_wdata(a_wdata),
        .sdram_wstrb(a_wstrb), .sdram_rdata(a_rdata), .sdram_rdata_valid(a_rvalid),
        .sdram_ready(a_ready), .sdram_init_done(a_init));


    wire        s_init, s_refvld, s_busy, a_widle, a_pfault;
    wire        aw_en, ar_en, s_rd_en;
    wire [20:0] aw_addr, ar_addr;
    wire [3:0]  aw_dm;
    wire [31:0] aw_din, s_rd_dout;
    sdram_app_adapter #(.FAST_READ(1),.PREFETCH_READ(1)) adapter(
        .clk(clk), .rst_n(rst_n), .req(a_req), .wr(a_wr), .addr(a_addr),
        .wdata(a_wdata), .wstrb(a_wstrb), .rdata(a_rdata), .rdata_valid(a_rvalid),
        .ready(a_ready), .init_done(a_init), .write_idle(a_widle), .protocol_fault(a_pfault),
        .Sdr_init_done(s_init), .Sdr_init_ref_vld(s_refvld), .Sdr_busy(s_busy),
        .App_wr_en(aw_en), .App_wr_addr(aw_addr), .App_wr_dm(aw_dm), .App_wr_din(aw_din),
        .App_rd_en(ar_en), .App_rd_addr(ar_addr), .Sdr_rd_en(s_rd_en), .Sdr_rd_dout(s_rd_dout));


    sdram #(.RD_LAT(11)) u_sdram(.Clk(clk), .Clk_sft(clk), .Rst(~rst_n),
        .Sdr_init_done(s_init), .Sdr_init_ref_vld(s_refvld), .Sdr_busy(s_busy),
        .App_wr_en(aw_en), .App_wr_addr(aw_addr), .App_wr_dm(aw_dm), .App_wr_din(aw_din),
        .App_rd_en(ar_en), .App_rd_addr(ar_addr), .Sdr_rd_en(s_rd_en), .Sdr_rd_dout(s_rd_dout));


    function [31:0] dataof(input [31:0] a);
        begin dataof = (a * 32'd2654435761) + 32'd1013904223;
     end endfunction

    reg [31:0] shadow [0:400000];

    integer errors = 0;
    integer wr_words = 0, rd_blocks = 0, rd_words = 0;


    task write_word(input [31:0] a);
        begin begin
            wr_addr = a; wr_data = dataof(a); wr_req = 1'b1;
            @(posedge clk);
            while (!(wr_busy && mem_req && mem_wr && mem_ready)) @(posedge clk);
            wr_req = 1'b0;
            @(posedge clk);
            wr_words = wr_words + 1;
        end
     end endtask


    reg [31:0] got [0:BLOCK-1];
    integer bi, k, first_bad_block, bad_word;
    reg [31:0] bad_got, bad_exp;

    task read_block(input [31:0] a);
        begin begin
            sd_addr = a; sd_len = BLOCK; sd_req = 1'b1;
            @(posedge clk);
            while (!sd_ack) @(posedge clk);
            sd_req = 1'b0;
            for (k = 0; k < BLOCK; k = k + 1) begin
                @(posedge clk);
                while (!sd_rdata_valid) @(posedge clk);
                got[k] = sd_rdata;
            end
            while (sd_busy) @(posedge clk);
        end
     end endtask

    integer n;
    reg [31:0] cur;
    integer col;

    initial begin
        first_bad_block = -1; bad_word = -1;
        rst_n = 0; repeat (20) @(posedge clk); rst_n = 1;
        repeat (200) @(posedge clk);


        cur = SLOT1 + (WORDS-ROW_WORDS)*4; col = 0;
        for (n = 0; n < WORDS; n = n + 1) begin
            shadow[cur >> 2] = dataof(cur);
            if (col == ROW_WORDS-1) begin col = 0; cur = cur - ROW_WORDS*8 + 4; end
            else                    begin col = col + 1; cur = cur + 4; end
        end


        $display("[TB] writing %0d words ...", WORDS);
        cur = SLOT1 + (WORDS-ROW_WORDS)*4; col = 0;
        for (n = 0; n < WORDS; n = n + 1) begin
            write_word(cur);
            if (col == ROW_WORDS-1) begin col = 0; cur = cur - ROW_WORDS*8 + 4; end
            else                    begin col = col + 1; cur = cur + 4; end
        end

        while (!(a_widle && !wr_busy)) @(posedge clk);
        repeat (20) @(posedge clk);
        $display("[TB] write done: %0d words, adapter write_idle=%0d", wr_words, a_widle);


        for (bi = 0; bi < BLOCKS; bi = bi + 1) begin
            read_block(SLOT1 + bi*BLOCK*4);
            rd_blocks = rd_blocks + 1;
            for (k = 0; k < BLOCK; k = k + 1) begin
                rd_words = rd_words + 1;
                if (got[k] !== shadow[(SLOT1>>2) + bi*BLOCK + k]) begin
                    if (first_bad_block < 0) begin
                        first_bad_block = bi; bad_word = k;
                        bad_got = got[k];
                        bad_exp = shadow[(SLOT1>>2) + bi*BLOCK + k];
                    end
                end
            end
        end

        $display("");
        $display("=================================================");
        $display("  MEMORY ROUND-TRIP  (arbiter+mem_ctrl+adapter+model)");
        $display("  words written   = %0d (expect %0d)", wr_words, WORDS);
        $display("  blocks read     = %0d (expect %0d)", rd_blocks, BLOCKS);
        $display("  words read      = %0d", rd_words);
        $display("  protocol_fault  = %0d  mem_error = %0d", a_pfault, mem_error);
        if (first_bad_block < 0)
            $display("  RESULT: PASS - every written word read back identical");
        else begin
            $display("  RESULT: FAIL - first mismatch at block %0d word %0d", first_bad_block, bad_word);
            $display("          addr= %08X  got= %08X  exp= %08X",
                     SLOT1 + first_bad_block*BLOCK*4 + bad_word*4, bad_got, bad_exp);
        end
        $display("=================================================");
        $finish;
    end


    initial begin
        #2_000_000_000;
        $display("[TB] WATCHDOG: still running at %0d ns (wr_words=%0d rd_blocks=%0d)",
                 $time, wr_words, rd_blocks);
        $finish;
    end
endmodule
