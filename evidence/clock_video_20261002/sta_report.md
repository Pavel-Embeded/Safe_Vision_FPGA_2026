# SafeVision Clock / Reset / Video Timing：TD 实现与 STA 验证报告

验证日期：2026-10-02。工具：Tang Dynasty 自报 `6.2.168116`，安装目录 `D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`，构建日期 2025-06-12。器件库 `eagle_s20.db`，封装 `EG4S20BG256`，默认 speed grade `NA`。

## 1. 验证结论

**BASE 和 HD 均完成官方综合、布局、布线及 routed 双角 Max/Min STA；该检查顶层的 setup、hold、recovery、removal 内部路径满足。TD 健康告警仍开放，因此整体结果是 `INTERNAL_TIMING_MET_HEALTH_WARNINGS_OPEN`，不是整机时序、电气或 HDMI 接收验收通过。**

正式一键脚本已实际执行 BASE 主流程 → BASE 独立 postroute → HD 主流程 → HD 独立 postroute，返回 **exit 2**。其硬门限均通过：8 个精确命名时钟、BASE 55 / HD 59 个完整叶时钟端、固定各域叶端数量、正确派生频率轮廓、Routed 分析、四类检查、非负 WNS/TNS，以及 `no_clock=0`。两档每个流程本身退出 0；外层返回 2 用于保留尚未关闭的健康告警。

开放项：每档三个 `USR-6135` 反馈补偿告警；clock definition 的 4 个 local 与 4 个未接 master 条目；5 个外部输入 / 17 个外部输出缺 delay；实际晶振/PLL 抖动、锁定与板级验证仍缺证据。官方 PLL 输出 400 MHz 上限与系列推荐 440 MHz 已查明，当前 HD 串行 370.833333 MHz 未超过这些标称频率限制。反馈 global 的物理证据已确认，但与告警的矛盾尚未得到厂商结论。

## 2. 验证对象及实际范围

检查顶层 `clock_video_verify_top.v` 实例化仓库的 `clock_video_subsystem`，下接 `clock_gen`、`clock_reset_ctrl`、九实例 `reset_sync` 和 `video_timing`。官方生成的系统、所选视频、音频三 PLL 进入该档编译；不会同时使用两个视频 PLL。

五个业务时钟域各有状态元件，九路复位分别控制对应状态，视频标签及坐标参与输出探针以避免整体逻辑被优化掉。两档分别检查 640×480（800×525）和 1280×720（1650×750）。视频参数在编译期固定，未实现运行时 PLL 切换。

这次 STA 工程没有 framebuffer、SDRAM 实体接口、业务数据 CDC、TMDS 编码/串化、差分输出和接收端。`NOPATH` 只说明检查网表没有相应跨域数据路径。正余量不能替代其它工程的仿真、完整产品顶层 STA、CDC 或硬件验证。

## 3. 源文件、约束与流程

初始 STA 在暂存工程 `D:\Codex\2026-09-30\sao\work\td_clock_verify` 运行；随后 10 份正式工程文件与 runner 已复制到目标仓库，并从 canonical 项目路径对最终源码重新完成两档全流程。最后运行输入见归档 `td/<mode>/source_manifest.txt` 与 `source_sha256.txt`。官方 PLL `.v/.ipc` 保持生成原样。

SDC 原文：

```tcl
create_clock -name board_clk_50 -period 20.000 -waveform {0.000 10.000} \
    [get_ports {board_clk}]
derive_clocks
```

以上约束仅含 50 MHz 主时钟与 PLL 派生，没有 false path、异步时钟组、multicycle、全域复位豁免或人为调整 PLL 周期。ADC 仅固定已核对的参考时钟 R7，其它引脚未确定。

主流程遵循官方 `DefaultFlow.tcl` 的阶段顺序：导入器件、读取明确 HDL / ADC、RTL 优化、读取 SDC、gate 优化 / legalize、重读原 SDC、place、route、最终 STA、报告、导出 `route.db`。EG4 不支持 `report_clock_utilization`，因此仅保存不支持说明 `place.clock_utilization.note`，真实资源以 `route.area` 为准。

