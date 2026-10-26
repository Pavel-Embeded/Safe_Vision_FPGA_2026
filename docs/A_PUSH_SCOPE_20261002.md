# A Clock / Video Timing：本次 GitHub 发布范围

日期：2026-10-02。目标：`Pavel-Embeded/Safe_Vision_FPGA_2026` 的 `main`。父提交：`7c5bee1a7a30b8d168da8fb17747a79e3065ca9d`。

## 1. 为什么以最新远程版本为基础

本地源项目HEAD为`8d3d7b469160d36579743b1425b4a5f2d3f481fa`，远程已经新增8个提交。通过已连接GitHub接口读取最新35个变化文件，按Git blob SHA逐个核对，在独立发布目录构造最新远程内容；随后仅合入A改动。原项目`D:\Safe_Vision_FPGA_2026`的文件和HEAD均未写入。未在桌面创建保存包；此前D:\Codex暂存包仍只是本地冻结副本。

## 2. 推送了什么

本次相对最新远程树：15个修改、156个新增，共171个路径；删除/重命名0。

- A逻辑：`video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`，以及`reset_sync.v`加固。
- 官方IP：system/VGA/HD/audio四组`.v/.ipc`；每档例化三个PLL。
- A验证：三个新增TB、XSim runner、PLL参数审计、两档TD检查顶层/Tcl/ADC/SDC、结构检查的A补充。
- A说明：实施文档、接口补充、提交正文与本说明；共用README/架构/管理/矩阵/证据索引保留最新远程原文，只追加A状态和导航。
- A证据：历史Clock/Timing工具输出及新五项XSim日志/输入哈希/范围核对。历史归档的完整本地工作树计数和B超时试验不属于本提交。

## 3. 明确排除的本地改动

| 路径 | 本次处理 |
|---|---|
| `safevision/rtl/memory/frame_swap_ctrl.v` | 保持最新远程blob；不推送之前默认超时修改 |
| `safevision/rtl/include/safevision_defs.vh` | 保持最新远程blob；不加入video include或帧超时宏；A直接include自己的video_mode_defs |
| `docs/B链-原理讲解-入门版.md` | 完整保留最新远程版本 |
| `docs/B链-待办与硬件验证清单.md` | 完整保留最新远程版本及上板记录 |

其他B/C的storage/media/memory/control/safety/audio/common、原B单元测试、`run_sim.ps1`、B bring-up顶层/约束/工程、板测脚本和board/reports证据也都保留最新远程blob。已逐文件验证131个非本次范围的原文件内容/模式不变。源码文件“出现在已有仓库中”不等于本次提交又修改它；实际变更名单如下。

原项目工作区此前的B修改仍留在本地，未撤销、未上传；本次使用独立发布副本，避免将它们混进提交。

## 4. A/B测试边界与本次验证

A新帧量级TB显式传入`TIMEOUT_N=5_000_000`，不修改B默认值。100MHz下原默认10ms短于一帧等待的问题仍需A/B正式联调确认；不能声称该默认值已在本提交修复。

新五项XSim runner实际退出0：扫描两档与小模式、88项复位、原23项帧交换、显式50ms的两次提交、官方PLL联合检查均PASS。PLL整数/已查明官方频率范围审计PASS，整仓结构检查PASS。见 [新验证证据](../evidence/a_only_push_20261002/README.md)。此次没有重跑完整B回归，也没有重新上板。

BASE/HD旧TD归档每档17个输入与本提交逐个SHA-256一致；保留该输入版本的内部STA结果，不登记为一次新TD运行。TD健康告警仍未闭合，runner为退出2；A完整输出链和板级未验收。

## 5. 实际变更路径

