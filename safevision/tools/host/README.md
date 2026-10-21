# 实板主机工具版本选择

当前BASE为 **26102004 / KEYFIX 5cff94e**。完整步骤见 [当前运维说明](../../../docs/releases/BASE_26102004/OPERATIONS.md)。

当前使用 `exercise_configuration_26102004.ps1`、`audit_configuration_26102004.py`，就绪等待显式传 `-ExpectedId 0x26102004`。串口115200/8N1，历史COM6，DTR/RTS关闭，输出目录必须全新，测试时不要同时操作实体按键。旧无后缀配置/几何/周期脚本面向26101802，保留用于历史记录，不作为当前固件的默认入口。

`burn_four_features_26102004.ps1` 是原机专用：固定D盘项目、TD和Python位置，并要求原批准提交在Git对象库中。新克隆先使用 `verify_base_delivery.py` 恢复隔离冻结包与原始对象，再按运维说明通过BitWriter下载同SHA位流；不要修改专用脚本的检查来绕过失败。

完整原始串口与板测记录在 `artifacts/board_validation/four_features_BASE_KEYFIX_5cff94e`。任何缺结束标记、端口断开或版本不符都不计通过；串口健康不能代替实际画面和声音。
