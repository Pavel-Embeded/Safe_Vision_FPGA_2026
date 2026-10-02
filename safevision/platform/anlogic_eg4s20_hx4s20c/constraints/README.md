# constraints

`pin.adc` 按原理图逐脚核对；`timing.sdc` 明确每个时钟、派生时钟、输入输出与 CDC 例外。两者是源文件，须版本管理。

当前已有第一版（对 `top_stage5_sector_rd`）：

- `pin.adc`：引脚来源按权威性排序——① 开发板手册《HX4S20开发板手册-HDL版2410.pdf》的官方引脚表
  （串口表 `RXD=F12`/`TXD=D12`；独立 LED 表 `LED1..4=A4/A3/C10/B12`；独立按键表 `KEY1=A2`）；
  ② `2_FPGA.pdf`（引脚号 ↔ 网络名）与 `6_EX_DEVICE.pdf`（SD/LED/按键页）；
  ③ 厂商同器件（EG4S20BG256）例程的 `pin.adc`。三者对 `clk`/`sd_*` 完全一致。
  结果：`clk=R7` / `rst_n=A2` / `sd_dclk=A14` / `sd_mosi=A13` / `sd_miso=B14` / `sd_ncs=A12` /
  `led[3:0]=A4,A3,C10,B12` / `uart_txd=D12`。
  ★ `uart_txd=D12` **已确认是 FPGA 发送脚**：手册图2-10 里 CH340G 的 pin2（芯片 TXD）接网络 `RXD`、
  pin3（芯片 RXD）接网络 `TXD`，**两线交叉**说明网络名按 FPGA 视角命名；且板上自带 USB-UART，
  **不需要外接 USB-TTL 模块**。
- `timing.sdc`：单一 50 MHz 时钟域，只有 `create_clock -name clk -period 20`；本顶层不接 PLL。

两者已登记进 `project/safevision.al` 的 FileSet `constraint_1`。实测值（SCLK 频率、I/O delay、
超时拍数）板到后回填，见 `docs/B链-待办与硬件验证清单.md` 的 M-1~M-9。
