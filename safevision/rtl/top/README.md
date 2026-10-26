# rtl/top

负责人：A。当前仅建立目录与命名计划，未提供功能 RTL。

模块文件夹 `safevision_core/`：计划放可移植 `safevision_core.v`，连接三链抽象端口、状态/错误汇总，不放引脚/IP/约束。顶层装配需系统 TB 与接口检查。

新增文件前先更新 `docs/architecture/module_registry.md`，跨人端口先更新 `docs/interface_spec.md`，并在 `verification/` 放对应测试。
