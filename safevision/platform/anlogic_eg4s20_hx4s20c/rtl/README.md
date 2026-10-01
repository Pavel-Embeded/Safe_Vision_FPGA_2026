# rtl

板级模块目录：`clock/`、`pixel_fifo/`、`hdmi/`、`chipwatcher/`、`safevision_top/`。板级顶层 `safevision_top/safevision_top.v` 与 PLL/FIFO/SDRAM/HDMI 适配 wrapper 只接抽象业务端口，不把业务状态机搬进 IP wrapper。

`clock/` 已有复位同步与分域控制 RTL，其余模块仍只有目录说明。PLL IP、板级顶层、约束及实物验证待补。
