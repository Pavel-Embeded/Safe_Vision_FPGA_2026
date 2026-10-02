# A 独立发布：当前版本验证

日期：2026-10-02。发布父提交：`7c5bee1a7a30b8d168da8fb17747a79e3065ca9d`。这次重新执行了筛选后的五项 XSim（runner退出0）、目录检查和PLL参数审计。

| 测试 | 结果 |
|---|---|
| Video Timing | BASE/HD各2,477,500周期、TINY150周期与运行中复位，PASS |
| Clock/Reset | 88 pass / 0 fail |
| 原帧交换测试 | 23 pass / 0 fail；复用B原TB与原RTL |
| A帧量级等待 | 显式 TIMEOUT_N=5,000,000；两次帧事件/两次提交/0错误；B默认值不变 |
| Clock/Video联合 | 官方EG4模型；BASE/HD五时钟、半周期、严格5:1、九复位、局部扫描隔离与重锁，PASS |

原始新日志见 `xsim/`；输入哈希见 `xsim_input_sha256.json`。保留工具原始输出编码，不重新编造或改写原日志。

旧 `../clock_video_20261002/` 是此前完整本地工作树的历史归档，其中包括未推送的B默认超时试验与旧全工作树盘点。不能把旧source/delivery清单当作本提交的完整清单。当前A提交范围见 [A发布说明](../../docs/A_PUSH_SCOPE_20261002.md)。

`td_inputs_match.json` 证明BASE/HD每档17个实际输入与旧TD执行版本SHA-256一致，故保留原内部STA结果；此次未重新综合或上板。内部四类时序满足，TD仍为退出2、健康告警未闭合。板级/完整HDMI/消费链未验收。
