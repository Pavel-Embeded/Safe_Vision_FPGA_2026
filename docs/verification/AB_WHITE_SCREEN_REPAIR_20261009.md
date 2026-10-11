> ⚠️ 本文写于 2026-10-11 仓库收敛之前。文中提到的 `evidence/ab_multiround_*`、`releases/ab_multiround_*`、`top_stage10_framebuffer`、`safevision_loopback.al`、`prepare_board_project.*` 等文件已在收敛中删除（**历史提交全部保留**）；取回方式与收敛清单见 [仓库收敛说明](../仓库收敛说明_20261011.md仓库收敛说明_20261011.md)。

# SafeVision A/B 白屏修复与验证记录（2026-10-09）

本轮从私有仓库 `Pavel-Embeded/Safe_Vision_FPGA_2026` 的
`codex/hdmi-offline-fix-20261008` / `ca85b100309a31f19adab4d6cfcfa81b693da929` 开始，
在独立分支 `codex/ab-white-screen-fix-20261009` 修改。用户观察为：原先能显示 SD 图片，
现在插卡白屏，KEY1、KEY2、CONFIG1 都不能恢复。没有获得当时下载文件的哈希、串口记录
或示波器数据，因此不能把某一项源码缺陷断言为这块实板白屏的唯一原因。

本轮已修复确定的工程和 RTL 问题，完成动态仿真与真实 TD 布局布线，生成 BASE/720p
下载文件。板卡 HDMI 实际画面、SD 卡电气时序和长期播放仍需实际下载后验收。
附件开发手册用来核对 A/B 分工与预期功能；文档里的学习步骤没有作为用户授权执行。

## 1. 历史与定位

| 历史点 | 本轮核查结果与处理 |
| --- | --- |
| `09c7f9f` A 应急/HDMI 合并 | 保留其图形、OSD、扫描、CDC 和接口模块；板级原来没有启用独立应急源，本轮接入 |
| `eaaf687` 早期 SD 上板链 | 保留 50 MHz SD 媒体链、按键消抖、遥测同步、MISO 上拉和双槽所有权 |
| `b6f2f1f` 存储突发/帧发布修复 | 保留至少两拍写入、单字掩码邻拍、至少 16 拍物理静默、write_idle 和 mailbox 发布屏障 |
| `63db41b` HDMI 复位/CRC 时序 | 保留 HDMI 插拔触发恢复、队列恢复及真实 CRC 双周期约束；对应回归继续通过 |
| `ca85b10` 默认 SD 时钟测试 | 保留产品初始化 100 kHz；新增超过 200 ms 的真实慢卡初始化回归 |
| 当前 GUI 工程入口 | 旧 `safevision.al` 顶层是 `top_sdram_loopback`，不能代表完整 HDMI 图片显示；改为 `safevision_top`，旧回环工程另存 |

用户说 CONFIG1 也不能恢复，并不能证明 BMP 文件或某条 RTL 一定有错。当前顶层只接
KEY1/A2、KEY2/B2、KEY3/B1、KEY4/C1；CONFIG1 不参与图片播放模式选择。
必须先确认实际下载的是这一轮的 `safevision_top` 文件，并接 HDMI B。

## 2. 已确认缺陷、推测与修复

