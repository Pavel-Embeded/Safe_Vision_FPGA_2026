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

**新增（2026-10-02）**：B 侧板级 bring-up 落地——`platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v` + `constraints/{pin.adc,timing.sdc}` + `tb_top_stage5_sector_rd.sv`，TD 工程 `TOP_MODULE` 与约束已配好。**仍待人工确认**：`uart_txd`（暂取 D12，网络名 `TXD`）到物理连接器的落点；以及在 TD GUI 里确认依赖分析没有把用到的模块标 `AutoExcluded`。这两条不解决，第 8 行"B 板级最小扇区读取"就还不能算可下载。
