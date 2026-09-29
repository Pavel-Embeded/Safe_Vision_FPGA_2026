// ============================================================================
// frame_swap_cdc.v — 帧交换跨时钟域（SafeVision 阶段 15 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.15「技术纠错：帧交换的两类跨域错误」——原文照录关键结论：
//         ✗ 错误做法 1：把 frame_ready 当单拍脉冲直接打两拍跨到像素时钟域。
//             单周期脉冲可能因目标时钟采样不到而【整体丢失】，也会因脉宽不足
//             被两级同步器"吃掉"。→ 正确做法：改用 toggle 电平翻转，读侧先两级
//             同步电平、再对电平做【边沿检测】得到"有一次新请求"。
//         ✗ 错误做法 2：slot_id、generation、crc_ok、frame_index 是多位载荷，
//             逐位各打两拍会取到"半新半旧"的组合值（例如槽号已更新而代次还是旧的），
//             导致 A 读到尚未写完的块。→ 正确做法：mailbox 锁存。
//         ★ 源域在收到 ack 之前【不得修改】这组寄存器。
//       docs/interface_spec.md §一 CDC 约定 / §3.4 swap_ctrl / §7 决策 D-3
//
// 本模块只做"搬运"，不含任何策略：
//   B→A：swap_req 单比特 toggle → 两级同步 + 边沿检测（swap_req_evt_a）；
//        slot_id / generation / frame_index / crc_ok 多位载荷 → mailbox 锁存，
//        在 req 事件那一拍一次性捕获（保证四个字段同代）。
//   A→B：frame_start（A 侧单拍）→ 先转成 toggle 再同步 + 边沿检测；
//        swap_ack（A 侧 toggle）→ 两级同步 + 边沿检测。两者都还原成 B 域单拍事件。
// ============================================================================
`include "safevision_defs.vh"

module frame_swap_cdc (
    // ---- B 侧（sys_clk 域）----
    input  wire       clk_b,
    input  wire       rst_b_n,
    input  wire       swap_req_b,        // B 产出：toggle 电平
    input  wire       mb_frame_index_b,  // B 产出：mailbox 载荷（须保持稳定）
    input  wire [1:0] mb_slot_id_b,
    input  wire [7:0] mb_generation_b,
    input  wire       mb_crc_ok_b,
    output wire       frame_start_evt_b, // 同步到 B：A 的帧边界单拍事件
    output wire       swap_ack_evt_b,    // 同步到 B：A 的 swap_ack 边沿事件

    // ---- A 侧（pixel_clk 域）----
    input  wire       clk_a,
    input  wire       rst_a_n,
    output wire       swap_req_evt_a,    // 同步到 A：请求单拍事件
    output wire       swap_req_lvl_a,    // 同步到 A：请求电平（观测用）
    output wire       mb_frame_index_a,  // mailbox 载荷（捕获后稳定）
    output wire [1:0] mb_slot_id_a,
    output wire [7:0] mb_generation_a,
    output wire       mb_crc_ok_a,
    output wire       mb_valid_a,        // 载荷已捕获有效
    input  wire       frame_start_a,     // A 本地：帧边界（单拍）
    input  wire       swap_ack_a         // A 产出：toggle 电平
);

    // ========================================================================
    // B → A
    // ========================================================================
    // ---- 单比特 swap_req：两级同步 + 边沿检测（第 3 级只用于比较，不增加延迟风险）----
    reg [2:0] req_sync;
    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) req_sync <= 3'b000;
        else          req_sync <= {req_sync[1:0], swap_req_b};
    end
    assign swap_req_lvl_a = req_sync[1];
    assign swap_req_evt_a = req_sync[2] ^ req_sync[1];   // 只用两级稳定值比较

    // ---- 多比特载荷：mailbox 锁存（在 req 事件那一拍一次性捕获，禁止逐位打两拍）----
    reg [1:0] mb_slot_id_a_r;
    reg [7:0] mb_generation_a_r;
    reg       mb_frame_index_a_r;
    reg       mb_crc_ok_a_r;
    reg       mb_valid_a_r;

    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) begin
            mb_slot_id_a_r    <= 2'd0;
            mb_generation_a_r <= 8'd0;
            mb_frame_index_a_r<= 1'b0;
            mb_crc_ok_a_r     <= 1'b0;
            mb_valid_a_r      <= 1'b0;
        end else if (swap_req_evt_a) begin
            // 四个字段同拍一起取，保证是"同一代"的载荷
            mb_slot_id_a_r     <= mb_slot_id_b;
            mb_generation_a_r  <= mb_generation_b;
            mb_frame_index_a_r <= mb_frame_index_b;
            mb_crc_ok_a_r      <= mb_crc_ok_b;
            mb_valid_a_r       <= 1'b1;
        end
    end

    assign mb_slot_id_a     = mb_slot_id_a_r;
    assign mb_generation_a  = mb_generation_a_r;
    assign mb_frame_index_a = mb_frame_index_a_r;
    assign mb_crc_ok_a      = mb_crc_ok_a_r;
    assign mb_valid_a       = mb_valid_a_r;

    // ========================================================================
    // A → B
    // ========================================================================
    // ---- frame_start 是 A 侧【单拍】：先转成 toggle，再同步 + 边沿检测 ----
    reg fs_tgl_a;
    always @(posedge clk_a or negedge rst_a_n) begin
        if (!rst_a_n) fs_tgl_a <= 1'b0;
        else if (frame_start_a) fs_tgl_a <= ~fs_tgl_a;   // 单拍 -> 电平翻转
    end

    reg [2:0] fs_sync;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) fs_sync <= 3'b000;
        else          fs_sync <= {fs_sync[1:0], fs_tgl_a};
    end
    assign frame_start_evt_b = fs_sync[2] ^ fs_sync[1];

    // ---- swap_ack 已是 toggle 电平：两级同步 + 边沿检测 ----
    reg [2:0] ack_sync;
    always @(posedge clk_b or negedge rst_b_n) begin
        if (!rst_b_n) ack_sync <= 3'b000;
        else          ack_sync <= {ack_sync[1:0], swap_ack_a};
    end
    assign swap_ack_evt_b = ack_sync[2] ^ ack_sync[1];

endmodule