# BASE 26102301：Flash 固化、验收与恢复

**Flash 已写入并校验通过；真实断电再上电仍待验收。** 用户于本轮明确回复“目前无法断电，稍后操作”，因此没有把重载测试写成冷启动通过。GitHub 未上传。

## 1. 当前文件与身份

- 安装目录：`D:\Safe_Vision_FPGA_2026\artifacts\flash_install\BASE_26102301_6a957b0`。
- 最新位流：`SafeVision_BASE_6a957b0.bit`，636,622 字节，固件 ID `26102301`。
- SHA-256：`95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e`。
- 批准源码提交：`6a957b0365adbc8d8b4069319d29c9fb63680428`；原始物理构建提交 `c6a6549871d97755708120d2a76239011cef94bb`。本轮没有修改 RTL、改变位流或重新综合。
- 原完整发布包：`D:\Safe_Vision_FPGA_2026\artifacts\releases\BASE_FLEX_SPECTRUM_261023_6a957b0`；其中仿真、时序、资源和源码清单保持原样。
- FPGA：EG4S20BG256；本次实际识别 Flash JEDEC `EF4015`，容量 2,097,152 字节（16 Mbit）。

## 2. 本次实际执行的证据

| 检查 | 结果 | 本地证据 |
| --- | --- | --- |
| 固化前源码、证据与完整发布包校验 | 通过；41,395 个源/证据文件、41,452 个包内文件 | evidence/flash_program/preflight.json |
| 固化前整片 Flash 连续读取两遍 | 2 MiB × 2，逐字节一致 | recovery/original_flash_a.bin、original_flash_b.bin |
| PROGRAM_SPI | 通过，实际执行且退出码为 0 | evidence/flash_program/program_verify_flash.console.log |
| 独立 VERIFY_SPI | 通过 | 同上；programming.verified.json |
| 固化后整片 Flash 再读取两遍 | 2 MiB × 2，相同且与旧内容不同 | evidence/flash_program/programmed_flash_a.bin、programmed_flash_b.bin |
| 官方 Refresh 从 Flash 重新配置 | 通过；随后没有 SRAM 下载 | evidence/flash_program/read_after_refresh.console.log |
| Flash 重载后完整串口回归 | 通过 | evidence/after_flash_refresh |
| 真正断开全部供电后自行启动 | **待验收** | evidence/cold_boot_deferred/user_reply.json |

旧整片 Flash SHA-256：`0241f34a8af7288067684f9146f16c4579cd77d433b07d225d341ab076ba3857`。

新整片 Flash SHA-256：`5647f05ec18958947d32874eeb788fa396a05d0bab7c1b71f112ceb7e9b31eee`。

整片 Flash 的二进制回读与 .bit 是不同格式，哈希不应相等。是否正确写入由厂商独立校验、两次回读一致及随后从 Flash 运行共同核实。

## 3. Flash 重载后的实际串口测试

COM6，115200、8N1、DTR/RTS 关闭。六个阶段均正常结束，原始收发字节、ACK 校验和以及命令/回执一一对应再次独立核验，共 5016 帧有效 ACK。

- 固件身份与四槽缓存：ID=26102301、STATUS=7、CACHE=15；480 行、153600 字；当前 TF 卡的 WAV 回退掩码为 0。
- 40 项配置：亮度、对比度、Alpha、Fade、音量、菜单字段、缩放方式与轮播周期等写入和回读。
- 最近邻/双线性 × 四种缩放几何，共八组合；32 次手动 Fade 提交及对应自动轮播检查。
- 2、5、10、30 秒四种周期：12 次提交、8 段实际间隔。
- 两次完整媒体恢复，恢复前后所选媒体身份一致。
- 最后连续观察约 70 秒的 5 秒轮播，计数和 UART 运行健康检查通过。
- 缓存完整性、视频欠载、音频欠载/溢出及恢复等本次检查的关键故障计数均为 0；最终恢复默认 5 秒自动轮播、音量 70、菜单关闭。

| 配置周期 | 本次测得的相邻提交间隔 | 结果 |
| --- | --- | --- |
| 2 秒 | 2541 / 2448 毫秒 | 通过 |
| 5 秒 | 5565 / 5566 毫秒 | 通过 |
| 10 秒 | 10612 / 10527 毫秒 | 通过 |
| 30 秒 | 30449 / 30565 毫秒 | 通过 |

原始记录位于 evidence/after_flash_refresh 各阶段的 trace.jsonl 和 rx.bin；独立复核结论为 uart_capture.verified.json。串口不能代替肉眼/听觉验收。本位流此前已由用户确认图片、声音、频谱正常；本轮尚无断电后实体反馈。

## 4. 稍后进行真实断电验收

