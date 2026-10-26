# 项目结构

生产源码、验证代码、原始证据和发布文件分别保存。新成员从根目录 README 和当前版本入口开始；历史交接文档按记录日期阅读。

| 目录 | 用途 | 修改时注意 |
| --- | --- | --- |
| `safevision/rtl/storage`、`rtl/media` | SD/FAT32、文件名、BMP/WAV、流与描述符 | 尺寸/长度边界、坏文件跳过、目录完整扫描、反压 |
| `safevision/rtl/memory` | SDRAM 请求仲裁、帧写入、行校验 | 请求接受时刻、读回数据有效、地址与掩码 |
| `safevision/rtl/video` | 行缓存、缩放、颜色、渐变、图层、HUD、频谱 | 像素与同步标签对齐、帧边界提交 |
| `safevision/rtl/audio` | PCM 队列与环缓存、48 kHz 调度、音量、报警 | 声道/槽标签、跨域、下溢和媒体复位 |
| `safevision/rtl/control`、`rtl/safety` | 按键、菜单、UART、监控及恢复 | 计时频率、配置保留、事件时间戳与优先级 |
| `safevision/platform/anlogic_eg4s20_hx4s20c` | 生产顶层、管脚、时钟、TD 工程和厂商 IP | 使用实际生产清单与约束，保留 IP 来源 |
| `safevision/build/manifests` | 仿真/综合显式输入清单 | 新文件需要进入对应清单 |
| `safevision/build/qualification` | 固定需求、测试和输入身份 | 修改后重新检查受影响证据 |
| `safevision/verification` | 单元、子系统、整机、参考模型和负控 | 检查正常结束，保留检错证据 |
| `safevision/tools` | 构建、时序、输入、记录和交付检查 | 默认使用只读检查入口 |
| `docs/modules` | 当前生产模块说明 | 以实际端口和顶层连接为准 |
| `docs/debug` | 调试时间线和查找入口 | 新记录给出触发、修正、验证和边界 |
| `evidence/v3` | 既有离线执行记录 | 原始字节保持不变 |
| `evidence/debug_history` | 本次收录的本地历史记录无损归档 | 索引保留原路径、大小和 SHA-256 |
| `evidence/board` | 原始板测及用户实物反馈 | 明确机器采集与用户确认的区别 |
| `artifacts/releases/BASE_26102301_6a957b0` | 当前冻结发布包 | 保持 82 份负载文件及索引的原始字节 |
| 其他 `artifacts/releases` | 成功历史包和恢复资料 | 按历史版本验收，不替代当前入口 |

## 当前数据通路

TF 扇区经共享文件系统送入目录索引、BMP 归一化与 WAV 解析。四幅批准后的图像常驻 SDRAM，视频行缓存从当前和目标槽取数，再执行缩放、渐变、颜色调整与图层合成。音频通过描述符选择伴音，经 PCM 环缓存和调度后送往 HDMI；频谱观察处理后的实际左声道 PCM。

控制链通过按键或 UART 设置参数。图像和伴音使用同一 generation 协调提交。安全链监测进展、心跳、完整性和欠载状态，必要时选择片上文字与几何逻辑产生的 SAFE 画面。

## 当前资料与历史资料

[模块手册](modules/README.md)、[官方赛题对应](requirements/official_problem1.md) 和 [当前验收](releases/BASE_26102301/ACCEPTANCE.md) 描述当前 BASE。`docs/v3`、早期 A/B 交接文档及旧版本 REQUIREMENTS 反映当时状态，可能使用不同的 E01 至 E05 编号。[历史索引](history/README.md) 保留这些入口。

本地 `D:/Safe_Vision_FPGA_2026/artifacts/archive` 保存此前调试工作区的归档；`codex_v3_checkpoints` 和本地未跟踪诊断源保持原位。清理清单仅处理旧交付包中与保留路径完全相同的副本。原始成功位流、故障日志、时序报告和当前验证依赖继续保留。
