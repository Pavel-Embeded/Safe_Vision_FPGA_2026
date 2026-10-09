# 2026-10-10 正常播放修复验证

源基线为 `7d99493eaba837192d45a3ce7647aa78895c1949`。本轮设计说明见 [正常播放花屏修复与时序说明](../../docs/正常播放花屏修复与时序说明_20261010.md)。

`validation.json` 是验收清单：仅收录包含成功断言及 `$finish`、没有失败断言的完整日志；`complete` 仅在最终 BASE、720p 长链回归均结束后为真。未完成或失败的开发候选不作为通过证据。

原始 TD 表格包含 CRLF 和对齐用尾空格。本目录证据文件按原字节保存，Git 属性仅对它们关闭格式化空白检查；源码及本 README 继续接受空白检查，不通过重写原始报告来改变哈希。

- `integrity_32_checks.log`：源地址/长度、两槽/两种 BMP 行序、独立 CRC 预期、整帧读回、播放前校验、块首/末字损坏、丢失响应超时及复位。
- `reservation.log`：低水位且视频请求尚未发出时，不让下一次写入占总线；DMA 空闲后首帧/后台写入正常获得服务。
- `card_*_source_clock_stress.log`：完整 FAT32/24 位 BMP 输入、手动和连续切换、完整扫描像素及行帧标记、物理写排空、槽所有权、存储损坏后的红色 Exit 和 KEY1 重新加载。
- `board_uart_buttons.log`：原按钮/状态接口及新增 82 字节诊断行；报告包开始时统一快照。
- `a_*.log` 和 B 模块日志：原 A 显示流水线、CDC、图层及 B 存储/SD/BMP 等默认接口回归。
- `base.*` / `hd.*`：本机 TD 6.2.168116 的最终真实布局布线门禁、资源、约束健康及输入哈希；不是功能模型给出的时序数值。
- `protected_blobs.json`：基线中本轮未修改的 472 个文件，按 Git blob 哈希逐一核验。

正常播放段要求 underflow、overflow、SOF/EOL 错误均为零。故意损坏存储之后会停止输出未通过校验的块，并进入红色 Exit；此阶段的安全像素/断流事件不能混算为健康播放，也不能从日志中删除。本长链测试在公共复位后重新加载整帧、通过整帧读回并发布，随后结束；不将该阶段表述为额外完成了复位后的逐像素扫描。

720p 的 `[UNDERFLOW]` 诊断监视器在计数任何变化时打印，包括故障注入后的增加，以及公共复位将计数清零。判断健康播放应看注入之前的零值断言及逐帧检查，不能把复位清零打印误读为新增一次断流。

长链压力测试使用加快的 SD 源时钟（500 MHz，SPI 分频 0），MEM 保持 40 MHz，扫描时钟使用 BASE/720p 的模型频率。它用于增加生产者压力、验证反压和并发；产品位流仍采用板载 50 MHz 及 12.5 MHz SPI。另有默认产品初始化分频及超时测试。720p 模型扫描为 74.25 MHz，真实 TD PLL 为 74.167 MHz；模型略快。

官方可读异步 FIFO RTL 参加仿真。SDRAM 加密控制器和 HDMI PHY 使用接口契约模型；不能将这些测试称为加密物理核的动态仿真，也不能将 CRC、STA 或生成 bit 当作真实板卡长时间运行证明。

在 PowerShell、仓库根目录可复现：

```powershell
& ./safevision/tools/run_card_display_xsim.ps1 -Case integrity,reservation,adapter,timeout,dma,drain,writer,crc,idle,bridge,edid,top,safety,init
& ./safevision/tools/run_card_display_xsim.ps1 -Case card -HD 0 -StressSdClock -RunDir D:/Codex/recheck_card_base
& ./safevision/tools/run_card_display_xsim.ps1 -Case card -HD 1 -StressSdClock -RunDir D:/Codex/recheck_card_hd
& ./safevision/tools/run_board_sta.ps1 -Mode base,hd -Bitgen -RunDir D:/Codex/recheck_board_sta
```

长链逐像素测试耗时明显高于模块回归。原始健康报告中的外部 SPI/UART/DDC 输入/输出延迟预算缺项仍保留，没有伪造为已测量。
