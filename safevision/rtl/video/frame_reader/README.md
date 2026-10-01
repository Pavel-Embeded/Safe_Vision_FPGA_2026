# frame_reader（A 模块落点）

状态：仅创建模块文件夹，尚未实现功能 RTL。

用途：在固定扫描速率下消费 B 的像素 FIFO；处理预取、首像素对齐和欠载安全色。B 的 video_read_dma 与 frame_swap_cdc 仍在 rtl/memory。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
