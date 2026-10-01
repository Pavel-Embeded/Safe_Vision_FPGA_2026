# pattern_generator（A 模块落点）

状态：仅创建模块文件夹，尚未实现功能 RTL。

用途：彩条和网格等不依赖 SDRAM 的上电测试图案；先验证固定速率时序与首像素。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