新进程 `postroute.tcl` 导入同一个 routed DB，`clear_sdc -user` 后读取原始 SDC，再 `update_timing -mode final`。主流程与独立阶段均保留全部健康报告和警告。新进程时钟及叶端基线门限防止重新读约束时丢失真实约束而获得虚假正余量。

## 4. 实际频率与 TD 数字精度

下表按理想 50 MHz 参考输入及官方生成分频参数计算；实际晶振误差、抖动和锁定动态需实测。Normal / CLKC0_EXT 模式的 `fVCO = fREF / REF_DIV × FB_DIV × C0_DIV`，各输出为 `fVCO / Ci_DIV`。

| IP | REF / FB / C0 / C1 / C2 | VCO MHz | C0 MHz | 业务输出 MHz |
|---|---|---:|---:|---|
| system | 1 / 2 / 10 / 8 / — | 1000 | 100 | sys 100；mem 125 |
| video BASE | 3 / 17 / 4 / 45 / 9 | 1133.333333 | 283.333333 | pixel 25.185185185；serial 125.925925926 |
| video HD | 4 / 1 / 89 / 15 / 3 | 1112.5 | 12.5 | pixel 74.166666667；serial 370.833333333 |
| audio | 2 / 1 / 29 / 59 / — | 725 | 25 | audio 12.288135593 |

两个视频的 serial / pixel 数学比值均严格为 5。相对 25.175 MHz BASE 像素目标为 +404.575 ppm，相对 74.25 MHz HD 目标为 −1122.334 ppm，音频相对 12.288 MHz 为 +11.035 ppm。这里的偏差是实际整数解，不能写成名义频率完全精确。

TD 报告周期以 ps 量化，BASE serial 显示 7.941 ns / 125.929 MHz，BASE C0 显示 3.529 ns / 283.366 MHz；HD serial 显示 2.696 ns / **370.920 MHz**。这些显示精度不等于 IP 被改成该频率。Runner 采用 0.1% 的 STA 轮廓容差以容纳报告量化，该门限不是接收端时钟容差、实际抖动或 HDMI 合规门限。

[纠正/新增] 官网已实际取得 DS301 v2.7.6，其第 3 节将 EG4S20 DC/AC 引至 EAGLE 系列。DS300 v3.9.4 表 2-14/3-18 给出输入/PFD 10–400 MHz、VCO 300–1200 MHz、输出 4–400 MHz；表 3-17 的 EAGLEA_10/20 推荐最大时钟为 440 MHz。当前所有启用 C0/C1/C2 均在输出范围内，HD 370.833333 MHz 距 PLL 400 MHz 约 29.166667 MHz。检查工具已按这些限制重跑 PASS，最近合法频点与官方 IP 不变。该检查确认标称频率范围，不确认板上抖动、相位补偿、实际工作条件或 TMDS 电气。详见 official_spec_review.json 和 completion_audit.md。

## 5. 时钟树与覆盖门限

所有八个时钟都在 `board_clk_50` 同一个根组中。系统 C0 兼作 100 MHz 业务时钟及系统 PLL 反馈；视频 C0 和音频 C0 仅反馈，不驱动业务寄存器，因此这两个时钟叶端为 0 是合理的。下面的叶端是 TD clock tree 的叶时钟引脚数量，不能直接等同于逻辑寄存器 bit 数。

| 时钟 | BASE 叶端 | HD 叶端 | BASE STA MHz | HD STA MHz |
|---|---:|---:|---:|---:|
| board_clk_50（根组累计） | 55 | 59 | 50.000 | 50.000 |
| system C0 / sys | 8 | 10 | 100.000 | 100.000 |
| system C1 / mem | 8 | 8 | 125.000 | 125.000 |
| video C1 / pixel | 29 | 31 | 25.185 | 74.167 |
| video C2 / serial | 6 | 6 | 125.929 | 370.920 |
| video C0 / feedback | 0 | 0 | 283.366 | 12.500 |
| audio C1 / audio | 4 | 4 | 12.288 | 12.288 |
| audio C0 / feedback | 0 | 0 | 25.000 | 25.000 |

