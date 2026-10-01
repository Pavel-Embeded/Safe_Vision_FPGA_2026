# clock（A：板级时钟复位）

本目录已有两个面向综合的 Verilog-2001 文件：reset_sync.v 实现单域异步断言、默认两拍同步释放；clock_reset_ctrl.v 按 PLL 锁定与局部请求产生九路低有效复位。接口登记于 docs/interface_spec.md v1.9，单元测试见 safevision/verification/unit/tb_clock_reset_ctrl.sv；TD 综合与仿真尚未执行。

这两个模块不生成时钟。sys_clk、mem_clk、pixel_clk、serial_clk、audio_clk 必须由已配置的安路 PLL IP 输入。当前仓库无 TD PLL IP、引脚/时序约束、safevision_top 和板级实测，因此此目录不能单独生成 bitstream。局部复位请求需保持到目标域观察到复位，跨域请求先做 CDC。

目标：board 50 MHz；sys 100 MHz；mem 125 MHz；基础 pixel 25.175 MHz；HD pixel 74.25 MHz；serial 为对应 pixel 的 5 倍；audio_mclk 12.288 MHz。频率以最终 IP 配置、STA 和板级测量为准，视频模式切换方案尚未冻结。
