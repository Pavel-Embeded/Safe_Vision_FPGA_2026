# 当前交付

当前稳定版本为 BASE 26102301，输出 640×480。2026-10-26 的整理更新文档和记录，硬件位流保持原字节。

| 项目 | 身份 |
| --- | --- |
| 位流 | [SafeVision_BASE_6a957b0.bit](artifacts/releases/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit) |
| SHA-256 | `95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e` |
| 批准源码 | `6a957b0365adbc8d8b4069319d29c9fb63680428` |
| 物理构建 | `c6a6549871d97755708120d2a76239011cef94bb` |
| 固定发布标签 | `base-26102301`，保留原交付提交 |

Flash 写入和独立校验通过，双份完整回读一致，重载后的完整串口验收通过。用户于 2026-10-25 确认真实掉电重启正常；[冷启动反馈记录](evidence/board/cold_boot_261025_user_report.json) 保存原话和证据类型，未填写未知的测试次数。

原始 [release.index.json](artifacts/releases/BASE_26102301_6a957b0/release.index.json) 和机器日志固定了 2026-10-23 的交付字节。当前实物验收补充见 [acceptance_updates.json](evidence/board/acceptance_updates.json)，二者共同说明版本和验证状态。

使用见 [菜单](docs/releases/BASE_26102301/MENU_CN.md) 与 [恢复说明](docs/releases/BASE_26102301/OPERATIONS.md)。旧成功版本及恢复文件保留。两份旧发布包内的重复源码/证据副本按 [去重恢复说明](docs/history/DEDUPLICATION_261026.md) 取回，HD 试验仍按各自历史结果读取。