原始 `route.clock_summary` 的根组就包含 8 时钟、55 / 59 叶端和 `nonclocks=0`。独立 `postroute/final.clock_summary` 展开了全部八个时钟及叶端，数量和原始组摘要一致。Runner 最新复现再次逐个检查固定叶端基线。

`clock_intersection` 业务时钟自域为 `TIMED_SAFE`，交叉数据单元为 `NOPATH`；没有将 pixel / serial 设置成异步。同源关系保留，但本工程缺少真实 TMDS pixel→serial 数据路径，因此此表不验证将来的串化接口时序。

## 6. 原始与独立 STA 一致性

| 结果 | 时钟数 / 叶端 | no_clock | SWNS ns | STNS ns | HWNS ns | HTNS ns | STA coverage |
|---|---|---:|---:|---:|---:|---:|---:|
| BASE 原始 route | 8 / 55 | 0 | 5.627 | 0.000 | 0.147 | 0.000 | 94.68% |
| BASE 独立 postroute | 8 / 55 | 0 | 5.627 | 0.000 | 0.147 | 0.000 | 94.68% |
| HD 原始 route | 8 / 59 | 0 | 0.619 | 0.000 | 0.159 | 0.000 | 94.64% |
| HD 独立 postroute | 8 / 59 | 0 | 0.619 | 0.000 | 0.159 | 0.000 | 94.64% |
| BASE 最新 runner 主流程 / 独立阶段 | 8 / 55 | 0 | 5.627 | 0.000 | 0.147 | 0.000 | 94.68% |
| HD 最新 runner 主流程 / 独立阶段 | 8 / 59 | 0 | 0.619 | 0.000 | 0.159 | 0.000 | 94.64% |

报告 `Confidence=Routed`，`Check Corner=Both (Slow and Fast)`，Slow / Fast 的 Max / Min 均为 yes，CRPR 启用。原始、独立以及最终 runner 的相同余量支持约束和实现的一致性。

### 6.1 四类独立最差路径

下列余量分别从四类路径中取最小；HWNS 还包含 removal，所以不能用汇总 HWNS 替代普通数据 hold 的最差余量。每组设置报告 100 个 endpoint、每端 3 条路径，下列“报告条数”是文本输出数量，不是工具内部全部可能路径的总数。

| 档位 | 检查 | 最差 slack ns | 报告条数 | 起点 → 终点（省略层次见原报告） |
|---|---|---:|---:|---|
| BASE | setup | 5.627 | 164 | mem_count_reg[0].clk → probe_domain[1].do[0]，125 MHz |
| BASE | hold | 0.266 | 151 | sys_count_reg[0].clk → sys_count_reg[2].d[1]，100 MHz |
| BASE | recovery | 6.482 | 26 | u_serial_reset/release_pipe[1].clk → serial_toggle_reg.sr |
| BASE | removal | 0.147 | 39 | u_sys_reset/release_pipe[1].clk → sys_count_reg[2].sr |
| HD | setup | 0.619 | 165 | serial_toggle_reg.clk → probe_domain[3].do[0]，HD serial |
| HD | hold | 0.264 | 150 | u_sys_reset/release_pipe[0].clk → release_pipe[1].mi[0] |
| HD | recovery | 1.221 | 25 | u_hdmi_serial_reset/release_pipe[1].clk → hdmi_serial_toggle_reg.sr |
| HD | removal | 0.159 | 40 | u_mem_reset/release_pipe[1].clk → mem_count_reg[2].sr |

