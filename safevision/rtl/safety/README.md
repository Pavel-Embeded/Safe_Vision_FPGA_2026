# 安全状态管理

故障分级和锁存由 `fault_manager` 等模块完成。生产 `v3_supervisor` 汇集心跳、进展、完整性与欠载状态，再由恢复控制执行有次数上限的重试。

接口、时钟、复位和测试入口见 [生产模块手册](../../../docs/modules/README.md)。当前验收见 [BASE 26102301](../../../docs/releases/BASE_26102301/ACCEPTANCE.md)。本目录同时保留部分早期实现，生产选择以显式源清单为准。
