# HX4S20C / EG4S20BG256 平台（规划）

`rtl/`：`safevision_top/safevision_top.v`、`clock/` 时钟复位与其他 IP 适配 wrapper；`ip/`：可再生的 IP 配置、版本说明（生成物放 ignored `generated/`）；`constraints/`：经原理图核对的 `pin.adc`、`timing.sdc`；`project/`：TD 工程脚本/文件表，不提交工具中间产物。当前仅 `rtl/clock/` 有两份复位 RTL；PLL IP、板级顶层、引脚/时序约束尚未建立，不能生成 bitstream。A 负责顶层集成，B/C 复核对应外设。
