> ⚠️ 本文写于 2026-10-11 仓库收敛之前。文中提到的 `evidence/ab_multiround_*`、`releases/ab_multiround_*`、`top_stage10_framebuffer`、`safevision_loopback.al`、`prepare_board_project.*` 等文件已在收敛中删除（**历史提交全部保留**）；取回方式与收敛清单见 [仓库收敛说明](../仓库收敛说明_20261011.md仓库收敛说明_20261011.md)。

# 需求 → 模块 → 测试 → 证据

状态为本次盘点口径，不是赛题验收结论。`evidence/` 尚未填入原始结果。B 文档记载的单元仿真不等于整项需求完成。

| ID | 目标 | 现有/规划模块 | 计划测试与证据 | 状态 |
|---|---|---|---|---|
| B01 | 本地媒体读取、四图识别 | `storage/*`（含新增 `mbr_parser` 卷基址）、`media/bmp_*`、`file_index` 现有；板级 `top_stage5_sector_rd` 现有 | TC-B01-01..03、TC-B-TOP；`evidence/{sim,board}` | **阶段 1–5 已上板实测通过**（M-9：512/512 逐字节一致，`evidence/board` 条目 M-9-PASS）；阶段 6–7 的板级验证与"四图识别"仍待做（`mbr_parser` 单测已过，板级顶层待写） |
| B02 | SDRAM 缓存、HDMI 稳定显示 | `memory/*` 现有（新增 `framebuffer_loopback_core` + `mem_read_burst` 做阶段 10 帧缓存回环）；`video/*`、板级 HDMI 规划 | TC-B02-01..02；报告/板级/水位 | **阶段 10 帧缓存回环核心已仿真通过**（整帧写→整帧读回→逐像素零错，`tb_framebuffer_loopback_core` 11 项）；板级 `top_stage10_framebuffer` **已上板验收通过（2026-10-03）**：整帧 307200 像素逐像素零错（`BAD=000000`）、三个地址斜坡探针全对；定位用的根因（适配器读预取地址未每拍自增）已修，`sdram_app_adapter` 另有 7 项单元 TB 覆盖；**仅余自研组时序 −0.992 ns 待收**；HDMI 稳定显示未整机集成 |
| B03 | 按键/自动切换 | `frame_swap_*` 现有；`control/playback_fsm` 规划 | TC-B03-01..02；事件日志/录像 | 未整机集成 |
| B04 | HDMI 音频 | `media/wav_parser` 现有；PCM 环/调度/HDMI 音频规划 | TC-B04-01..02；两台设备录音/录像 | 未整机集成 |
| E01 | 高级转场/画面组织 | 视频转场规划 | TC-E01-01；水位/录像 | 计划 |
| E02 | 音画联动 | 索引与音频调度规划 | TC-E02-01；generation 日志 | 计划 |
| E03 | UART 配置 | `common/uart_tx` 现有；RX/命令规划 | TC-B03-02；参数测量 | 计划 |
| E04 | 鲁棒性与恢复 | `safety/*` 规划，B 错误上报现有 | TC-R-01..06；故障与长稳 | 计划 |
| E05 | 完整场景展示 | 三链整机规划 | 场景演示与答辩记录 | 计划 |

测试编号来自手册 V2.0 §11 的示例/基线；实际用例定义与执行命令登记在 `docs/verification/test_matrix.md`。证据索引必须填具体文件名、Git 构建 tag、设备/条件、结论，禁止预填“通过”。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](../clock_video_implementation.md)，端口/时钟域见 [A接口补充](../A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](../A_PUSH_SCOPE_20261002.md)。


## A 阶段 1–9 需求落地（2026-10-04）

手册 §6.1–6.9：基础四模块→`common/a_*.v`；测试图/一像素框/坐标文字→`pattern_generator.v` + `osd_coordinate_text.v`；片上字库/OSD→`font8x16_rom.v` + `.mem` + `osd_overlay.v`；四级流水→OSD 与既有 `video_pipeline` 同拍接线。状态文字可用于后续 B03/E03 观测，但 C 控制/UART 配置接入尚未完成；字体 ROM 是后续 E01 的基础，未宣称完整应急安全场景完成。已执行 TB、内部 STA 与尚缺上板验收见 [阶段对应表](../A_stages1_9.md)。
