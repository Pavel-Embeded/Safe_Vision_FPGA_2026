# rtl

板级模块分为 `clock/`、`pixel_fifo/`、`hdmi/`、`chipwatcher/` 和 `safevision_top/`。早期顶层为 `safevision_top/safevision_top.v`，PLL/FIFO/SDRAM/HDMI 包装模块通过抽象端口连接业务逻辑，业务状态机仍留在业务层。

`clock/` 已有复位同步与分域控制 RTL，其余模块仍只有目录说明。PLL IP、板级顶层、约束及实物验证待补。
