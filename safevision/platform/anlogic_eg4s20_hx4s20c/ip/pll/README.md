# PLL IP（A：待接入）

手册要求使用安路 TD 官方 PLL IP；当前仓库没有可复用的生成配置或工程文件。本文件夹不包含仿真假时钟或手写倍频电路。

接入前须核对 HX4S20C/EG4S20BG256 实物板的输入晶振与复位极性，在 TD 中配置 sys 100 MHz、mem 125 MHz、基础 pixel 25.175 MHz、HD pixel 74.25 MHz、serial=5×pixel、audio_mclk 12.288 MHz 的可实现方案，记录 IP/工具版本、输出端口、locked、相位及模式切换方法，再完成 pin.adc/timing.sdc、STA 和板级测量。A 负责板级接线，C 负责音频时钟消费接口。
