# rtl/audio

负责人：C。**当前仅建立目录与命名计划，未提供功能 RTL。**

建议 `audio_scheduler.v`、`audio_priority_arbiter.v`、`alarm_tone_gen.v`。WAV/PCM 源由 B 提供；HDMI 数据岛/ACR 由板级 HDMI 适配与 A/C 联合验收。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
