> 历史记录整理版。内容对应原记录的版本与日期，当前验收请查仓库首页；原件按索引保留。

# sim 证据索引

尚无本次目录整理新增的测试证据。新记录只追加，不覆盖原始记录。

> 2026-10-14（C 链）：`rtl/{control,safety,audio}` 的 11 个模块与 7 个 `tb_c_*.sv` 已用 ModelSim `vlog` 编译 EXIT=0，并在本机 `vsim` 跑通：入口 `tools/run_c_sim.ps1` 汇总 `C-chain TOTAL PASS=154 FAIL=0`（7 个 TB 的 `[TB] ... done, errors=0` 全部为 0）。运行条件：先设 `MGLS_LICENSE_FILE` 指向本机许可证文件（本机路径不入库；不设则 `vsim` 无法检出许可证）。原始日志与 SHA-256 见下表。局限：未上板、未 STA，不宣称整项需求完成。

| 测试/条目 ID | 需求 ID | 构建 tag / Git 提交 | 条件与设备 | 结论 | 原始文件与 SHA-256 |
|---|---|---|---|---|---|
| C-chain 单元回归（7 TB / 154 断言） | B03 / B04 / E02 / E04 | `0234402`（工作树，未提交） | 本机 Windows + ModelSim SE-64 10.7（`vopt`+`vsim`，`MGLS_LICENSE_FILE` 指向本机许可证） | PASS=154 FAIL=0（input_sync 17 / priority_arbiter 11 / playback_fsm 27 / emergency_fsm 23 / watchdog 14 / fault_manager 12 / audio 50） | `evidence/sim/run_c_sim_20261014.log`，SHA-256 `BC6C2AF5E48B2061CD84D14EAE9731883AF2E72F9248175BCF7935380D225DE5` |