1. 保持当前 TF 卡不变。可以在 Windows PowerShell 中运行下方等待工具，工具只观察串口并进行功能测试，不烧录。
2. 断开开发板全部供电，包括 Type-C、JTAG USB-B、外部电源；确认所有灯熄灭，至少等待 10 秒。只拔一条线可能仍被另一条线供电。
3. 重新连接线缆，不打开下载工具、不重新烧录、不按复位或 CONFIG1，观察是否自行显示四图、播放声音并显示频谱。
4. 工具见到 COM6 消失并恢复后会自动完成六阶段串口测试，最后恢复默认设置。串口断连本身不能证明整板已完全断电，仍需人的断电确认和实际画面/声音反馈。

```powershell
& 'D:\Safe_Vision_FPGA_2026\artifacts\flash_install\BASE_26102301_6a957b0\tools\verify_cold_boot.ps1' -Port COM6
```

等待上限默认 30 分钟。证据写入 evidence/cold_boot_时间戳；如需中止，在新建的该目录中创建空文件 STOP。serial_after_reconnect.json 只表示重连后的串口验收；冷启动、画面、声音与频谱的最终确认应另外记录，不自动把这些字段置为通过。

## 5. 恢复上一版已成功运行的 BASE

保留的成功历史位流为 recovery/SafeVision_BASE_34462ee.bit（原文件不删）。SHA-256 为 `f5cdfedd128199509f45e038397a650214ff3d3ada426fef3dcb835f9af8f5f9`。

先只检查文件，不接触硬件：

```powershell
& 'D:\Safe_Vision_FPGA_2026\artifacts\flash_install\BASE_26102301_6a957b0\tools\program_flash.ps1' -Image Previous
```

确实需要回退时运行下方命令。它会先核对位流与备份哈希、实际 FPGA 与 Flash 身份，再 PROGRAM_SPI、VERIFY_SPI、Refresh，并保留独立日志。回退动作本轮没有执行；提供的是预留恢复入口。

```powershell
& 'D:\Safe_Vision_FPGA_2026\artifacts\flash_install\BASE_26102301_6a957b0\tools\program_flash.ps1' -Image Previous -Apply
```

恢复到本轮最新版则把 Previous 改成 Latest。工具默认只预演，只有显式 -Apply 才写 Flash。工具路径默认指向本机 TD 6.2.1 安装，可用 -ToolPath 指定同版本 bw_commands_prompt.exe。写入时保持供电，不与其他下载工具抢占 JTAG。旧版固件不使用本目录仅接受 26102301 的新串口测试脚本。

如只想临时排查，可在 BitWriter 用 PROGRAM_SRAM 加载保留的成功 .bit；临时 SRAM 下载不会替换当前 Flash。

## 6. 恢复固化前的原始整片 Flash

两份原始备份是安装之前实际读取的完整 2 MiB，哈希一致，保存在 recovery/original_flash_a.bin 和 original_flash_b.bin。不要仅根据文件内容推断原始程序的版本。

在 BitWizard/BitWriter 选择 Program SPIBIN，将 original_flash_a.bin 写到 Flash 偏移 0x000000；长度为完整 2,097,152 字节。结束后用 Flash Read 从 0x000000 读回相同长度，保存成另一个新 .bin，并计算 SHA-256，必须等于上面旧整片 Flash 的哈希，再进行 Refresh/断电验证。不要把 .bin 当成 .bit 使用，也不要覆盖原始备份。

厂商安装文档：D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\doc\SWUG\SWUG110_BitWizard_User_Guide.pdf，PDF 第 20–22 页（印刷页 19–21），包含 Program Flash、Program SPIBIN、Flash Read、Verify Flash。原始整片回退本轮没有执行。

## 7. 本地文件、清理与验证边界

- Flash 当前运行身份及本地批准源码均绑定 26102301 / 6a957b0；flash_install.index.json 汇总本轮状态及文件哈希。
- 本轮缓存清理记录：`D:\Safe_Vision_FPGA_2026\artifacts\maintenance\flash_cleanup_261023\CLEANUP_FLASH_261023.md`，删除约 881.39 MiB 生成缓存，日志/配置已压缩保留。成功位流、原始报告、旧 Flash、源码、Git 和回收站均保留。
- 既有发布包及旧验收记录是各自时点的不可变证据；其中历史 flash_written=false 不改写。本文件与本轮 index 描述后续真实 Flash 安装状态。
- 功能和测试结论限定于该位流、当前板卡与当前 TF 卡；真实冷启动待验收，不能据此承诺任意卡/任意损坏文件/任意硬件都必然成功。
- 本轮没有推送 GitHub，没有改动 TF 卡内容。
