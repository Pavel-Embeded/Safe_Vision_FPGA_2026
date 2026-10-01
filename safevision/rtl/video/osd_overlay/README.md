# osd_overlay（A 模块落点）

状态：仅创建模块文件夹，尚未实现功能 RTL。

用途：将状态、告警文字与图标叠加到像素流；需登记 ROM 延迟并对齐 de/坐标。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
