


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_ab_storage_contract;


    reg clk_sys = 1'b0;  always #5.0    clk_sys = ~clk_sys;
    reg clk_mem = 1'b0;  always #4.0    clk_mem = ~clk_mem;
    reg clk_pix = 1'b0;  always #6.734  clk_pix = ~clk_pix;

    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end

     end endtask


    wire        rd_req;
    reg  [31:0] rd_addr = 32'd0;
    reg  [15:0] rd_len  = 16'd64;
    wire        rd_ack, rd_busy, rd_data_valid;
    wire [31:0] rd_data;

    reg  [15:0] fifo_level = 16'd0;


    wire        mem_req, mem_wr;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg         mem_ready = 1'b1;
    reg  [31:0] mem_rdata = 32'd0;
    reg         mem_rdata_valid = 1'b0;

    integer mcyc = 0;
    always @(posedge clk_mem) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 23) != 0);
    end


    reg [2:0] rv_pipe = 3'd0;
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            rv_pipe <= 3'd0; mem_rdata_valid <= 1'b0; mem_rdata <= 32'd0;
        end else begin
            rv_pipe         <= {rv_pipe[1:0], (mem_req && mem_ready && !mem_wr)};
            mem_rdata_valid <= rv_pipe[2];
            if (rv_pipe[2]) mem_rdata <= 32'hA5A5_0000 + {16'b0, mem_addr[15:0]};
        end
    end

    memory_arbiter #(.MAX_BURSTS(4), .STARVE_LIMIT(64)) u_arb (
        .clk              (clk_mem),
        .rst_n            (rst_n),
        .video_fifo_level (fifo_level),
        .rd_req           (rd_req),
        .rd_addr          (rd_addr),
        .rd_len           (rd_len),
        .rd_ack           (rd_ack),
        .rd_busy          (rd_busy),
        .rd_data          (rd_data),
        .rd_data_valid    (rd_data_valid),
        .wr_req           (1'b0),
        .wr_addr          (32'd0),
        .wr_data          (32'd0),
        .wr_len           (16'd0),
        .wr_ack           (),
        .wr_busy          (),
        .sd_req           (1'b0),
        .sd_wr            (1'b0),
        .sd_addr          (32'd0),
        .sd_wdata         (32'd0),
        .sd_len           (16'd0),
        .sd_ack           (),
        .sd_busy          (),
        .sd_rdata         (),
        .sd_rdata_valid   (),
        .mem_req          (mem_req),
        .mem_wr           (mem_wr),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_wstrb        (mem_wstrb),
        .mem_ready        (mem_ready),
        .mem_rdata        (mem_rdata),
        .mem_rdata_valid  (mem_rdata_valid),
        .wr_starve_cnt    (),
        .rd_starve_cnt    ()
    );


    localparam integer N_RD_BURST = 6;
    reg              rd_req_r = 1'b0;
    integer          bursts_sent = 0;
    integer          rd_base = 32'h0000_1000;
    assign rd_req = rd_req_r;

    always @(posedge clk_mem) begin
        if (!rst_n) begin
            rd_req_r <= 1'b0;
        end else if (bursts_sent < N_RD_BURST) begin
            if (!rd_req_r && !rd_busy) begin
                rd_req_r <= 1'b1;
                rd_addr  <= rd_base + bursts_sent * 256;
                rd_len   <= 16'd64;
            end else if (rd_ack) begin
                rd_req_r <= 1'b0;
                bursts_sent = bursts_sent + 1;
            end
        end else begin
            rd_req_r <= 1'b0;
        end
    end


    integer ack_multi = 0;
    integer len_bad   = 0;
    integer vcnt_bad  = 0;
    integer v_wo_busy = 0;
    integer step_bad  = 0;
    integer bursts_done = 0;

    reg        ack_d = 1'b0;
    reg        in_burst = 1'b0;
    integer    vcnt = 0;
    reg        have_last = 1'b0;
    reg [31:0] last_maddr = 32'd0;

    always @(posedge clk_mem) begin
        if (!rst_n) begin
            ack_d <= 1'b0; in_burst <= 1'b0; vcnt <= 0; have_last <= 1'b0;
        end else begin
            ack_d <= rd_ack;


            if (rd_ack && ack_d) ack_multi = ack_multi + 1;


            if (rd_req && (rd_len !== 16'd64)) len_bad = len_bad + 1;


            if (rd_data_valid && !rd_busy) v_wo_busy = v_wo_busy + 1;


            if (rd_ack) begin
                in_burst <= 1'b1;
                vcnt     <= 0;
            end else if (rd_data_valid && in_burst) begin
                vcnt <= vcnt + 1;
            end else if (in_burst && !rd_busy) begin

                in_burst <= 1'b0;
                if (vcnt !== 64) vcnt_bad = vcnt_bad + 1;
                bursts_done = bursts_done + 1;
            end


            if (mem_req && mem_ready && !mem_wr) begin
                if (have_last && (mem_addr !== (last_maddr + 32'd4))) step_bad = step_bad + 1;
                last_maddr <= mem_addr;
                have_last  <= 1'b1;
            end
            if (!rd_busy) have_last <= 1'b0;
        end
    end


    reg         frame_ready = 1'b0;
    reg  [1:0]  wr_slot     = 2'd0;
    reg  [7:0]  wr_gen      = 8'd0;
    reg         wr_fidx     = 1'b0;
    reg         wr_crc      = 1'b1;

    wire        swap_req, mb_fidx, mb_crc, swap_error, active_commit;
    wire [1:0]  mb_slot, active_next;
    wire [7:0]  mb_gen, gen_next;
    wire        fs_evt_b, ack_evt_b;

    frame_swap_ctrl #(.TIMEOUT_N(32'd4000)) u_swap (
        .clk              (clk_sys),
        .rst_n            (rst_n),
        .frame_ready      (frame_ready),
        .wr_frame_index   (wr_fidx),
        .wr_slot_id       (wr_slot),
        .wr_generation    (wr_gen),
        .wr_crc_ok        (wr_crc),
        .frame_start      (fs_evt_b),
        .swap_ack         (ack_evt_b),
        .swap_req         (swap_req),
        .frame_index      (mb_fidx),
        .slot_id          (mb_slot),
        .generation       (mb_gen),
        .crc_ok           (mb_crc),
        .swap_error       (swap_error),
        .active_commit    (active_commit),
        .active_next      (active_next),
        .generation_next  (gen_next),
        .frame_index_next (),
        .state_o          ()
    );

    wire req_evt_a, mb_valid_a, mb_crc_a;
    wire [1:0] mb_slot_a;
    wire [7:0] mb_gen_a;
    wire       frame_start_a, swap_ack_a;

    frame_swap_cdc u_cdc (
        .clk_b              (clk_sys),
        .rst_b_n            (rst_n),
        .swap_req_b         (swap_req),
        .mb_frame_index_b   (mb_fidx),
        .mb_slot_id_b       (mb_slot),
        .mb_generation_b    (mb_gen),
        .mb_crc_ok_b        (mb_crc),
        .frame_start_evt_b  (fs_evt_b),
        .swap_ack_evt_b     (ack_evt_b),
        .clk_a              (clk_pix),
        .rst_a_n            (rst_n),
        .swap_req_evt_a     (req_evt_a),
        .swap_req_lvl_a     (),
        .mb_frame_index_a   (),
        .mb_slot_id_a       (mb_slot_a),
        .mb_generation_a    (mb_gen_a),
        .mb_crc_ok_a        (mb_crc_a),
        .mb_valid_a         (mb_valid_a),
        .frame_start_a      (frame_start_a),
        .swap_ack_a         (swap_ack_a)
    );


    reg [3:0] a_st = 4'd0;
    reg       ack_tgl = 1'b0;
    reg       fs_pulse = 1'b0;
    integer   a_req_seen = 0;
    integer   a_acks     = 0;

    always @(posedge clk_pix) begin
        if (!rst_n) begin
            a_st <= 4'd0; ack_tgl <= 1'b0; fs_pulse <= 1'b0;
        end else begin
            fs_pulse <= 1'b0;
            case (a_st)
                4'd0: if (req_evt_a) begin a_req_seen = a_req_seen + 1; a_st <= 4'd4; end
                4'd4: a_st <= 4'd3;
                4'd3: a_st <= 4'd2;
                4'd2: a_st <= 4'd1;
                4'd1: begin fs_pulse <= 1'b1; a_st <= 4'd5; end
                4'd5: a_st <= 4'd6;
                4'd6: begin ack_tgl <= ~ack_tgl; a_acks = a_acks + 1; a_st <= 4'd0; end
                default: a_st <= 4'd0;
            endcase
        end
    end
    assign frame_start_a = fs_pulse;
    assign swap_ack_a    = ack_tgl;


    integer   req_toggles = 0;
    integer   commits     = 0;
    integer   fs_multi    = 0;
    integer   ack_multi_b = 0;
    reg       swap_req_d  = 1'b0;
    reg       fs_d        = 1'b0;
    reg       ackb_d      = 1'b0;
    reg       cmt_d       = 1'b0;

    always @(posedge clk_sys) begin
        if (!rst_n) begin
            swap_req_d <= 1'b0; fs_d <= 1'b0; ackb_d <= 1'b0; cmt_d <= 1'b0;
        end else begin
            swap_req_d <= swap_req;
            fs_d       <= fs_evt_b;
            ackb_d     <= ack_evt_b;
            cmt_d      <= active_commit;
            if (swap_req !== swap_req_d) req_toggles = req_toggles + 1;
            if (fs_evt_b  && fs_d)       fs_multi    = fs_multi + 1;
            if (ack_evt_b && ackb_d)     ack_multi_b = ack_multi_b + 1;
            if (active_commit && !cmt_d) commits = commits + 1;
        end
    end


    localparam integer N_SWAP = 5;
    integer i;
    integer toggles_before_crc;

    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;


        wait (bursts_done >= N_RD_BURST);
        #200;

        check(len_bad   == 0, "T1 rd_len 恒为契约值 64");
        check(ack_multi == 0, "T2 rd_ack 是单拍（无连续两拍）");
        check(vcnt_bad  == 0, "T3 每个突发的 rd_data_valid 计数 == rd_len");
        check(v_wo_busy == 0, "T4 rd_data_valid 只在 rd_busy 期间出现");
        check(step_bad  == 0, "T5 突发内 mem_addr 每次 +4（字节地址）");
        check(bursts_done == N_RD_BURST, "T5b 全部读突发都完成（不多不少）");


        for (i = 0; i < N_SWAP; i = i + 1) begin
            @(negedge clk_sys);
            wr_slot = (i + 1) % 4;
            wr_gen  = 8'h10 + i;
            wr_fidx = i[0];
            wr_crc  = 1'b1;
            frame_ready = 1'b1;
            @(negedge clk_sys);
            frame_ready = 1'b0;

            wait (commits == (i + 1));
            repeat (40) @(negedge clk_sys);
        end

        check(a_req_seen == N_SWAP, "T6a A 侧恰好看到 N 次请求事件（不重不漏）");
        check(a_acks     == N_SWAP, "T6b A 侧恰好回了 N 次 ack");
        check(commits    == N_SWAP, "T6c B 侧恰好提交 N 次（CDC 往返恰好一次）");
        check(req_toggles== N_SWAP, "T6d swap_req 恰好翻转 N 次（toggle 电平，非脉冲）");
        check(swap_error == 1'b0,   "T6e 无握手超时（swap_error 恒 0）");
        check(fs_multi   == 0,      "T6f frame_start_evt_b 是单拍");
        check(ack_multi_b== 0,      "T6g swap_ack_evt_b 是单拍");


        toggles_before_crc = req_toggles;
        @(negedge clk_sys);
        wr_slot = 2'd2;
        wr_gen  = 8'h99;
        wr_fidx = 1'b1;
        wr_crc  = 1'b0;
        frame_ready = 1'b1;
        @(negedge clk_sys);
        frame_ready = 1'b0;
        repeat (200) @(negedge clk_sys);

        check(req_toggles == toggles_before_crc, "T7a 无效 CRC：swap_req 不翻转");
        check(commits     == N_SWAP,             "T7b 无效 CRC：不产生 active_commit");
        check(swap_error  == 1'b0,               "T7c 无效 CRC：不报握手超时");

        $display("[TB] tb_ab_storage_contract done, errors=%0d (bursts=%0d rd_words_ok=%0d req=%0d acks=%0d commits=%0d toggles=%0d)",
                 errors, bursts_done, N_RD_BURST - vcnt_bad, a_req_seen, a_acks, commits, req_toggles);
        $finish;
    end


    initial begin
        #400_000;
        $display("[FAIL] tb_ab_storage_contract 看门狗超时（bursts_done=%0d commits=%0d a_req=%0d）",
                 bursts_done, commits, a_req_seen);
        $finish;
    end

endmodule