| 问题 | 证据 / 后果 | 修改 |
| --- | --- | --- |
| GUI 顶层与真实显示顶层不一致 | 仓库原工程是存储回环入口；重新综合可能下载了不含图片显示的工程 | 主 `.al` 改为 `safevision_top`，58 项依赖与命令行共享清单；明确 HDMI B 引脚、完整 SDC 和字体准备步骤 |
| 125 MHz 存储边界时序没有闭合 | 历史与本轮旧配置均出现 SDRAM setup -6.826 ns，复位不能消除布局布线违例 | 单独新增 `sv_board_memory_pll`，SYS100/MEM50/SDRAM50 MHz，SDRAM 上升沿延后 8 ns；控制器时间常量同时使用 50 MHz；旧 PLL 不覆盖 |
| 旧“片上回落图”仍依赖 SDRAM | 它先写入 SDRAM 再由 DMA 显示，存储出问题时回落也失败 | 接入 BRAM 字体/几何应急图形；启动、卡故障、存储故障和 KEY3 显示完整安全画面，HDMI 扫描持续 |
| 产品 SD 外层初始化仅 200 ms | 慢卡可以尚未完成 ACMD41 就被播放器终止；规范允许卡初始化到 1 s | 外层上限改为 2 s；继续保留重试及回落完成后的槽所有权交接 |
| SDRAM 返回丢失导致 adapter 永久等待 | 原 H_WAIT 没有响应超时出口 | 新增 READ_TIMEOUT=4096 拍（50 MHz 时约 81.92 us），故障锁存并禁止继续读写，只能通过共同复位重建事务周期 |
| 板级把仲裁 grant 当成写入接受 | 双图完整测试第 2 张图有少量字/像素错误，CRC、帧发布、欠载检查却正常；首张图无积压时掩盖了错误 | sink 与回落 writer 的 wr_ready 改接 prod_wr_busy && mem_req && mem_wr && mem_ready；数据保持到 adapter 真正接受，物理排空仍由 write_idle 单独保证 |
| 降频后的 720p 带宽不足 | 初始 50 MHz 试验每帧欠载，120 ms 时 U=6、无完整正常帧 | 完整读缓存可在物理静默期内输出；物理命令仍等待至少 16 拍。DMA 边接收边拆像素，FIFO 使用 AW12/8190 个有效像素、256-word 逻辑突发，预取水位 7662 |
| FIFO 原始异步复位约束依赖物理寄存器名字 | TD 打包后 SR 引脚改名，旧匹配变空，BASE recovery 最差 -3.815 ns | 保留原始 fifo_reset 网名并验证集合非空；只将该原始异步断言到 SR 的路径排除，域内同步释放、正常数据和 Gray 指针继续计时 |
| 字体与 HDL 路径易漂移 | 旧 GUI 不含真实显示依赖；字体相对运行目录读取 | 准备脚本复制官方 IP 与 font8x16.mem；GUI 路径相对工程，CLI/GUI 共用 board_sources.list |
| Windows 仿真长命令行 | xvlog 超过 cmd 长度时截断或退出；`--prj` 会误按 Verilog 解析 SV | 使用 `--file` 带引号的文件响应清单；RTL 与 SystemVerilog 编译明确分开，所有修改过的入口已实际运行 |
| 顶层 UART 测试保留旧 125 MHz 接收器 | 产品发送器已按 MEM_CLK_HZ 使用 50 MHz，旧测试把正确 115200 波特误采样 | 更新测试接收器为 434 拍/位；mailbox 送达断言等待真实跨域传播的有限窗口，不把提交与送达当作同一拍 |

