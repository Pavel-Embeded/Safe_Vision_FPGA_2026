# SafeVision FPGA 2026

SafeVision 在康芯 HX4S20C 开发板上运行，使用安路 EG4S20BG256。FPGA 完成主要媒体处理和控制。当前稳定版为 BASE 26102301，HDMI 输出 640×480，用于验证视听信息发布终端。

系统读取 FAT32 根目录中的 BMP 和 WAV，按名称选择前四张有效图片，等比例适配并装载到 SDRAM。播放链支持自动配音、32 帧渐变、实体菜单、运行时间和 512 点 FFT / 32 频段频谱。用户已确认图片、声音、频谱和菜单正常，并于 2026-10-25 反馈真实掉电重启正常。

| 入口 | 内容 |
| --- | --- |
| [文档入口](docs/README.md) | 当前说明、历史记录与阅读顺序 |
| [当前版本](SAFEVISION_CURRENT.md) | 位流、源码身份和验收状态 |
| [项目结构](docs/PROJECT_STRUCTURE.md) | 目录用途、当前资料与历史资料的边界 |
| [模块手册](docs/modules/README.md) | 接口、时钟、复位、握手和测试入口 |
| [调试记录](docs/debug/README.md) | 故障时间线、逐次记录和原始日志 |
| [赛题对应](docs/requirements/official_problem1.md) | 四类基础要求、五类扩展要求及证据 |
| [操作与恢复](docs/releases/BASE_26102301/OPERATIONS.md) | TF 卡准备、按键、Flash 和旧版恢复 |
| [菜单说明](docs/releases/BASE_26102301/MENU_CN.md) | 八项参数、状态数字与实物照片 |
| [验收记录](docs/releases/BASE_26102301/ACCEPTANCE.md) | 离线测试、时序、实板和冷启动记录 |

## 使用

1. 下载 [SafeVision_BASE_6a957b0.bit](artifacts/releases/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit)，按 [当前版本](SAFEVISION_CURRENT.md) 核对 SHA-256。
2. TF 卡使用 FAT32，根目录放至少四张合法的 24 位或 32 位 BI_RGB BMP。支持中文长文件名；超过四张时按确定的名称字典顺序选图。
3. 默认每张稳定停留 5 秒。KEY2 手动换图，KEY3 切换自动播放；KEY2+KEY3 同时长按约 2 秒进入菜单。按键细节见 [菜单说明](docs/releases/BASE_26102301/MENU_CN.md)。
4. 在仓库根目录运行 `node safevision/tools/verify_base_release.mjs`，核对原始发布包和 206 个生产输入；运行 `python -B safevision/tools/audit_repository_records.py`，核对后续实物反馈、调试归档及去重清单。

## 已有验证

| 项目 | 结果 |
| --- | --- |
| 离线功能 | 303 个独立正向 top、304 条含别名记录、221 项语义负控 |
| 原生 Slow/Fast 时序最小裕量 | setup +0.195 ns；hold +0.030 ns；recovery +3.767 ns；removal +0.038 ns |
| 资源 | LUT 18749/19600；REG 13875/19600；等效 RAM 63/64；DSP 29/29 |
| Flash | 写入、独立校验、完整回读及重载后的串口验收通过 |
| 串口 | 原始记录中的 5016 帧 ACK 独立核对通过 |
| 实物 | 用户确认图像、声音、频谱、实体菜单和真实掉电重启正常 |

冷启动依据为 [用户实物反馈](evidence/board/cold_boot_261025_user_report.json)，测试次数和现场串口日志未提供。2026-10-23 冻结包保留当时的待验状态，后续状态以 [验收更新](evidence/board/acceptance_updates.json) 为准。

当前批准范围为 BASE。长期运行、多 TF 卡和多显示器兼容性继续按具体测试记录验收。自动感光、图片内容自动亮度和主峰频率数字显示尚未进入当前位流。厂商加密 IP 的接口验证、原生时序与实际板测分别记录。

开发要求见 [CONTRIBUTING](CONTRIBUTING.md)，依赖来源见 [第三方说明](THIRD_PARTY_NOTICES.md)。[GitHub Actions](https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026/actions/workflows/base-qualification.yml) 复核源码及已有证据，不执行实体板卡测试。
