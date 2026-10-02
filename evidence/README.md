# 证据目录

依据手册 V2.0 §11.4。按“需求编号 → 测试编号 → 原始文件 → 构建 tag”索引，不预填结果。`requirements/` 评审；`sim/` 日志与随机种子；`waveform/` 原始波形；`reports/` 综合/STA/CDC/资源；`board/` 实机；`measurements/` 带宽/水位/长稳；`provenance/` 许可与第三方来源。

文件名建议 `TC-B02-01_YYYYMMDD_<build-tag>_<run>.<ext>`，每个子目录的 `INDEX.md` 记录：测试编号、需求、Git 提交/bitstream 哈希、工具/板卡/外设、步骤、结论、原始文件。敏感个人资料与无许可第三方原件不得进入版本库。大文件可另存受控位置，但索引必须记录不可变哈希和可访问路径。空索引表示尚无证据，不是通过。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](../docs/clock_video_implementation.md)，端口/时钟域见 [A接口补充](../docs/A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](../docs/A_PUSH_SCOPE_20261002.md)。
