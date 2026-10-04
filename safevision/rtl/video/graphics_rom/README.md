# graphics_rom（A 模块落点）

状态：A 阶段 7 已实现 `font8x16_rom.v`；同步读一拍；全地址仿真与 TD BRAM 初始化回读通过，尚未上板。

字库资源：`safevision/assets/fonts/font8x16.mem`，4096 字节，95 个可打印 ASCII 字符。使用官方 TD 推断 BRAM；独立全地址 ROM 映射 4 块 9K，不需要占额外 PLL。图标/颜色查表仍属后续实现。

文件路径规则、bit7 左端和验证入口见 [A 阶段 1–9](../../../../../docs/A_stages1_9.md)。