| 状态 | 路径 |
|---|---|
| M | `.gitignore` |
| M | `README.md` |
| A | `docs/A_PUSH_SCOPE_20261002.md` |
| A | `docs/A_clock_video_interfaces.md` |
| M | `docs/PROJECT_STRUCTURE.md` |
| M | `docs/architecture/module_registry.md` |
| M | `docs/architecture/system_design.md` |
| A | `docs/clock_video_change_log.md` |
| A | `docs/clock_video_commit_message.txt` |
| A | `docs/clock_video_implementation.md` |
| M | `docs/interface_spec.md` |
| M | `docs/management/WORK_ITEMS.md` |
| M | `docs/requirements/traceability.md` |
| M | `docs/verification/test_matrix.md` |
| M | `evidence/README.md` |
| A | `evidence/a_only_push_20261002/README.md` |
| A | `evidence/a_only_push_20261002/changes.tsv` |
| A | `evidence/a_only_push_20261002/pll_integer_audit.json` |
| A | `evidence/a_only_push_20261002/push_scope.json` |
| A | `evidence/a_only_push_20261002/structure_check.log` |
| A | `evidence/a_only_push_20261002/td_inputs_match.json` |
| A | `evidence/a_only_push_20261002/xsim/clock_reset/xelab.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_reset/xsim.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_reset/xvlog_sv.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_reset/xvlog_verilog.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_video_subsystem/xelab.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_video_subsystem/xsim.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_video_subsystem/xvlog_sv.log` |
| A | `evidence/a_only_push_20261002/xsim/clock_video_subsystem/xvlog_verilog.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_existing/xelab.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_existing/xsim.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_existing/xvlog_sv.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_existing/xvlog_verilog.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_real_frame/xelab.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_real_frame/xsim.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_real_frame/xvlog_sv.log` |
| A | `evidence/a_only_push_20261002/xsim/frame_swap_real_frame/xvlog_verilog.log` |
| A | `evidence/a_only_push_20261002/xsim/video_timing/xelab.log` |
| A | `evidence/a_only_push_20261002/xsim/video_timing/xsim.log` |
| A | `evidence/a_only_push_20261002/xsim/video_timing/xvlog_sv.log` |
| A | `evidence/a_only_push_20261002/xsim/video_timing/xvlog_verilog.log` |
| A | `evidence/a_only_push_20261002/xsim_input_sha256.json` |
| A | `evidence/clock_video_20261002/README.md` |
| A | `evidence/clock_video_20261002/changes.tsv` |
| A | `evidence/clock_video_20261002/completion_audit.md` |
| A | `evidence/clock_video_20261002/delivery_audit.json` |
| A | `evidence/clock_video_20261002/delivery_sha256.txt` |
| A | `evidence/clock_video_20261002/official_spec_review.json` |
| A | `evidence/clock_video_20261002/pll_config_sha256.txt` |
| A | `evidence/clock_video_20261002/pll_integer_audit.json` |
| A | `evidence/clock_video_20261002/pll_provenance.json` |
| A | `evidence/clock_video_20261002/repository_hdl_sha256.txt` |
| A | `evidence/clock_video_20261002/source_sha256.txt` |
| A | `evidence/clock_video_20261002/sta_report.md` |
| A | `evidence/clock_video_20261002/sta_summary.json` |
| A | `evidence/clock_video_20261002/td/base/flow.console.log` |
| A | `evidence/clock_video_20261002/td/base/place.clock_utilization.note` |
| A | `evidence/clock_video_20261002/td/base/postroute.console.log` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.area` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.check_timing` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.clock_intersection` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.clock_summary` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.derived.sdc` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.exceptions` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.ignored` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.status` |
| A | `evidence/clock_video_20261002/td/base/postroute/final.timing` |
| A | `evidence/clock_video_20261002/td/base/route.area` |
| A | `evidence/clock_video_20261002/td/base/route.check_timing` |
| A | `evidence/clock_video_20261002/td/base/route.clock_intersection` |
| A | `evidence/clock_video_20261002/td/base/route.clock_summary` |
| A | `evidence/clock_video_20261002/td/base/route.db` |
| A | `evidence/clock_video_20261002/td/base/route.derived.sdc` |
| A | `evidence/clock_video_20261002/td/base/route.exceptions` |
| A | `evidence/clock_video_20261002/td/base/route.ignored` |
| A | `evidence/clock_video_20261002/td/base/route.qor` |
| A | `evidence/clock_video_20261002/td/base/route.status` |
| A | `evidence/clock_video_20261002/td/base/route.timing` |
| A | `evidence/clock_video_20261002/td/base/source_manifest.txt` |
| A | `evidence/clock_video_20261002/td/base/source_sha256.txt` |
| A | `evidence/clock_video_20261002/td/diagnostics/README.md` |
| A | `evidence/clock_video_20261002/td/diagnostics/order.clock_tree` |
| A | `evidence/clock_video_20261002/td/diagnostics/order.console.log` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_after.check` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_after.timing` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_base_route.db` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_before.check` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_before.timing` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_experiment.tcl` |
| A | `evidence/clock_video_20261002/td/diagnostics/order_input.sdc` |
| A | `evidence/clock_video_20261002/td/hd/flow.console.log` |
| A | `evidence/clock_video_20261002/td/hd/place.clock_utilization.note` |
| A | `evidence/clock_video_20261002/td/hd/postroute.console.log` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.area` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.check_timing` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.clock_intersection` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.clock_summary` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.derived.sdc` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.exceptions` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.ignored` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.status` |
| A | `evidence/clock_video_20261002/td/hd/postroute/final.timing` |
| A | `evidence/clock_video_20261002/td/hd/route.area` |
| A | `evidence/clock_video_20261002/td/hd/route.check_timing` |
| A | `evidence/clock_video_20261002/td/hd/route.clock_intersection` |
| A | `evidence/clock_video_20261002/td/hd/route.clock_summary` |
| A | `evidence/clock_video_20261002/td/hd/route.db` |
| A | `evidence/clock_video_20261002/td/hd/route.derived.sdc` |
| A | `evidence/clock_video_20261002/td/hd/route.exceptions` |
| A | `evidence/clock_video_20261002/td/hd/route.ignored` |
| A | `evidence/clock_video_20261002/td/hd/route.qor` |
| A | `evidence/clock_video_20261002/td/hd/route.status` |
| A | `evidence/clock_video_20261002/td/hd/route.timing` |
| A | `evidence/clock_video_20261002/td/hd/source_manifest.txt` |
| A | `evidence/clock_video_20261002/td/hd/source_sha256.txt` |
| A | `evidence/clock_video_20261002/td/runner_exit.txt` |
| A | `evidence/clock_video_20261002/td/verification_status.txt` |
| A | `evidence/clock_video_20261002/xsim/clock_reset/xelab.log` |
| A | `evidence/clock_video_20261002/xsim/clock_reset/xsim.log` |
| A | `evidence/clock_video_20261002/xsim/clock_reset/xvlog_sv.log` |
| A | `evidence/clock_video_20261002/xsim/clock_reset/xvlog_verilog.log` |
| A | `evidence/clock_video_20261002/xsim/clock_video_subsystem/xelab.log` |
| A | `evidence/clock_video_20261002/xsim/clock_video_subsystem/xsim.log` |
| A | `evidence/clock_video_20261002/xsim/clock_video_subsystem/xvlog_sv.log` |
| A | `evidence/clock_video_20261002/xsim/clock_video_subsystem/xvlog_verilog.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_existing/xelab.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_existing/xsim.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_existing/xvlog_sv.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_existing/xvlog_verilog.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_real_frame/xelab.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_real_frame/xsim.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_real_frame/xvlog_sv.log` |
| A | `evidence/clock_video_20261002/xsim/frame_swap_real_frame/xvlog_verilog.log` |
| A | `evidence/clock_video_20261002/xsim/video_timing/xelab.log` |
| A | `evidence/clock_video_20261002/xsim/video_timing/xsim.log` |
| A | `evidence/clock_video_20261002/xsim/video_timing/xvlog_sv.log` |
| A | `evidence/clock_video_20261002/xsim/video_timing/xvlog_verilog.log` |
| A | `evidence/clock_video_20261002/xsim_report.md` |
| M | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/README.md` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_audio_pll.ipc` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_audio_pll.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_system_pll.ipc` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_system_pll.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_hd_pll.ipc` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_hd_pll.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_vga_pll.ipc` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/sv_video_vga_pll.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/README.md` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/base.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/base_postroute.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/clock_video_verify_top.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/hd.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/hd_postroute.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/postroute.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/td_flow.tcl` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/verify_clock.sdc` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/verify_pin.adc` |
| M | `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/README.md` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_gen.v` |
| A | `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_video_subsystem.v` |
| M | `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v` |
| A | `safevision/rtl/include/video_mode_defs.vh` |
| M | `safevision/rtl/video/video_timing/README.md` |
| A | `safevision/rtl/video/video_timing/video_timing.v` |
| A | `safevision/tools/check_pll_profiles.py` |
| M | `safevision/tools/check_repo.ps1` |
| A | `safevision/tools/run_video_clock_sim.ps1` |
| A | `safevision/tools/run_video_clock_td.ps1` |
| A | `safevision/verification/unit/tb_clock_video_subsystem.sv` |
| A | `safevision/verification/unit/tb_frame_swap_real_frame.sv` |
| A | `safevision/verification/unit/tb_video_timing.sv` |

实际Git blob清单与范围断言见 `../evidence/a_only_push_20261002/push_scope.json`；新清单不是旧`delivery_sha256.txt`。GitHub提交SHA由发布结果给出，文档不把自身未知的提交SHA写入自身内容。
