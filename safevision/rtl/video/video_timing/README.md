# video_timing

`video_timing.v` 是 A 链像素时钟域的固定速率扫描模块。`clk` 接板级 PLL 的像素时钟，`rst_n` 接本域低有效复位。它只计数和生成同步标签，不生成时钟、不读 FIFO，也不因像素欠载而停止扫描。

`x[11:0]/y[11:0]` 是包含消隐区的 active-first 原始计数；`de=1` 时才把它们当图像坐标。`hsync/vsync/de/line_start/frame_start/active_frame_start/hblank/vblank` 均由同拍 `x/y` 组合译码，彼此无额外延迟。下游寄存器在**下一上升沿**采样当前像素周期的这些标签。RGB、坐标、同步、`de` 与 `pixel_valid` 的后续延迟统一由 `video_pipeline` 对齐。

| 事件 | 条件 | 用途 |
|---|---|---|
| `line_start` | 每行 `x=0`，含消隐行 | 行边界，单像素周期 |
| `frame_start` | `x=0,y=V_ACTIVE` | **垂直消隐入口**，供帧交换 CDC；每帧单像素周期 |
| `active_frame_start` | `x=0,y=0` | 第一个可见像素；不得代替 `frame_start` |

显示模式参数集中在 `../../include/video_mode_defs.vh`，与 `pixel_format_defs.vh` 的 640×480 存储帧布局分开。默认 BASE：640/16/96/48、480/10/2/33，总计 800×525，负同步，目标像素时钟 25.175 MHz。HD：1280/110/40/220、720/5/5/20，总计 1650×750，正同步，目标 74.25 MHz。HD 输出扫描画布不意味着 B 链媒体帧已升级至原生 720p。模式在编译时确定；运行中切换还需 PLL、PHY 与视频链重初始化。

复位期间 `x/y=0`，`de` 和三个事件为 0，同步输出不活动，`hblank/vblank=1`。同步释放后从 `(0,0)` 开始。参数要求 ACTIVE/SYNC 大于 0、前后肩非负、行场总数均不超过 4096；非法参数在仿真时停止。

接口已登记到 `docs/interface_spec.md` 和 `docs/architecture/module_registry.md`。RTL 实现完成，完整帧 VGA/720p、边界、极性和运行中复位仍需 `verification/unit/tb_video_timing.sv` 回归；像素时钟频率、STA 与 HDMI 实机输出仍需板级证据。
