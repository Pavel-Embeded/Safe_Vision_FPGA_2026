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
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v` | RTL 已写，待仿真/综合/板测 | A | `clk`、异步低有效 `async_rst_n` 输入；本域低有效 `rst_n` 输出；默认两级同步释放 | `tb_clock_reset_ctrl.sv` 已写未运行 |
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v` | RTL 已写，待仿真/综合/板测 | A | 板级复位、各 PLL 锁定及分区复位请求输入；九路按域复位输出；不生成时钟 | `tb_clock_reset_ctrl.sv` 已写未运行 |

安路 PLL 的实际 IP 配置、端口、引脚与约束尚未提供，`clock/` 目录的 RTL 只承担可综合的复位控制；频率生成须待 TD IP 接入。A 的其他模块目录是落点，不表示有功能 RTL。

## 待实现模块命名（不是空 RTL）

| 建议文件 | 负责人 | 最小交付条件 |
|---|---|
| `rtl/top/safevision_core/safevision_core.v` | A | A/B/C 抽象接口装配、系统 TB |
| `rtl/video/video_timing/video_timing.v` | A | 目标模式时序 TB、约束 |
| `rtl/video/pattern_generator/pattern_generator.v` | A | 彩条与网格、首像素 TB |
| `rtl/video/graphics_rom/graphics_rom.v` | A | 字模/图标读取延迟 TB；BRAM IP 留平台 |
| `rtl/video/video_pipeline/video_pipeline.v` | A | 像素/同步/valid 延迟对齐 TB |
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
