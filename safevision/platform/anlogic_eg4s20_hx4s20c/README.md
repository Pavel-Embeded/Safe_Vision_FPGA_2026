# HX4S20C / EG4S20BG256 平台

`rtl/`：`clock/` 时钟复位 RTL（A，已仿真通过）、`top_stage5_sector_rd.v` 板级 bring-up 顶层（B，接引脚、阶段 5 最小验证、已仿真通过未上板）；`safevision_top/safevision_top.v`（A 的产品顶层）待写。`ip/`：可再生的 IP 配置、版本说明（生成物放 ignored `generated/`）。`constraints/`：经原理图逐脚核对的 `pin.adc`、单一 50 MHz 时钟域的 `timing.sdc`。`project/`：TD 工程 `safevision.al`（器件 EG4S20BG256，35 条设计文件全为相对路径，`TOP_MODULE = top_stage5_sector_rd`，`constraint_1` 已挂两约束），不提交工具中间产物。PLL IP、HDMI PHY 与产品顶层尚未接入，因此**还不能生成产品 bitstream**；bring-up 顶层不需 PLL，可先综合下载验证阶段 5。A 负责顶层集成，B/C 复核对应外设。
