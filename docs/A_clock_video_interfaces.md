# A Clock / Video Timing 接口补充

记录日期为 2026-10-02，发布范围为 A 链。B/C 的既有接口与源码使用当时最新的远程版本。

### A 板级时钟复位接口（v1.10 更新，不改变 B 链既有端口）

`platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v` 接收 TD PLL 输出的时钟与 `locked`，只产生低有效复位。时钟由新增的 `clock_gen.v` 连接官方 `ip/pll/sv_*_pll.v` 产生；`clock_video_subsystem.v` 统一装配 PLL、九路复位和 `video_timing`。`VIDEO_MODE_HD=0/1` 是编译期参数，同一次构建只例化 BASE 或 HD 中的一套视频 PLL，不支持运行时模式切换。

| 时钟 | 手册标称目标 | 本版官方配置实际频率 | 说明 |
|---|---:|---:|---|
| board | 50 MHz | 输入参考 50 MHz，实物待测 | sys/mem/video/audio 共用参考 |
| sys / mem | 100 / 125 MHz | 100 / 125 MHz | 同一系统 PLL；两个锁定许可共用 extlock |
| BASE pixel / serial | 25.175 / 125.875 MHz | 25.185185185 / 125.925925926 MHz | +404.575 ppm；同 PLL 严格 1:5 |
| HD pixel / serial | 74.25 / 371.25 MHz | 74.166666667 / 370.833333333 MHz | −1122.334 ppm；同 PLL 严格 1:5 |
| audio MCLK | 12.288 MHz | 12.288135593 MHz | +11.035 ppm；若 /256，则约 48000.529661 Hz |

频率由 50 MHz 输入和整数 PLL 参数计算，不是板级实测值。BASE/HD 实际帧率分别约 59.964727/59.932660 Hz；`video_mode_defs.vh` 的频率宏保留手册标称值，不能当作实际输出证明。PLL 参数、可实现性与频差推导见 [clock_video_implementation.md](clock_video_implementation.md)。初步验证约束已有 50 MHz 参考及派生时钟；产品级引脚/外部时序、HDMI PHY、显示器与音频兼容性须另行验证。

| 输入 | 有效电平 / 所在域 | 用途 |
|---|---|---|
| `board_rst_n` | 低有效，异步 | 板级全局复位源；低电平异步断言全部输出复位 |
| `sys_clk`、`mem_clk`、`pixel_clk`、`serial_clk`、`audio_clk` | 各自 PLL 输出 | 仅给对应复位同步器采样；时钟本身不在本模块内产生 |
| `sys_pll_locked`、`mem_pll_locked`、`video_pll_locked`、`audio_pll_locked` | 高有效，异步锁定电平 | 对应域释放许可；同一 PLL 供多个域时可连接同一个 `locked` |
| `media_reset_req` | 高有效，`sys_clk` 域保持电平 | 仅复位媒体业务；跨域发起者须先完成 CDC，不可送单拍脉冲 |
| `memory_client_reset_req` | 高有效，`mem_clk` 域保持电平 | 仅复位 SDRAM 客户端，保留 `mem_rst_n` 与 SDRAM IP 刷新 |
| `hdmi_reinit_req` | 高有效，跨像素/串行域保持电平 | 只复位 HDMI 前级与串行路径；控制源须做跨域握手并稳定保持到两域均已复位 |
| `audio_reset_req` | 高有效，`audio_clk` 域保持电平 | 只复位音频消费链 |

| 输出 | 所在域 / 释放延迟 | 所属逻辑与异常策略 |
|---|---|---|
| `sys_rst_n` | `sys_clk`，RTL 第 2 拍释放 | 控制、故障锁存；不受 `media_reset_req` 影响 |
| `mem_rst_n` | `mem_clk`，RTL 第 2 拍释放 | SDRAM PHY/仲裁基础域；不受客户端局部复位影响 |
| `pixel_rst_n` | `pixel_clk`，RTL 第 2 拍释放 | Video Timing、安全画面；媒体/HDMI 局部复位不影响 |
| `serial_rst_n` | `serial_clk`，RTL 第 2 拍释放 | 串行时钟域基础复位；HDMI 重初始化不改变此基础许可 |
| `audio_rst_n` | `audio_clk`，RTL 第 2 拍释放 | 音频消费；音频 PLL 掉锁或 `audio_reset_req` 均复位，不牵连视频 |
| `media_rst_n` | `sys_clk`，RTL 第 2 拍释放 | SD/文件/媒体业务局部复位；不复位视频时序、安全画面、HDMI PHY |
| `memory_client_rst_n` | `mem_clk`，RTL 第 2 拍释放 | 帧缓存客户端局部复位；不复位 SDRAM IP |
| `hdmi_pixel_rst_n`、`hdmi_serial_rst_n` | 各自像素/串行域，RTL 第 2 拍释放 | HDMI 重初始化分域复位；不复位 `pixel_rst_n` 的视频时序 |

`locked` 拉低或相应请求拉高时，相关复位异步立即断言；各自释放条件恢复后，RTL 名义上在该域第 2 个上升沿释放。异步变化靠近采样边沿时，物理释放时刻受亚稳态与 recovery/removal 约束影响，仍须 STA 和板测核实。PLL 锁定不能证明输出频率正确；最终需 TD IP 配置、约束、STA、板级波形与上电录像。板级音频时钟由 A 接入平台，C 负责音频链消费与节拍接口。


### A Video Timing 接口补充（v1.10 冻结）

- `video_timing` 输入：`clk` 为 pixel_clk，`rst_n` 为 pixel_rst_n；Verilog-2001 编译期参数 H/V_ACTIVE、FRONT、SYNC、BACK 和同步有效电平。
- 输出：`x[11:0]`、`y[11:0]` 是 active-first 原始扫描计数，包含消隐坐标；只有 `de=1` 时可作图像坐标。`hsync/vsync/de/line_start/frame_start/active_frame_start/hblank/vblank` 均与该拍坐标对应，不带独立标签延迟。
- `line_start`：每行 x=0 单拍，包含消隐行；`frame_start`：x=0,y=V_ACTIVE 单拍，供帧交换；`active_frame_start`：x=0,y=0 单拍，不能替代帧交换事件。
- 复位断言时计数清零、de/事件为0、同步为不活动电平；本域复位释放后确定性从 (0,0) 开始。没有 ready/stall，欠载只能替换像素，不能停扫描。
- VGA：640/16/96/48、480/10/2/33，负同步；HD：1280/110/40/220、720/5/5/20，正同步；同步极性参数化，由子系统按模式一起冻结。总数须 <=4096，ACTIVE/SYNC >0、porch >=0。
- RGB 与扫描标签的端到端延迟由后续 video_pipeline 统一对齐；FWFT 不免除 SDRAM/仲裁/跨域/输出流水线总延迟测量。Video Timing 不直接消费 FIFO，也不实现尚未完成的像素域帧交换回执。
- 标签为本域当前坐标的组合译码，不作为时钟使用；跨域帧事件须经事件 CDC。HD 扫描不修改现有 640×480 RGB565 四槽缓存，原生 HD 读帧/像素策略及带宽仍待实现。

## A/B 联调参数边界

B 的 `frame_swap_ctrl` 默认 TIMEOUT_N 保持原版本；本次没有推送其默认超时修改，也没有修改 `safevision_defs.vh`。A 的帧等待测试显式实例化 TIMEOUT_N=5,000,000（100 MHz 下 50ms），用于验证合法帧量级等待；不是证明 B 的默认值已经修正。正式联调顶层需与 B 确认后显式配置参数。
