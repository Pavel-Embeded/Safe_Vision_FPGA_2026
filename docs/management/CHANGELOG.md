# 管理结构变更记录

## 2026-10-14

- [新增] C 控制/安全/音频链 11 个 RTL 模块：`rtl/control/{input_sync,key_debounce,priority_arbiter,control_event_queue,playback_fsm}.v`、`rtl/safety/{watchdog,fault_manager,emergency_fsm}.v`、`rtl/audio/{audio_scheduler,alarm_tone_gen,audio_priority_arbiter}.v`。遵守仓库红线：一 reg 一驱动源；多比特控制信号整组 mailbox + commit/ack toggle；看门狗喂狗来自被监控真实活动、超时只由全局复位或 `recover_ack` 清除；三路心跳阈值互异。
- [新增] C 单元 TB 7 个（`verification/unit/tb_c_{input_sync,priority_arbiter,playback_fsm,emergency_fsm,watchdog,fault_manager,audio}.sv`）与独立入口 `safevision/tools/run_c_sim.ps1`，并登记进 `safevision/tools/run_all.ps1` 的条目表。
- [登记] 接口缺口 **O-12**：B 的 `common/error_report.v` 只有 `wr_en`、`rd_en` 恒 0，冻结的 Control Event Interface 无读出信号；已在 `control_event_queue.v` 文件头如实登记，不擅自改 B 文件。
- [改名/登记] 消除 C 内部同名歧义：`fault_manager` 的**请求脉冲**保留 `media_rst_req`，`playback_fsm` 的**执行电平**改名 `media_rst_req`→`media_rst_active`，两模块头注互指。登记 **O-13**（同名不同义，已改名消歧，待 A/B 复核）与 **O-14**（`fault_manager` 的请求脉冲尚无输入接到 `playback_fsm`，集成期待接线）。`playback_fsm`、`tb_c_playback_fsm.sv` 与文档同步；其余端口/行为/断言一字未改。
- [状态] RTL + TB 已用 ModelSim `vlog` 编译 **EXIT=0**，并用 `vsim` **本机跑通**：`run_c_sim.ps1` 汇总 **`C-chain TOTAL PASS=154 FAIL=0`**（7 TB 的 `errors=0`）；原始日志 `evidence/sim/run_c_sim_20261014.log`。运行前需设 `MGLS_LICENSE_FILE` 指向本机许可证文件。跑仿真时修掉三处：`tb_c_input_sync` 未释放 `rst_n`、`tb_c_audio.do_sample` 多走一拍、`playback_fsm` 的媒体复位输出改为 `media_rst_active` 电平（见 WORK_ITEMS「C 链落地」）。未上板、未 STA。

## 2026-09-30

- [新增] 按 A 视频、顶层、板级 RTL 与 IP 分类建立逐模块文件夹；未实现模块仅放用途说明。
- [新增] 板级 `clock/reset_sync.v` 与 `clock/clock_reset_ctrl.v`，分别实现异步断言/本域同步释放和锁定许可/局部复位隔离。
- [新增] `tb_clock_reset_ctrl.sv` 与独立 ModelSim 入口；仿真尚未执行，板级 PLL IP、顶层和约束待接入。
- [改写] 接口规范升至 v1.9，登记 clock 端口、复位时序及与 B/C 的边界；模块表、结构导航和测试矩阵同步。

## 2026-09-29

- [新增] A/B/C 目录、板级适配、构建、分层验证、证据与评审框架。
- [新增] 模块登记、需求追踪、工作项、发布规则和结构检查。
- [保留] B 链全部现有 RTL、Testbench、模型、仿真脚本和原接口文档；不修改其行为。
- [纠正] 根 README 的 GitHub Desktop 占位说明由项目入口替换（应用覆盖包后生效）。
- [风险] 新目录是开发落点，未实现模块不宣称可综合、可上板或通过验收。
