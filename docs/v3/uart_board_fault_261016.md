> 历史记录整理版。内容对应原记录的版本与日期，当前验收请查仓库首页；原件按索引保留。

# 2026-10-16 实板串口排查：F3 完整性故障

当前仍未完成实板修复验收。所有更新仅保存本地，未上传 GitHub。原始记录在 `evidence/v3/board_uart_20261016/`，不能用仿真或示例替代这些数据。

## 两个已经确认的问题

1. 初次 COM6 采集实际输出 `SV-WPR3 / ID=26101003`，不是 V3 发布版的命令协议。旧日志重复出现 `EC=F3 PH=3`。不能把这份旧程序的字段当成 V3 字段解释。用户重新执行 `PROGRAM_SRAM` 下载指定的 `9d40698` BASE 后，全部 22 项 V3 基线查询得到合法回执。此核对确认了协议切换；串口自报版本不是 FPGA 配置内容的密码学读回证明。断电或 CONFIG1 可能重新加载配置 Flash，因此下载文件、下载成功日志和运行协议必须分别核对。
2. 正确 V3 协议运行后仍出现真实故障：`STATUS=A CACHE=0 FAULT=F3 LEVEL=3 INTEGRITY=1`；`REJECTED=0 BADERROR=0 PRESENTATION=0`，音视频欠载和 UART 错误计数均为 0。F3 是当前 sink 的验证失败返回，不能通过放行坏帧解决。初始失败没有证明 TF 文件名错误，也没有证明某个具体 SDRAM 相位、DQM 位或地址是物理根因。

只发送一次 `C:RECOVER=1`，得到接受回执。随后观察到 `STATUS=8`、`INTEGRITY=0`、`RECOVERY=4`；约 1.4 秒后出现 `EVT source=03 code=03`，完整性再次置 1，恢复进入状态 5，尝试次数为 1。整个跟踪收到 145 条 ACK 和 2 条事件，校验和全部正确，原始 RX 3387 字节，SHA-256 `fdc6ea6c38ca7e62a381fd5afcc8ada880008fcaca9c776ba134f57d2e3561d8`。第二条事件为 source=06/code=03，属于监督器启动/HDMI/PLL 组合来源；不能凭此单独判定 PLL 故障。

LED4 是 SAFE；未完成四图校验时显示应急画面属于保护行为。KEY2 恢复请求确实已进入系统。KEY3 在 SAFE 中不会必然改变画面，KEY4 也不能播放未批准的缓存，这些现象本身不能证明按键损坏。

## 精简 UART 诊断候选 26101611

该候选保留 C3 的全部媒体功能，并保留 D63 的 500ms 合法像素等待修正和 D64 的系统 SAFE 按键恢复修正。实板此次 F3 不能归因为 D63/D64。未构建成功的宽屏诊断原型移入 `verification/experiments/board_safe_wide_26101610`，生产视频恢复到原 C3 实现，诊断通过按需 32 位快照实现。

新增只读命令 `B:DIAG=0` 至 `B:DIAG=15`，`B:DIAG?` 也返回自报构建 ID。发送仍采用原 XOR、CRLF 帧格式。这些数值是读取选择器，不是配置写入。原有 35 个命令 ID 保持不变，DIAG 附加为 36；原有 24 项 B 查询的行为保持兼容。负数和大于 15 的选择器返回 03，媒体复位或通路忙返回 04。

| 选择器 | 返回值 |
|---|---|
| 0 / ? | 自报 ID `26101611` |
| 1 | `{player_code8, player_detail8, player_state4, player_stage4, cache_ref4, cache_count3, card_ready1}` |
| 2 | 低 12 位 `{0, init_seq3, init_r1_8}` |
| 3 | 真实 REF 媒体进展计数 |
| 4 | 低 20 位 `{sink_state4, sink_code8, approved4, sdr_init, adapter_init, guard_fault, bus_fault}` |
| 5 | guard 首次失败地址 |
| 6 | 源行期望 CRC32 |
| 7 | 该行实际回读 CRC32 |
| 8 | 本幅图被写入接口接受的 32 位字数；完整图应为 `00025800` |
| 9 | 本幅图已通过的行数；完整图应为 `000001E0` |
| 10 / 11 | 本媒体复位周期第一次 / 最近一次 `Sdr_rd_en` 返回字 |
| 12 | 本幅图第一次被写入接口接受的数据 |
| 13 | 本媒体复位周期第一次 `App_wr_en` 命令的数据 |
| 14 | `{物理写命令次数16, 物理返回次数16}`；各自饱和于 FFFF |
| 15 | 低 16 位 `{首个读命令时App_dm4, 首个返回时App_dm4, 当前App_dm4, 0, Sdr_busy, Sdr_ref_valid, Sdr_init}` |

选择器 4 至 15 通过一个请求、一个带标签响应跨域，最多一项未完成。响应在 MEM 接受时拍照，SYS 检查返回标签；公共媒体复位取消旧查询。选择器 1 至 3 使用现有 REF→SYS 原子邮箱。每次查询独立拍照，多次查询不是一个同时刻的全系统快照。

App/Sdr 字是厂商控制器应用接口观测，不是 SDRAM 焊盘采样；App_dm 也不是芯片 DQM 焊盘值。原始返回可能包含超前预取，最近返回字不一定对应失败地址。选择器 12 按图更新、13 按媒体周期更新，跨图后不能直接将两者比较。源 CRC 与实际 CRC 不同只证明完整性失配，仍须结合地址、字数、行数及真实返回继续定位。

## 采集与构建入口

```powershell
# 关闭其他占用该串口的助手；脚本不复位、不恢复、不更改播放配置。
& .\safevision\tools\probe_v3_uart.ps1 -Port COM6 -Diagnostics
```

`probe_v3_uart.ps1` 保存 `rx.bin` 和带时间戳的 TX/RX JSONL；只保留一项未完成查询，缺失合法 ACK 时停止。扩展诊断先核对 DIAG00 的 ID，再解释其余寄存器。`decode_v3_uart.py <采集目录> --output <报告.json>` 独立核验帧、校验和、回执归属、完整查询清单及原始字节一致性，报告中的 `capture_complete` 不等于上板验收通过。

当前功能证据索引为 `evidence/v3/uart_diag_26101611/functional.index.json`，包括 9 项原生正向测试及标签错误、交换 CRC、恢复旧 KEY2 条件 3 项语义负控。构建必须使用精确匹配的源码、原始路由报告、Slow/Fast 全部 setup/hold/recovery/removal 检查和 Git blob 绑定。`bitgen_v3_uart_diagnostic.py` 专门生成 BASE 排查候选，不替代生产版 113/28 门禁，不宣称 HD 或硬件已经通过。

最终 BASE 候选仅在本地 `artifacts/v3/uart_diag_26101611/diagnostic.index.json` 生成后可下载。不存在该索引说明构建仍未验收；不能从运行目录挑选位流。必须取得新实板寄存器后再修改物理通路，最后重新回归、构建并验证显示、音频和恢复。GitHub main 按用户要求暂不更新。
