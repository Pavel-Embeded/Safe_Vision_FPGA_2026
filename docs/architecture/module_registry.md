# 模块登记表

盘点时间：2026-09-29。下表“现有”只表示源文件存在；B 链仿真状态见现有 `docs/B链-待办与硬件验证清单.md`，本次未重跑。新增模块需先在本表登记状态、负责人、接口和测试，再写代码。

| 文件 | 状态 | 负责人 | 作用 |
|---|---|---|---|
| `safevision/rtl/common/error_report.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/rv_skid_buffer.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/shift_reg.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/spi_byte_rx.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/sync_fifo.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/uart_tx.v` | 现有 | B（跨链边界 A/C 复核） | 通用握手、FIFO、UART 和错误上报 |
| `safevision/rtl/common/crc16_ccitt.v` | 现有 | B（跨链边界 A/C 复核） | 公共算法：CRC16-CCITT(XMODEM) 字节步进（纯组合） |
| `safevision/rtl/common/crc7.v` | 现有 | B（跨链边界 A/C 复核） | 公共算法：SD 命令 CRC7 字节步进（纯组合） |
| `safevision/rtl/storage/spi_master.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/sd_initializer.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/sd_sector_reader.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/mbr_parser.v` | **新增（2026-10-02）**，单测通过 | B | **卷基址解析**：读卡 0 号扇区（MBR），给出分区 0 起始物理 LBA（`vol_base_lba`）与扇区数；供板级顶层把"卷内相对 LBA"换算成卡上地址（见 interface_spec §3.2.1） | `tb_mbr_parser.sv`（T1–T4，7 项断言全通过） |
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v` | **新增（2026-10-02）**，单测通过；**板级 M-10（阶段 6–7）已通过**；v1.13 新增连读阶段（M-6/M-8） | B | **阶段 6–7 板级 bring-up 顶层**（接引脚）：上电 → SD 初始化 → `mbr_parser` → `fat32_boot_parser` → `fat32_directory_scanner`(+`fat32_cluster_walker`) → **连读阶段（`RPT_N`，默认 100，复用同一 reader）** → 经 UART 发**纯 ASCII 报告**（每行 `KEY=HEX`，新增 `RPT=<total> OK=<ok> BAD=<bad>` 行，末行 `DONE` 或 `ERR=02`；行尾为显式 CRLF）。★ **卷基址只在此处加一次**：`rd_addr_to_reader = bus_rd_addr + vol_base_lba`（见 interface_spec §3.2.1 / §3.8） | `tb_top_stage6_fat32_mount.sv`（**26 项断言全通过**：含报告字节数/无前导 0x00/每行 CRLF、连读 `RPT OK=100 BAD=0`、连读中拔卡进 `ST_ERR`+`ERR=02`） |
| `safevision/rtl/storage/fat32_boot_parser.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/fat32_directory_scanner.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/fat32_cluster_walker.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/file_streamer.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/storage/file_index.v` | 现有 | B（跨链边界 A/C 复核） | SD SPI、扇区读取、FAT32 和文件索引/流 |
| `safevision/rtl/media/bmp_parser.v` | 现有 | B（跨链边界 A/C 复核） | BMP/WAV 格式解析和像素转换 |
| `safevision/rtl/media/bmp_unpack.v` | 现有 | B（跨链边界 A/C 复核） | BMP/WAV 格式解析和像素转换 |
| `safevision/rtl/media/wav_parser.v` | 现有 | B（跨链边界 A/C 复核） | BMP/WAV 格式解析和像素转换 |
| `safevision/rtl/memory/mem_ctrl.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/frame_address_gen.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/frame_writer.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/frame_buffer_manager.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/memory_arbiter.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/video_read_dma.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/frame_swap_ctrl.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/frame_swap_cdc.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/memory_bandwidth_monitor.v` | 现有 | B（跨链边界 A/C 复核） | 逻辑地址、帧缓存、仲裁、预取与交换 |
| `safevision/rtl/memory/fifo_health_monitor.v` | 现有 | B（跨链边界 A/C 复核） | 历史最低水位 + underflow/overflow（属 memory，非平台无关件） |


| 文件 | 状态 | 负责人 | 作用 |
|---|---|---|---|
| `safevision/rtl/include/safevision_defs.vh` | 现有 | B，A/C 复核公共项 | 系统常量与地址/格式约定（已 include 下面三个） |
| `safevision/rtl/include/fault_code_defs.vh` | 现有 | B，C 复核错误码 | 错误码定义（ERR_* / DET_*） |
| `safevision/rtl/include/pixel_format_defs.vh` | 现有 | B，A/C 复核 | 像素格式 + 帧几何 + 冻结四槽地址表 |
| `safevision/rtl/include/event_code_defs.vh` | 现有 | B，C 复核 | 事件码与源标识 |

## A 时钟复位模块（2026-09-30 登记，先登记接口与验证，再写 RTL）

| 文件 | 状态 | 负责人 | 接口与作用 | 测试 |
|---|---|---|---|---|
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v` | RTL 已写，本机已仿真通过（clock 88 项；另被板级顶层 TB 复用） | A | `clk`、异步低有效 `async_rst_n` 输入；本域低有效 `rst_n` 输出；默认两级同步释放 | `tb_clock_reset_ctrl.sv` 88 项通过 |
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v` | RTL 已写，本机已仿真通过（clock 88 项）；未上板 | A | 板级复位、各 PLL 锁定及分区复位请求输入；九路按域复位输出；不生成时钟 | `tb_clock_reset_ctrl.sv` 88 项通过 |

安路 PLL 的实际 IP 配置、端口、引脚与约束尚未提供，`clock/` 目录的 RTL 只承担可综合的复位控制；频率生成须待 TD IP 接入。A 的其他模块目录是落点，不表示有功能 RTL。

## 板级 bring-up 顶层与约束（2026-10-02 登记）

| 文件 | 状态 | 负责人 | 接口与作用 | 测试 |
|---|---|---|---|---|
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v` | RTL 已写，仿真通过；**未上板** | B（A 复核板级落点） | 接引脚的阶段 5 最小验证顶层：`clk`(R7, 50 MHz) / `rst_n`(A2) / `sd_ncs`·`sd_dclk`·`sd_mosi`·`sd_miso` / `uart_txd`(D12) / `led[3:0]`；内部例化 `sd_initializer` + `sd_sector_reader`（**共用一份 `spi_master`，按 `init_done` 二选一**）+ `uart_tx` + `reset_sync`；上电延时 → 初始化 → 读 `TARGET_LBA`（默认 `32'd8192` = 分区首扇区/FAT32 DBR；原定 1000 落在分区前空隙里、全是 0）→ 512 Byte 经 UART 回传。接口与时钟取舍见 interface_spec §3.7 | `tb_top_stage5_sector_rd.sv`（T1–T4 已通过） |
| `safevision/platform/anlogic_eg4s20_hx4s20c/constraints/pin.adc` | 已写，综合/上板核对中 | B | 引脚约束。来源：开发板手册官方引脚表（串口 / LED / 按键）+ `2_FPGA.pdf` / `6_EX_DEVICE.pdf` + 厂商同器件例程，三处一致。`uart_txd = D12` 已确认是 FPGA 发送脚（板载 CH340G，无需外接 USB-TTL）。★ **分成两段**：公共 6 条（`clk`/`rst_n`/`uart_txd`/`led[3:0]`，三个 bring-up 顶层通用）+ **`[SD-ONLY]` 4 条**（`sd_*`，只有阶段 5/6 顶层有；用 `top_sdram_loopback` 时必须注释 —— TD 对"约束里出现顶层没有的端口"是**报错** `HDL-1492`/`USR-8168`，详见待办清单 §2.4.2 与 `constraints/README.md`） | 综合报告 |
| `safevision/platform/anlogic_eg4s20_hx4s20c/constraints/timing.sdc` | 已写（单一 50 MHz 主时钟 + `derive_clocks`） | B | `create_clock -name clk -period 20 -waveform {0 10}` + **`derive_clocks`**（2026-10-02 新增：接 `sv_system_pll` 之后不派生的话，125 MHz 域没有时钟定义、**STA 会是假通过**；对不接 PLL 的顶层派生不出额外时钟，可安全常开） | STA |
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v` | ★★ **已写、已综合、且上板通过（2026-10-02，条目 M-11-PASS）** | B | 阶段 9 第一步 / 手册 7.9「SDRAM 先跑官方 Demo」。端口只有 **`clk`/`rst_n`/`uart_txd`/`led[3:0]`（7 个，无 `sd_*` —— SDRAM 是封装内硬核、不用 TF 卡）**，所以 `pin.adc` 里 `[SD-ONLY]` 那 4 条**必须注释掉**（2026-10-02 首次综合就是被这条拦下的，见待办清单 §2.4.2）。内部：50 MHz → `sv_system_pll`（C1 = 125 MHz → SDRAM `Clk`、C2 = 125 MHz 180° → `Clk_sft`）→ 厂商 `sdram` 控制器 → 写图案 / 落地等待 / 读回比对 → `uart_tx`（125 MHz 域，115200）发**定长 71 Byte 纯 ASCII 报告**。**全部逻辑单域（含 uart）**，刻意不做 CDC。接口见 interface_spec §3.9 | ★ **无 TB、进不了回归**（控制器是安路 RSA 加密 IP，只能 TD 解密）⇒ 只能上板验收，步骤见待办清单 §2.4.2。**实测结果**：`INIT=01 / LOCK=01 / W=1000 R=1000 CAP=1000 BAD=0000 / DONE`（71 Byte，与设计值一字不差） |
| `safevision/platform/anlogic_eg4s20_hx4s20c/ip/sdram/` | 厂商 IP 已落库（2026-10-02） | 厂商（Anlogic）；B 负责登记与对接 | 应用级 SDRAM 控制器 `sdram.v` + 位宽宏 `global_def.v` + **三个加密实现 `sdr_as_ram/sdr_init_ref/sdr_wrrd.enc.v`** + PHY 配置 `sdram.ipc`。★ `EG_PHY_SDRAM_2M_32` 是**封装内硬核**（2M×32 = 8 MB），信号不出引脚 ⇒ `pin.adc` 不该有 SDRAM 引脚。版权/来源/唯一一处前导行改动见该目录 `README.md` | 综合报告（不可仿真） |
| `safevision/platform/anlogic_eg4s20_hx4s20c/ip/pll/` | 厂商 IP 已落库（2026-10-02；系统 PLL 于 2026-10-03 去重） | 厂商（Anlogic）；A/B 共用 | `sv_system_pll`（50 MHz → C0=100M / C1=125M / C2=125M@180°；A 的系统/存储时钟 + B 的 SDRAM；**2026-10-03 由 A 的 `sv_system_pll` 与 B 的 `sys_pll` 去重而来**，C0/C1 电气参数取 A 的 Medium/13/4）、`sv_video_vga_pll` / `sv_video_hd_pll`（给 A 的 HDMI 用）、`sv_audio_pll`。均为 **TD 生成的可综合网表**，可直接进工程 | STA |

`project/safevision.al` 已把 `TOP_MODULE` 设为 `top_stage5_sector_rd`，并加入 `reset_sync.v`、`top_stage5_sector_rd.v` 与 `constraint_1` 的 `pin.adc`/`timing.sdc`。**2026-10-02 已在 TD 里跑通完整流程**：修掉 `sd_initializer` / `sd_sector_reader` 的 `bdata` 多驱动（`HDL-8007`，详见 interface_spec v1.10 变更历史）后，综合 → 布局 → 布线 → 位流**一次通过**；**时序收敛**（Setup WNS +11.297 ns / Hold WNS +0.046 ns，违反端点 0，50 MHz 约束下 Fmax 114.9 MHz），资源 IO 11/188、LUT 814/19600、REG 434/19600、BRAM/DSP 0。`syn_1/run.log` 中不再有 `black box`。原始报告留证于 `evidence/reports/`（索引条目 TC-Q-STA）。★ 该证据对应的是 **`TARGET_LBA = 1000`** 那次构建；`TARGET_LBA` 默认值已改为 `8192`，**需要重新综合一次以对齐证据**（只改了一个常量，时序/资源预期不变，但按本项目口径证据必须与构建一致）。**位流尚未下载，未上板**（上板步骤见待办清单 §2.2）。

★ **2026-10-02 后续状态变更（以磁盘上的 `.al` 为准，不要被上面这段的历史数字误导）**：
- ★★ **已查明：磁盘上的 `.al` 从来没保存过阶段 6 的登记。** 阶段 6–7 的 `top_stage6_fat32_mount.v` /
  `mbr_parser.v` 是在 **TD GUI 的内存会话里**加进去的（19:35 起的那次会话），**没有回写 `.al`**；
  所以 `.al` 停留在更早的**阶段 5** 快照（只有 `top_stage5_sector_rd.v`，`TOP_MODULE = top_stage5_sector_rd`）。
  ⇒ 文档里以前写的"TD 工程已登记新顶层（`TOP_MODULE = top_stage6_fat32_mount`）"**描述的是 GUI 状态、不是工程文件**，属于表述错误，据此更正。
- ★★ **TD 运行时用的是内存状态，不是磁盘 `.al`。** 证据：2026-10-02 **21:25** 那次综合（当时磁盘 `.al` 的
  `TOP_MODULE` 已是 `top_sdram_loopback`）产出 `syn_1/safevision.prj`，里面 `TOP_MODULE = top_stage6_fat32_mount`、
  文件表**没有任何 `ip/` 文件**；`syn_1/run.log` 也写着 `elaborate -top top_stage6_fat32_mount`。
  位流行为与 20:52 那次**逐字节相同**（见 `evidence/board/INDEX.md`）。
  ⇒ **SDRAM 回环顶层至今没有被综合过**，板子上跑的是阶段 6–7 设计。
- ⚠ **因此：只要那个 TD 会话还在（进程 `td`，19:34:49 启动），在 GUI 里"保存工程"就会用内存状态
  覆盖磁盘 `.al`，本轮加进去的 7 条 IP/新顶层登记会全部丢失。** 正确做法是**在 GUI 里手动添加**
  `../ip/sdram/` 5 个文件 + `../ip/pll/sys_pll.v` + `../rtl/top_sdram_loopback.v`，把 `TOP_MODULE`
  设为 `top_sdram_loopback`，**再保存**；或者关掉 TD（不保存）后重新打开，让 TD 读取已修好的 `.al`。
- 本轮已在磁盘 `.al` 上：新增 `../ip/sdram/` 5 个文件、`../ip/pll/sys_pll.v`、`../rtl/top_sdram_loopback.v`，
  **并把此前丢掉的 `../../../rtl/storage/mbr_parser.v` 与 `../rtl/top_stage6_fat32_mount.v` 补回**
  （共 9 条）；`TOP_MODULE = top_sdram_loopback`。`timing.sdc` 同时加了 `derive_clocks`。
  要回退阶段 5，只需把 `TOP_MODULE` 改回 `top_stage5_sector_rd`。
- ★ **21:41:36 确实发生了一次覆盖**（上面的警告应验）：TD 在 GUI 里保存工程，把 `.al` 写成了
  它内存里的**阶段 6–7 快照**（37 条 Verilog，`TOP_MODULE = top_stage6_fat32_mount`，
  **7 条 SDRAM/IP 登记全部消失**）。随后已按同一份内容**重新加回并复验**：
  **46 条 File 条目路径全部 `Test-Path` 通过、Verilog `CompileOrder` 1–44 无重复、
  `TOP_MODULE = top_sdram_loopback`（登记为 order 44）**。
  ⇒ **结论不变：`.al` 谁写的不重要，TD 内存里是什么才决定综合结果。**
  要让 TD 采用这份 `.al`，必须**关闭 TD（在"保存工程"提示里选【否】）后重新打开**，
  或直接在 GUI 里手动添加那 7 条 —— 否则一保存又会被内存状态盖回去。

## 待实现模块命名（不是空 RTL）

| 建议文件 | 负责人 | 最小交付条件 |
|---|---|
| `rtl/top/safevision_core/safevision_core.v` | A | A/B/C 抽象接口装配、系统 TB |
| `rtl/video/video_timing/video_timing.v` | A | 目标模式时序 TB、约束 |
| `rtl/video/pattern_generator/pattern_generator.v` | A | 彩条与网格、首像素 TB |
| `rtl/video/graphics_rom/graphics_rom.v` | A | 字模/图标读取延迟 TB；BRAM IP 留平台 |
| `rtl/video/frame_reader/frame_reader.v` | A | 预取/标签对齐/欠载 TB |
| `rtl/video/video_compositor/video_compositor.v` | A | 数据与 OSD 延迟对齐 TB |
| `rtl/video/osd_overlay/osd_overlay.v` | A | 字模 BRAM 延迟 TB |
| `rtl/video/emergency_mux/emergency_mux.v` | A | 应急优先级与无黑屏 TB |
| `rtl/video/safe_scene_gen/safe_scene_gen.v` | A | 片上字模与实时坐标生成 TB |
| `rtl/video/video_cdc/`、`platform/anlogic_eg4s20_hx4s20c/rtl/pixel_fifo/` | A/B | 视频控制 CDC 与安路 FWFT 像素 FIFO 适配；先冻结接口 |
| `platform/anlogic_eg4s20_hx4s20c/rtl/hdmi/`、`rtl/chipwatcher/` | A | HDMI/调试板级适配，需 IP/STA/板级证据 |
| `rtl/control/input_sync.v`、`key_debounce.v` | C | 异步按键/抖动/长按 TB |
| `rtl/control/playback_fsm.v`、`control_event_queue.v` | C | 模式与事件顺序 TB |
| `rtl/safety/fault_manager.v`、`watchdog.v`、`emergency_fsm.v` | C | 故障首因、恢复、复位隔离 TB |
| `rtl/audio/audio_scheduler.v`、`audio_priority_arbiter.v`、`alarm_tone_gen.v` | C | 48 kHz 样本、欠载、报警优先 TB |
| `platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v` | A | 引脚/IP/时钟复位接线、STA、上板 |

文件名为计划建议，若实现时变更，先更新本表与接口规范。`pcm_ring`、`audio_cdc_fifo`、HDMI 音频包装、PLL/FIFO/SDRAM/HDMI 厂商适配仍是待定义/待实现，不可因目录存在而视作完成。

## A 阶段十已实现模块（2026-10-03）

| 文件 | 负责人 | 时钟/延迟 | 验证与接线 |
|---|---|---|---|
| `rtl/video/video_pipeline/video_pipeline.v` | A | pixel_clk；像素与全部标签统一 LATENCY 拍，默认 1 | 两个新 TB 通过；原 B 源表合编与 TD RTL 综合通过；独立 BASE/HD 内部 routed STA 无负裕量，已有 PLL 健康告警开放，未上板。接口与验证范围见 [阶段十说明](../A_stage10_latency.md) |


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](../clock_video_implementation.md)，端口/时钟域见 [A接口补充](../A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](../A_PUSH_SCOPE_20261002.md)。
