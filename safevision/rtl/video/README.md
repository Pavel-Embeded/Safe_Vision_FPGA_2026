# rtl/video

负责人：A。**当前仅建立目录与命名计划，未提供功能 RTL。**

模块文件夹：`video_timing/`、`pattern_generator/`、`graphics_rom/`、`osd_overlay/`、`video_pipeline/`、`frame_reader/`、`video_compositor/`、`safe_scene_gen/`、`emergency_mux/`、`video_cdc/`。各目录 README 定义用途；当前都尚无功能 RTL。固定速率 HDMI、前置预取、de/pixel_valid 区分、流水线对齐。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
