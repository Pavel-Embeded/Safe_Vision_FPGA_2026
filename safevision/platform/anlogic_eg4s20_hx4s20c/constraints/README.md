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

## ★ `pin.adc` 的 `[SD-ONLY]` 开关（2026-10-02 新增，踩过坑）

三个 bring-up 顶层的端口**不完全一样**：

| 顶层 | 端口 |
|---|---|
| `top_stage5_sector_rd` | `clk` / `rst_n` / `sd_ncs`·`sd_dclk`·`sd_mosi`·`sd_miso` / `uart_txd` / `led[3:0]` |
| `top_stage6_fat32_mount` | 同上（都与 TF 卡打交道） |
| `top_sdram_loopback` | `clk` / `rst_n` / `uart_txd` / `led[3:0]` ★ **没有 `sd_*`**（SDRAM 是封装内硬核） |

**TD 对"约束文件里出现顶层不存在的端口"是报错、不是警告**，2026-10-02 实测：

```
RUN-1002 : start command "read_adc ../../../constraints/pin.adc"
USR-8168 ERROR: set_pin_assignment { sd_dclk } { LOCATION = A14; ... } in ../../../constraints/pin.adc(56)
               is not a valid ADC command.
（GUI 侧另报 HDL-1492 Failed to find pin sd_dclk in model top_sdram_loopback）
⇒ 随后 PRJ-5013 : Run syn_1 failed
```

因此 `pin.adc` 分成两段：

- **公共 6 条**（`clk` / `rst_n` / `uart_txd` / `led[3:0]`）—— 三个顶层都有，**恒定生效**；
- **`[SD-ONLY]` 4 条**（`sd_dclk`/`sd_mosi`/`sd_miso`/`sd_ncs`）—— **只有阶段 5/6 顶层有**，
  用 `top_sdram_loopback` 时必须**保持注释**；重跑 M-7（多卡）/ M-8（拔卡）时**去掉行首 `#`**。

★ 好消息：`read_adc` 是**每次 Run 都执行**的命令（在 `syn_1/run.log` 里能看到），
所以**改完 `.adc` 直接重新综合即可，不需要关掉/重开 TD**。

`timing.sdc` 在 2026-10-02 加了 `derive_clocks`（`top_sdram_loopback` 接了 `sys_pll`；
不派生的话 125 MHz 域没有时钟定义、**STA 会是假通过**；对不接 PLL 的顶层派生不出额外时钟，可常开）。
