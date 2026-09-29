// ============================================================================
// tb_frame_swap_ctrl.sv — 阶段 B/C1/C2：双缓冲 · 帧交换握手 · 跨域
// ----------------------------------------------------------------------------
// 被测：
//   rtl/memory/frame_buffer_manager.v   （冻结地址表 / active 原子切换）
//   rtl/memory/frame_swap_ctrl.v        （交换握手 FSM + 超时保护）
//   rtl/memory/frame_swap_cdc.v         （B 域 -> A 域 payload 跨域）
//   （对应蓝图 verification/unit/tb_frame_swap_ctrl.sv）
//
// 依据：
//   设计手册 7.14（帧交换握手与原子切换）/ 7.15（跨域 payload 稳定性）。
//
// 覆盖的 23 项断言要点：
//   B  FBM：冻结地址表 IMG0..IMG3 / line_stride + frame_bytes / 查表口 / slot_valid 置位（4 项）
//   B  SWAP：状态序列 IDLE->WAIT_VBLANK->COMMIT->WAIT_ACK / 回到 IDLE / 无超时错误 /
//            active_slot 原子切换 + 基地址 + generation 更新 / 只在 frame_start 那拍改 /
//            swap_req 发生翻转 / swap_req 保持电平（toggle 非单拍）（7 项）
//   B  CDC：mailbox 载荷被 A 侧捕获 / payload 在 req 翻转前已稳定 /
//           ack 之前 payload 未被修改（3 项）
//   C1 TIMEOUT：无 frame_start -> swap_error 拉高 / 进入 SAFE /
//               当前显示块保持为 0 / 超时后持续保持（4 项）
//   C2 TIMEOUT2：无 swap_ack -> swap_error 拉高 / 提交已生效（槽 3）/
//                超时后显示块不变并停在 SAFE（3 项）
//   合计 23 项。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_frame_swap_ctrl;

    // ------------------------------------------------------------------
    // 时钟 / 复位
    // ------------------------------------------------------------------
    reg clk_b = 1'b0;          // sys_clk / mem_clk 100MHz
    reg clk_a = 1'b0;          // pixel_clk 25MHz
    always #5  clk_b = ~clk_b;
    always #20 clk_a = ~clk_a;

    reg rst_b_n   = 1'b0;
    reg rst_a_n   = 1'b0;

    integer passes = 0;
    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                passes = passes + 1;
                $display("[PASS] %0s", name);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // 状态编码（与 frame_swap_ctrl 一致，供 TB 断言用）
    // ------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0, S_REQ = 3'd1, S_WAIT_VBLANK = 3'd2,
                     S_COMMIT = 3'd3, S_WAIT_ACK = 3'd4, S_SAFE = 3'd5;

    // ==================================================================
    // 一、帧缓存 / 帧交换 / 跨域
    // ==================================================================
    reg         frame_ready = 1'b0;
    reg         wr_fidx     = 1'b0;
    reg  [1:0]  wr_slot     = 2'd0;
    reg  [7:0]  wr_gen      = 8'd0;
    reg         wr_crc      = 1'b1;

    wire        swap_req;
    wire        swap_error;
    wire [1:0]  mb_slot;
    wire [7:0]  mb_gen;
    wire        mb_fidx, mb_crc;
    wire [2:0]  state_o;

    wire        active_commit;
    wire [1:0]  active_next;
    wire [7:0]  gen_next;
    wire        fidx_next;

    wire        fs_evt_b, ack_evt_b;
    wire        req_evt_a, mb_fidx_a, mb_crc_a, mb_valid_a;
    wire [1:0]  mb_slot_a;
    wire [7:0]  mb_gen_a;

    reg         frame_start_a = 1'b0;
    reg         swap_ack_a    = 1'b0;

    // FBM 装载口
    reg  [1:0]  wr_slot_sel  = 2'd0;
    reg         wr_slot_set  = 1'b0;
    reg         slot_valid_set = 1'b0;
    reg  [1:0]  slot_valid_id  = 2'd0;
    reg         slot_valid_clr = 1'b0;
    reg  [1:0]  sel_slot = 2'd0;

    wire [1:0]  active_slot, write_slot;
    wire [3:0]  slot_valid;
    wire        fbm_frame_index;
    wire [7:0]  fbm_generation;
    wire [31:0] active_slot_base, slot_base_o;
    wire [31:0] slot_base0, slot_base1, slot_base2, slot_base3, line_stride, frame_bytes;

    frame_buffer_manager u_fbm (
        .clk(clk_b), .rst_n(rst_b_n),
        .wr_slot_sel(wr_slot_sel), .wr_slot_set(wr_slot_set),
        .slot_valid_set(slot_valid_set), .slot_valid_id(slot_valid_id), .slot_valid_clr(slot_valid_clr),
        .active_commit(active_commit), .active_next(active_next),
        .generation_in(gen_next), .frame_index_in(fidx_next),
        .sel_slot(sel_slot), .slot_base_o(slot_base_o),
        .active_slot(active_slot), .write_slot(write_slot), .slot_valid(slot_valid),
        .frame_index(fbm_frame_index), .generation(fbm_generation),
        .active_slot_base(active_slot_base),
        .slot_base0(slot_base0), .slot_base1(slot_base1), .slot_base2(slot_base2),
        .slot_base3(slot_base3), .line_stride(line_stride), .frame_bytes(frame_bytes)
    );

    frame_swap_ctrl #(.TIMEOUT_N(32'd64)) u_swap (
        .clk(clk_b), .rst_n(rst_b_n),
        .frame_ready(frame_ready), .wr_frame_index(wr_fidx), .wr_slot_id(wr_slot),
        .wr_generation(wr_gen), .wr_crc_ok(wr_crc),
        .frame_start(fs_evt_b), .swap_ack(ack_evt_b),
        .swap_req(swap_req), .frame_index(mb_fidx), .slot_id(mb_slot),
        .generation(mb_gen), .crc_ok(mb_crc), .swap_error(swap_error),
        .active_commit(active_commit), .active_next(active_next),
        .generation_next(gen_next), .frame_index_next(fidx_next),
        .state_o(state_o)
    );

    frame_swap_cdc u_cdc (
        .clk_b(clk_b), .rst_b_n(rst_b_n),
        .swap_req_b(swap_req), .mb_frame_index_b(mb_fidx), .mb_slot_id_b(mb_slot),
        .mb_generation_b(mb_gen), .mb_crc_ok_b(mb_crc),
        .frame_start_evt_b(fs_evt_b), .swap_ack_evt_b(ack_evt_b),
        .clk_a(clk_a), .rst_a_n(rst_a_n),
        .swap_req_evt_a(req_evt_a), .swap_req_lvl_a(),
        .mb_frame_index_a(mb_fidx_a), .mb_slot_id_a(mb_slot_a),
        .mb_generation_a(mb_gen_a), .mb_crc_ok_a(mb_crc_a), .mb_valid_a(mb_valid_a),
        .frame_start_a(frame_start_a), .swap_ack_a(swap_ack_a)
    );

    // ---- A 侧（像素域）行为模型 ----
    //   a_mode = 0：完整应答（给 frame_start，再 toggle swap_ack）
    //   a_mode = 1：只给 frame_start，不给 swap_ack
    //   a_mode = 2：完全不响应
    reg  [1:0] a_mode = 2'd2;
    reg  [2:0] a_state = 3'd0;
    reg  [7:0] a_delay = 8'd0;

    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) begin
            a_state <= 3'd0; a_delay <= 8'd0;
            frame_start_a <= 1'b0; swap_ack_a <= 1'b0;
        end else begin
            frame_start_a <= 1'b0;                    // 单拍脉冲默认低
            case (a_state)
            3'd0: if ((a_mode != 2'd2) && req_evt_a) begin a_delay <= 8'd2; a_state <= 3'd1; end
            3'd1: if (a_delay == 8'd0) begin
                      frame_start_a <= 1'b1;          // 进入垂直消隐 -> 帧边界
                      a_delay <= 8'd3; a_state <= 3'd2;
                  end else a_delay <= a_delay - 8'd1;
            3'd2: if (a_delay == 8'd0) begin
                      if (a_mode == 2'd0) swap_ack_a <= ~swap_ack_a;  // toggle 回执
                      a_state <= 3'd0;
                  end else a_delay <= a_delay - 8'd1;
            default: a_state <= 3'd0;
            endcase
        end
    end

    // ==================================================================
    // 二、监视器（断言用）
    // ==================================================================
    // (1) active_slot 只允许在 frame_start 触发的那一拍改变
    reg [1:0] aslot_q = 2'd0;
    reg [2:0] state_q = S_IDLE;
    reg       aslot_ok = 1'b1;
    integer   aslot_changes = 0;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin
            aslot_q <= 2'd0; state_q <= S_IDLE; aslot_ok <= 1'b1; aslot_changes <= 0;
        end else begin
            if (active_slot !== aslot_q) begin
                aslot_changes <= aslot_changes + 1;
                // 变化发生在上一拍：那一拍状态应从 WAIT_VBLANK 进入 COMMIT
                if (!(state_q == S_WAIT_VBLANK && state_o == S_COMMIT)) aslot_ok <= 1'b0;
            end
            aslot_q <= active_slot;
            state_q <= state_o;
        end
    end

    // (2) swap_req 是 toggle 电平，不是单拍脉冲
    reg       sr_q = 1'b0;
    integer   sr_changes = 0;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin sr_q <= 1'b0; sr_changes <= 0; end
        else begin
            if (swap_req !== sr_q) sr_changes <= sr_changes + 1;
            sr_q <= swap_req;
        end
    end

    // (3) payload 在 req 翻转【前】就稳定（翻转那一拍 payload 与上一拍相同）
    reg [1:0] slot_p = 2'd0;
    reg [7:0] gen_p  = 8'd0;
    reg       sr_p   = 1'b0;
    reg       mb_pre_ok = 1'b1;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin slot_p <= 2'd0; gen_p <= 8'd0; sr_p <= 1'b0; mb_pre_ok <= 1'b1; end
        else begin
            if (swap_req !== sr_p)
                if (!((mb_slot === slot_p) && (mb_gen === gen_p))) mb_pre_ok <= 1'b0;
            sr_p <= swap_req; slot_p <= mb_slot; gen_p <= mb_gen;
        end
    end

    // (4) ack 之前 payload 不许改
    reg       win = 1'b0;
    reg [1:0] win_slot = 2'd0;
    reg [7:0] win_gen  = 8'd0;
    reg       win_fidx = 1'b0;
    reg       sr_qq = 1'b0;
    reg       win_ok = 1'b1;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin win <= 1'b0; win_ok <= 1'b1; sr_qq <= 1'b0; end
        else begin
            if (swap_req !== sr_qq) begin
                win <= 1'b1;
                win_slot <= mb_slot; win_gen <= mb_gen; win_fidx <= mb_fidx;
            end
            if (win && ((mb_slot !== win_slot) || (mb_gen !== win_gen) || (mb_fidx !== win_fidx)))
                win_ok <= 1'b0;
            if (ack_evt_b) win <= 1'b0;
            sr_qq <= swap_req;
        end
    end

    // (5) 状态序列观察
    reg saw_wv = 1'b0, saw_cm = 1'b0, saw_wa = 1'b0, ack_seen = 1'b0;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) begin
            saw_wv <= 1'b0; saw_cm <= 1'b0; saw_wa <= 1'b0; ack_seen <= 1'b0;
        end else begin
            if (state_o == S_WAIT_VBLANK) saw_wv <= 1'b1;
            if (state_o == S_COMMIT)      saw_cm <= 1'b1;
            if (state_o == S_WAIT_ACK)    saw_wa <= 1'b1;
            if (ack_evt_b)                ack_seen <= 1'b1;
        end
    end

    // ==================================================================
    // 三、测试流程
    // ==================================================================
    integer i;
    reg [1:0] sr_snap;

    initial begin
        // --------------------------------------------------------------
        // 阶段 B：正常帧交换一轮
        // --------------------------------------------------------------
        $display("==== 阶段 B：正常帧交换 ====");
        rst_b_n = 1'b0; rst_a_n = 1'b0; a_mode = 2'd0;
        frame_ready = 1'b0; wr_slot = 2'd0; wr_gen = 8'd0; wr_fidx = 1'b0; wr_crc = 1'b1;
        repeat (10) @(posedge clk_b);
        rst_b_n = 1'b1; rst_a_n = 1'b1;
        repeat (5) @(posedge clk_b);

        // FBM 地址表核对
        check(slot_base0 == 32'h0000_0000 && slot_base1 == 32'h000A_0000 &&
              slot_base2 == 32'h0014_0000 && slot_base3 == 32'h001E_0000,
              "FBM: 冻结地址表 IMG0..IMG3");
        check(line_stride == 32'd1280 && frame_bytes == 32'd614400,
              "FBM: line_stride / frame_bytes");
        sel_slot = 2'd2; #1;
        check(slot_base_o == 32'h0014_0000, "FBM: 查表口返回 IMG2");
        sel_slot = 2'd0; #1;

        // 装载侧置 slot 有效
        slot_valid_id = 2'd1; slot_valid_set = 1'b1;
        @(posedge clk_b);
        #1 slot_valid_set = 1'b0;
        check(slot_valid[1] == 1'b1, "FBM: slot_valid[1] 置位");

        // 提交一帧：frame_ready 只给一拍，保证只有一轮握手
        wr_slot = 2'd1; wr_gen = 8'd1; wr_fidx = 1'b1; wr_crc = 1'b1;
        frame_ready = 1'b1;
        @(posedge clk_b);
        #1 frame_ready = 1'b0;      // 只给一拍，避免多轮握手

        for (i = 0; i < 800 && !ack_seen; i = i + 1) @(posedge clk_b);
        repeat (3) @(posedge clk_b);

        check(saw_wv && saw_cm && saw_wa,      "SWAP: 状态序列 IDLE->WAIT_VBLANK->COMMIT->WAIT_ACK");
        check(state_o == S_IDLE,               "SWAP: 握手结束回到 IDLE");
        check(swap_error == 1'b0,              "SWAP: 无超时错误");
        check(active_slot == 2'd1,             "SWAP: active_slot 原子切换到槽 1");
        check(active_slot_base == 32'h000A_0000,"SWAP: 前台槽基地址 = IMG1");
        check(fbm_generation == 8'd1,          "SWAP: generation 随提交更新为 1");
        check(aslot_ok == 1'b1,                "SWAP: active_slot 只在 frame_start 那一拍改变");
        check(sr_changes >= 1,                 "SWAP: swap_req 发生了翻转");
        check(mb_valid_a == 1'b1 && mb_slot_a == 2'd1 && mb_gen_a == 8'd1,
                                               "CDC: mailbox 载荷已被 A 侧捕获（slot=1 gen=1）");
        check(mb_pre_ok == 1'b1,               "CDC: payload 在 req 翻转前已稳定");
        check(win_ok == 1'b1,                  "CDC: ack 之前 payload 未被修改");

        // toggle 电平（不是单拍脉冲）：翻转后应长时间保持
        sr_snap = swap_req;
        repeat (30) @(posedge clk_b);
        check(swap_req === sr_snap,            "SWAP: swap_req 保持电平（toggle 而非单拍脉冲）");

        // --------------------------------------------------------------
        // 阶段 C1：不给 frame_start -> 超时 -> 保持显示块
        // --------------------------------------------------------------
        $display("==== 阶段 C1：超时（无 frame_start）====");
        rst_b_n = 1'b0; rst_a_n = 1'b0; a_mode = 2'd2;
        frame_ready = 1'b0;
        repeat (10) @(posedge clk_b);
        rst_b_n = 1'b1; rst_a_n = 1'b1;
        repeat (5) @(posedge clk_b);

        wr_slot = 2'd2; wr_gen = 8'd5; wr_fidx = 1'b1; wr_crc = 1'b1;
        frame_ready = 1'b1;
        @(posedge clk_b);
        #1 frame_ready = 1'b0;      // 只给一拍，避免多轮握手

        for (i = 0; i < 400 && !swap_error; i = i + 1) @(posedge clk_b);
        repeat (3) @(posedge clk_b);        // 等 state_o 追上 state
        check(swap_error == 1'b1,              "TIMEOUT: 无 frame_start 时 swap_error 拉高");
        check(state_o == S_SAFE,               "TIMEOUT: FSM 进入 SAFE");
        check(active_slot == 2'd0,             "TIMEOUT: 当前显示块保持为 0（未切换）");
        repeat (30) @(posedge clk_b);
        check(active_slot == 2'd0,             "TIMEOUT: 超时后显示块持续保持");

        // --------------------------------------------------------------
        // 阶段 C2：给 frame_start 但不给 swap_ack -> 超时 -> 显示块不再变
        // --------------------------------------------------------------
        $display("==== 阶段 C2：超时（无 swap_ack）====");
        rst_b_n = 1'b0; rst_a_n = 1'b0; a_mode = 2'd1;
        frame_ready = 1'b0;
        repeat (10) @(posedge clk_b);
        rst_b_n = 1'b1; rst_a_n = 1'b1;
        repeat (5) @(posedge clk_b);

        wr_slot = 2'd3; wr_gen = 8'd7; wr_fidx = 1'b0; wr_crc = 1'b1;
        frame_ready = 1'b1;
        @(posedge clk_b);
        #1 frame_ready = 1'b0;      // 只给一拍，避免多轮握手

        for (i = 0; i < 600 && !swap_error; i = i + 1) @(posedge clk_b);
        check(swap_error == 1'b1,              "TIMEOUT2: 无 swap_ack 时 swap_error 拉高");
        check(active_slot == 2'd3,             "TIMEOUT2: 提交已生效（槽 3）");
        repeat (30) @(posedge clk_b);
        check(active_slot == 2'd3 && state_o == S_SAFE,
                                               "TIMEOUT2: 超时后显示块保持不变，停在 SAFE");

        // --------------------------------------------------------------
        // 汇总
        // --------------------------------------------------------------
        $display("========================================");
        $display("  PASS = %0d   FAIL = %0d", passes, errors);
        $display("========================================");
        if (errors == 0) $display("[RESULT] ALL PASS");
        else             $display("[RESULT] %0d FAILED", errors);
        $finish;
    end

    // 兜底看门狗
    initial begin
        #500000;
        $display("[FAIL] watchdog timeout");
        $finish;
    end

endmodule