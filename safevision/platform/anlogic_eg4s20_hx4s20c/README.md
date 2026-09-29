# HX4S20C / EG4S20BG256 平台（规划）

`rtl/`：`safevision_top.v`、时钟复位与 IP 适配 wrapper；`ip/`：可再生的 IP 配置、版本说明（生成物放 ignored `generated/`）；`constraints/`：经原理图核对的 `pin.adc`、`timing.sdc`；`project/`：TD 工程脚本/文件表，不提交工具中间产物。当前板级文件尚未建立，不能生成 bitstream。A 负责顶层集成，B/C 复核对应外设。
