# 当前工作项（2026-09-29 盘点）

这是一份起始清单，不是实施完成证明。状态据仓库文件与现有 B 文档记录；未运行 ModelSim，也未见上板证据。

| 优先级 | 工作项 | 主责 | 前置与验收 | 状态 |
|---|---|---|---|---|
| P0 | 冻结全链 A/B、A/C、音频/安全接口，处理 `interface_spec.md` O-1–O-11 | A/B/C | 七字段、CDC、复位、TB、双方评审 | 待评审 |
| P0 | B 板级最小扇区读取与真实 SDRAM IP 适配 | B/A | 原始扇区逐字节比对；控制器读写回环 | 顶层 + 约束 + TB 已就绪（TB 通过），待上板 |
| P0 | A 彩条/时序→固定帧→Frame Reader→HDMI | A | 首像素、hsync/vsync/de、欠载安全色、STA | 待实现 |
| P0 | C 按键/播放/故障安全状态最小闭环 | C | 消抖、优先级、media_reset 不影响安全显示 | 待实现 |
| P0 | A/B 固定红帧经 SDRAM→HDMI 联调 | A/B | 行首对齐、无撕裂、带宽与最低水位配对 | 待实现 |
| P0 | B01–B04 与基础音频链板级验收 | A/B/C | 需求表中每项有测试与原始证据 | 待实现 |
| P1 | 故障注入、恢复与长稳 | A/B/C | 手册 §11.5–11.6 的计数与原始记录 | 待实现 |
| P2 | E01–E05 扩展 | A/B/C | B01–B04 已闭环，逐项证据 | 待开始 |

**已知不一致的现状（2026-10-02 更新）**：① 本文件原记录的"`run_sim.ps1` 顶部的 `$MSIM_BIN` 写死为本机 ModelSim 路径，移植时需参数化并回归"——**已解决**：`run_sim.ps1` 改为 `-ModelSimBin` 参数 + `MSIM_BIN` 环境变量回退，与 `run_clock_sim.ps1` 同口径，脚本里不再有本机路径，并已在参数化后重跑回归（`TOTAL PASS=507 FAIL=0`）。② 接口 O-11 记录的 CMD18 多扇区读未实现仍然成立，此处不按手册样例假定它已支持。③ 现有 `docs/B链-待办与硬件验证清单.md` 的旧路径引用已修正，其 §2.2 写的是 `rtl/include/` 与 `rtl/storage/`，与 `docs/interface_spec.md` 的迁移表一致。

**新增（2026-10-02）**：B 侧板级 bring-up 落地——`platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v` + `constraints/{pin.adc,timing.sdc}` + `tb_top_stage5_sector_rd.sv`，TD 工程 `TOP_MODULE` 与约束已配好。两条原"待人工确认"已在同一天解决：① `uart_txd`（D12，网络名 `TXD`）经开发板手册串口引脚表 + 图2-10 CH340G 原理图确认是 **FPGA 发送脚**，对接**板载 USB-UART**（无需外接 USB-TTL）；② `AutoExcluded` 经 `run.log` 核对，顶层闭包内 7 个模块全部 elaborate，无误排除。
**同一次 TD 综合还暴露并修掉一个真 bug**：`sd_initializer` / `sd_sector_reader` 的 `bdata` 被两个 `always` 块驱动（`HDL-8007`），**ModelSim 完全不报**；已收归单一驱动源，全仓静态复查确认无同类问题。**未决事项**：该次综合未通过，**需要重新综合 + 布局布线**。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](../clock_video_implementation.md)，端口/时钟域见 [A接口补充](../A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](../A_PUSH_SCOPE_20261002.md)。