关于 SD 初始化依据：[SD Association Physical Layer Simplified Specification v7.10](https://www.sdcard.org/cms/wp-content/themes/sdcard-org/dl.php?f=Part1_Physical_Layer_Simplified_Specification_Ver7.10.pdf)，4.4 的 ACMD41 初始化时限。

尚未确认的可能原因包括：实际 Flash/SRAM 仍装旧文件、HDMI 端口/线材/显示器兼容、
SD 供电或接触、错误分区/文件格式、卡内容损坏、现场 IP 安装版本不同。
这些不能通过源码推测或模型替代实测。用本轮带哈希的下载文件和测试卡内容，能先排除版本和文件格式混用。

## 3. 修改边界

- A：板级应急图形接入、帧边界选源、显示预取、HDMI/复位约束、真实工程入口。
- B：SD 初始化外层时限、适配器有限等待/高速缓存、可选流式 DMA；原模块默认参数仍使用旧兼容方式。
- 共享：DMA_STREAMING 从 core 传到 display/fetch/DMA；只在板级显式启用。
- 工具：官方 IP 依赖准备、共享 HDL 清单、长命令行修正、额外回归和测试 BMP 生成。
- 386 个未修改的原有 Git 文件 blob 与基线一致；未改动任何加密 SDRAM/HDMI HDL 内容；SDRAM 只调整公开的频率宏，原系统 PLL 文件保留。
- A 的 OSD/可配置应急方向接口已经经过模块和系统仿真；当前板级播放器默认关闭普通 OSD，应急方向固定向上，外部 C 配置控制尚未连接。B 的 WAV/PCM 属于已有模块合同验证，本顶层只播放 BMP，未输出 HDMI 音频。
- C 的完整报警优先级、看门狗、音频调度与 HDMI 音频整机功能不因本轮视频修复自动完成。

## 4. 动态验证

| 验证 | 结果 | 覆盖边界 |
| --- | --- | --- |
| 原 B 单元与集成套件 | 28 项通过，668 条 PASS 记录 | SD、FAT32、BMP/WAV、帧写入、内存、PCM 等已有 B 合同；不是 HDMI 音频上板证明 |
| A 阶段 11–15 | 9 项通过 | 合成/OSD、独立字体与像素记分板、BASE/HD 完整帧、饥饿/恢复、原子槽切换、复位重启 |
| A 阶段 16–20 | 6 项通过 | 应急图形/控制、HDMI 队列与插拔、完整 BASE/HD 光栅及反压恢复 |
| A 系统 720p 联调 | 3 次请求/ACK/提交；1,843,200 正常像素一致；完整应急光栅通过 | 即时应急、退出恢复、OSD/调试字段与正常图像共同运行 |
| 50 MHz BASE 显示 | 3 帧、921,600 图片像素一致，U/O=0 | 实际 adapter + 流式 DMA + 官方 FIFO + 扫描，SD 加载用预置存储隔离 |
| 50 MHz 720p 显示 | 3 帧、921,600 图片像素一致，U/O=0 | 640×480 图片居中；1280×720 其余像素为黑；每个 SOF/EOL 核对 |
| 720p 并发存储写入 | 显示 921,600 图片像素一致，另一槽 18,267 字/73,068 字节读回一致，U/O=0 | 单字写入最大供给率限制为 2 MB/s，包含真实仲裁反压；不是加密 IP 的内部仿真 |
| 独立安全画面 | 3 帧、921,600 输出像素、15 个独立颜色检查点通过 | 存储不初始化、KEY3、存储故障；SOF/EOL 完整，未触发 HDMI 复位 |
| 流式 DMA | 1,228,800 像素一致 | 突发 1/7/16/64、非整除尾突发、FIFO 余量、延迟返回、竞争写入、中途复位 |
| adapter 延迟矩阵 | RD_LAT=1/2/4/24/64 均通过 | 数据/顺序/掩码/16 拍物理间隔；不表示任意延迟下都满足 720p 吞吐 |
| 无返回故障 | 通过 | 限时故障、迟到数据不能解除故障、故障期间不接受新写、共同复位恢复 |
| 产品慢卡 | 第 200 次 ACMD41 后，260.990390 ms 才 ready，通过 | 产品 50 MHz/100 kHz、无 SIM_FAST_TO；能跨过旧 200 ms 上限 |
| 产品 SD 时钟/初始化 | 通过 | 100 kHz 初始时钟、合法 SDHC 初始化及默认超时配置 |
| 板级 KEY1/KEY2 恢复 | 40 项检查通过 | 初始化重试、共同复位、重新接纳新帧与 mailbox 周期 |
| 板级 UART/按键/回落顶层 | 0 错通过 | 完整 107 字节 115200 波特状态行、遥测字段、消抖、回落 mailbox 和显示激活 |
| 720p + 真实 sink 完整帧积压 | 153,600 字/614,400 字节全部读回一致；正常显示 921,600 图片像素一致，U/O=0 | 经实际 board sink/FIFO/frame writer，输入为完整 640×480 像素流；保留产品超时 |
| 原握手负向对照 | 隔离副本只恢复 wr_ready=grant，第 89 字错误，测试明确拒绝；修复版本同一输入通过 | 确认测试能发现该回归，未丢弃失败输入 |
| 真 BMP 字节流的 SD→HDMI 双图 | 15 项检查、50 帧/15,360,000 图片像素全部一致，errors=0，U/O=0；两次帧发布均已物理排空 | 两个不同图案、两个槽各 153,600 字、KEY2 切换；256,035 次写突发、489,600 次读突发，无活动槽覆盖、HDMI 队列溢出或协议违例 |

内存和 HDMI 的板级仿真使用明确的接口合同模型；官方双时钟 FIFO 使用其 Verilog。
这不是加密 SDRAM/HDMI IP 的功能仿真，也不是线缆/显示器/外部 AC 验证。
仿真吞吐、物理 STA 与实板画面分别记录，不能互相代替。

## 5. 最终布局布线与文件身份

工具：实际安装的 TD 6.2.168.116，器件 EG4S20BG256；正常严格门禁，没有使用
`-ExperimentalSdramBitgen`。发布快照包含 RTL、公开 IP、字体、ADC/SDC、Tcl、共享 `.list`
和检查脚本；构建前后逐文件哈希一致。

| 模式 | 全局 SWNS（建立/恢复） | 全局 HWNS（保持/移除） | 报告负路径 | 下载文件 SHA256 |
| --- | --- | --- | --- | --- |
| BASE | +1.174 ns | +0.010 ns | 0 | `b447d1328a8ef7e23b10f89ef6940d8cdec1ecc1d3f6b31976c0127a98ca4a43` |
| 720p | +0.455 ns | +0.004 ns | 0 | `fed0ec0e97cfe3e95903137fe8c2a507ec084c9667e4f290c607292da149289c` |

720p 使用 LUT 11735/19600、REG 7828/19600、BRAM9k 32/64、DSP 12/29、PLL 2/4。
没有超资源或时钟缺失/无效约束/组合环/无路径约束问题。
仍有 6 个未设输入延迟、14 个未设输出延迟诊断，涉及未测量的 SPI/DDC/UART 等外部预算；
本轮“时序通过”准确指现有约束与最终报告覆盖的路径，不声称全部外部接口已完成电气验收。
最小保持余量接近零，下载后应做温度/供电/长时间播放检查。

## 6. 使用与复现

本地同步目录为 `D:\Safe_Vision_FPGA_2026`。打开真正的图片工程：
`safevision\platform\anlogic_eg4s20_hx4s20c\project\safevision.al`。
先运行准备脚本，再重新打开新 GUI 工程，避免旧窗口沿用回环顶层。第一轮上板建议选 BASE，再验 720p。
本轮下载文件在交付目录的 `BASE/safevision_top.bit`、`720p/safevision_top.bit`；
本地对应副本在 `safevision/build/out/white_screen_release/`。

```powershell
cd D:\Safe_Vision_FPGA_2026
./safevision/tools/prepare_board_project.ps1
./safevision/tools/run_board_sta.ps1 -Mode base,hd -Bitgen
./safevision/tools/run_card_display_xsim.ps1 -Case adapter,timeout,dma,safety,memory,slowinit,init,top,card -FastRead 1
./safevision/tools/run_card_display_xsim.ps1 -Case memory -HD 1 -WriteLoad 2
./safevision/tools/run_board_recovery_xsim.ps1
./safevision/tools/run_b_xsim_compat.ps1
./safevision/tools/run_a_stage11_15_sim.ps1
./safevision/tools/run_a_stage16_20_sim.ps1
./safevision/tools/run_a_system_sim.ps1 -Tool XSim -HD 1 -Immediate 1 -SwapCount 3 -SubmitLead 2
```

XSim 临时运行目录必须为 ASCII 路径；脚本默认 build/out 目录可以使用。
若系统没有 python 命令，TD 脚本会使用 Codex 的已安装 Python，或传入 `-Python <exe>`。
上述脚本不自动下载板卡。

测试卡：FAT32 分区，根目录放四张 `SV0001.BMP`–`SV0004.BMP`，640×480、24 位、BI_RGB 无压缩。
交付的四张 BMP 已逐字节读回核对并附 manifest.json；Pillow 标准解码器独立检查了 12 个颜色采样点。
不要把 PNG/JPEG 改扩展名当 BMP；不要用 32 位、压缩 BMP 或 exFAT 卡测试这一条已实现的链路。
本轮没有格式化或写入用户 SD 卡。

连接 HDMI B，KEY1 全局复位；KEY2 短按下一幅；KEY4 按住自动播放；KEY3 按住应急画面，松开后
在下一帧恢复健康图像。启动/未激活时显示安全图形，媒体或存储故障显示红色警示，手动应急为黄色。
UART 115200 8N1；`ST=1` 初始化、2/3 挂载、4/5 扫描/索引、7 就绪、8 读取、9 换帧、A 错误。
`FS/EC/ED/R1/SQ` 用来定位阶段、错误和 SD 原始响应；`F/SLOT/CRC/PX` 来自实际 sink。
CRC 表示输入链检查，真实 SDRAM 读回和显示质量仍需实板观察。

## 7. 实板验收记录（尚未执行）

| 步骤 | 验收条件 | 当前状态 |
| --- | --- | --- |
| 校对版本 | 下载文件哈希与第 5 节一致，确认下载至实际启动介质 | 待实测 |
| 不插卡上电 | HDMI B 有完整安全画面，串口正常；不以白屏作为错误提示 | 待实测 |
| 四张测试图 | 颜色条、渐变、四边框和坐标图清晰，四角齐全，KEY2 确实换图 | 待实测 |
| 自动/应急 | KEY4 按住循环，KEY3 进入/退出应急，KEY1 重新加载并恢复 | 待实测 |
| HDMI 插拔 | 重插重新显示，重连没有持续白屏/队列死锁 | 待实测 |
| 故障与长期运行 | 坏卡/错误 BMP 有提示；至少 30 分钟连续播放，无花屏/撕裂/欠载 | 待实测 |
| 两种模式 | BASE 与 720p 在实际显示器上分别验收 | 待实测 |

若下载本轮 BASE 后不插卡仍白屏，应优先看实际文件/HDMI B/PLL 与 HDMI 锁定/线材，
因为这一安全画面已经不依赖 SD 和 SDRAM。若安全画面正常、卡图失败，再根据 UART
阶段检查初始化、FAT32、BMP、写入/换帧。保留 UART 原行、下载文件哈希和画面录像，
这样下一轮能把具体实板问题定位到一个阶段，而不是继续仅凭颜色猜测。
