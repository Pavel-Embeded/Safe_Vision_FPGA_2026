# 安全状态管理

`fault_manager` 等模块处理故障分级和锁存；生产 `v3_supervisor` 连接心跳、进展、完整性及欠载状态，恢复控制执行有界重试。

接口、时钟、复位和测试入口见 [生产模块手册](../../../docs/modules/README.md)。当前验收见 [BASE 26102301](../../../docs/releases/BASE_26102301/ACCEPTANCE.md)。本目录同时保留部分早期实现，生产选择以显式源清单为准。
