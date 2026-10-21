# SafeVision FPGA 2026

面向康芯 HX4S20C / 安路 EG4S20BG256 的 HDMI 多媒体播放与应急终端。工程按媒体存储、视频显示、音频控制和板级适配组织，交付源码、显式构建清单、原始验证证据及可追溯位流。

**当前推荐：BASE 640×480，功能版本 `26102004`，按键修复批准 `5cff94e`。** 此 BASE 已完成全功能证据复核、综合布局布线、全部 Slow/Fast 时序及 SRAM 实板下载；用户已确认四图轮播和声音、秒计时、PCM 波形，以及修复后的实体按键菜单/亮度/对比度操作。不同观察属于各自验收轮次，详见[验证分层](docs/releases/BASE_26102004/VERIFICATION.md)。**当前 HD 未通过发布门槛**；历史 HD 位流不代表当前功能版本通过。

| 入口 | 内容 |
|---|---|
| [下载最新 BASE](artifacts/releases/BASE_26102004_5cff94e/SafeVision_BASE_5cff94e.bit) | 已实际烧录的位流，644,770 字节 |
| [发布说明与精确身份](docs/releases/BASE_26102004/RELEASE.md) | 提交、SHA-256、资源、时序、兼容性与限制 |
| [快速使用与按键](docs/releases/BASE_26102004/OPERATIONS.md) | TF 卡、下载、菜单、串口与故障定位 |
| [架构与接口](docs/releases/BASE_26102004/ARCHITECTURE.md) | 模块职责、数据流、时钟域、复位、延迟与握手 |
| [需求与验收矩阵](docs/releases/BASE_26102004/REQUIREMENTS.md) | 基础/扩展功能、实现位置与实际验证边界 |
| [验证与原始证据](docs/releases/BASE_26102004/VERIFICATION.md) | 288 正向、202 语义负控、管脚、STA、实板串口 |
| [复核及构建](docs/releases/BASE_26102004/BUILD.md) | 新克隆复核、精确冻结源码与 TD 构建命令 |
| [开发与变更规范](CONTRIBUTING.md) | 分模块开发、评审、回归与发布标准 |

## 功能

- FAT32/SD SPI、合法 BMP/WAV 扫描、四幅图片常驻 SDRAM、CRC32/写入读回检查、坏文件跳过。
- 手动切图，2/5/10/30 秒轮播，默认 5 秒；帧边界提交、32 帧 Fade、四层 Alpha 合成。
- 1–1920 × 1–1080 的 24 位无压缩 BMP，支持 top-down/bottom-up 与行填充；等比例归一化到 640×480，输出支持最近邻/双线性及多种显示几何。
- 48 kHz PCM 音频、四路环形缓存、音画 generation 提交、独立报警音与 SAFE 恢复路径。
- 左下角 `UP … s` 每秒递增；右下角显示实际 HDMI 左声道 PCM 的青色波形，128 样本窗口，已取消音量柱。
- KEY2+KEY3 长按约 2 秒进入菜单，亮度、对比度、音量、缩放等参数在画面回显；UART 查询、设置与回执。
- 已完成手动亮度/对比度调节；自动/自适应亮度尚未在当前合格源实现，作为明确开放项保留。

## 当前 BASE 指标

| 项目 | 实际结果 |
|---|---:|
| LUT | 18,170 / 19,600（92.70%） |
| DFF | 13,116 / 19,600（66.92%） |
| 物理 RAM | 60 / 64 个等效 9K 单元（93.75%） |
| DSP / PLL | 18/29；3/4 |
| 全局 setup / hold WNS | +0.145 ns / +0.029 ns |
| 工具 / 器件 | TD V6.2.168116 / EG4S20BG256 |

RAM32K 每个消耗 4 个物理 9K 单元，不能把 RAM9K 与 RAM32K 当作独立容量相加。本次门槛为器件实际容量及完整时序通过；旧 80%/85% 内部资源目标不再作为否决门槛。

## 目录

```text
safevision/rtl/                    可移植媒体、缓存、视频、音频、控制与安全 RTL
safevision/platform/.../           管脚、PLL、SDRAM/HDMI IP、生产顶层及 TD 工程
safevision/build/manifests/        显式仿真源文件清单
safevision/tools/                  构建、审计、时序门槛与发布工具
safevision/verification/           单元/系统测试、独立参考模型与故障注入
evidence/v3/                       当前验收依赖的原始日志、清单和负向控制
artifacts/releases/BASE_.../       位流、完整冻结验收包、原始物理报告和发布清单
artifacts/board_validation/.../    实际 SRAM/串口与用户按键验收记录
artifacts/test_media/.../          多尺寸 BMP 和已知 PCM 测试媒体；实卡测试待验
docs/releases/BASE_26102004/       本次发布的唯一当前状态入口
docs/history/                     保留的历史项目首页
```

## 完整性复核

Windows 安装 Python 3.11+、Git 和 `pypdf` 后，在仓库根执行：

```powershell
python -m pip install pypdf==6.10.0
python -B safevision/tools/verify_base_delivery.py --run-dir D:/sv_verify/base_20261021
```

使用全新、仓库外的纯英文输出目录。工具会核对交付文件、恢复原始内容寻址证据对象，并重放原版验收器。它不需要 TD、板卡或串口；离线复核不能代替实物测试。依赖版本以[构建说明](docs/releases/BASE_26102004/BUILD.md)和验证环境清单为准。

**仍待验收：** 当前 HD 布线/时序、不同尺寸图片的实体 TF 卡显示、最大媒体恢复预算、广泛 HDMI 设备兼容性及长时间实板运行。查看[开放事项](docs/releases/BASE_26102004/REQUIREMENTS.md#开放事项)。历史说明保留各自日期与结论，不能覆盖当前发布清单。
