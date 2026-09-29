# 接口管理

`../interface_spec.md` 是现有 B 链接口基线。此目录存模板、接口评审记录与后续 A/C 扩展说明，不能创建第二份互相冲突的“正式接口规范”。

流程：提出变更 → 填 [模板](interface_template.md) → A/B 或 A/C 双方评审 → 更新 Testbench → 更新 RTL → 子系统回归、CDC/STA → 板级握手留证 → 在需求追踪表登记。手册 V2.0 §10.5 要求文档先于 RTL。

优先冻结 `mem_write_cmd`、`pixel_fifo`、`slot_commit`、`control_event`、`fault_snapshot`、`audio_sample`、Global Status；有歧义时以经过双方签收的版本和实际代码为准，记录差异，不从手册表格直接推断已实现端口。
