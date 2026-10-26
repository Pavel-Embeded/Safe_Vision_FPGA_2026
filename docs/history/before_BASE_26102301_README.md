# SafeVision FPGA 2026

面向康芯 HX4S20C / 安路 EG4S20BG256 的 HDMI 多媒体与应急终端。工程分为媒体存储、视频处理、音频与控制、板级适配和独立验证，保留明确接口、时钟复位契约、构建清单和原始证据。

## 当前 BASE 整合版本

目标固件 ID 为 `26102301`，输出 640×480。任意名称、多尺寸 BMP、自动配音和真实音频频谱整合到同一个 BASE 工程。旧 `26102237` 因真实板测行完整性错误已撤回；本版本修正其写缓存时钟，并重新进行完整功能、原生时序、位流和实板验证。

最终允许下载的文件以本地交付包的 `release.index.json`、位流 SHA-256 和同一份程序的板测记录为准。 源码实现、仿真通过、时序通过、生成位流、下载成功和实板功能是独立验收步骤。本文不替代这些原始记录；HD 当前不在 BASE 批准范围。

通过验收后的交付包位于本地 `D:\Safe_Vision_FPGA_2026\artifacts\releases\BASE_FLEX_SPECTRUM_261023_<批准提交前7位>`。本轮不上传 GitHub，不修改 TF 卡或 Flash。旧成功版本保留作对照和恢复入口，不能混同为新频谱程序。

| 入口 | 内容 |
| --- | --- |
| [媒体与频谱架构](docs/architecture/flexible-media-and-spectrum.md) | 命名、格式范围、模块接口、数据流、频谱和限制 |
| [写通路修正与最新时序](docs/changes/BASE_WRITE100_REPAIR_261023.md) | 实板故障、真实时钟、地址流水线、完整物理结果 |
| [功能整合变更记录](docs/changes/BASE_FLEX_MEDIA_SPECTRUM_261022.md) | BMP/WAV/LFN/FFT 的修正与正负验证依据 |
| [开发与评审规范](CONTRIBUTING.md) | 模块边界、变更、回归和发布流程 |
| [上一成功 BASE 的使用说明](docs/releases/BASE_26102004/OPERATIONS.md) | 原有实体按键和串口协议；媒体与频谱差异以当前说明为准 |
| [历史首页](docs/history/README_BEFORE_FLEX_261023.md) | 已跑通的旧程序和原始交付入口 |

## 使用和功能

- FAT32 卡根目录至少四张合法 BMP。允许中文和长文件名；按完整名称的确定字典顺序取前四张有效图，坏文件跳过。旧图仍参与排序，不能假定取最后复制的四张。
- BMP 支持 24 位 BGR 或 32 位 BGRX 的 BI_RGB，单轴 1 至 16384，正负高度及行填充；居中等比例适配、正确黑边。调色板、RLE、位掩码、JPG/PNG 和截断文件会安全拒绝。
- WAV 优先完整同名主干，否则按轮播槽使用稳定目录顺序的 WAV；坏音频有界重试，穷尽使用内置提示音。支持 48 kHz、16 位、双声道 PCM WAV。
- 默认 5 秒轮播，可选 2/5/10/30 秒；手动切图、32 帧 Fade、四层 Alpha、最近邻/双线性缩放、亮度、对比度、自适应亮度和音量保留。
- 左下角 `UP … s` 每秒增加。右下角为实际 HDMI 左声道 PCM 的 512 点 FFT、32 频段频谱，含频率标记、参考刻度和峰值保持；持续纯音集中在少数频段是正常行为。
- KEY2+KEY3 同时长按约 2 秒进入菜单，短按 KEY2/KEY3 增减，长按 KEY2 切换项目，长按 KEY3 退出；参数在画面回显。应急、独立报警和最多三次的故障恢复继续保留。

更换卡片后用 KEY1/RESET 重新扫描。下载使用 PROGRAM_SRAM；断电或 CONFIG1 会重新加载 Flash 中的旧程序。图片装载耗时随文件大小和 TF 速度变化，不能只凭安全画面仍显示就判断失败，应结合串口的加载进展和错误信息。

## 验证与物理资源

主功能门禁包含 303 个独立正向顶层和 221 个必须正常结束并检出错误的语义负控；另有写缓存时钟、完整帧读回、音频入口、WAV 上下文、地址运算、流水线和原生时钟归属的强制附加检查。输入变化的捕获实际重跑，输入字节一致的旧捕获保留来源后复核，不能把复核说成全部重跑。

匹配物理源码 `c6a6549871d97755708120d2a76239011cef94bb` 的 BASE 已正常完成实际 TD 综合布局布线，Slow/Fast 的 3320 条报告路径无负裕量。Setup/Hold/Recovery/Removal 最小值分别为 +0.195/+0.030/+3.767/+0.038 ns；206 个物理输入、实际写时钟和约束命中均独立复核。

| 资源 | 实际占用 |
| --- | ---: |
| LUT | 18749 / 19600 |
| 寄存器 | 13875 |
| 等效 9K RAM 单元 | 63 / 64 |
| DSP | 29 / 29 |

门槛为芯片实际容量和真实布局布线、时序通过；旧 80%/85% 内部目标不再否决。RAM32K 每个消耗四个等效 9K 单元。厂商加密 IP 内部不能由行为模型直接证明；显示器兼容性、实体频谱观感与长时间运行仍需要对应实板记录。

## 工程与复核入口

```text
safevision/rtl/                  媒体、缓存、视频、音频、控制与安全 RTL
safevision/platform/             管脚、时钟、厂商 IP、生产顶层与 TD 工程
safevision/build/manifests/      显式仿真源文件清单
safevision/verification/         独立模型、单元/整机测试与故障注入
safevision/tools/                仿真、构建、源输入绑定、审计与发布工具
evidence/v3/                    原始日志、完整输入 SHA、正负控制和历史
docs/architecture/              接口、时钟、握手及媒体规则
docs/changes/                   错误触发条件、修正和验证边界
artifacts/releases/             成功历史和最终冻结交付包
artifacts/board_acceptance/      实际 SRAM 下载及串口板测
```

最终包包含 `verify_payload.py`，使用 Python 3.11+、Git、pypdf 和 NumPy，传入含批准提交及冻结参考历史对象的完整 Git 项目即可离线复核。脚本不联网、不烧录；最终包的自检回执分别绑定实际源码、证据、原始时序报告和位流。Windows 深目录检出需要仓库级 `core.longpaths=true`。

主验收工具为 `safevision/tools/audit_v3_four_features.py`，原生构建为 `run_v3_board.py`，严格批准与位流生成为 `finalize_v3_four_features.py`。BASE 工程输出必须显式使用 `--engineering-base-only`，不得据此宣称 HD 或双模式发布通过。
