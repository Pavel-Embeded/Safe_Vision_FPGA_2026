# Clock / Reset / Video Timing 子系统

本目录使用 Verilog-2001，安路 IP 在平台 `ip/pll/`，可移植扫描在 `safevision/rtl/video/video_timing/`。完整说明见仓库 `docs/clock_video_implementation.md` 和 `docs/clock_video_change_log.md`。

| 模块 | 用途 |
|---|---|
| clock_gen.v | 50 MHz 板时钟接入系统、所选视频、音频三颗 PLL；输出五路时钟及四个 lock 许可 |
| reset_sync.v | 各域异步断言、至少两级同步释放；STAGES 默认 2，可设 3 |
| clock_reset_ctrl.v | 板复位、PLL lock 与四个请求生成九路复位，隔离基础域和业务域 |
| clock_video_subsystem.v | 将时钟/复位与 video_timing 模块化接线，统一选择 PLL 及几何 |

## 固定构建与实际时钟

VIDEO_MODE_HD=0：640×480 有效区，800×525 总周期，pixel=25.185185185 MHz，serial=125.925925926 MHz。

VIDEO_MODE_HD=1：1280×720 有效区，1650×750 总周期，pixel=74.166666667 MHz，serial=370.833333333 MHz。

两档均为 sys=100、mem=125、audio=12.288135593 MHz。sys/mem 共用 PLL lock；pixel/serial 来自同一 PLL，严格 1:5。模式只在综合前选择。

## 复位分配

| 输出 | 目标时钟 | 断言来源 |
|---|---|---|
| sys_rst_n | sys | 板复位 / 系统 PLL 失锁 |
| mem_rst_n | mem | 板复位 / 系统 PLL 失锁 |
| pixel_rst_n | pixel | 板复位 / 视频 PLL 失锁 |
| serial_rst_n | serial | 板复位 / 视频 PLL 失锁 |
| audio_rst_n | audio | 板复位 / 音频 PLL 失锁 / audio_reset_req |
| media_rst_n | sys | 基础 sys 来源 / media_reset_req |
| memory_client_rst_n | mem | 基础 mem 来源 / memory_client_reset_req |
| hdmi_pixel_rst_n | pixel | 基础 video 来源 / hdmi_reinit_req |
| hdmi_serial_rst_n | serial | 基础 video 来源 / hdmi_reinit_req |

各输出独立同步释放。请求为保持电平，跨域发起需按接口规范保持/握手。SDRAM 控制器基础刷新接 mem_rst_n，业务客户端接 memory_client_rst_n。扫描接 pixel_rst_n，媒体/HDMI 重初始化期间继续扫描。PLL 失锁或板复位则允许基础扫描复位。

## 视频输出与验证

x/y 为含消隐的 12 位原始计数；de 标记有效区；frame_start 在 (0,V_ACTIVE) 即垂直消隐入口；active_frame_start 在 (0,0)；line_start 在每行 x=0。标签组合译码与当前坐标对齐；下游 RGB 和同步标签须匹配流水延迟，欠载输出安全颜色并保持扫描。

`safevision/tools/run_video_clock_sim.ps1` 用 XSim 做五项功能回归；平台 `project/clock_video_verify/{base,hd}.tcl` 用 TD 做内部实现检查。最终结果和证据以完整实施文档及 evidence 报告为准。

720p 当前完成扫描和时钟；B 链 framebuffer 仍固定 640×480 RGB565。验证顶层不是整机 HDMI 顶层，仍需 Frame Reader、像素 FIFO、视频流水、TMDS/PHY、HDMI 音频和完整板级约束接入。
