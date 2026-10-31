# SafeVision FPGA 2026

SafeVision 使用安路 EG4S20BG256，从 TF 卡读取图片和音频，经 SDRAM 缓存后输出到 HDMI。BASE 输出为 640×480、约 60 Hz，可用于站内指引、公共展陈和应急提示。

![Source checks](https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026/actions/workflows/source-checks.yml/badge.svg?branch=main)

## 当前功能

- 扫描 FAT32 根目录中的 BMP，按文件名顺序选择前四张。支持长文件名、中文名及不同尺寸图片。
- 等比例显示图片，保留必要黑边；提供最近邻、双线性和显示比例设置。
- 优先播放同名 WAV，随后按播放顺序匹配卡内音频；使用片上提示音处理音频回退。
- 支持手动换图、自动轮播、帧边界提交和 32 帧 Fade。
- 通过按键菜单调节亮度、对比度、音量等参数，画面同步显示设置值。
- 显示启动秒数、运行状态、中文滚动提示和音频频谱。
- 监测媒体、缓存及显示通路；故障时输出安全画面和报警音，并执行有次数限制的恢复流程。

已验收的 Flash 固件为 `26102801`，对应构建源码 `75b34e6`。图片、声音、频谱、字幕、菜单及真实断电重启均已在开发板上确认。源码整理、仿真和综合的记录见[验证说明](docs/verification.md)。

RTL、HDL 参考模型和测试平台使用 Verilog-2005。构建、数据生成和串口工具使用 Python、PowerShell、Tcl。四份厂商受保护 IP 由 TD 工程加载，并按原始文件校验值核对。

## 工程目录

| 路径 | 内容 |
| --- | --- |
| `safevision/rtl/` | 媒体、存储、视频、音频和控制逻辑 |
| `safevision/platform/anlogic_eg4s20_hx4s20c/` | 板级顶层、时钟、厂商 IP、管脚和时序约束、TD 工程 |
| `safevision/assets/` | 字库、提示音及初始化 ROM 数据 |
| `safevision/build/manifests/` | 仿真源文件、测试顶层和数据依赖清单 |
| `safevision/verification/` | HDL 测试平台与参考模型、Python 激励工具及对照实验 |
| `safevision/tools/` | 构建、检查、仿真和串口工具 |
| `.github/workflows/` | GitHub 自动检查 |

构建输出放在仓库外。每份固件归档保存原始日志、位流和 Flash 恢复文件。

## 开始使用

使用康芯 HX4S20C 开发板，连接 TF 卡、HDMI、Type-C 串口及 JTAG 下载器。TF 卡至少放入四张合法 BMP；媒体格式和按键操作见[使用说明](docs/operation.md)。

在仓库根目录执行以下命令，`python` 应指向 Python 3.12：

```powershell
python -B safevision/tools/check_source_tree.py
python -B safevision/tools/check_verilog.py --compile --elaborate --run-dir D:/sv_runs/verilog_check
python -B safevision/tools/check_source_tree.py --simulate --output D:/sv_runs/base_regression
```

第二条命令需要 Icarus Verilog；第三条命令默认使用 `D:/Xilinx/Vivado/2018.3/bin` 中的 XSim，可通过 `--xsim-bin` 指定其他位置。每次运行使用新的输出目录。

BASE 的 TD 工程入口：

```text
safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/base/safevision_v3_base.al
```

## 开发资料

- [模块、数据流和复位关系](docs/architecture.md)
- [工具版本、构建和回归命令](docs/build.md)
- [TF 卡、按键、菜单和串口](docs/operation.md)
- [验证范围和迁移记录](docs/verification.md)
- [第三方 IP 与字体许可](THIRD_PARTY_NOTICES.md)
