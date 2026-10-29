# 当前交付

BASE 26102801 输出 640×480 HDMI，保留任意合法名称与多尺寸 BMP、自动配音、渐变、八项菜单、运行时间和 FFT 频谱，并在底部显示 32 字中文滚动提示。

| 项目 | 身份 |
| --- | --- |
| 位流 | [SafeVision_BASE_75b34e6.bit](artifacts/releases/BASE_26102801/SafeVision_BASE_75b34e6.bit) |
| 便携 Flash 包 | [SafeVision_BASE_26102801_FLASH.zip](artifacts/releases/BASE_26102801/SafeVision_BASE_26102801_FLASH.zip) |
| SHA-256 | `1a0cf8cccdb1487b34f70e20eaa333dc106826dbc1d821be99b6a828b80b4083` |
| 批准源码 | `10168948e372d290b2f3b85428c1d07108d95883` |
| 物理构建 | `75b34e6ca2fa3517b521ccc08c6d0f4d3ea72079` |
| 发布索引 | [release.index.json](artifacts/releases/BASE_26102801/release.index.json) |
| 逐文件交付清单 | [delivery.manifest.json](artifacts/releases/BASE_26102801/delivery.manifest.json) |

批准提交绑定源码、验证工具和依赖。后续交付提交增加说明与板测证据，位流仍按发布索引识别。程序的 UART 固件标识为 `26102801`；完整位流身份用 SHA-256 核对。

`release.index.json` 保存烧录前的批准状态，硬件与 Flash 标志保留当时的值。实际安装结果见 `flash/receipt.json`，完整板测和逐文件身份见 `board` 与 `delivery.manifest.json`；历史批准记录不随后续操作改写。

## 本版板测

本版保留最初的实际 SRAM 下载回执；Flash 固化、校验和重载后，从零采集启动、配置、缩放、轮播周期、100 次换图、10 次恢复及 60 秒连续观察。原始数据位于 [board](artifacts/releases/BASE_26102801/board)。连续运行前完成 100 次有效换图和 10 次媒体恢复，并写入、读回默认参数。原始 ACK 与派生汇总由独立工具重新核对，实体画面和声音反馈单独保存在 [physical_acceptance.json](artifacts/releases/BASE_26102801/board/physical_acceptance.json)。

构建时使用原板级管脚、50 MHz 参考时钟、SDRAM 时钟预算和全部 Slow/Fast 检查。原始报告位于 [资格归档](artifacts/releases/BASE_26102801/qualification.zip)，统计和报告指纹同时写入发布索引。

## Flash 与恢复

板载 EF4015 Flash 已写入 BASE 26102801。安装执行器件识别、两次 2 MiB 原始备份、`program_spi`、`verify_spi`、两次 2 MiB 读回和 `refresh`，各阶段的命令及日志保存在 [flash](artifacts/releases/BASE_26102801/flash)。重载后串口固件标识为 `26102801`，四槽有效，启动健康计数为零。

安装前两份完整备份一致，SHA-256 为 `a5f548e3c02d2315fb17640c08e713fbd9831ceec3090112dc5bfd1a6747ab7a`，其内容与旧归档不同，按原始读出内容保存。安装后两份读回一致，SHA-256 为 `634dd515f442560b297b96bd4cdd4b71bbbff107ef8ba916a6dc6f8a6206265d`。完整 Flash 镜像与 `.bit` 使用不同封装，校验值分别记录。

旧成功 BASE 26102301 位流及恢复脚本位于 [recovery](artifacts/releases/BASE_26102801/flash/recovery) 和 [program_flash.ps1](artifacts/releases/BASE_26102801/flash/tools/program_flash.ps1)。该旧版的完全断电反馈见 [原始记录](evidence/board/cold_boot_261025_user_report.json)。本版另经用户完全断电重接，用户确认图片、声音、字幕、UP 计时和频谱正常，原话及证据范围见 [cold_boot_user_report.json](artifacts/releases/BASE_26102801/board/cold_boot_user_report.json)。随后只读串口确认本版固件、四槽有效和零健康错误；实体断电动作按用户反馈登记。

## 复查

在项目根目录运行 `python -B safevision/tools/verify_ticker_flash_delivery261029.py --run-dir <新的空目录>`。它核对当前源码、位流、归档、原生时序和串口数据，同时在冻结的 `09faac2` 基线中复查 BASE 26102301 的原资格。另运行 `python -B safevision/tools/verify_ticker_flash261028.py --output <新的结果文件>` 复查 Flash 安装、完整读回及重载串口的原始证据。复查使用保存的采集和报告，实体板卡测试由操作手册中的主机脚本执行。

## 本次安装验收范围

按用户于 2026-10-29 的要求，两小时长测不作为本次交付条件。安装验收使用 60 秒连续观察、100 次有效换图和 10 次恢复，其他配置、缩放、周期、功能与原生时序检查保留。具体条件见 [acceptance.policy.json](artifacts/releases/BASE_26102801/acceptance.policy.json)，此前长测的串口中断原件单独归档，不记为两小时通过。原两小时审核入口 `verify_ticker_ci.py` 保持原样。
