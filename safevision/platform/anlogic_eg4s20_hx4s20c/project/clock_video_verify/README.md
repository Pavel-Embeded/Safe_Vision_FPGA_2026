# Clock / Reset / Video Timing 的 TD 实现检查工程

此工程检查 `clock_video_subsystem`、`clock_gen`、`clock_reset_ctrl`、`reset_sync` 和 `video_timing` 在 EG4S20BG256 上的综合、布局布线与内部静态时序。`clock_video_verify_top.v` 为检查专用顶层：保留五个生成业务时钟域和九路复位对应的状态元件、视频计数器及输出标签。

## 1. 两档固定构建

| 构建 | RTL / 布局布线入口 | 独立进程 STA 入口 | 宏 | 视频 IP | 扫描总周期 |
|---|---|---|---:|---|---|
| BASE | `base.tcl` | `base_postroute.tcl` | `SV_VERIFY_HD=0` | `sv_video_vga_pll.v` | 640×480 有效，800×525 总周期 |
| HD | `hd.tcl` | `hd_postroute.tcl` | `SV_VERIFY_HD=1` | `sv_video_hd_pll.v` | 1280×720 有效，1650×750 总周期 |

模式在 elaboration 时确定，未实现运行时切换。每档使用系统、视频、音频三个 PLL；BASE 与 HD 视频 PLL 不会同时编入同一设计。五个业务时钟为 sys、mem、pixel、serial、audio；另两个 PLL C0 仅供反馈，合计七个派生时钟及一个 50 MHz 主时钟。

`td_flow.tcl` 明列 HDL、头文件目录、ADC、SDC，按 TD 官方默认流程运行并导出 `route.db`。`postroute.tcl` 在新的 TD 进程中导入该 routed DB，清除用户约束、读取原始 SDC、重新派生和分析，保留详细时钟树及原始健康检查。两阶段结束标记只表示命令完成。

## 2. 前提

- 本机安装：`D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`，TD 自报版本 `6.2.168116`，器件库 `eagle_s20.db`，封装 `EG4S20BG256`，speed grade 默认为 `NA`。
- TD IP Generator 生成并保存四组 `.v` / `.ipc`：`sv_system_pll`、`sv_video_vga_pll`、`sv_video_hd_pll`、`sv_audio_pll`，位于 `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/`。
- 本目录位于 `safevision/platform/anlogic_eg4s20_hx4s20c/project/clock_video_verify/`。暂存目录运行时用 `SAFEVISION_REPO` 指向仓库根目录。
- 读取 IP 采用已生成的官方模块；核对频率请使用 `.ipc` 的整数分频参数和生成日志。TD STA 显示频率存在周期量化，不能用其小数反改 IP。

## 3. 一键运行及返回值

在仓库根目录运行：

```powershell
& '.\safevision\tools\run_video_clock_td.ps1' -RepoRoot (Get-Location).Path -Mode both
```

可用 `-Mode base` / `-Mode hd`，可用 `-TdRoot` 指定安装目录，`-RunDir` 指定输出根目录。默认输出 `safevision/build/out/clock_video_verify/{base,hd}/`；日志为 `flow.console.log`、`postroute.console.log`，新进程报告位于 `postroute/final.*`。

| 返回值 | 含义 |
|---:|---|
| 0 | 内部时序门限满足，且脚本检查的 TD 健康告警门限满足；仍须补板级外部约束与硬件验证 |
| 2 | 内部时序满足，但健康告警未关闭，结果标记 `INTERNAL_TIMING_MET_HEALTH_WARNINGS_OPEN` |
| 1 | 工具失败、缺报告、时钟/叶端覆盖异常、缺少四类检查、时序余量为负等硬失败 |

Runner 的结构门限包括：8 个精确命名时钟、单一 `board_clk_50` 根组、BASE 55 / HD 59 个完整叶时钟端、每个派生时钟的固定叶端基线、频率轮廓、Routed 时序、setup / hold / recovery / removal 四类、SWNS / STNS / HWNS / HTNS 非负、`no clock(0)`。若修改验证顶层而改变叶端数量，必须先复核网表和时钟树，再更新基线。视频/audio C0 反馈没有业务寄存器，叶端为 0 是预期结果。

2026-10-02 实际两档完整执行返回 **2**，保留三条 `USR-6135` 和 `clock definition(4)`，未把正 WNS 写成全面通过。

## 4. 手工复现

必须在本目录作为 cwd，顺序运行不同进程：

