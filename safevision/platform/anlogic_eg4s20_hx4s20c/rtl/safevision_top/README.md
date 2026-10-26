# safevision_top（A 模块落点）

早期记录：目录已建立，功能 RTL 当时尚未实现。

用途：板级 safevision_top 规划落点；负责引脚、PLL、IP、复位和 safevision_core 接线。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