四类数值在原始与独立报告一致。PAD `.do[0]` 在这里是目标 PAD 内部寄存器路径的终点，不能把其正 slack 解释为未约束外部接收端已经满足时序。复位释放在域内的 recovery / removal 也已分析，未通过全局 false path 隐藏；外部异步 reset / lock 的相位、MTBF 和板级扰动依然需要其它验证。

## 7. 资源与真实时钟路由

| 资源 | BASE | HD |
|---|---:|---:|
| LUT | 145 | 163 |
| register | 68 | 71 |
| logic element | 163 | 180 |
| slice | 87 | 98 |
| PLL | 3 / 4（75%） | 3 / 4（75%） |
| 显式 GCLK buffer | 3 / 16（18.75%） | 3 / 16（18.75%） |
| BRAM / DSP | 0 / 0 | 0 / 0 |

`Clock Resource Statistics` 有 8 条 Global 时钟网络。显式 buffer 数 3 与被路由的时钟网络数 8 是不同统计对象，不矛盾。系统、视频和音频反馈真实网络的连接证据如下：

| 反馈真实网 | 驱动 | 驱动位置 | PLL.fbclk 负载位置 | Route Type |
|---|---|---|---|---|
| sys_clk | u_system_pll/bufg_feedback.clko，EG_PHY_GCLK | [39,42] | system [40,71] | global |
| gen_video_*$u_video_pll/clk0_out | 官方 IP BUFG 的 clko，EG_PHY_GCLK | [1,1] | video [0,0] | global |
| u_audio_pll/clk0_out | 官方 IP BUFG 的 clko，EG_PHY_GCLK | [1,42] | audio [0,71] | global |

原始与新进程 `report_nets -connection` 均确认 `is_clock=True`、真实 `PLL.fbclk` 接在上述 global net；参考 `board_clk_dup_1` 也是 global，并连接三个 `PLL.refclk`。路由器另打印：

```text
PHY-1001 : All clock nets do not utilize local routing resource.
```

详细时钟树确有 board 端口→PAD 输入、PLL C0→BUFG 输入的短 local 段，之后真实反馈和业务分布网为 global。对 local 短段与整条反馈 global 的分类差异是可能的告警原因，但这仍是推断。

## 8. 健康告警定位：保留原文和边界

### 8.1 USR-6135：独立开放项

新进程重新分析仍打印以下原文。BASE：

```text
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/gen_video_base$u_video_pll/pll_inst is on local network, of which compensation delay is unpredictable.
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/u_audio_pll/pll_inst is on local network, of which compensation delay is unpredictable.
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/u_system_pll/pll_inst is on local network, of which compensation delay is unpredictable.
```

HD：

```text
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/gen_video_hd$u_video_pll/pll_inst is on local network, of which compensation delay is unpredictable.
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/u_audio_pll/pll_inst is on local network, of which compensation delay is unpredictable.
USR-6135 CRITICAL-WARNING: The feedback path of PLL u_subsystem/u_clock_gen/u_system_pll/pll_inst is on local network, of which compensation delay is unpredictable.
```

物理报告证明实际反馈用了全局网络；USR-6135 却声称 local。能确认的是：官方生成 IP 反馈连接存在、BUF 输出至 fbclk 的实际路由为 global，且告警在 fresh analysis 重现。不能确认的是：工具为何发出告警、补偿模型是否在所有条件下正确、厂商是否已认定该版本缺陷。未修改官方 IP、未屏蔽告警，结论保留“未关闭”。DS300 第 2.4.3 节与 TN305 第 3 页还证明 Normal 和 No Compensation 的延迟补偿不同，改用内部无补偿反馈需要重新定义相位契约与验证，不能算等价修复。

### 8.2 clock definition：同一 DB 的报告顺序实验

默认顺序的 `check_timing` 保留：

```text
2. checking clock definition(4) (HIGH)
2.4 There are 4 local clocks. (HIGH)
2.5 There are 4 generated clocks that are not connected to their master clocks. (HIGH)
```

