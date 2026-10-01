# video_cdc（A 模块落点）

状态：仅创建模块文件夹，尚未实现功能 RTL。

用途：A 侧视频控制 CDC 的规划落点；单比特、事件、载荷和像素流分别采用适当手段，不复制 B 已有 frame_swap_cdc。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
