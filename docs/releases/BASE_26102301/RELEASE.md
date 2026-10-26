# BASE 26102301 正式交付

任意名称、多尺寸 BMP、自适应长宽比、自动配音、512 点 FFT/32 频段、秒级 UP、实体八项菜单、四图自动轮播及应急恢复整合到同一份 BASE 640×480 位流。用户已确认图片、声音、频谱，并提供菜单实物照片。

- 下载：[SafeVision_BASE_6a957b0.bit](../../../artifacts/releases/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit)
- 批准源码：`6a957b0365adbc8d8b4069319d29c9fb63680428`
- 物理构建：`c6a6549871d97755708120d2a76239011cef94bb`
- 位流 SHA-256：`95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e`
- [菜单详解](MENU_CN.md) · [使用与恢复](OPERATIONS.md) · [分层验收](ACCEPTANCE.md)
- 既有完整本地冻结包仍保留；本次 GitHub 精简包包括同一位流、原始完整 STA/异常/资源报告、206 个输入指纹、真实 Flash 与串口证据、旧版恢复文件。

## 项目职责与数据流

| 层/目录 | 职责 |
| --- | --- |
| safevision/rtl/storage | TF/FAT32/LFN、排序、BMP/WAV 解析、四槽 SDRAM 缓存、CRC 与环缓冲 |
| safevision/rtl/video | 等比例后的画布坐标、插值、色彩、Fade、图层、HUD/频谱合成 |
| safevision/rtl/audio | PCM 调度、音量、报警优先级及 HDMI 音频服务 |
| safevision/rtl/control | 实体按键、菜单、UART、轮播与故障恢复 |
| safevision/platform | 板级 top、管脚、时钟/复位、厂商 IP 及 TD 工程 |
| safevision/build/manifests + verification | 显式源清单、独立参考、正向/负向/恢复测试 |
| docs/architecture + changes | 跨域、握手、generation、错误触发与修正依据 |
| artifacts/releases/BASE_26102301_6a957b0 | 本次可用位流、原始证据及可核验清单 |

总体媒体/音视频图见 [架构说明](../../architecture/flexible-media-and-spectrum.md)。保留 A 视频、B 存储、C 控制/音频/安全的职责边界；本轮不为整理文件而改动已经通过的 RTL。

用户于 2026-10-25 确认真实掉电重启正常，补充记录见 [验收](ACCEPTANCE.md)。当前批准仅为 BASE。历史 HD、旧位流和旧失败记录保留为历史，不作为当前下载入口。
