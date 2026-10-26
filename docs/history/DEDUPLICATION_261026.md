# 旧交付包重复副本清理与恢复

本次清理 14688 份重复文件，逻辑大小合计 549393778 字节。它们来自 `BASE_MEDIA_ALIAS_261022_34462ee` 与 `BASE_MEDIA_ALIAS_261022_34462ee_WINFIX1` 的 `source/` 子树，每份都有相同 Git blob、大小及 SHA-256 的保留路径。

清理前逐文件比对主项目原件与保留副本。后续说明文档修改后再次比对，已产生差异的历史文件继续保留。另将待清理文件保存为本地 ZIP 并解压核对每份 SHA-256。备份为 `D:/Safe_Vision_FPGA_2026/artifacts/archive/repository_cleanup_261026/duplicate_payloads.zip`，SHA-256 为 `ce1f36318bbca5f2c0b2494dfd7686032cf00e6b3fd764677bf1e8f9bee2411d`。

成功位流、原始路由报告、恢复文件和独有源快照保留。当前 BASE 的 206 个生产输入、82 个发布负载及完整离线证据依赖保持原位。两个历史包的原始全目录继续保存在 Git 提交 `3f32c8a4b755d5bb315b910afc8b7ee506e1c14c`，固定发布标签未移动。

## 恢复

逐文件清单见 [duplicates.json](../../evidence/repository_cleanup_261026/duplicates.json)。`removed` 是旧包中的路径，`retained` 是当前保留路径，`git_blob` 和 `sha256` 固定其内容。

`python -B safevision/tools/restore_debug_records.py --duplicates --output D:/SafeVision_Duplicate_Restore` 预演恢复；添加 `--apply` 才会写入空目标目录。恢复时从保留副本取字节并核对，必要时读取固定 Git blob。原始本地 ZIP 也可在空目录直接解压。

旧包的原始索引保持不变。若需要按旧索引重放完整历史包，先恢复被移出的重复文件；当前日常使用从 [最新版本](../../SAFEVISION_CURRENT.md) 开始。

清理数字表示被移出工作树的逻辑字节。Git 历史保留，仓库对象不会因普通删除提交立即消失；新增记录归档、本地恢复备份和文件系统分配也影响实际可用空间。
