// ============================================================================
// event_code_defs.vh — 事件来源与事件类型登记（唯一来源）
// ----------------------------------------------------------------------------
// 依据：《工业级模块化架构蓝图》§4 的 rtl/include/ 约定
//        docs/interface_spec.md §3.5（error_report / 全局状态）
//        手册 7.16.2（错误处理：异常与上报必须成对出现）
//
// ★ 用途：`error_report` 的 `err_src[3:0]` 与 `evt_type[3:0]` 共用同一套编码。
//   看到 evt_type=1 就知道"这是媒体/SD 链报上来的"，不用翻别的文档。
//
// ★ 与错误码的分工（别混）：
//     SV_EVT_SRC_*  → **谁**报的（来源）
//     ERR_*（fault_code_defs.vh）→ 报的**是什么对外主码**
//     DET_*（fault_code_defs.vh）→ 内部细分码，只在 B 链日志里用
//
// ★ 前缀 `SV_`：与 error_report.v 内部的 EVT_W / EVT_DEPTH 等本模块参数
//   在阅读上区分开（Verilog 宏带反引号才展开，不会编译冲突）。
// ============================================================================
`ifndef EVENT_CODE_DEFS_VH
`define EVENT_CODE_DEFS_VH

// ---------------------------------------------------------------------------
// 事件来源（= error_report 的 err_src / evt_type）
// ---------------------------------------------------------------------------
`define SV_EVT_SRC_NONE       4'h0   // 无 / 保留
`define SV_EVT_SRC_STORAGE    4'h1   // B：SD / FAT32 / 文件流 / 媒体解析
`define SV_EVT_SRC_VIDEO      4'h2   // A：视频时序 / 帧读 / OSD / 应急图形
`define SV_EVT_SRC_MEMORY     4'h3   // B：SDRAM 控制器 / 帧缓存 / 仲裁 / 帧交换
`define SV_EVT_SRC_FIFO       4'h4   // B：FIFO 水位 / 欠载 / 溢出
`define SV_EVT_SRC_CONTROL    4'h5   // C：输入 / 优先级 / 应急状态机
`define SV_EVT_SRC_WATCHDOG   4'h6   // C：看门狗（视频进度 / 存储）
`define SV_EVT_SRC_AUDIO      4'h7   // C：音频链 / 欠载
`define SV_EVT_SRC_RECOVERY   4'h8   // C：恢复流程
`define SV_EVT_SRC_DIAG       4'h9   // 诊断 / 自检
`define SV_EVT_SRC_RESERVED   4'hA

// ---------------------------------------------------------------------------
// 事件类型（evt_type）
// ---------------------------------------------------------------------------
`define SV_EVT_TYPE_FAULT     4'h0   // 故障上报
`define SV_EVT_TYPE_RECOVER   4'h1   // 恢复完成
`define SV_EVT_TYPE_INFO      4'h2   // 一般信息（状态快照等）

`endif // EVENT_CODE_DEFS_VH