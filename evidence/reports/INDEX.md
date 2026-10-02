# reports 证据索引

尚无本次目录整理新增的测试证据。新记录只追加，不覆盖原始记录。

| 测试/条目 ID | 需求 ID | 构建 tag / Git 提交 | 条件与设备 | 结论 | 原始文件与 SHA-256 |
|---|---|---|---|---|---|
| TC-Q-STA | B01（阶段 5 bring-up 顶层） | 源码基线 `bb77955`（构建时工作树 HEAD，含多驱动修复） | TD 6.2.168116；器件 EG4S20BG256（HX4S20C 板）；顶层 `top_stage5_sector_rd`；约束 `constraints/timing.sdc`（单 50 MHz：`create_clock -period 20`）+ `constraints/pin.adc`；流程：read_design → opt_rtl → opt_gate → opt_place → opt_route → bitgen，全流程一次通过 | **时序收敛**：Setup WNS = +11.297 ns、Setup TNS = 0、违反端点 0（906 端点 / 3480 路径）；Hold WNS = +0.046 ns、Hold TNS = 0、违反端点 0。约束 50 MHz 下报告 Fmax = 114.903 MHz（R-Period 8.703 ns）。资源：IO 11/188（5.85%，与顶层 11 个端口一致 ⇒ 引脚约束已生效）、LUT 814/19600（4.15%）、REG 434/19600（2.21%）、BRAM 0、DSP 0、slices 436（4.45%）。`syn_1/run.log` 中已无 `HDL-8007/9007`、无 `remains a black box`（对比同日早先那次失败的 elaborate） | `TC-Q-STA_20261002_bb77955_final_timing.rpt`（TD 布线后 STA 原文，103837 B，SHA-256 `B9D8D5F167F0E85E…`）<br>`TC-Q-STA_20261002_bb77955_route.qor`（布线 QoR，1313 B，`23CF55291D5B83A2…`）<br>`TC-Q-STA_20261002_bb77955_place.qor`（布局 QoR，1741 B，`7546089288A7BC8B…`）<br>`TC-Q-STA_20261002_bb77955_syn_run.log`（综合日志，16367 B，`2E8B013D691EEEEA…`）<br>`TC-Q-STA_20261002_bb77955_gate.area`（综合后资源，2017 B，`CB51097B5CCF93BA…`） |

## 说明与遗留

- 位流 `phy_1/safevision.bit`（629641 B，10-02 16:41:46）**已生成且已复制到 TD 的 `best_result/`**，但
  `.bit` 被 `.gitignore` 全局忽略（可再生、体积大），故不进仓库；本索引记录它存在与生成时间。
- STA 覆盖率 99.53%：未覆盖部分是**故意未约束的 I/O 路径**（`sd_dclk` / `sd_mosi` / `sd_ncs` /
  `uart_txd` 输出与 `sd_miso` 输入，实测 I/O delay 见待办清单 M-5/M-6）；`rst_n` 到 `reset_sync`
  第一级的异步路径也未设 false path（STA 未报违例）。
- **Hold（removal）余量只有 0.046 ns**，为正但很薄。目前 50 MHz 下无违例；后续若在
  `reset_sync` 输出的复位域里增加寄存器、或提高频率，需重新评估。缓解手段：给复位树加约束/
  分区同步，而不是把复位直接当异步全局网。
- 本页只记"静态时序与资源"这一类结论。**上板行为（UART 回传比对、SCLK 实测频率）不在此页**，
  见 `evidence/board/` 与 `evidence/measurements/`（待填）。