local 名单是 `board_clk_50` 与三个 PLL C0。2.5 没有打印具体四条名单；不能假称已逐条定位。详细 clock tree 的八个时钟实际都归属同一主时钟根组，全部业务时钟有有效叶端；两条仅反馈 C0 有 0 业务叶端，但不应误删该反馈连接。

隔离实验仅导入同一原始 BASE route.db、重读原始 SDC 和 update final，随后执行 timing_before → check_before → clock_summary → check_after → timing_after。无网表或约束变更，check_before 的 local / not-connected 均为 0，而 check_after 均变成 4；两次 WNS、8 时钟及覆盖不变。

**这个差异支持 TD 状态或报告逻辑缺陷的推断，并不是厂商确认，也不是已修好四条告警。** 交付保留默认报告顺序和 4 条计数，不选择报 0 的顺序隐藏问题。顺序实验也不能证明 USR-6135 已关闭；它是独立 warning。

第 5 节标题 `checking pll/clock buffer clock constraints(3)` 中的 3 是三个 PLL 的检查条目数。正文每个 PLL 的 “no clock constraints” 和 “frequency do not match” 都为 **0**，不能将标题误解为三条频率违规。

### 8.3 被排除的同进程约束丢失实验

在综合 / route 同一个 TD 进程内 `clear_sdc -user` 并重读原文件或字节相同副本曾使所有业务回退为 50 MHz `DeriveClock`、8→1 时钟、`no_clock=13`、覆盖 86.76%、假性 SWNS 9.992 ns。该结果约束错误，全部排除，不作为通过证据。

正式主流程已恢复官方读取顺序，新进程 postroute 才进行清除 / 重新读取，并强制 8 时钟及完整叶端门限。未用全局时钟路由 enforce、复位豁免或手写 PLL 参数消除告警。诊断实验脚本不进入正式项目目录。

## 9. 无约束外部路径及剩余验证

两档报告均列 `no input delay(5)`、`no output delay(17)`。五个输入为板复位及四请求，17 个输出是九路域状态探针和八路视频探针。ADC 未给其真实 PCB 引脚，SDC 未给它们 input / output delay；BASE 94.68%、HD 94.64% 的覆盖不能被描述为全部外部接口已约束。

内部异步置位 / 同步释放结构和其可见域内 recovery / removal 满足本报告的条件；板级 reset 引脚真值、时钟晶振误差、PLL 锁定失锁、CDC 亚稳态指标、实际 TMDS 时钟及数据输出、接收端画面稳定性、HDMI 电气测试、完整产品顶层 STA 与 bitstream 下载均未由本 STA 工程执行。后续应补齐板级资料、厂商反馈补偿告警与实际 AC 测量后，以真实产品顶层重新验证。

## 10. 可复现材料与证据目录

正式 clean 项目文件：`td_flow.tcl`、`base.tcl`、`hd.tcl`、`postroute.tcl`、`base_postroute.tcl`、`hd_postroute.tcl`、`clock_video_verify_top.v`、`verify_clock.sdc`、`verify_pin.adc`、`README.md`。统一执行器：`D:\Safe_Vision_FPGA_2026\safevision\tools\run_video_clock_td.ps1`（ASCII；语法和完整执行已验证）。

### 最后一次统一 runner 的可信输出

- 根目录：`D:\Codex\2026-09-30\sao\work\delivery_td`；完整归档在本目录 `td/{base,hd}/`。
- `verification_status.txt`：两档内部满足且健康开放。
- 各档 `source_manifest.txt`、`flow.console.log`、`route.db`、`route.timing`、`route.status`、`route.clock_summary`、`route.clock_intersection`、`route.check_timing`、`route.area`、`route.derived.sdc`、`route.exceptions`、`route.ignored`、`route.qor`。
- 各档 `postroute.console.log` 和 `postroute/final.{timing,status,clock_summary,clock_intersection,check_timing,area,derived.sdc,exceptions,ignored}`。
- 本次外层退出码 2 见 `td/runner_exit.txt`，两档结果标记见 `td/verification_status.txt`；原始 TD 全文在各档 console log。