```powershell
$env:SAFEVISION_REPO = 'D:/Safe_Vision_FPGA_2026'
$env:SAFEVISION_VERIFY_OUT = 'D:/Safe_Vision_FPGA_2026/safevision/build/out/clock_video_verify'
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' './base.tcl'
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' './base_postroute.tcl'
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' './hd.tcl'
& 'D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe' './hd_postroute.tcl'
```

主流程保持官方 SDC 读取顺序。在同一个综合进程内反复 `clear_sdc` / 重读 SDC 的实验曾丢失有效时钟约束，故新进程 postroute 是必要的独立复核；不可把该无效实验结果用于验收。独立阶段重新读取原始 SDC，并用 8 时钟 / 全叶端基线确认约束未丢失。

## 5. 必须审查的报告

| 文件 | 用途 |
|---|---|
| `source_manifest.txt` | 本档真实 HDL、约束及路径 |
| `route.timing`、`postroute/final.timing` | Routed、双角 Max/Min、四类路径和余量 |
| `route.status`、`postroute/final.status` | 总 WNS / TNS |
| `postroute/final.clock_summary` | XML 详细时钟树、8 时钟、55 / 59 叶时钟端 |
| `*.clock_intersection` | 时钟相关性及实际跨域路径 |
| `*.check_timing` | 无时钟、定义问题、外部 delay 缺项等健康检查 |
| `*.exceptions`、`*.ignored` | 时序例外与忽略；此工程未添加任何例外 |
| `route.area`、`postroute/final.area` | 资源以及 Clock Resource Statistics |
| `*.console.log` | `USR-6135` 原文，以及反馈网 `report_nets -connection` 的真实驱动、负载和 global 路由 |
| `route.db` | 保存真实 routed 设计供新进程重读 |

EG4 器件不支持 `report_clock_utilization`；脚本保存 `place.clock_utilization.note` 说明，时钟资源应读 `route.area` 和详细时钟树。

## 6. 当前已验证结果与开放项

BASE / HD 均完成综合、布局布线、双角 STA，8 时钟及全叶端保持，`no_clock=0`。setup / hold / recovery / removal 最差余量分别为 BASE **5.627 / 0.266 / 6.482 / 0.147 ns**，HD **0.619 / 0.264 / 1.221 / 0.159 ns**；总 STNS / HTNS 为 0。

健康检查仍列 4 个 local clock 和 4 个未接 master 的 generated clock。只读同一 routed DB 的报告顺序实验中，`report_clock_summary` 前后该数字从 0 变为 4，而全部时钟及余量保持，支持工具状态或报告逻辑缺陷的推断。保留实际默认顺序的 4 项，不选择输出 0 的顺序宣告修复。

三条 `USR-6135` 在新进程依然出现。`report_nets` 又显示系统、视频、音频三条实际反馈网均由 `EG_PHY_GCLK` 输出驱动、连接各 PLL 的 `fbclk`，`Route Type=global`。该物理证据确认反馈全局路由；告警与该证据的矛盾仍需厂商澄清，不能声称告警已关闭。

## 7. 约束与验证边界

`verify_clock.sdc` 仅定义 50 MHz 参考时钟并 `derive_clocks`，未添加 false path、异步时钟组、multicycle 或整体复位豁免。所有时钟同根相关；检查顶层没有业务数据跨域连接，所以交叉关系报告为 `NOPATH`，不等于整机 CDC/TMDS 已验收。

`verify_pin.adc` 只确认 `board_clk=R7`。复位与四请求共 5 个外部输入无 input delay，17 个探针输出无 output delay。STA coverage BASE **94.68%**、HD **94.64%**；这不是 100% 的整机约束覆盖。最差 setup 终点可能是 PAD 内部输出寄存器数据脚，该内部路径已分析，外部 PAD 到板外设备的预算仍缺失。

此工程未执行 bitgen/下载，也没有 HDMI 编码、差分输出、外部接收端、真实 PCB 复位及锁定/失锁硬件验证。现有官方 PLL 文档允许已用 VCO 范围，但提供资料没有给出 HD 370.833333 MHz 的独立 GCLK/PLL 输出 AC 上限，因此不能仅凭正 STA 宣称其电气与工作条件全部保证。

依据为安装自带 `DefaultFlow.tcl`、SWUG105 Tcl、SWUG200 Timing Constraints、SWUG201 Timing Tools，以及板包 TN305 PLL 用户指南与 DS301 EG4S20 数据手册；详细定位、原文和可审计结果见交付 STA 中文报告。
