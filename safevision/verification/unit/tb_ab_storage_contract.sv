// ============================================================================
// tb_ab_storage_contract.sv — A↔B 存储侧接口的【契约守门】TB（B 侧 · ModelSim）
// ----------------------------------------------------------------------------
// 依据：docs/B链-整机集成-存储侧接线表.md（§2 读口 / §3 交换口 / §4 时序语义 / §5 不该做什么）
//       对应 interface_spec v1.34「A 阶段11–15补充契约」+ v1.35 的 B 侧应答
//
// ★★ 本 TB 的定位（**不要和 A 的 TB 搞混**）
//   · A 的 `tb_a_video_display_core.sv`（跑在 **XSim**）= **端到端真实集成**：
//     A 的真实 core + B 的真实 arbiter/swap_ctrl，验像素正确性、欠流、应急、换槽。
//     ★ 本机**没装 Vivado/XSim**，所以那条 TB 只能在 A 的机器上跑。
//   · **本 TB（ModelSim，本机可跑）= 契约守门**：用**符合契约的驱动模型**驱动 B 的模块，
//     只断言"接线表里写下的那几条承诺" —— 这是 **B 侧的责任边界**。
//     驱动模型严格按接线表 §4 的语义写，所以它验的是"B 兑现了承诺"，不是"B 与 A 联调成功"。
//
// ★★ 为什么需要它（现有 TB 的真空，已核对过）
//   `tb_frame_swap_ctrl.sv` 已经验了：状态序列 / 两类超时进 SAFE / 原子切换 /
//     payload 在 req 翻转前稳定 / ack 前 payload 不变 / swap_req 保持电平。
//   `tb_memory_arbiter.sv`  已经验了：突发数上限 / 防饥饿计数 / 持续供数。
//   ⇒ **仍然没人守的 7 条**（本 TB 补的）：
//     T1  `rd_len` 恒为契约值 64
//     T2  `rd_ack` 是**单拍**（不连续两拍）
//     T3  每个突发的 `rd_data_valid` 计数**恰好等于** `rd_len`
//     T4  `rd_data_valid` 只在 `rd_busy` 期间出现
//     T5  `rd_addr` 是**字节**地址：突发内 `mem_addr` 每次 **+4**
//     T6  ★ **CDC 往返"恰好一次"**：连续 N 次换帧，B 侧每次 `swap_req` 翻转
//         都**有且仅有一次** `swap_ack` 事件回到 B（这正是"A 警告的再次转 toggle"会破坏的性质）
//     T7  ★ **无效 CRC 不提交、不 ACK**：`wr_crc_ok=0` 时 `swap_req` 不翻转、`active_commit` 不产生
//         （现有 TB 里 `wr_crc` **恒为 1**，这条分支从没被跑过）
//
// ★ 不能证明什么：不验 SDRAM 物理层、不验 A 的真实 core、不验像素正确性
//   ⇒ 那三项分别由 A 的 XSim TB / 板级实测覆盖。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_ab_storage_contract;

    // ------------------------------------------------------------------------
    // 三个时钟域（与整机一致）
    // ------------------------------------------------------------------------
    reg clk_sys = 1'b0;  always #5.0    clk_sys = ~clk_sys;   // 100 MHz
    reg clk_mem = 1'b0;  always #4.0    clk_mem = ~clk_mem;   // 125 MHz
    reg clk_pix = 1'b0;  always #6.734  clk_pix = ~clk_pix;   // 74.25 MHz

    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ========================================================================
    // Part A：存储器读口（mem_clk 域）—— 契约 T1~T5
    // ========================================================================
    wire        rd_req;
    reg  [31:0] rd_addr = 32'd0;
    reg  [15:0] rd_len  = 16'd64;
    wire        rd_ack, rd_busy, rd_data_valid;
    wire [31:0] rd_data;

    reg  [15:0] fifo_level = 16'd0;          // 像素 FIFO 水位（本 TB 不驱动水位策略）

    // ---- mem_ctrl 行为模型：读命令延迟 3 拍回一个 word；ready 偶尔拉低 ----
    wire        mem_req, mem_wr;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg         mem_ready = 1'b1;
    reg  [31:0] mem_rdata = 32'd0;
    reg         mem_rdata_valid = 1'b0;

    integer mcyc = 0;
    always @(posedge clk_mem) begin
        mcyc <= mcyc + 1;
        mem_ready <= ((mcyc % 23) != 0);       // 周期性忙，逼出 busy 覆盖
    end

    // ★ 读响应用【移位流水】：每个被受理的读命令打 3 拍后产生一个 data_valid。
    //   （初版写成"收到命令就把计数器重置成 3"，连续读时永远倒不到 0
    //     ⇒ data_valid 一个都不产生 ⇒ 响应收不齐 ⇒ rd_busy 永不落下。已订正。）
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

    // ---- A 侧读驱动模型（严格按接线表 §4：req 保持到 ack、突发之间不重叠）----
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
                rd_addr  <= rd_base + bursts_sent * 256;   // 字节地址，每突发 256 B = 64 word
                rd_len   <= 16'd64;                        // ★ 契约默认值
            end else if (rd_ack) begin
                rd_req_r <= 1'b0;
                bursts_sent = bursts_sent + 1;
            end
        end else begin
            rd_req_r <= 1'b0;
        end
    end

    // ---- 契约监视（T1~T5）----
    integer ack_multi = 0;        // rd_ack 连续两拍
    integer len_bad   = 0;        // rd_len != 64
    integer vcnt_bad  = 0;        // 突发内 data_valid 计数 != rd_len
    integer v_wo_busy = 0;        // data_valid 出现在 busy 之外
    integer step_bad  = 0;        // mem_addr 不是 +4
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

            // T2：rd_ack 必须是单拍
            if (rd_ack && ack_d) ack_multi = ack_multi + 1;

            // T1：rd_len 必须是契约值 64（req 有效期间）
            if (rd_req && (rd_len !== 16'd64)) len_bad = len_bad + 1;

            // T4：data_valid 只能出现在 busy 期间
            if (rd_data_valid && !rd_busy) v_wo_busy = v_wo_busy + 1;

            // T3：按突发统计 data_valid
            if (rd_ack) begin
                in_burst <= 1'b1;
                vcnt     <= 0;
            end else if (rd_data_valid && in_burst) begin
                vcnt <= vcnt + 1;
            end else if (in_burst && !rd_busy) begin
                // busy 落下的那一拍：上一拍已经把最后一个 valid 计进去了
                in_burst <= 1'b0;
                if (vcnt !== 64) vcnt_bad = vcnt_bad + 1;
                bursts_done = bursts_done + 1;
            end

            // T5：突发内 mem_addr 每次 +4（字节地址）
            if (mem_req && mem_ready && !mem_wr) begin
                if (have_last && (mem_addr !== (last_maddr + 32'd4))) step_bad = step_bad + 1;
                last_maddr <= mem_addr;
                have_last  <= 1'b1;
            end
            if (!rd_busy) have_last <= 1'b0;
        end
    end

    // ========================================================================
    // Part B：帧交换口（sys_clk ↔ pixel_clk，CDC 真接上）—— 契约 T6/T7
    // ========================================================================
    reg         frame_ready = 1'b0;
    reg  [1:0]  wr_slot     = 2'd0;
    reg  [7:0]  wr_gen      = 8'd0;
    reg         wr_fidx     = 1'b0;
    reg         wr_crc      = 1'b1;      // ★ 可控：用来测"无效 CRC 不提交不 ACK"

    wire        swap_req, mb_fidx, mb_crc, swap_error, active_commit;
    wire [1:0]  mb_slot, active_next;
    wire [7:0]  mb_gen, gen_next;
    wire        fs_evt_b, ack_evt_b;     // A → B（单拍）

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

    // ---- A 侧（像素域）行为模型：收到 req 事件 → 等几拍 → frame_start 单拍 → 再 toggle ack ----
    //   严格对应接线表 §4 第 9/10 条与 A 的契约（"A 仅在原始垂直消隐更新并回 ack"）。
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
                4'd1: begin fs_pulse <= 1'b1; a_st <= 4'd5; end        // frame_start 单拍
                4'd5: a_st <= 4'd6;
                4'd6: begin ack_tgl <= ~ack_tgl; a_acks = a_acks + 1; a_st <= 4'd0; end  // toggle
                default: a_st <= 4'd0;
            endcase
        end
    end
    assign frame_start_a = fs_pulse;
    assign swap_ack_a    = ack_tgl;

    // ---- 监视：swap_req 的翻转次数 / 提交次数 / 两个 evt 是否单拍 ----
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
            if (fs_evt_b  && fs_d)       fs_multi    = fs_multi + 1;    // 单拍检查
            if (ack_evt_b && ackb_d)     ack_multi_b = ack_multi_b + 1; // 单拍检查
            if (active_commit && !cmt_d) commits = commits + 1;
        end
    end

    // ========================================================================
    // 主流程
    // ========================================================================
    localparam integer N_SWAP = 5;
    integer i;
    integer toggles_before_crc;

    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        // ---- 等 Part A 的读突发全部完成 ----
        wait (bursts_done >= N_RD_BURST);
        #200;

        check(len_bad   == 0, "T1 rd_len 恒为契约值 64");
        check(ack_multi == 0, "T2 rd_ack 是单拍（无连续两拍）");
        check(vcnt_bad  == 0, "T3 每个突发的 rd_data_valid 计数 == rd_len");
        check(v_wo_busy == 0, "T4 rd_data_valid 只在 rd_busy 期间出现");
        check(step_bad  == 0, "T5 突发内 mem_addr 每次 +4（字节地址）");
        check(bursts_done == N_RD_BURST, "T5b 全部读突发都完成（不多不少）");

        // ---- Part B：连续 N_SWAP 次换帧，验 CDC 往返"恰好一次" ----
        for (i = 0; i < N_SWAP; i = i + 1) begin
            @(negedge clk_sys);
            wr_slot = (i + 1) % 4;
            wr_gen  = 8'h10 + i;
            wr_fidx = i[0];
            wr_crc  = 1'b1;
            frame_ready = 1'b1;
            @(negedge clk_sys);
            frame_ready = 1'b0;
            // 等这次握手走完（回到 IDLE 且提交过）
            wait (commits == (i + 1));
            repeat (40) @(negedge clk_sys);       // 留出 CDC 往返余量
        end

        check(a_req_seen == N_SWAP, "T6a A 侧恰好看到 N 次请求事件（不重不漏）");
        check(a_acks     == N_SWAP, "T6b A 侧恰好回了 N 次 ack");
        check(commits    == N_SWAP, "T6c B 侧恰好提交 N 次（CDC 往返恰好一次）");
        check(req_toggles== N_SWAP, "T6d swap_req 恰好翻转 N 次（toggle 电平，非脉冲）");
        check(swap_error == 1'b0,   "T6e 无握手超时（swap_error 恒 0）");
        check(fs_multi   == 0,      "T6f frame_start_evt_b 是单拍");
        check(ack_multi_b== 0,      "T6g swap_ack_evt_b 是单拍");

        // ---- Part C：无效 CRC 不提交、不 ACK ----
        toggles_before_crc = req_toggles;
        @(negedge clk_sys);
        wr_slot = 2'd2;
        wr_gen  = 8'h99;
        wr_fidx = 1'b1;
        wr_crc  = 1'b0;                            // ★ 无效 CRC
        frame_ready = 1'b1;
        @(negedge clk_sys);
        frame_ready = 1'b0;
        repeat (200) @(negedge clk_sys);           // 给足时间，若会误触发早就触发了

        check(req_toggles == toggles_before_crc, "T7a 无效 CRC：swap_req 不翻转");
        check(commits     == N_SWAP,             "T7b 无效 CRC：不产生 active_commit");
        check(swap_error  == 1'b0,               "T7c 无效 CRC：不报握手超时");

        $display("[TB] tb_ab_storage_contract done, errors=%0d (bursts=%0d rd_words_ok=%0d req=%0d acks=%0d commits=%0d toggles=%0d)",
                 errors, bursts_done, N_RD_BURST - vcnt_bad, a_req_seen, a_acks, commits, req_toggles);
        $finish;
    end

    // 看门狗
    initial begin
        #400_000;
        $display("[FAIL] tb_ab_storage_contract 看门狗超时（bursts_done=%0d commits=%0d a_req=%0d）",
                 bursts_done, commits, a_req_seen);
        $finish;
    end

endmodule
