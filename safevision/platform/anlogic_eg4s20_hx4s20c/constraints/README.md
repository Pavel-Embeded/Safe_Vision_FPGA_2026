# constraints

`pin.adc` 按原理图逐脚核对；`timing.sdc` 明确每个时钟、派生时钟、输入输出与 CDC 例外。两者是源文件，须版本管理。

当前已有第一版（对 `top_stage5_sector_rd`）：

- `pin.adc`：引脚依据 `2_FPGA.pdf`（FPGA 引脚分布）与 `6_EX_DEVICE.pdf`（SD/LED/KEY 页），
  并与厂商同器件例程 `7_lab_ex_2026_nosoft/example/lab_ex4_tf` 的 `pin.adc` 交叉核对。
  `clk=R7` / `rst_n=A2` / `sd_dclk=A14` / `sd_mosi=A13` / `sd_miso=B14` / `sd_ncs=A12` /
  `led[3:0]=A4,A3,C10,B12` / `uart_txd=D12`（**物理落点待复核**，备用 `GPIOA_0=H13`）。
- `timing.sdc`：单一 50 MHz 时钟域，只有 `create_clock -name clk -period 20`；本顶层不接 PLL。

两者已登记进 `project/safevision.al` 的 FileSet `constraint_1`。实测值（SCLK 频率、I/O delay、
超时拍数）板到后回填，见 `docs/B链-待办与硬件验证清单.md` 的 M-1~M-9。
