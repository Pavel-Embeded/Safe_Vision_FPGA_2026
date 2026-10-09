# TD 板级工程入口

`safevision.al` 的顶层为 **safevision_top**，输出使用 **HDMI B**。
旧版 `safevision.al` 指向 SDRAM 回环顶层，不能作为完整图片显示工程；旧工程保留为
`safevision_loopback.al`。不要将回环测试产生的下载文件当成图片播放器。

第一次使用或换机器后，从仓库根目录执行：

```powershell
./safevision/tools/prepare_board_project.ps1
./safevision/tools/run_board_sta.ps1 -Mode base,hd -Bitgen
```

准备脚本查找已安装的赛方官方 HDMI IP，复制所需源文件到本地忽略目录
`vendor_hdmi/hdl_source`，复制字体，并由 `board_verify/board_sources.list` 生成 GUI 文件表。
也可以用 `-VendorRoot` 指定官方 HDMI HDL 目录。厂商软件和加密 IP 包不上传 Git。

GUI 与命令行采用同一份 HDL 依赖表和 `board_verify/board_b.adc`、`board_b.sdc`、
`board_cdc.sdc`。器件为 **EG4S20BG256**，工程 `Path="."`，设计文件路径相对本目录。
GUI 入口默认 BASE 640×480；720p 使用命令行 `-Mode hd`，不猜测 GUI 宏设置格式。
只有严格时序检查通过，`run_board_sta.ps1 -Bitgen` 才生成对应模式的 `safevision_top.bit`。

发布存储配置：SYS 100 MHz、MEM 50 MHz、SDRAM 时钟 50 MHz 且上升沿延后 8 ns；
BASE 像素时钟约 25.185 MHz，720p 为 74.25 MHz。原 125 MHz PLL 保留给独立旧测试。
新工程的 SDRAM 控制器时间参数与 MEM 频率一致。不要只替换 PLL、却留下旧控制器频率。

SD 卡内容为 FAT32 根目录 `SV0001.BMP` 至 `SV0004.BMP`，640×480、24 位、无压缩 BMP。
可执行 `make_board_test_card.py --out <目录>` 生成四张不同的测试图。

按键接口以 ADC 引脚为准：KEY1/A2 全局复位，KEY2/B2 下一幅，KEY4/C1 按住自动播放，
KEY3/B1 按住显示片上应急画面。CONFIG1 不是本顶层的模式输入。
片上安全画面在卡/存储未就绪或故障时仍保持完整扫描；它不依赖 SDRAM 的回落写入器。

详见 [白屏修复与验证报告](../../../../docs/verification/AB_WHITE_SCREEN_REPAIR_20261009.md)。
仿真、布局布线报告、真实板卡验收分别记录；生成下载文件不等于已证明实板显示正常。
