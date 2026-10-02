# Clock / Video Timing 2026-10-02 证据索引

## 构建标识与结论

- 日期：2026-10-02，Asia/Shanghai；仓库 `D:\Safe_Vision_FPGA_2026`。
- 比较基准 HEAD：`8d3d7b469160d36579743b1425b4a5f2d3f481fa`；本次为未提交工作树，实际构建由各源 SHA-256 标识，没有虚构 tag、commit 或 bitstream。
- 五项 XSim 退出 0；整数 PLL 审计 PASS；BASE/HD 受分析的内部 setup/hold/recovery/removal 满足。
- TD runner 退出 **2：INTERNAL_TIMING_MET_HEALTH_WARNINGS_OPEN**。USR-6135、clock definition=4 保留，定位推断未获厂商确认。
- 官方频率范围已复核：PLL 输出 4–400 MHz，系列推荐最大时钟 440 MHz；当前 HD serial 370.833 MHz 未超标。板级引脚/外部 IO 时序、实测抖动/锁定、HDMI PHY、显示器兼容性与长期实机未验证。

## 文件与测试对应

| 文件/目录 | 对应测试或用途 |
|---|---|
| [xsim_report.md](xsim_report.md)、`xsim/<case>/` | TC-A-TIMING、TC-A-CLOCK、TC-AB-SWAP、TC-AB-SWAP-TIME、TC-A-CLOCK-VIDEO；五组完整编译/展开/运行日志 |
| [pll_integer_audit.json](pll_integer_audit.json) | 精确参数与 IPC 一致性、官方输入/PFD/VCO/输出频率限制、5:1、最近合法整数频点 |
| [official_spec_review.json](official_spec_review.json) | 官网实际 PDF 来源、版本、页/表、SHA-256 与反馈模式区别 |
| [completion_audit.md](completion_audit.md) | 原始用户要求/手册范围逐项核对，已验证层级、剩余阻塞与恢复条件 |
| [pll_provenance.json](pll_provenance.json)、`pll_config_sha256.txt` | 四组官方 IP 来源、GUI/规范副本逐字一致和配置哈希 |
| [sta_report.md](sta_report.md)、[sta_summary.json](sta_summary.json) | 官方工具四类时序、资源/时钟/覆盖、告警和边界 |
| `td/{base,hd}/route.*` | 最终源码的官方综合/布局/布线；含 route.db 供独立进程复现 |
| `td/{base,hd}/postroute/final.*` | 对同一 DB 重建原约束后的最终分析，8 时钟与完整叶端门限 |
| `td/{base,hd}/{flow,postroute}.console.log` | 官方完整控制台；USR-6135 与物理反馈 Global 的原文同时保留 |
| `td/verification_status.txt`、`td/runner_exit.txt` | 外层实际返回值与两档状态 |
| `td/diagnostics/` | 历史同 DB 报告顺序实验，只是定位证据，不是额外通过用例 |
| `source_sha256.txt` | 25 个实际 XSim 输入，包含递归头与两份 TD 公共模型 |
| `td/{base,hd}/source_sha256.txt` | 每档真实 TD 源、约束、入口及 runner 哈希 |
| `repository_hdl_sha256.txt` | 66 份 Git 非忽略 HDL 的最终交付快照，不代表全仓仿真 |
| [changes.tsv](changes.tsv)、`delivery_sha256.txt` | 所有新增/修改路径与交付字节哈希；哈希清单不包含自身 |

## 复现与阅读顺序

先看 `docs/clock_video_implementation.md`、`docs/verification/test_matrix.md`；在仓库根用 `safevision/tools/run_video_clock_sim.ps1`、`check_pll_profiles.py`、`run_video_clock_td.ps1` 复现。脚本参数可覆盖工具安装和输出路径。正式 TD 工程 README 解释 postroute 必须新进程及退出 2 的含义。

原件仍在本机 `D:\Codex\2026-09-30\sao\work\delivery_xsim` 与 `work\delivery_td`；本归档保留完整原始输出中的实际绝对路径，没有改写日志。没有执行上板、bitgen、Git commit/push，也没有重跑历史 502 项完整 B 回归。
