# rtl/video

负责人：A。**当前仅建立目录与命名计划，未提供功能 RTL。**

建议 `video_timing.v`、`frame_reader.v`、`osd_overlay.v`、`video_compositor.v`、`safe_scene_gen.v`、`emergency_mux.v`。固定速率 HDMI、前置预取、de/pixel_valid 区分、流水线对齐。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
