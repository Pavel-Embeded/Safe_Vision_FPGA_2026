# rtl/safety

负责人：C。**当前仅建立目录与命名计划，未提供功能 RTL。**

建议 `fault_manager.v`、`watchdog.v`、`emergency_fsm.v`。故障首因粘滞、媒体复位隔离、安全状态/恢复；安全画面渲染归 A 的 video。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