### 原始证据和诊断证据

- 原始已完成路由：`D:\Codex\2026-09-30\sao\work\final_td\{base,hd}\route.*`，最初全文 `work/td_base_stdout.log`、`work/td_hd_stdout.log`。
- 同一原始 DB 的独立分析：该根目录各档 `postroute/final.*`，全文 `work/td_base_postroute_stdout.log`、`work/td_hd_postroute_stdout.log`。
- 顺序实验原件：`work/final_td/base/order_before.check`、`order_after.check`、`order_before.timing`、`order_after.timing`、`order.clock_tree`，全文 `work/td_report_order_stdout.log`。
- 汇总数据：`work/final_td/sta_summary.json`；表格依据原始和独立原件，不只依据 JSON。

`final_td_refresh`、`final_td_snapshot`、`final_td_enforce*` 是失败或无效诊断实验，禁止并入可信验收结果。正式项目不复制 `probe_*.tcl` 等探查脚本。

## 11. 本地官方依据

- TD 安装 `doc/scripts/DefaultFlow.tcl`：实际流程阶段顺序。
- `doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf`（2024.11），PDF 第 12–13 页脚本流程、第 80 / 82 / 85 页时序与时钟报告、健康检查。
- `SWUG201_Timing_Tools_User_Guide.pdf`（2025.01），PDF 第 70–71 页默认 Max/Min、Slow/Fast 对 setup / recovery / hold / removal 的分析。
- `SWUG200_Timing_Constraints_User_Guide.pdf`（2024.09），PDF 第 45–46 页全局路由强制与非全局路由命令区别；此次正式工程未使用这种附加路由强制。
- 本地板包 `6_EG4S20数据手册/PLL用户指南.pdf`，TN305_1.1（2018.09），PDF 第 2–3 页输入 / VCO / divider / Normal 补偿结构。
- 同目录 `EG4S20数据手册.pdf`，DS301_2.7.1（2021.06），资源与 BG256 第 19 页 R7 GCLK 输入。

上述本地资料之外，本轮已从官网下载页打开并读取 [DS301 v2.7.6](https://anlogic.oss-cn-shanghai.aliyuncs.com/web_doc/%E5%B7%A5%E5%85%B7%E4%B8%8E%E8%B5%84%E6%96%99%E4%B8%8B%E8%BD%BD/%E6%8A%80%E6%9C%AF%E6%96%87%E6%A1%A3/EG4/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/DS301_EG4S20_Datasheet_en.pdf) 与 [DS300 v3.9.4](https://anlogic.oss-cn-shanghai.aliyuncs.com/web_doc/%E5%B7%A5%E5%85%B7%E4%B8%8E%E8%B5%84%E6%96%99%E4%B8%8B%E8%BD%BD/%E6%8A%80%E6%9C%AF%E6%96%87%E6%A1%A3/EG4/%E6%95%B0%E6%8D%AE%E6%89%8B%E5%86%8C/DS300_Eagle_Datasheet_en.pdf)；下载字节哈希、关键页/表、适用关系和检查结果见 official_spec_review.json。未使用 DSP 频率或宣传数据率代替时钟限制。

## 12. 最终归档说明

最后一次正式运行从目标仓库 canonical 工程/runner 读取最终源码，输出原件位于 work/delivery_td。两档主流程与独立 postroute 的完整报告、route.db、控制台以及运行源哈希已归档到本目录 td/{base,hd}/。诊断原件另放 td/diagnostics/，包括旧 DB 和实验 Tcl；失败的 clear/reload 实验不计入验收。

五项 XSim 及 PLL 审计独立归档。仓库未 commit，采用 SHA-256 标识工作树；不虚构构建 tag。本报告保留初始原件的历史路径，最新交付证据以 td/ 子目录为准。
