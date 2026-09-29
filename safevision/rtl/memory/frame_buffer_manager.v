// ============================================================================
// frame_buffer_manager.v — 帧缓存槽管理与前后帧所有权（SafeVision 阶段 14 · rtl/memory）
// ----------------------------------------------------------------------------
// 依据：手册 7.12「表 7-3 图像与内存容量账」、7.14「阶段 14：Ping-Pong 双缓冲」
//         · 保留两块帧空间，读侧与写侧分居两块，只在帧边界互换角色
//         · 易错点：两块地址未按帧大小对齐；未获回执就改写对方在读的块
//       docs/interface_spec.md §五「冻结的存储地址表（逻辑字节地址）」
//         IMG0=0x000000 / IMG1=0x0A0000 / IMG2=0x140000 / IMG3=0x1E0000
//         AUDIO_RING=0x280000 / WORK=0x2C0000
//
// 职责：唯一持有槽基地址、行步长与槽所有权的模块。
//       · slot_base0..3 / 查表口 slot_base_o：槽起始逻辑字节地址
//       · active_slot：当前显示（前台）槽，只由 frame_swap_ctrl 的提交脉冲原子更新
//       · write_slot：当前写入（后台）槽
//       · slot_valid[3:0]：A 只允许读 slot_valid 已置位的槽
//       · frame_index：前后帧块（0/1），每提交一次翻转
//       · generation：写入代次，每提交一次 +1（防重复提交）
//
// ★ 所有地址常量一律 localparam，禁止散落 magic number（蓝图 §3.3 / 手册 7.12）。
// ★ active_slot + slot_base + generation 的原子更新：本模块在 active_commit 这一个
//   脉冲上把三者一起改写（同一时钟沿），满足手册 7.15「同一时刻一起更新」。
// ============================================================================
`include "safevision_defs.vh"

module frame_buffer_manager (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 装载侧：slot_writer / file_index ----
    input  wire [1:0]  wr_slot_sel,       // 本轮要写的槽
    input  wire        wr_slot_set,       // 单拍：确定 write_slot
    input  wire        slot_valid_set,    // 单拍：置某槽有效
    input  wire [1:0]  slot_valid_id,
    input  wire        slot_valid_clr,    // 单拍：清全部 valid（新一轮装载）

    // ---- 显示侧：frame_swap_ctrl 在 COMMIT 时刻给出 ----
    input  wire        active_commit,     // 单拍：原子切换前台槽
    input  wire [1:0]  active_next,       // 新的前台槽
    input  wire [7:0]  generation_in,     // 新代次
    input  wire        frame_index_in,    // 新前后帧块

    // ---- 查表口 ----
    input  wire [1:0]  sel_slot,
    output reg  [31:0] slot_base_o,

    // ---- 对外状态 ----
    output reg  [1:0]  active_slot,
    output reg  [1:0]  write_slot,
    output reg  [3:0]  slot_valid,
    output reg        frame_index,
    output reg  [7:0]  generation,
    output reg  [31:0] active_slot_base,  // 前台槽基地址，供 video_read_dma

    // ---- 常量透出 ----
    output wire [31:0] slot_base0,
    output wire [31:0] slot_base1,
    output wire [31:0] slot_base2,
    output wire [31:0] slot_base3,
    output wire [31:0] line_stride,
    output wire [31:0] frame_bytes
);

    // ------------------------------------------------------------------------
    // 冻结地址表（interface_spec §五）——唯一落点，全部 localparam
    // ------------------------------------------------------------------------
    localparam [31:0] IMG0_BASE       = 32'h0000_0000;   // 第 1 幅 RGB565
    localparam [31:0] IMG1_BASE       = 32'h000A_0000;   // 第 2 幅
    localparam [31:0] IMG2_BASE       = 32'h0014_0000;   // 第 3 幅
    localparam [31:0] IMG3_BASE       = 32'h001E_0000;   // 第 4 幅
    localparam [31:0] AUDIO_RING_BASE = 32'h0028_0000;   // 256 KiB 音频环
    localparam [31:0] WORK_BASE       = 32'h002C_0000;   // 工作区

    localparam [31:0] SLOT_STRIDE     = 32'h000A_0000;   // 槽间距（640 KiB）
    localparam [31:0] LINE_STRIDE    = 32'd1280;         // 每行 640×2 Byte
    localparam [31:0] FRAME_BYTES    = 32'd614400;       // 640×480×2

    // 槽 -> 基地址（用常量，不用裸数）
    function [31:0] slot_base_of;
        input [1:0] s;
        begin
            case (s)
                2'd0:    slot_base_of = IMG0_BASE;
                2'd1:    slot_base_of = IMG1_BASE;
                2'd2:    slot_base_of = IMG2_BASE;
                default: slot_base_of = IMG3_BASE;
            endcase
        end
    endfunction

    assign slot_base0  = IMG0_BASE;
    assign slot_base1  = IMG1_BASE;
    assign slot_base2  = IMG2_BASE;
    assign slot_base3  = IMG3_BASE;
    assign line_stride = LINE_STRIDE;
    assign frame_bytes = FRAME_BYTES;

    // ------------------------------------------------------------------------
    // 主逻辑
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_slot      <= 2'd0;
            write_slot       <= 2'd0;
            slot_valid       <= 4'b0000;
            frame_index      <= 1'b0;
            generation       <= 8'd0;
            active_slot_base <= IMG0_BASE;
        end else begin
            // ---- 装载侧 ----
            if (slot_valid_clr) begin
                slot_valid <= 4'b0000;
            end
            if (wr_slot_set) begin
                write_slot <= wr_slot_sel;
            end
            if (slot_valid_set) begin
                slot_valid[slot_valid_id] <= 1'b1;
            end

            // ---- 显示侧：原子更新（同一时钟沿一起改）----
            if (active_commit) begin
                active_slot      <= active_next;
                active_slot_base <= slot_base_of(active_next);
                generation       <= generation_in;
                frame_index      <= frame_index_in;
            end
        end
    end

    // ------------------------------------------------------------------------
    // 查表口（组合）
    // ------------------------------------------------------------------------
    always @(*) begin
        slot_base_o = slot_base_of(sel_slot);
    end

endmodule