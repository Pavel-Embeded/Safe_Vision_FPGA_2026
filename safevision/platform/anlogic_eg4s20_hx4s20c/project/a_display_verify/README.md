# A 阶段 11–15 TD 验证工程

入口：`base.tcl` / `hd.tcl`，器件 EG4S20BG256，TD 6.2.168116。推荐运行仓库 `safevision/tools/run_a_display_sta.ps1`，它检查最终 setup/hold、三域时钟、有效约束和 CDC 约束健康，而不是只看 TD 的退出码。

验证顶层 `a_display_verify_top` 保留 A 完整取帧/FIFO/字库/合成逻辑。三个独立时钟输入按 sys100 MHz、mem125 MHz、BASE25.185185 MHz/HD74.25 MHz约束；HD略严于已有PLL74.166667 MHz。现有 `clock_gen`、PLL文件及 B 的 `safevision.al` 保留。

`cdc.sdc` 只放宽已确认的同步器首级与复位同步入口；mailbox载荷和官方FIFO Gray指针受8 ns最大传播延迟限制。同步器第二级和普通业务路径继续检查。迁移到产品顶层必须替换 `core/` 层级及源B载荷寄存器名，并验证每条约束实际命中，不能直接照搬层级。

这是内部实现探针：响应器用于保留数据路径，并非SDRAM控制器。探针输入、RGB/诊断输出没有板级外设时序预算；TD报告会明确提示未设输入/输出延迟。未使用物理PLL、SDRAM DQ、HDMI PHY和板级引脚，没有生成烧录位流。不能用本工程的正余量宣称整板时序已闭合。

字体初始化按 `font8x16_rom.v` 所在目录解析已有相对路径；仿真脚本另复制同一字体到仿真运行目录。所有 `.db/.log/.timing` 和生成物仅写入 `safevision/build/out` 或指定 RunDir，不提交到仓库。
