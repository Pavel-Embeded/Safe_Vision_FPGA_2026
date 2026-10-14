// ============================================================================
// priority_arbiter.v — 优先级仲裁（纯组合，手册 8.3）
// ----------------------------------------------------------------------------
// 规则固定为 Fire（火情） > MediaFault（存储/媒体故障） > Notice（普通提示） > Normal。
// 实现就是 if-else if 链——分支顺序即优先级，天然保证高优先级不被遮挡。
//   FIRE=1 且 SD_ERROR=1 同时有效时，事件码必须是 EV_FIRE ⇒ 屏幕显示火灾疏散，
//   而不是一块 "SD CARD ERROR" 提示条。
//
// ★ 事件码用 2 bit 编码（PDF 写 event[3:0]；这里 4 个等级 2 bit 足够，
//   编码表见本文件 localparam）。
//   ★ 端口改名为 evt_code：`event` 是 Verilog/SystemVerilog 保留字，不能作标识符
//     （vlog-13069）。语义与 PDF 的 event 完全相同，仅名字规避保留字。
// ★ 评审考核点："同一时刻多告警，屏幕听谁的" ⇒ 必须留下两两组合的仿真记录
//   （见 tb_c_priority_arbiter.sv：8 种组合全部跑一遍）。
// ★ 本模块无时钟、无状态：同一拍内事件码不会抖动。
// ============================================================================

module priority_arbiter (
    input  wire       fire,
    input  wire       mediaf,
    input  wire       notice,
    output reg  [1:0] evt_code,
    output reg        valid
);
    localparam [1:0] EV_NONE       = 2'd0;   // 无事件
    localparam [1:0] EV_NOTICE     = 2'd1;   // 普通提示
    localparam [1:0] EV_MEDIAFAULT = 2'd2;   // 媒体/存储故障
    localparam [1:0] EV_FIRE       = 2'd3;   // 火情（最高）

    always @* begin
        if (fire)        begin evt_code = EV_FIRE;       valid = 1'b1; end
        else if (mediaf) begin evt_code = EV_MEDIAFAULT; valid = 1'b1; end
        else if (notice) begin evt_code = EV_NOTICE;     valid = 1'b1; end
        else             begin evt_code = EV_NONE;       valid = 1'b0; end
    end

endmodule
