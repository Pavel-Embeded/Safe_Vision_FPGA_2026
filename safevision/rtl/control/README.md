# rtl/control

负责人：C。**当前仅建立目录与命名计划，未提供功能 RTL。**

建议 `input_sync.v`、`key_debounce.v`、`playback_fsm.v`、`control_event_queue.v`。按键/UART/模式事件统一编码；跨域按接口规范。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
