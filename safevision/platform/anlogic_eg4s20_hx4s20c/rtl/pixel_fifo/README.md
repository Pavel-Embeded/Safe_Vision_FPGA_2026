# pixel_fifo（A 模块落点）

状态：仅创建模块文件夹，尚未实现功能 RTL。

用途：安路异步像素 FIFO 的板级适配规划落点；FWFT、复位极性、水位与读延迟须与 B/A 接口核对。

新增端口与时钟域须先登记到 docs/interface_spec.md 和 docs/architecture/module_registry.md，再加入对应测试与显式源文件表。目录存在不表示模块已通过仿真或上板。
