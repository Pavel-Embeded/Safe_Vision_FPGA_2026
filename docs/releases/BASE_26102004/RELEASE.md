# BASE 26102004 / KEYFIX 5cff94e 发布说明

交付日期：2026-10-21（Asia/Shanghai）。发布范围：已经验证的 BASE；不授予当前 HD 发布资格。

## 精确版本

| 字段 | 值 |
|---|---|
| 板卡 / 器件 | 康芯 HX4S20C / EG4S20BG256 |
| 顶层 / 模式 | `safevision_v3_top` / `HD=0` |
| 运行时 ID | `26102004` |
| 设计构建提交 | `9c789eaddd514997c534602026ca14d20b03edbe` |
| 冻结批准提交 | `5cff94eb70e800337e4617dbfa44349066f3d504` |
| 位流 | [`SafeVision_BASE_5cff94e.bit`](../../../artifacts/releases/BASE_26102004_5cff94e/SafeVision_BASE_5cff94e.bit) |
| 字节数 | 644770 |
| SHA-256 | `394a0f8151142886c3c950e3ea7220727258eb97dc8f8c7f73c954e8ef04f42d` |
| 工具 | TD V6.2.168116；原生工具哈希在批准清单中 |
| 物理输入 | 198 个，包含模式、RTL、IP、ROM、管脚、约束和构建控制 |

仓库交付提交将详细文档、实板记录和合格源文件整理到远端已有 main 之上。它没有重新运行综合或改变位流字节。原设计/批准提交用[稀疏审计对象包](../../../artifacts/releases/BASE_26102004_5cff94e/audit-object-inventory.json)保留精确对象身份，供原版验证器读取；该包不是开发历史的完整克隆，也不应作为 Git 历史分支推送。

## 本次集成内容

相较仓库此前 2026-10-16 离线版本，集成后续已完成的 SDRAM 实板修复、稳定四图播放、自动轮播及 HDMI 音频、参数配置、四项显示功能和独立证据。保留队友原基线与既有文件；不把实验缓存、安装包、许可证或未合格 HD 候选作为交付物。

最后一次修复解决了实体按键与逻辑端口不一致：旧 ADC 和其复制参考表共同将 KEY3/KEY4 交换。原厂手册第 19 页规定 KEY3=B1、KEY4=C1。修正后 `btn_auto=B1`、`btn_emergency=C1`；原始封装 PAD 报告也已检查。该修复未改变功能 RTL 或 SDC 字节，额外增加 11 个管脚负控及 89 次实际 HDL 手势比较。详见[错误报告](../../v3/BASE_KEYFIX_5cff94e_验收记录.md)。

## 交付文件

- `qualification.zip`：原封不动的完整批准包，包含源文件、独立参考、288/202 原始证据、原始板卡 PDF/管脚负控、STA、布局数据库与原版验证器。
- `native/base/`：便于浏览的原始工具报告与数据库副本；绝对路径是当时构建路径，保留不改写。
- `approval.index.json` / `release.index.json`：当时生成的不可变批准收据。
- `delivery.manifest.json`：本次交付字节、源码、实板证据、ZIP 与对象包的 SHA-256 索引。
- `artifacts/board_validation/four_features_BASE_KEYFIX_5cff94e/`：实际烧录、串口、按键确认及不完整采集的明确记录。

旧批准收据中的 `github_uploaded=false`、`hardware_verified=false` 是生成时的事实，不通过修改原始收据覆盖后续状态。后续实板结果以板测目录为准；本次 GitHub 发布提交及本地同步结果另存交付收据。

## 时序与资源

BASE 已完整重新综合、布局布线，并在独立新进程对最终布局数据库执行 STA。Slow/Fast setup、hold、recovery、removal 无负裕量；实际约束对象、I/O 范围、时钟定义、厂商 ROM、独立采样寄存器及资源门槛通过。

| 指标 | 实测 |
|---|---:|
| 全局 setup WNS / TNS | +0.145 ns / 0 |
| 全局 hold WNS / TNS | +0.029 ns / 0 |
| 细分最小 setup / hold | +0.145 ns / +0.030 ns |
| 细分最小 recovery / removal | +4.212 ns / +0.029 ns |
| LUT / DFF | 18170/19600；13116/19600 |
| RAM9K / RAM32K | 44；4 |
| 物理 RAM9K 等效 | 44 + 4×4 = 60/64 |
| DSP / PLL | 18/29；3/4 |

全局与细分 hold 精度/汇总口径不同，保留原值。详细门槛见 [VERIFICATION](VERIFICATION.md)，使用说明见 [OPERATIONS](OPERATIONS.md)。
