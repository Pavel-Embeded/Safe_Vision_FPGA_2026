# SafeVision B 链接口规范（interface_spec）

> A 阶段 1–9 新增接口（2026-10-04）：见 [A_stages1_9.md](A_stages1_9.md)。新增模块独立注册，不变更下文 B 冻结接口；图形链 RGB888，pixel_clk 单域，OSD 统一延迟 4 拍。A 基础 FSM 为教学件，不作为 C 产品状态契约。

> 本文档是 **B 链（数据存储与数据搬运）** 与 A、C 的**冻结接口依据**。
> 任何一方改接口，必须先改本文档、再改 RTL，并通知对接人。
> 联调时以本文档为准，不以口头约定为准。

## 文档信息

| 项 | 内容 |
|---|---|
| 项目 | 安视 SafeVision · 赛题一 HDMI 多媒体播放与应急视听疏散终端 |
| 平台 | 康芯 HX4S20C 开发板 / 安路 EG4S20BG256 |
| 版本 | v1.18（保留 B/C 现行接口及 A 阶段十；新增 A 阶段 1–9 图形前端/四级 OSD） |
| 负责人 | B 队员（数据存储链 / 数据搬运） |
| 依据 | 赛题一官方选题指南；《赛选手册 V2.0》第 6/7/10 章 |
| 维护规则 | 接口先于联调存在；改接口必同步改文档并通知对方；信号名、有效电平、时钟域、延迟、异常策略五者必须写清 |

### 文档同步义务（改代码后必做）

本文档不是"代码写完回头补"的附属品，而是交付物的一部分。**如果一处改动让本文档的
某句话变成错的，就必须同步改过来**，并按下表登记：

| 文档 | 什么时候必须更新 |
|---|---|
| 本文件 `interface_spec.md` | **任何**信号名 / 有效电平 / 时钟域 / 延迟 / 异常策略变更；新增或删除模块接口；地址表（§五）或错误码（§六）变化；命名调整（见下方迁移表）。另须在 §九 变更历史补一行并升版本号 |
| [B链-待办与硬件验证清单.md](B链-待办与硬件验证清单.md) | 阶段状态、回归断言数、已知未完成项发生变化；新增实测项或排查条目 |
| [B链-原理讲解-入门版.md](B链-原理讲解-入门版.md) | 设计取舍发生变化，或新增了值得交接给下一位的概念解释 |
| [../README.md](../README.md) | 目录结构或回归数变化时，同步"当前状态"表与目录树 |
| 管理类文档（[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)、[architecture/module_registry.md](architecture/module_registry.md)、[verification/test_matrix.md](verification/test_matrix.md)、[requirements/traceability.md](requirements/traceability.md)） | 模块新增或删除、完成状态变化、验证矩阵变化时同步。**新增模块必须先登记 `module_registry.md`（状态/负责人/接口/测试）再写代码** |

**开发基准**：《赛题一对标学习与开发手册_V2.0.pdf》（工作区根目录，不进仓库）
——功能取舍、阶段节奏、验收口径一律以它为准。
**结构基准**：本仓库 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)（由队友的项目管理架构
确立，`v1.8` 起生效）——新增文件前先确认它落在哪个目录。
本项目**有意不做**的部分见下方"仍未采纳的部分"。

### 命名迁移表（手册名 → 工程名）

> 迁移表必须保留下来，便于把手册需求、旧提交和新模块对应起来。
> v1.5 起 B 链文件名与 module 名已对齐；**v1.8 起该"对齐基准"是本仓库的
> [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)，不再引用外部架构文档**。
> **对外契约（信号名、错误码）不随改名变化**，A / C 侧无需改动。

| 手册 / 旧名 | 工程名（现结构） | 说明 |
|---|---|---|
| `rtl/common/sd_defines.vh` | `rtl/include/safevision_defs.vh` + `rtl/include/fault_code_defs.vh` | 通用定义与错误码登记拆开，`safevision_defs.vh` 已 include 后者 |
| `rtl/stage1/shift_reg.v` | `rtl/common/shift_reg.v` | 阶段 1 教学件，**产品链未例化**；原结构无对应项，暂放 common |
| `rtl/stage1/spi_byte_rx.v` | `rtl/common/spi_byte_rx.v` | 同上 |
| `rtl/common/uart_tx.v` | `rtl/common/uart_tx.v` | 不变 |
| `rtl/sd/spi_master.v` | `rtl/storage/spi_master.v` | 仅目录变，名字保留 |
| `rtl/sd/sd_init_fsm.v` | `rtl/storage/sd_initializer.v` | |
| `rtl/sd/sd_sector_rd.v` | `rtl/storage/sd_sector_reader.v` | |
| `rtl/fs/fat32_mount.v` | `rtl/storage/fat32_boot_parser.v` | |
| `rtl/fs/dir_scan.v` | `rtl/storage/fat32_directory_scanner.v` | |
| （新增） | `rtl/storage/fat32_cluster_walker.v` | 簇链跟踪，被下面两者共用 |
| `file_stream`（原计划） | `rtl/storage/file_streamer.v` | |
| `bmp_check`（原计划） | `rtl/media/bmp_parser.v` | 媒体解析归 `rtl/media/` |
| `safevision/sim/tb_stage5.v` | `verification/unit/tb_sd_sector_reader.sv` | |
| `safevision/sim/tb_stage4_timeout.v` | `verification/unit/tb_sd_initializer.sv` | |
| `safevision/sim/tb_stage6_mount.v` | `verification/unit/tb_fat32_boot_parser.sv` | |
| `safevision/sim/tb_stage6_dir.v` | `verification/unit/tb_fat32_directory_scanner.sv` | |
| `safevision/sim/sd_card_model.v` | `verification/models/sd_spi_card_model.sv` | |
| `safevision/sim/run_sim.ps1` | `safevision/tools/run_sim.ps1` | work/ 库建在 `verification/` 下 |

#### v1.7 追加的重命名（按现结构逐项核对后修掉的最后 4 处不一致）

| 旧名 | 工程名（现结构） | 说明 |
|---|---|---|
| `rtl/media/wav_reader.v` | `rtl/media/wav_parser.v` | media 下统一用 `*_parser`（`bmp_parser`/`wav_parser`），`wav_reader` 是唯一例外 |
| `rtl/common/fifo_health_monitor.v` | `rtl/memory/fifo_health_monitor.v` | 它监测的是帧缓冲/FIFO 水位，属 memory 分类，不是平台无关件 |
| `verification/models/sdram_model.sv` | `verification/models/frame_memory_model.sv` | 它建的是"帧缓存视图"（8 MiB/2M×32bit），不是 SDRAM 器件模型 |
| `verification/unit/tb_mem_write.sv` | `verification/unit/tb_frame_writer.sv` | 被测件已叫 `frame_writer`，TB 同名；`tb_mem_write` 是阶段 9 的旧称 |

#### v1.16 追加的 IP 去重（合并 A/B 两套系统 PLL）

| 旧名 | 工程名（现结构） | 说明 |
|---|---|---|
| `ip/pll/sys_pll.v` / `sys_pll.ipc`（B 的，2026-10-02 落库） | `ip/pll/sv_system_pll.v` / `sv_system_pll.ipc`（A 的，去重后唯一一份） | 两套 PLL 输出频率**完全相同**（100/125 MHz），差别只在**电气参数**（A: Medium / ICP_CURRENT 13 / LPF_RESISTOR 4；B: High / 29 / 2）与 **B 多一路 C2 = 125 MHz@180°**（SDRAM 硬核 `Clk_sft` 要）。去重方案（2026-10-03）：**在 A 的 `sv_system_pll` 上补 C2@180°**，C0/C1 电气参数**取 A 的**（A 的时钟树与审计脚本几乎不动），**删除 B 的 `sys_pll`**；`top_sdram_loopback` 实例化改名 `sv_system_pll`。`check_pll_profiles.py` 相应放行"系统 PLL 允许第 3 路 180° 输出"。★ 影响：stage 9 的 PLL 电气参数由 B 的 High/29/2 变为 A 的 Medium/13/4 ⇒ **M-11 需重新综合 + 上板复测**。 |

#### v1.7 新增文件（补结构缺口，不是改名）

| 新增 | 落点 | 说明 |
|---|---|---|
| `rtl/include/pixel_format_defs.vh` | `rtl/include/` | 像素格式 + 帧几何 + **冻结四槽地址表**的唯一来源（见 §五） |
| `rtl/include/event_code_defs.vh` | `rtl/include/` | 事件码/源标识定义（与 `fault_code_defs.vh` 分工：后者是错误码，前者是正常事件） |
| `rtl/common/crc16_ccitt.v` | `rtl/common/` | CRC16-CCITT(XMODEM) 字节步进。此前 `sd_sector_reader` 与 `frame_writer` **各写了一份同名函数**，收敛成一份 |
| `rtl/common/crc7.v` | `rtl/common/` | SD 命令 CRC7 字节步进，配 `tb_crc` 把 `SD_CRC_CMD0/8` 两个魔数钉死在对数上 |
| `verification/unit/tb_crc.sv` | `verification/unit/` | CRC7/CRC16 单元测试（12 项） |
| `verification/unit/tb_memory_arbiter.sv` | `verification/unit/` | 由 `tb_frame_swap.sv` 拆出（仲裁部分 7 项） |
| `verification/unit/tb_frame_swap_ctrl.sv` | `verification/unit/` | 由 `tb_frame_swap.sv` 拆出（帧交换+跨域 23 项） |
| `verification/unit/tb_bmp_unpack.sv` | `verification/unit/` | 由 `tb_media.sv` 拆出（BMP 解包 44 项） |
| `verification/unit/tb_wav_parser.sv` | `verification/unit/` | 由 `tb_media.sv` 拆出（WAV 解析 31 项） |
| `verification/unit/tb_fat32_cluster_walker.sv` | `verification/unit/` | 新增：`fat32_cluster_walker` 此前只随编译、**判 EOC/越界/判环三条收尾分支从未被仿真跑过**（33 项） |

> 拆分类改动（`tb_frame_swap`→2 个、`tb_media`→2 个）**只搬位置、不改断言**：
> 断言名字与判据逐字保留，拆分前后合计断言数不变（30 → 7+23，75 → 44+31）。

**目录骨架（2026-09-29 由队友的项目管理覆盖包引入）**：`rtl/{video,audio,control,safety,top}`、
`platform/`、`build/`、`assets/`、`verification/{subsystem,system,board}`、`evidence/`、
`.github/` 当时建为**骨架**。2026-09-30 起仅 `platform/anlogic_eg4s20_hx4s20c/rtl/clock/` 有复位功能 RTL；A 其他新模块文件夹仍只有 README。
落点规则见 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)，理由见
[ADR-0001](management/adr/0001-layout.md)（"只创建目录及说明，不生成假 RTL"）。
★ **目录存在 ≠ 功能已实现**；判断完成度以验证证据为准。
`rtl/safety/` 是本项目在结构之外的补充（把看门狗/故障/应急从 `control` 分出，明确归 C）。

**仍未采纳的部分（有意为之，不视为缺陷）**：150+ 个文件里的大部分实现、
formal（SymbiYosys）、nightly CI、HIL 自动化、release manifest、CSR 总线、
HAL 抽象层、Codec I²C 配置，以及 `rtl/csr/` `rtl/diagnostics/` `rtl/platform/`
（板级适配改放 `safevision/platform/`）。原则是「不要一开始创建一堆空 RTL」与
「三人团队不要模仿大公司堆叠复杂框架」——这两条现在是本项目自定原则。

---

## 一、全链公共约定

| 项 | 约定 | 依据 |
|---|---|---|
| 时钟域 | `sys_clk` 100MHz：SPI / FAT / 控制 / UART<br>`mem_clk` 125MHz：SDRAM IP 与仲裁器<br>`pixel_clk` 25.175MHz：视频时序与 HDMI | 手册表 6-2 |
| 握手 | `valid` / `ready`。**`ready` 为低时发送方必须保持 `data` 不变** | 7.7 |
| 复位 | 系统统一 `rst_n`（低有效）；每个时钟域各自用复位同步器释放 | 第 10 章 |
| 地址 | **只传逻辑字节地址**（32bit）。物理 32bit word 地址由 `mem_ctrl` wrapper 内部转换，业务模块内**禁止**裸物理地址运算 | 7.6.2 |
| 像素格式 | RGB565，16 bit，2 byte/pixel | 7.6.2 |
| 命名 | snake_case，无前缀；`_n` 后缀表低有效 | 10.2.4 |
| 语言子集 | **`rtl/**` 一律 `.v` + Verilog-2001 子集**（要过安路 TD 综合，TD 只部分支持 SystemVerilog）；**`verification/**` 用 `.sv`**、允许 SystemVerilog（TB 不综合）；`rtl/include/**` 用 `.vh`。**禁止把 `.sv` 放进 `rtl/`**。注：当前 `.sv` 文件内容实际都是 Verilog-2001 写法，扩展名按这个分工走 | 项目自定约定（已固化） |
| 错误上报 | 统一走 `error_report` → Control Event Interface（`evt_type` / `evt_value` / `evt_valid` / `evt_full`），溢出计数在 C 侧 | 10.2.4 |

### A 板级时钟复位接口（v1.9 增补，不改变 B 链既有端口）

`platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v` 接收 TD PLL 输出的时钟与 `locked`，只产生低有效复位，**不生成、分频或切换时钟**。PLL 实例、引脚和约束尚未接入。手册表 6-2 的 `board_clk=50 MHz`、`sys_clk=100 MHz`、`mem_clk=125 MHz`、`pixel_clk_base=25.175 MHz`、`pixel_clk_hd=74.25 MHz`、`serial_clk=5×pixel_clk`、`audio_mclk=12.288 MHz` 是目标而非实测；当前工程仅冻结 `sys_clk/mem_clk/pixel_clk` 三个业务频率，视频模式和 HDMI PHY 方案确认前不作无毛刺时钟切换。

| 输入 | 有效电平 / 所在域 | 用途 |
|---|---|---|
| `board_rst_n` | 低有效，异步 | 板级全局复位源；低电平异步断言全部输出复位 |
| `sys_clk`、`mem_clk`、`pixel_clk`、`serial_clk`、`audio_clk` | 各自 PLL 输出 | 仅给对应复位同步器采样；时钟本身不在本模块内产生 |
| `sys_pll_locked`、`mem_pll_locked`、`video_pll_locked`、`audio_pll_locked` | 高有效，异步锁定电平 | 对应域释放许可；同一 PLL 供多个域时可连接同一个 `locked` |
| `media_reset_req` | 高有效，`sys_clk` 域保持电平 | 仅复位媒体业务；跨域发起者须先完成 CDC，不可送单拍脉冲 |
| `memory_client_reset_req` | 高有效，`mem_clk` 域保持电平 | 仅复位 SDRAM 客户端，保留 `mem_rst_n` 与 SDRAM IP 刷新 |
| `hdmi_reinit_req` | 高有效，跨像素/串行域保持电平 | 只复位 HDMI 前级与串行路径；控制源须做跨域握手并稳定保持到两域均已复位 |
| `audio_reset_req` | 高有效，`audio_clk` 域保持电平 | 只复位音频消费链 |

| 输出 | 所在域 / 释放延迟 | 所属逻辑与异常策略 |
|---|---|---|
| `sys_rst_n` | `sys_clk`，RTL 第 2 拍释放 | 控制、故障锁存；不受 `media_reset_req` 影响 |
| `mem_rst_n` | `mem_clk`，RTL 第 2 拍释放 | SDRAM PHY/仲裁基础域；不受客户端局部复位影响 |
| `pixel_rst_n` | `pixel_clk`，RTL 第 2 拍释放 | Video Timing、安全画面；媒体/HDMI 局部复位不影响 |
| `serial_rst_n` | `serial_clk`，RTL 第 2 拍释放 | 串行时钟域基础复位；HDMI 重初始化不改变此基础许可 |
| `audio_rst_n` | `audio_clk`，RTL 第 2 拍释放 | 音频消费；音频 PLL 掉锁或 `audio_reset_req` 均复位，不牵连视频 |
| `media_rst_n` | `sys_clk`，RTL 第 2 拍释放 | SD/文件/媒体业务局部复位；不复位视频时序、安全画面、HDMI PHY |
| `memory_client_rst_n` | `mem_clk`，RTL 第 2 拍释放 | 帧缓存客户端局部复位；不复位 SDRAM IP |
| `hdmi_pixel_rst_n`、`hdmi_serial_rst_n` | 各自像素/串行域，RTL 第 2 拍释放 | HDMI 重初始化分域复位；不复位 `pixel_rst_n` 的视频时序 |

`locked` 拉低或相应请求拉高时，相关复位异步立即断言；各自释放条件恢复后，RTL 名义上在该域第 2 个上升沿释放。异步变化靠近采样边沿时，物理释放时刻受亚稳态与 recovery/removal 约束影响，仍须 STA 和板测核实。PLL 锁定不能证明输出频率正确；最终需 TD IP 配置、约束、STA、板级波形与上电录像。板级音频时钟由 A 接入平台，C 负责音频链消费与节拍接口。

### CDC 约定

| 跨域方向 | 手段 |
|---|---|
| `sys_clk` → `mem_clk`（写侧数据） | 异步 FIFO（32bit 粒度） |
| `mem_clk` → `pixel_clk`（像素） | 异步 FIFO，**FWFT 模式** |
| `mem_clk` → `audio_clk`（PCM 样本） | 异步 FIFO，**FWFT 模式**，32bit = {r,l} |
| `sys_clk` → `audio_clk`（track_id / track_change） | toggle 电平翻转 + mailbox |
| 控制类单比特（请求/回执） | **toggle 电平翻转**，禁止单拍脉冲跨域 |
| 多比特 payload（slot_id / generation / crc_ok） | mailbox 锁存后再给回执，禁止逐位打拍 |

> ★ 全链统一：安路软 FIFO IP 的 `rst` 是**异步、高有效**，而系统 `rst_n` 是低有效。
> 所有 FIFO 例化处必须显式取反，**禁止把 `rst_n` 直连到 IP 的 `rst`**。

> ★ 全链统一（v1.4 新增）：凡是"从 `sd_sector_reader` 收字节"的模块
> （`fat32_boot_parser` / `fat32_directory_scanner` / 后续的 `file_stream` / `bmp_check` / `wav_parser`），
> 吃一个字节的条件必须是 **`data_valid && data_ready`**，不能只判 `data_valid`。
> 原因：`sd_sector_reader` 在 `data_valid` 拉高后会**一直保持**，直到看见 `data_ready`
> 才换下一个字节。只判 `data_valid` 会在反压期间把同一个字节吃掉很多次，
> 字节计数与数据流瞬间错位。这是 `fat32_directory_scanner` 实测中真实踩过的坑。

---

## 二、数据通路

```text
【视频链】
sys_clk 域
spi_master → sd_initializer → sd_sector_reader → fat32_boot_parser → fat32_directory_scanner → file_index
                                                              ↓
                                    file_stream → bmp_check → bmp_unpack
                                                              ↓ (异步 FIFO 跨域)
mem_clk 域                                         slot_writer → mem_arbiter → mem_ctrl → SDRAM

【音频链 B04】（与视频链分时复用 sd_sector_reader / file_stream）
sys_clk 域    wav_parser（解析 RIFF / fmt / data，输出 16bit 双声道 PCM）
                                          ↓ (异步 FIFO 跨域)
mem_clk 域    pcm_ring（SDRAM AUDIO_RING 环形缓冲，解耦慢读与连续消费）
                                          ↓ (CDC FIFO 跨域，FWFT)
audio_clk 域  audio_cdc_fifo → [C] audio_scheduler（48 kHz 节拍取样本）
                                    ↓
                              [C] audio_arbiter → [A/C] HDMI 数据岛（ACR + Audio InfoFrame）

横向：swap_ctrl（sys_clk ↔ pixel_clk 帧交换握手）
```

---

## 三、模块接口

### 3.1 SD 物理层（学习阶段 1–5）

#### spi_master

```text
时钟域 : sys_clk
职责   : SPI mode0 字节级全双工收发（不含任何 SD 协议语义）
实现   : safevision/rtl/storage/spi_master.v

clk                 in   1     sys_clk
rst_n               in   1     同步复位，低有效
clk_div[15:0]       in   16    SCLK 半周期分频：SCLK = clk / (2*(clk_div+1))
                               初始化段 400kHz -> clk_div=124 @100MHz
                               数据段   25MHz -> clk_div=1
cs_n                in   1     ★ 片选【输入】，由上层控制器在全事务期间拉低
tx_data[7:0]        in   8     待发送字节
tx_valid            in   1     请求发送
tx_ready            out  1     可接受新字节
rx_data[7:0]        out  8     收到的字节
rx_valid            out  1     单拍脉冲，与 rx_data 同拍
busy                out  1     传输中
sclk                out  1     板级
mosi                out  1     板级；空闲保持高
miso                in   1     板级

约定：CPOL=0 / CPHA=0；MOSI 在下降沿更新，MISO 在上升沿采样；
      IDLE 与 DONE 恒把 SCLK 拉低（SD 要求 CS 变化时 SCLK 必须为低）；
      发送一个字节的同时接收一个字节（全双工）。
★ 位计数口径：half_cnt 只在下降沿递增（一个完整 SCLK 周期 +1），
      8 位 = 8 个周期。写成 16 会多送一倍时钟，导致整条链协议错位——
      这是实测中真实踩过的坑，见 §9 v1.2。
```

#### SD 控制器 ↔ spi_master 字节总线（sd_initializer 与 sd_sector_reader 共用）

```text
两个 SD 控制器各自带一组同名字节总线端口，
由顶层按当前阶段二选一复用同一个 spi_master（二者互斥，不并发）：

spi_cs_n            out  1     片选
spi_clk_div[15:0]   out  16    分频值
spi_tx_valid        out  1     ★ 必须组合驱动，与 tx_ready 同拍握手，不能打拍
spi_tx_data[7:0]    out  8     ★ 同上
spi_tx_ready        in   1     来自 spi_master
spi_rx_data[7:0]    in   8     来自 spi_master
spi_rx_valid        in   1     来自 spi_master

★ 内部结构约定：每个控制器内含一个"字节收发引擎"
  （bstart 请求 -> B_SEND 等 tx_ready -> B_WAIT 等 rx_valid -> bdone 单拍）。
  bstart 必须【单驱动源】（只由主状态机驱动），字节引擎只读不写，
  否则多驱动会让仿真变 X、综合失效。
★ 轮询类状态（M_R1 / S_R1 / S_TOKEN）进入时必须先发出第一个字节，
  否则只等 bdone 永远等不到响应——这是实测中真实踩过的坑。
```

#### sd_initializer

```text
时钟域 : sys_clk
职责   : 上电时序 + CMD0 / CMD8 / ACMD41 协商，判定 SDHC

clk / rst_n         —    —     —
start               in   1     板级稳定后由顶层拉起
sdhc                out  1     1 = SDHC/SDXC（块寻址）
init_done           out  1     初始化成功
init_error          out  1     初始化失败
err_code[7:0]       out  8     ERR_SD_INIT / ERR_SD_TIMEOUT
retry_cnt[7:0]      out  8     重试次数，供观测

约定：上电后必须先发 ≥74 个 SCLK；ACMD41 带 HCS 位且必须轮询超时；
      CMD58 读 CCS 位判定 sdhc；初始化完成后 SCLK 切至 25MHz
```

#### sd_sector_reader

```text
时钟域 : sys_clk
职责   : CMD17 单扇区 / CMD18 多扇区读

clk / rst_n         —    —     —
sdhc                in   1     决定 rd_addr 语义
rd_en               in   1     请求读
rd_addr[31:0]       in   32    起始扇区号
rd_len[15:0]        in   16    扇区数
rd_ready            out  1     可接受请求
data[7:0]           out  8     数据字节
data_valid          out  1     —
data_ready          in   1     下游反压
data_last           out  1     整块最后一个字节
rd_done             out  1     读完
timeout_err         out  1     读超时
crc16_err           out  1     数据 CRC 校验失败
err_code[7:0]       out  8     —

约定：读超时拍数必须可配并把数值写进本文档（对应学习阶段 4）；
      CRC16 失败允许重读一次，连续两次失败才上报
```

### 3.2 文件系统层（学习阶段 6）

#### fat32_boot_parser

```text
时钟域 : sys_clk
职责   : 读 DBR、校验 BPB、定位 FAT 表与根目录

clk / rst_n         —    —     —
start               in   1     触发挂载
mount_done          out  1     —
mount_error         out  1     —
err_code[7:0]       out  8     ERR_FAT_BPB / ERR_FAT_NOT_FAT32 / ERR_FAT_IO
bytes_per_sec[15:0] out  16    必须 = 512，否则拒绝挂载
sec_per_clus[7:0]   out  8     每簇扇区数
num_fats[7:0]       out  8     只支持 1 或 2
fat_start_lba[31:0] out  32    FAT 表起始扇区
root_clus[31:0]     out  32    根目录起始簇
root_dir_lba[31:0]  out  32    = data_start_lba + (root_clus-2)*sec_per_clus
data_start_lba[31:0] out 32    = reserved + num_fats * fat_size
total_clus[31:0]    out  32    用于簇链越界判定与判环

约定：首版只支持 单分区 / FAT32 / 512B 扇区 / 根目录 / 8.3 短名。
      中文名、LFN、子目录、exFAT、NTFS 一律拒绝。
```

#### fat32_directory_scanner

```text
时钟域 : sys_clk
职责   : 遍历根目录项，抛出合法候选项

输入   : fat32_boot_parser 的部分输出
                         （root_clus / root_dir_lba / sec_per_clus / data_start_lba）
                         + fat32_cluster_walker 的 wk_* 握手
                         ⚠ v1.5 起 fat_start_lba / total_clus 归 walker，
                           不再进本模块（避免留死输入）
scan_en             in   1     开始遍历（**必须在 mount_done 之后**）
scan_done           out  1     遍历已结束。**成功和出错都置 1**，成功/失败看 dir_bad / err_code
dir_bad             out  1     目录结构异常（簇链越界 / 成环）。SD 层超时**不算**结构异常
err_code[7:0]       out  8     对外主码（ERR_MEDIA_INVALID / ERR_SD_IO）
err_detail[7:0]     out  8     内部细分码（DET_DIR_OOB / DET_FS_LOOP / DET_SD_*）
ent_valid           out  1     一条目录项有效
ent_ready           in   1     下游反压
ent_name[87:0]      out  88    8.3 名，11 Byte，如 "SV0001  BMP"
                               ⚠ v1.2 前误写为 `ent_name[10:0]`（11 **bit**），
                                 11 Byte 实际需要 88 bit，v1.4 修正
ent_attr[7:0]       out  8     属性字节
ent_first_clus[31:0] out 32    首簇号 = {FstClusHI, FstClusLO}
ent_size[31:0]      out  32    文件字节数
ent_index[15:0]     out  16    目录项槽位序号，0 基，**含被跳过的项**
                               （如槽 0 是 LFN、槽 1 才是文件，则文件的 ent_index = 1），供日志定位

约定：首字节 0x00 → 提前结束；0xE5 → 删除项跳过；
      attr[3]=1 卷标跳过；attr[4]=1 子目录跳过；attr[7:0]=0x0F → LFN 跳过；
      目录跨扇区必须背靠背读全

★ 见到 0x00 也不许中途停读：sd_sector_reader 的 rd_ready 只在 S_IDLE 有效，
  而它只有把整块数据发完才回得到 S_IDLE。中途把 data_ready 拉低不放，
  它会永远停在 S_DATA，之后每一次读都拿不到 rd_ready。正确做法是记下
  "该收工了"，把当前扇区的 512 Byte 收干净，再收工。

★ 32 Byte 目录项在扇区内天然对齐（512/32 = 16），绝不会被扇区边界切两半，
  不需要跨扇区拼接缓冲。

★ 根目录本身也是一条簇链（FAT32 里根目录不再占固定区域）。一个簇读完后去
  FAT 查下一个簇号，直到 EOC。入口地址 = fat_start_lba + (clus*4)/512，
  扇区内偏移 = (clus*4)%512；**入口是小端**，高 4 bit 是保留位必须掩掉，
  只取 [27:0] 再判 EOC（>= 0x0FFFFFF8）。
  越界 → DET_DIR_OOB；跳簇次数 > total_clus → DET_FS_LOOP。

★ 字节消费门控：`sd_data_valid` 为高期间 sd_sector_reader 会**一直保持**
  `data_valid`，直到看见 `data_ready`。所以接收侧必须用
  `sd_data_valid && sd_data_ready` 作为"吃一个字节"的条件；
  只判 `sd_data_valid` 会在反压期间把同一个字节吃掉很多次，计数与
  数据流立刻错位。这是实测中真实踩过的坑。

★ 反压期间不推进本模块的兜底超时计数器，否则"下游慢"会被误判成"卡超时"。

★ 依赖 O-11：sd_sector_reader 目前只支持单扇区读，所以这里是"一个扇区一次 CMD17"。
```

#### file_index

```text
时钟域 : sys_clk
职责   : 编号扫描 + 数字后缀排序，冻结索引表

输入   : fat32_directory_scanner 的 ent_* 全部
idx_commit          in   1     收到 scan_done 后提交
idx_done            out  1     —
file_cnt[3:0]       out  4     合法文件数
file_valid[3:0]     out  4     每槽是否有合法文件（供 C 看全貌）
insufficient        out  1     不足 4 幅 → ERR_BMP_COUNT

---- 查表口（单口读，见 §7 决策 D-1）----
sel_slot[1:0]       in   2     请求第几槽
sel_first_clus[31:0] out 32    该槽首簇号
sel_size[31:0]      out  32    该槽文件字节数
sel_valid           out  1     该槽索引有效

---- WAV 索引口（音画联动 E02 用，见 §3.6）----
sel_wav_first_clus[31:0] out 32  该槽同编号 WAV 的首簇号
sel_wav_size[31:0]  out  32    该槽同编号 WAV 的字节数
sel_wav_valid       out  1     同编号 WAV 存在

约定：候选图片形如 SV0001.BMP – SV9999.BMP；
      按数字后缀升序排序，取前四个合法文件；
      WAV 候选形如 SV0001.WAV，与图片**数字后缀一致**（手册 8.6）；
      WAV 缺失不算 B01 失败，只置 sel_wav_valid=0，由 §3.6 回退提示音；
      索引表一经冻结，只有重新扫描才更新；
      扫描全程由 fat32_directory_scanner 的 ent_ready 反压
```

### 3.2.1 卷基址约定（v1.11 增补）—— `mbr_parser`

★ **这条约定是板级实测（2026-10-02）逼出来的，改它之前先读完。**

**问题**：FAT32 层（`fat32_boot_parser` / `fat32_directory_scanner` / `fat32_cluster_walker` /
`file_streamer`）内部一律按 **【卷内相对 LBA】** 工作 —— 卷的第一个扇区记作 0 号扇区
（`fat32_boot_parser` 里写死 `sd_rd_addr <= 32'd0`，TB 断言 `T11.3 挂载读的是 0 号扇区`
也是照这个口径写的）。但**真实 TF 卡是分区的**：卡的 0 号扇区是 MBR，真正的 FAT32 卷
从**分区起始 LBA** 开始。实测 HX4S20C 那张卡的**分区起始 = 物理扇区 8192**
（`Get-Partition`），直接接上去等于让 FAT32 层去解析 MBR，必然 `mount_error`。

**约定**：
1. **FAT32 层内部永远不碰分区偏移**，只用卷内相对 LBA（卷 0 号扇区 = 0）。
2. 卷基址由 `mbr_parser` 解析，**只在板级顶层加一次**：
   送给 `sd_sector_reader` 的地址 = `FAT32 层的相对 LBA + vol_base_lba`。
   ⇒ 加两次是最难查的一类错，改这块务必先看本节。
3. `mbr_parser` 的容错：无 `0x55AA` 签名、或分区项为空（类型=0 / 起始 LBA=0）时
   **不报错**，按"无分区表"处理（`has_mbr=0`、`vol_base_lba=0`），下游按卷 0 = 卡 0 去试；
   真是坏卡则由 `fat32_boot_parser` 以 `DET_FAT_BPB` 报错，错误码不丢。
   只有 SD 层错误（数据令牌超时 / CRC16）才透传成失败。

**接口**：`safevision/rtl/storage/mbr_parser.v`

| 端口 | 方向 | 说明 |
|---|---|---|
| `start` | in | 单拍脉冲，触发一次解析 |
| `parse_done` | out | 电平：解析结束（成败都置位，下次 `start` 清零） |
| `has_mbr` | out | 1 = 有有效分区表且分区 0 可用 |
| `vol_base_lba` | out | 卷起始**物理** LBA（无分区表时为 0） |
| `part_secs` | out | 分区 0 的扇区数（无分区表时为 0） |
| `err_code` / `err_detail` / `dbg_state` | out | 错误主码 / 细分码 / 状态观测 |
| `sd_rd_addr/len/en`、`sd_rd_ready`、`sd_data/…_valid/…_ready/…_last`、`sd_rd_done`、`sd_timeout_err`、`sd_crc16_err`、`sd_err_code/detail` | — | **与 `fat32_boot_parser` 完全同一种接法**（同一个 `sd_sector_reader`，顶层做总线复用） |

**读的扇区**：卡的 **0 号扇区（MBR）**；字段偏移与字节序：`446+4` 分区类型、
`446+8..11` 起始 LBA（**小端**）、`446+12..15` 扇区数（**小端**）、`510/511` = `0x55AA`。

---

### 3.3 格式层（学习阶段 7）

#### fat32_cluster_walker（阶段 7 新增）

```text
时钟域 : sys_clk
职责   : FAT 簇链跟踪 —— 给一个簇号，查出下一个簇号，并判定收尾
实现   : safevision/rtl/storage/fat32_cluster_walker.v

rst_walk            in   1     单拍：清跳簇计数（开始走一条新链前拉一拍）
start               in   1     单拍：请求查 cur_clus 的下一个簇
cur_clus[31:0]      in   32    当前簇号
busy                out  1     —
done                out  1     单拍：本次查表结束（eoc/error/next_clus 与它同拍有效）
next_clus[31:0]     out  32    有效 = done && !eoc && !error
eoc                 out  1     链到头（下一个簇号 >= 0x0FFFFFF8）
error               out  1     簇链异常
err_code[7:0]       out  8     ERR_MEDIA_INVALID / ERR_SD_IO
err_detail[7:0]     out  8     DET_DIR_OOB / DET_FS_LOOP / DET_SD_*
hop_cnt[31:0]       out  32    已跳簇次数，供观测
fat_start_lba[31:0] in   32    来自 fat32_boot_parser
total_clus[31:0]    in   32    来自 fat32_boot_parser
（另有一组 sd_* 端口直连 sd_sector_reader）

约定：入口字节偏移 = clus*4，扇区号 = fat_start_lba + (clus*4)/512，
      扇区内偏移 = (clus*4)%512；
      **入口是小端**，高 4 bit 是保留位必须掩掉，只取 [27:0] 再判 EOC；
      越界 -> DET_DIR_OOB；跳簇次数 > total_clus -> DET_FS_LOOP

★ 为什么单独抽出来：fat32_directory_scanner（遍历根目录）和 file_streamer
  （读文件内容）都要跳簇。各写一份会导致"两处判环逻辑不一致"这种最难查的
  bug（v1.4 时确实是各写了一份），阶段 7 收敛成同一个模块。
★ 与 sd_sector_reader 的抢占：walker 与 file_streamer 分时复用同一个读口，
  由 walker 的 busy 做总线选择——walk 期间 file_streamer 不发读请求。
  正式顶层由 file_request_arbiter 统一调度。
```

#### file_streamer（阶段 7 落地；原 `file_stream` 改名）

```text
时钟域 : sys_clk
职责   : 把 (首簇, 文件大小) 变成字节流；簇链跟踪交给 fat32_cluster_walker
实现   : safevision/rtl/storage/file_streamer.v

clk / rst_n         —    —     —
start               in   1     单拍：触发
first_clus[31:0]    in   32    来自 file_index
file_size[31:0]     in   32    来自 file_index
busy                out  1     —
done                out  1     电平：本次读结束（成功或出错都置 1）
error               out  1     电平：出错
err_code[7:0]       out  8     ERR_MEDIA_INVALID / ERR_SD_IO
err_detail[7:0]     out  8     DET_FS_SHORT / DET_FS_LOOP / DET_DIR_OOB / DET_SD_*
bytes_rd[31:0]      out  32    已输出字节数，与电脑端比对用
data[7:0]           out  8     字节流
valid               out  1     —
ready               in   1     下游反压
sof                 out  1     与第一个字节同拍（原 file_start）
eof                 out  1     与最后一个字节同拍（原 file_end）

约定：valid && ready 同拍才推进一个字节；
      **valid=1 且 ready=0 时 data/sof/eof 必须保持**；
      file_size = 0 时一个字节都不发，也不发 sof/eof

★ 跳簇不在本模块里：一个簇读完，拉一拍 walker.start，等 walker.done
  再决定下一个簇从哪来（见 fat32_cluster_walker）。

★ 三条实测踩过的坑（都写进 RTL 注释了）：
  1) 从 sd_sector_reader 收字节必须用 `sd_data_valid && sd_data_ready` 门控；
  2) 字节数够到 file_size 之后**不能中途停读**，要把本扇区收干净再收工；
  3) "下游取走字节"的清零逻辑必须放在状态机**之外**。扇区最后一个字节被锁存
     的那一拍正好也是扇区结束、state 跳走的那一拍；清零逻辑若只写在接收态里，
     valid 就再也没人清，而死等到兜底超时。
★ 另一个边界：文件的最后一个字节正好落在扇区最后一个字节时，stop_pending
  要到下一拍才生效，扇区结束判定必须把"本拍锁存的就是最后一字节"也算进去，
  否则会白跳一次簇、撞上 EOC 误报 DET_FS_SHORT。

★ EOC 提前到达（还没凑够 file_size 字节链就没了）-> DET_FS_SHORT。
  访问 FAT 表会与数据扇区读抢占 sd_sector_reader，必须串行化。
```

#### bmp_parser（阶段 7 落地；原 `bmp_check` 改名）

```text
时钟域 : sys_clk
职责   : BMP 头严格校验；不合格立即放弃该文件，不消费像素
实现   : safevision/rtl/media/bmp_parser.v

输入   : file_streamer 的 data / valid / ready / eof / file_size 直连
check_done          out  1     单拍：头解析结束
check_error         out  1     电平：头不合法
err_code[7:0]       out  8     ERR_MEDIA_INVALID
err_detail[7:0]     out  8     DET_BMP_SIG / _DIB / _SIZE / _FMT / _TRUNC
width[15:0]         out  16    必须 640
height[15:0]        out  16    480 或 -480（bit15=1 表示 top-down）
top_down            out  1     1 = 负高度，自顶向下
bpp[7:0]            out  8     必须 24
compression[31:0]   out  32    必须 0（BI_RGB）
pixel_off[31:0]     out  32    = bfOffBits，像素数据起始偏移
file_size_o[31:0]   out  32    回读声明长度，供日志
out_data / out_valid / out_ready / out_sof / out_eof
                    —    —     透传口：校验通过后把像素字节转给 bmp_unpack

约定：校验清单（第一条不通过就停，细分码指出是哪一条）
      1) 0x00 两字节 == 'B','M'                -> DET_BMP_SIG
      2) biSize >= 40                          -> DET_BMP_DIB
      3) 宽 = 640，高 = ±480                    -> DET_BMP_SIZE
      4) planes = 1，bpp = 24，compression = 0  -> DET_BMP_FMT
      5) bfOffBits >= 54，bfSize <= file_size，
         bfOffBits + 640*480*3 <= file_size     -> DET_BMP_TRUNC
      640×480 严格比对，不满足即跳过（半幅图比黑屏更难解释）

★ file_size 的口径是【目录项里的声明长度】，不是"到目前收到了多少字节"。
★ BMP 所有多字节字段都是小端，装配同样要"新字节从高端进"。
★ 校验不通过时仍把本文件剩余字节排空（只丢不外送），避免上游 file_streamer
  卡死。**已知待优化**：坏文件也要把整条流走完；后续可加 abort 输入提前收工。
★ 头之后、bfOffBits 之前的调色板/填充字节会被丢掉，不会当成像素数据透传。
```

#### bmp_unpack

```text
时钟域 : mem_clk（写侧）
职责   : BGR888 → RGB565；处理行填充与上下方向

输入   : bmp_check 的 row_stride / top_down / width / height
din[7:0] / din_valid / din_ready   in    来自 file_stream
dout[15:0] / dout_valid / dout_ready out RGB565 像素
px_x[9:0] / px_y[9:0]  out  10/10  像素坐标
done                out  1     —
err_code[7:0]       out  8     ERR_BMP_TRUNC

约定：舍入还是截断必须全队统一并写入本文档（见 §8 待确认）；
      注意 BGR → RGB 字节序，避免红蓝颠倒；
      每行末尾填充字节必须丢弃；
      输出统一为左上原点、从左到右、从上到下
```

### 3.4 存储层（学习阶段 9–15）

#### slot_writer

```text
时钟域 : mem_clk
职责   : 把像素流写入指定槽；写完做 CRC 抽检并置 slot_valid

clk(mem_clk) / rst_n       —    —
slot_sel[1:0]       in   2     目标槽
slot_base[31:0]     in   32    槽起始逻辑字节地址（只能取自 §5 地址表常量）
din[15:0]           in   16    RGB565
din_valid           in   1     —
din_ready           out  1     反压
wr_req              out  1     写请求
wr_addr[31:0]       out  32    逻辑字节地址 = slot_base + (y*640 + x)*2
wr_data[31:0]       out  32    打包为 32bit word（2 像素/word）
wr_len[15:0]        out  16    突发长度
wr_ready            in   1     来自 mem_arbiter
wr_done             out  1     —
slot_valid[3:0]     out  4     ★ 置位后 A 才允许读该槽
crc_ok              out  1     抽样点比对通过
crc_value[15:0]     out  16    —
px_cnt[18:0]        out  19    应等于 307200
wr_error            out  1     —

约定：★ slot_valid 未置位不许读——把"半幅图 / 坏图进画面"的路径在结构上排除；
      业务模块内禁止出现裸物理地址运算
```

#### mem_arbiter

```text
时钟域 : mem_clk
职责   : 仲裁写侧（slot_writer）与读侧（frame_reader）对 SDRAM 的访问

---- 写通道 ----
wr_req / wr_addr[31:0] / wr_data[31:0] / wr_len[15:0] / wr_ack / wr_busy
---- 读通道 ----
rd_req / rd_addr[31:0] / rd_len[15:0] / rd_ack / rd_data[31:0] / rd_data_valid
---- 到 mem_ctrl ----
mem_req / mem_wr / mem_addr[31:0] / mem_wdata[31:0] / mem_ready
mem_rdata[31:0] / mem_rdata_valid
---- 观测 ----
wr_starve_cnt[15:0] / rd_starve_cnt[15:0]   out  饥饿计数

约定：读优先但写不许饿死；仲裁切换必须发生在突发边界；突发长度固定写死
```

#### mem_ctrl（SDRAM IP wrapper）

```text
时钟域 : mem_clk
职责   : 封装安路 SDRAM IP，对外只暴露逻辑字节地址

init_done           out  1     初始化完成
req                 in   1     访问请求
wr                  in   1     1=写 0=读
addr[31:0]          in   32    逻辑字节地址
wdata[31:0]         in   32    —
wstrb[3:0]          in   4     字节选通
rdata[31:0]         out  32    —
rdata_valid         out  1     —
ready               out  1     —
mem_error           out  1     —
sdram_*             —    —     板级引脚

约定：IP 版本与参数以 APUG011 与板级报告为准；对外声明可见容量 4MiB
```

#### swap_ctrl

```text
时钟域 : sys_clk ↔ pixel_clk（跨域，toggle 握手）

frame_ready         B→A  1     新帧已完整写入并通过 CRC 抽检
frame_index         B→A  1     新帧所在块（0/1）
slot_id             B→A  2     图像槽编号
generation          B→A  8     写入代次，防止重复提交
crc_ok              B→A  1     抽样点 CRC 比对通过
swap_req            B→A  1     请求切换（toggle 电平翻转，不是单拍脉冲）
frame_start         A→B  1     到达帧边界（垂直消隐入口），每帧 1 拍
swap_ack            A→B  1     已完成切换（toggle 翻转）
swap_error          A→C  1     握手超时，交 C 的可靠性链

约定：IDLE → WAIT_VBLANK → COMMIT → WAIT_ACK → IDLE；
      超时 TIMEOUT_N 后进 SAFE，保持当前显示块；
      active_slot + slot_base + generation 必须在同一时刻原子更新；
      多比特 payload 先锁存进 mailbox 再给回执
```

### 3.5 横切模块

#### error_report

```text
时钟域 : sys_clk
职责   : 汇总全链错误码，经 Control Event Interface 交 C 的 UART

err_push            in   1     压入一条错误事件
err_code[7:0]       in   8     见 §6 错误码表
err_src[3:0]        in   4     来源模块编号
err_ts[31:0]        in   32    时间戳（ms）
evt_type[3:0]       out  4     —
evt_value[15:0]     out  16    —
evt_valid           out  1     —
evt_full            out  1     满标志；溢出计数在 C 侧

约定：错误事件不允许丢弃；满时置 evt_full 并计数
```

#### 全局状态（Global Status）

```text
sd_ready / sd_error / media_present / mem_error        out  1 each
```

#### uart_tx（第 9 章三人公共调试模块 · 雏形）

```text
时钟域 : sys_clk
职责   : UART 发送，115200 8N1，LSB 先发
实现   : safevision/rtl/common/uart_tx.v
用途   : 阶段 5「SD -> FPGA -> UART -> 电脑」逐字节比对；后续扩成收+发给 C 用

clk                 in   1     sys_clk
rst_n               in   1     —
tx_valid            in   1     单拍脉冲，请求发送
tx_data[7:0]        in   8     待发字节
tx_ready            out  1     可接受新字节
txd                 out  1     串行输出，空闲为高

参数：CLK_FREQ / BAUD，DIV = CLK_FREQ / BAUD
      100MHz / 115200 = 868（误差 0.006%，远小于 2% 容限）
约定：发送侧只按波特率计数移位；位中点采样是接收侧的事（手册第 9 章）
```

### 3.6 音频链（B04）

> 职责边界（手册 7.16.3 原话）：**B 的职责止于"提供正确的 PCM 样本与环形缓冲水位"**。
> B **不做**：48 kHz 节拍、优先级仲裁、应急告警音、ACR、Audio InfoFrame、音频样本包打包。
> 链路刻意不走外部 I²S Codec——那是外接声卡的接口，不是 HDMI 的音频接口（手册 8.6 纠错）。

#### wav_parser

```text
时钟域 : sys_clk
职责   : 解析 WAV 容器（RIFF / fmt / data），输出 16bit 双声道 PCM 样本流

clk / rst_n            —    —     —
start                  in   1     触发
first_clus[31:0]       in   32    来自 file_index 的 WAV 索引口
file_size[31:0]        in   32    —
track_id[7:0]          in   8     音轨编号（与图片数字后缀一致），透传
bitstream 输入          —    —     复用 file_stream 的 data / valid / ready
---- 解析结果 ----
fmt_code[15:0]         out  16    必须 = 1（PCM）
num_channels[15:0]     out  16    必须 = 2
sample_rate[31:0]      out  32    必须 = 48000
bits_per_sample[15:0]  out  16    必须 = 16
data_offset[31:0]      out  32    data 块内 PCM 起始偏移
data_size[31:0]        out  32    PCM 总字节数
header_done            out  1     头部解析完成
---- PCM 输出 ----
pcm_l[15:0]            out  16    左声道，有符号
pcm_r[15:0]            out  16    右声道，有符号
pcm_valid              out  1     —
pcm_ready              in   1     下游反压
pcm_end                out  1     本音轨结束
---- 状态 ----
wav_error              out  1     —
err_code[7:0]          out  8     对外码 0x07；细分码见 §6.2
fallback_req           out  1     请求回退到提示音
samples_rd[31:0]       out  32    已输出样本对数，与电脑端比对用

约定：只接受 PCM format code 1 / 48 kHz / 16 bit / 立体声；
      其余编码或采样率在 header_done 后立即 wav_error，对外码 0x07；
      fmt 与 data 之间的未知块按 chunk size 跳过并做边界检查（手册 8.6 原话）；
      RIFF chunk_size 与 data_size 必须做越界校验；
      与 bmp_check 分时复用 file_stream，同一时刻只允许一路占用
```

#### pcm_ring

```text
时钟域 : mem_clk
职责   : 在 SDRAM AUDIO_RING 区维护环形缓冲，解耦 SD 慢读与 48 kHz 连续消费

clk(mem_clk) / rst_n   —    —     —
---- 写侧（来自 wav_parser，经 CDC）----
wr_en                  in   1     写入一对样本
wr_l[15:0]             in   16    左声道
wr_r[15:0]             in   16    右声道
wr_ready               out  1     可写（未溢出）
wr_req                 out  1     写请求到 mem_arbiter
wr_addr[31:0]          out  32    逻辑字节地址（限 AUDIO_RING 区内）
wr_data[31:0]          out  32    打包 {r[15:0], l[15:0]}
---- 读侧（供 audio_cdc_fifo）----
rd_req                 out  1     读请求到 mem_arbiter
rd_addr[31:0]          out  32    逻辑字节地址
rd_data[31:0]          in   32    —
rd_data_valid          in   1     —
---- 状态 ----
level[15:0]            out  16    当前样本对数（水位）
overflow               out  1     ★ 写溢出，必须计数上报，禁止静默丢样本
track_id[7:0]          out  8     当前音轨编号
track_change           out  1     音轨切换事件（toggle）

约定：环形容量取满 AUDIO_RING 区：256 KiB ÷ 4 byte = 65536 对样本 ≈ 1.37 s @48 kHz；
      读写指针均为逻辑字节地址，物理 word 地址由 mem_ctrl 转换；
      音频读写是 mem_arbiter 的第三个客户端，但其带宽仅约 0.192 MB/s
      （48000 × 2ch × 2byte），相对视频链可忽略，不得让音频饿死视频或反之
```

#### audio_cdc_fifo

```text
时钟域 : mem_clk（写）→ audio_clk（读）
职责   : 把 PCM 样本对跨到音频域

位宽     : 32bit = {r[15:0], l[15:0]}
深度     : 建议 512（≈10.7 ms @48 kHz）
读出方式 : FWFT，与像素 FIFO 同一策略（见 §7 决策 D-2）
写侧     : clkw / we / di[31:0] / full_flag / afull
读侧     : clkr / re / dout[31:0] / valid / empty_flag
水位     : wrusedw / rdusedw

★ 该 FIFO IP 的 rst 同样是【异步、高有效】，必须取反后接入
```

#### B→C 边界：PCM Sample Interface

```text
=== PCM Sample Interface（B→C）===
audio_clk           in   1     C 在 B→C 接口处分发；物理源由 A 平台 PLL 提供（audio_mclk 12.288 MHz = 256 × Fs）
pcm_l[15:0]         out  16    左声道，有符号
pcm_r[15:0]         out  16    右声道，有符号
pcm_valid           out  1     与 pcm_l / pcm_r 同拍有效（FWFT，等效 !empty）
pcm_rd              in   1     C 取走一对样本，推进指针
pcm_empty           out  1     空标志
pcm_level[15:0]     out  16    缓冲内样本对数，供 C 观测与低水位告警
track_id[7:0]       out  8     当前音轨编号，随 generation 生效
track_change        out  1     音轨切换事件（toggle）
audio_fallback      out  1     1 = 当前为提示音回退

约定：C 的 audio_scheduler 按 48 kHz 节拍拉 pcm_rd；
      pcm_empty 为 1 时 C 必须输出零样本并计入 audio_underflow，
      ★ 绝不输出随机数据（手册 8.6 原话）；
      分工：B 保证"样本连续供上"，C 负责"欠载计数"；
      音画同步：track 切换必须在与视频相同的 generation 内生效。
```

#### 仅供登记：Audio Sample Interface（C→A）

```text
手册 10.2.4 已定义，此处仅登记，B 不实现：
audio_l[23:0] / audio_r[23:0] / audio_valid   （C 将 16bit 符号扩展为 24bit 后产出）
track_id[7:0] / audio_underflow（计数器，C 侧）
```

---

### 3.7 板级 bring-up 顶层 `top_stage5_sector_rd`（阶段 5 最小验证，不属产品链）

定位：**接引脚、只用于阶段 5 上板验证**的最小顶层，放
`platform/anlogic_eg4s20_hx4s20c/rtl/`。它不是产品顶层——产品顶层是 A 的
`platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_top.v`，
不带引脚的可移植装配才是 `rtl/top/safevision_core/`。

功能：上电延时 → `sd_initializer` 初始化 → 读 `rd_addr = TARGET_LBA` 单扇区 →
512 Byte 按序灌 `uart_tx`（115200 8N1）。LED 显示序列状态码。

| 端口 | 方向 | 引脚 | 原理图网络名 | 说明 |
|---|---|---|---|---|
| `clk` | in | R7 | `FPGA_GCLK` | 板载 50 MHz 晶振（本顶层**不接 PLL**） |
| `rst_n` | in | A2 | `KEY_1` | 独立按键，低有效；经 `reset_sync` 两级释放 |
| `sd_dclk` | out | A14 | `FPGA_SD_CLK` | SPI SCLK |
| `sd_mosi` | out | A13 | `FPGA_SD_CMD` | SPI MOSI |
| `sd_miso` | in | B14 | `FPGA_SD_D0` | SPI MISO |
| `sd_ncs` | out | A12 | `FPGA_SD_D3` | CD/DAT3 当 SPI 片选（低有效） |
| `uart_txd` | out | D12 | `TXD` | 已确认：FPGA 发送（板载 CH340G，见下方） |
| `led[3:0]` | out | A4 / A3 / C10 / B12 | `LED0`…`LED3` | 状态码 1/2/3/4/5/8，失败显示错误主码低 4 位 |

参数：`CLK_FREQ`（默认 50 MHz）、`BAUD`（115200）、`TARGET_LBA`（默认 `32'd8192`）、
`POWERUP_CYC`（50 ms 上电等待）。

★ **`TARGET_LBA` 的默认值为什么是 8192 而不是 1000**：`TARGET_LBA` 是**读哪个扇区**的参数，
它是 SD 卡上的**块地址**（SDHC）或字节地址（SDSC，模块内部左移 9 位）。原本按手册初稿取
1000，但实测本机这张 TF 卡的**分区从物理扇区 8192 开始**，于是 LBA 1000 落在
"MBR 之后、分区之前"的未分配空隙里 —— **读出来是 512 个 0x00**，两边都全零会让
"逐字节比对"失去证明力。改成 **8192 = 分区首扇区 = FAT32 引导扇区（DBR）**：内容非零且
可识别（`eb 58 90 "MSDOS5.0"`…结尾 `55 aa`）。电脑侧参考值（512 B，SHA-256
`E4704165…C426EEE`）存于 `evidence/board/lba8192_pc_20261002.bin`。
注意 Windows 的**卷句柄偏移是从分区开头算的**，所以物理 LBA 8192 = 卷偏移 0（不需要管理员
权限即可读）；直接用 `\\.\G:` 偏移 512000 读到的**不是** LBA 1000。

★ **时钟取舍（bring-up 专用，不代表产品时钟方案）**：本顶层全部逻辑跑板载 50 MHz，
不经 PLL。原因是 bring-up 阶段先排除"IP 配置错"这一层变量。由此：
`spi_master` 的 SCLK 由 `clk_div` 决定（`SD_DIV_INIT=124` → 200 kHz，仍在规范的
100–400 kHz 内；`SD_DIV_FAST=1` → 12.5 MHz）；`safevision_defs.vh` 的超时拍数按
100 MHz 推导，50 MHz 下墙上时间翻倍（只会更宽松）。产品链仍按 §一 的
`sys_clk=100MHz / mem_clk=125MHz / pixel_clk=25.175MHz`，PLL 由 TD IP 提供。

★ **两个 SD 模块共用一条 SPI 总线**：`sd_initializer` 与 `sd_sector_reader` 各带一套
字节引擎，顶层用 `init_done` 做二选一（初始化段归 initializer，之后归 reader），
`spi_rx_*` 广播给两者（另一个停在 `B_IDLE` 不会误吞）；`sd_ncs` 取两路低有效片选的与。

★ **UART 反压**：`uart_tx_valid = rd_data_valid & uart_ready`，
`rd_data_ready = uart_tx_valid`（同拍握手一拍）。UART 115200 每字节约 87 us，
512 Byte 约 44.6 ms，reader 的 `S_DATA` 停 SCLK 等下游且该状态本身无超时计数器，
所以慢发不会被误判成超时。

★ **`uart_txd = D12` 已确认（2026-10-02），无需外接 USB-TTL 模块**：板载就有 USB-UART
（**CH340G**，位号 U41）。依据：
① 开发板手册《HX4S20开发板手册-HDL版2410.pdf》的**串口引脚分配表**：`RXD = F12`、`TXD = D12`；
② 同手册 **图2-10「USB连接CH340串口原理图」**：CH340G 的 pin2（`TXD`，芯片输出）接的是网络
**`RXD`**，pin3（`RXD`，芯片输入）接的是网络 **`TXD`**——**两路线是交叉的**，说明网络名是按
**FPGA 视角**命名的。所以：
  `RXD`(F12) = FPGA 接收（输入，由 CH340 驱动）；`TXD`(D12) = **FPGA 发送（输出，驱动 CH340 pin3）**。
D12 是输出、对方是输入，**不存在双向争用**，可以放心接线。上板只需插 USB 线，
在电脑上打开对应 COM 口，**115200 8N1**。

其余引脚依据：手册的 LED 表（LED1=A4 / LED2=A3 / LED3=C10 / LED4=B12）、独立按键表（KEY1=A2）；
SD 四线由 `2_FPGA.pdf` 的网络名（`FPGA_SD_CLK/CMD/D0/D3`）+ `6_EX_DEVICE.pdf` + 厂商同器件例程
三处一致；手册 TF 卡一节只印了连接器引脚语义（SPI 模式 pin2=cs / pin3=di / pin5=sclk / pin7=do），
与上面的映射一致，未给 FPGA 引脚号。

★ 阶段 6–7 的板级顶层 `top_stage6_fat32_mount` 见 **§3.8**（引脚、时钟取舍与本节完全相同）。

---

### 3.8 板级 bring-up 顶层 `top_stage6_fat32_mount`（阶段 6–7 最小验证，不属产品链）

定位：接引脚的阶段 6–7 最小验证顶层，放 `platform/anlogic_eg4s20_hx4s20c/rtl/`。
**引脚、时钟取舍与 §3.7 完全一致**（`clk`=R7 / `rst_n`=A2 / `sd_*` / `uart_txd`=D12 /
`led[3:0]`，**不接 PLL**，全跑板载 50 MHz）；**无新增引脚**，`pin.adc` / `timing.sdc` 不变。
板级验收结论见 `B链-待办与硬件验证清单.md` 的 M-10。

流程：上电 → `sd_initializer` → `mbr_parser`（读卡 0 号扇区，给出卷基址）→
`fat32_boot_parser` → `fat32_directory_scanner`(+`fat32_cluster_walker`) →
**连读阶段（M-6）** → `uart_tx`(115200) 发纯 ASCII 报告。
`mbr_parser` / `fat32_boot_parser` / `fat32_directory_scanner` / `fat32_cluster_walker` /
**连读阶段** 共用一个 `sd_sector_reader`（顶层做总线复用）。

参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `CLK_FREQ` | `50_000_000` | 板载晶振（不接 PLL） |
| `BAUD` | `115200` | UART 波特率 |
| `POWERUP_CYC` | `24'd2_500_000` | 上电等待 50 ms @50 MHz |
| `RPT_N` | `16'd100` | **★ M-6 连读次数**：挂载 + 扫目录后，对同一 LBA（根目录扇区，**卷内相对** LBA = `root_dir_lba`）连读 `RPT_N` 次，每次由 `sd_sector_reader` 自带的 CRC16 判好坏 |

**连读阶段（M-6 / M-8）行为约定**：

1. 请求经**共享的** `sd_sector_reader`（本顶层是第 5 个读请求方，走同一个 mux）；
   地址给的是**卷内相对 LBA**，**卷基址仍由 §3.2.1 那唯一一个加法器加一次**——
   ★ 不新增第二个加法器。
2. 连读阶段 `data_ready` 恒 1，把 512 Byte 全部排空（否则 reader 会停在**无超时**
   的 `S_DATA` 等下游）。
3. **失败策略：无论成败都跑满 `RPT_N` 次，不提前退出**。理由：报告长度/行数固定，
   PC 侧逐字节 diff 永远成立；「100 次里坏 1 次」与「100 次全坏」可区分开；拔卡时
   每次读由 reader 自己的出口兜底（`S_R1` 轮询到 `SD_RESP_MAX_BYTES` 即退、
   数据段有 `SD_TO_DATA`），100 次仍在毫秒级，**必然在有限时间内结束**。
4. 任一次读**超时或 CRC16 错** → 计入 `BAD`，对外主码取 `ERR_SD_IO`(0x02)。
5. **每个等待态独立超时**（手册 7.4）：连读的每一次 `ST_RPTWAIT` 都有自己的计数器
   （每次读开始时清零）。
6. `BAD != 0` 时报告末行改发 `ERR=<2hex>`；全 OK 则发 `DONE`。失败发生在连读之前时，
   整份报告只有一行 `ERR=<2hex>`。

LED 状态码：在 §3.7 的 `1..8` 基础上新增 **`9 = 连读进行中`**；失败仍是「错误主码低 4 位」。

报告格式（纯 ASCII / 大写十六进制 / 定宽 / **CRLF 行尾**，全 ASCII 是为了规避串口
工具文本模式把 `≥0x80` 字节换成 `U+FFFD` 的有损转换）：

```text
行1  SAFEVISION B STAGE6
行2  MBR=<8hex> BASE=<8hex> SECS=<8hex>
行3  BPS=<4hex> SPC=<2hex> NFAT=<2hex>
行4  FATLBA=<8hex> DATALBA=<8hex> ROOTLBA=<8hex>
行5  TOTSEC=<8hex> TOTCLUS=<8hex>
行6  ENT=<4hex>
每项 E <idx:4hex> <name:22hex> <attr:2hex> <clus:8hex> <size:8hex>   (52 Byte)
行7  RPT=<total:4hex> OK=<ok:4hex> BAD=<bad:4hex>                    (27 Byte)
末行 DONE (6 Byte) 或 ERR=<2hex> (8 Byte)
```

★ **各段字节数**：HDR `183` = `21+42+25+51+34+10`；每项 `52`；`RPT` `27`；`DONE` `6`；
`ERR` `8`。早期版本把报告头声明成 **184 Byte**（实际 183），Verilog 在 MSB 侧补零 ⇒
**整份报告多一个前导 `0x00`**（板上实测 450 = 1 NUL + 183 + 260 + 6）。现已按真实字节数
声明并保留「逐段相加」的核对。

★ **行尾一律用显式字节 `8'h0D` / `8'h0A`，不用字符串转义 `"\r\n"`**：**ModelSim vlog 10.7
与 TD 6.2 都不把字符串里的 `\r` 当转义**——实测二者都把 `"DONE\r\n"` 编成
`44 4F 4E 45 72 0A`（字母 `r` + LF）。旧版 RTL 与旧版 TB 同用转义，仿真里「错得一样」
因而自洽通过，板子上却是 `72 0A`（M-10 记档的纯外观偏差之一）。改显式字节后，
仿真与硬件都得到真正的 CR。

健康卡（实卡 5 项）整份报告 = `183 + 5×52 + 27 + 6` = **476 Byte**，
`RPT=0064 OK=0064 BAD=0000`，末行 `DONE`。

---

### 3.9 板级 bring-up 顶层 `top_sdram_loopback`（阶段 9 第一步 / 手册 7.9，不属产品链）

**定位**：接引脚、不属产品链的 bring-up 顶层，**不是** A 的产品顶层 `safevision_top.v`。
只做一件事：上电 → 等 PLL 锁定 → 等 SDRAM 控制器初始化完成 → 写图案 → 等落地 → 读回比对
→ 经 UART 发纯 ASCII 报告。

★★ **2026-10-02 上板通过（条目 M-11-PASS）**：位流 22:01:24 下载后收 **71 Byte**，
`SV-SDRAM-LOOP` / `INIT=01 LOCK=01` / `W=1000 R=1000 CAP=1000 BAD=0000` / `DONE`，
与设计值**一字不差** ⇒ 接口与报告格式实地确认。STA 见 `evidence/reports/` 条目 TC-Q-STA-4。

```text
文件 : safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v
端口 : clk(R7 50MHz) / rst_n(A2) / uart_txd(D12) / led[3:0]
       —— 与 §3.7 / §3.8 完全相同，pin.adc 无需改动
参数 : CLK_FREQ(50M) MEM_CLK_FREQ(125M) BAUD(115200)
       POWERUP_CYC(2_500_000) INIT_TO_CYC(2_000_000)
       BASE_ADDR(21'd0) TEST_WORDS(21'd4096) ADDR_SHIFT(0)
       BURST_N(128) BURST_GAP(16) WR_DRAIN_CYC(512) RD_WAIT_TO_CYC(200_000)
```

**时钟**：板载 50 MHz → `sv_system_pll`：C0 = 100 MHz（外部业务端口留空，wrapper 内反馈保持连接）、C1 = 125 MHz = SDRAM 侧
`Clk`、C2 = 125 MHz **180° 相移** = `Clk_sft`。`timing.sdc` 因此新增 `derive_clocks`
（**不加的话 125 MHz 域无时钟定义、STA 是假通过**）。
**全部逻辑（含 `uart_tx`）跑 125 MHz 单域，刻意不做 CDC**：报告只有 71 Byte，瓶颈在 UART
（115200 下约 6.2 ms），把 `uart_tx` 也挂 125 MHz（`DIV = 125e6/115200 = 1085`，误差 0.006%）
比引一条跨时钟域更少变量。⇒ 本顶层**只有一个逻辑时钟域**。

**SDRAM 是封装内硬核（die-in-package）**：`EG_PHY_SDRAM_2M_32`，2M × 32 bit = 8 MB。
其 55 根信号（`addr/ba/dq/dm/ras/cas/we/cs`）**不出芯片引脚**，因此
**`constraints/pin.adc` 里不应该有、也确实没有** SDRAM 引脚（厂商例程同样一条都没有）。
`ip/sdram/sdram.v` 里的 `SDRAM_*` 只在 `SIMULATION` 宏打开时才成为端口，综合时是内部 `wire`。

**应用侧协议（照厂商例程，非自创）**：
- 写：`App_wr_en` 逐 word 使能、`App_wr_addr` 逐拍递增、`App_wr_dm = 4'b0000`（全字节写）。
- 读：`App_rd_en` + `App_rd_addr` 发命令，**数据是延迟应答式** —— `Sdr_rd_en` 才是取数时刻，
  与 `Sdr_rd_dout` 同拍有效。**不许假设"发读命令下一拍就有数据"**。
- `Sdr_busy` / `Sdr_init_ref_vld` 在例程里是**纯直通、从不参与判断**（`frame_fifo_*` 收了
  这两个端口却一次没用），所以应用侧只需自负两条责任：**突发要留间隔**（本顶层
  `BURST_N=128` + `BURST_GAP=16`）、**读写突发不许重叠**（写完 → `WR_DRAIN_CYC` 落地等待 → 再读）。

**[纠正 2026-10-04] 数据检查**：原图案拼接只有 28 bit，忽略地址 `[20:12]`，会漏检高位地址混叠。新版图案为 32 bit，包含全部 21 个地址位，可从数据独立反解地址；连续 256 个地址使每个 DQ 位均出现 0 和 1。写侧和比对侧使用同一函数，TB 另用独立反解和地址混叠注入验证。默认仍写读 4096 word，71 Byte UART 格式不变，报告选择器增加一个字节缓存以满足 fabric 时序。

默认 `ADDR_SHIFT=0` 为连续 16 KB 块；`BASE_ADDR=0`、`ADDR_SHIFT=11`、`TEST_WORDS=1024` 为 1024 个稀疏样本，地址为 `0..2095104`、步长 2048 word，只改变地址 `[20:11]`。它不覆盖全部 bank/row/列，也不是全容量逐字测试。详见 [SDRAM/PLL 核查修正版](B链-SDRAM接口与PLL时序核查.md)。

**LED 状态码**：`1` 上电等待 / `2` 等 SDRAM 初始化 / `3` 写图案 / `4` 等写落地 /
`5` 发读命令 / `6` 等读回收齐 / `7` 发报告 / `8` 成功；失败显示错误主码低 4 位。

**报告格式（定长 71 Byte，纯 ASCII，显式 `8'h0D`/`8'h0A` 行尾）**：

```text
行1  SV-SDRAM-LOOP                  (13 + CRLF = 15 Byte)
行2  INIT=<2hex> LOCK=<2hex>        (5+2+6+2  + CRLF = 17 Byte)
行3  W=<4hex> R=<4hex> CAP=<4hex> BAD=<4hex>   (31 + CRLF = 33 Byte)
行4  DONE                           (4 + CRLF = 6 Byte)
```

默认参数下的理想报告为 `W=1000 R=1000 CAP=1000 BAD=0000`（`TEST_WORDS = 4096 = 0x1000`）。
判定：`W == R == CAP == TEST_WORDS` 且 `BAD == 0000` 才算过；`CAP < W` 说明有读命令没返回
（控制器丢命令），`CAP == W` 但 `BAD != 0` 才是真的数据错。

**错误主码**（本顶层局部，非 §6 的团队对外错误码）：`01` = SDRAM 初始化超时（独立计数器）、
`02` = 读回不齐（独立计数器）、`03` = 数据不一致。

**★ 本顶层没有 testbench，也进不了 `run_sim.ps1`**：厂商 SDRAM 控制器的真正实现是
`ip/sdram/sdr_as_ram.enc.v` 等三个**安路 RSA 加密**文件（IEEE-1735 `pragma protect`），
只能由 TD 综合时解密。**验收方式只有上板 + 读 UART 报告**。这是"加密 IP 不可仿真"的客观
限制，与阶段 1–7"仿真先绿再上板"的节奏不同，不是遗漏。

**IP 落点与来源**：`safevision/platform/anlogic_eg4s20_hx4s20c/ip/sdram/`
（`sdram.v` 应用级外壳 + `global_def.v` + 三个 `.enc.v` + `sdram.ipc`）、
`ip/pll/`（`sv_system_pll` / `sv_video_*_pll` / `sv_audio_pll`；系统 PLL 于 2026-10-03 去重为唯一一份）。均来自厂商例程包（工作区参考材料，本身不进仓库），
详见该目录 `README.md`。★ 例程里**有两个同名 `sdram` 模块**：`IP/sdram.v` 是引脚级 PHY 外壳
（例程顶层没用它），`SD/sdram.v` 才是被 `sdram U3(...)` 例化的应用级控制器 —— 两者不能同时
进同一个 TD 工程。本仓库只保留后者。

---

## 四、与 A / C 的边界

### 4.1 Pixel FIFO（mem_clk → pixel_clk）

```text
type        : 异步 FIFO，读出方式 = FWFT（Show-Ahead），见 §7 决策 D-2
位宽        : 写侧 32bit（2 像素/word），读侧 16bit（RGB565）
推荐配置    : 复用工程内 afifo_16_32_256 的配置
              CLKMODE=ASYNC, RAM_OPT=ERAM
              SHOW_AHEAD=Enable, OUT_REG=Disable

---- 读侧（pixel_clk，A 负责）----
clk / dout[15:0] / re / valid / empty_flag
---- 写侧（mem_clk，B 负责）----
clkw / we / di[31:0] / full_flag / afull
---- 水位 ----
wrusedw / rdusedw

★ 陷阱：该 FIFO IP 的 rst 是【异步、高有效】，而系统 rst_n 低有效，
        B 链必须显式取反后接入，禁止直连。
★ FWFT 不等于免维护：A 仍须保证 de 有效时 FIFO 非空，
        欠载（underflow）计数照样要做。
```

### 4.2 Frame Swap

见 §3.4 `swap_ctrl`。

---

## 五、冻结的存储地址表（逻辑字节地址）

| 区域 | 逻辑起始地址 | 预留大小 | 用途 |
|---|---|---|---|
| IMG0 | `0x000000` | `0x0A0000` | 第 1 幅 RGB565 图像 |
| IMG1 | `0x0A0000` | `0x0A0000` | 第 2 幅 RGB565 图像 |
| IMG2 | `0x140000` | `0x0A0000` | 第 3 幅 RGB565 图像 |
| IMG3 | `0x1E0000` | `0x0A0000` | 第 4 幅 RGB565 图像 |
| AUDIO_RING | `0x280000` | `0x040000` | 256 KiB 音频环形缓冲 |
| WORK | `0x2C0000` | `0x140000` | 目录 / CRC / 转场 / 压力测试工作区 |
| UNALLOCATED | `0x400000` | 约 4 MiB | 安全余量，以控制器可见容量为准 |

单槽容量核对：640 × 480 × 2 byte（RGB565）= 614400 = `0x96000` ＜ `0x0A0000`，有余量。

> ⚠ 与参考例程的差异：参考例程 `lab_ex4_tf` 采用 RGB888 + 32bit 数据位宽，
> 帧像素数 307200、双缓冲槽地址定义完全不同。**两套地址禁止混用**，
> 本项目的地址一律以本表为准。

> ★★ **本表的唯一代码来源是 `rtl/include/pixel_format_defs.vh`**（每个地址一个
> `` `SV_`` 宏）。`frame_buffer_manager` / `frame_writer` / `bmp_unpack` /
> `video_read_dma` 等模块一律引用这几个宏，**业务模块里禁止再出现裸物理地址或
> 第二份地址副本**。改地址只改这一个文件（v1.7 落实，此前有 4 个模块各抄了一份
> 常量，属于同一个常量有多份副本的结构性风险）。
>
> 同一文件里还定义了帧几何（`` `SV_FRAME_WIDTH `` / `` `SV_FRAME_BYTES `` /
> `` `SV_FRAME_PIXELS ``）与像素格式字节数，理由同上。
>
> ★ 命名空间提醒（v1.7 更正）：Verilog 宏只在写成 `` `名字 `` 时才展开，
> 裸标识符**不参与宏展开**。所以 `` `SV_FRAME_WIDTH `` 与模块里的
> `parameter FRAME_WIDTH` **不会命名冲突**——加 `SV_` 前缀不是为了避开编译冲突，
> 而是为了让读代码的人一眼分清"全项目常量"与"本模块可被顶层覆盖的参数"。

---

## 六、错误码表（B 链）

### 6.1 对外错误码（团队冻结，手册表 9-3）

UART / C 侧可见的事件码。**全队统一，任何一方不得自行扩展或改义。**

| 码 | 含义 | 来源 | 默认动作 |
|---|---|---|---|
| `0x01` | SD 初始化失败 | B | 进 WARNING，提示音 |
| `0x02` | 扇区读超时或 CRC 错 | B | 有限次重试后报 E |
| `0x03` | 媒体文件非法（目录项、簇链或 BMP 头） | B | 跳过该图并计数 |
| `0x04` | SDRAM 读写校验失败 | B | 升级到 SAFE 或 DEGRADED |
| `0x05` | 视频读 FIFO 欠载 | A | 计数并上报 C |
| `0x06` | 帧交换握手超时 | A/B | 保持当前块并上报 |
| `0x07` | WAV 编码或采样率不支持 | B | 使用提示音回退 |
| `0x08` | 音频欠载 | C | 输出零样本并计数 |
| `0x09` | 看门狗超时 | C | 锁存原因，进 SAFE |

### 6.2 B 链内部细分码 `err_detail[7:0]`

对外 `0x03` 一个码覆盖了"目录项 / 簇链 / BMP 头"三大类共十几种失败，
`0x02` 也分不清是超时还是 CRC。调试和留证必须知道**具体是哪一条校验挂了**，
所以 B 链内部另设一字节细分码，随 `error_report` 一起送：
`evt_type = 对外主码`，`evt_value[15:8] = err_detail`，`evt_value[7:0] = err_src`。

| 细分码 | 主码 | 含义 |
|---|---|---|
| `0x00` | — | 无错误 |
| `0x11` | `0x01` | CMD0 / CMD8 / ACMD41 协商失败 |
| `0x12` | `0x01` | 卡无 OCR 响应 |
| `0x21` | `0x02` | 命令响应超时 |
| `0x22` | `0x02` | 数据 CRC16 校验失败 |
| `0x23` | `0x02` | 数据起始 token 异常 |
| `0x31` | `0x03` | BPB 非法 |
| `0x32` | `0x03` | 非 FAT32 |
| `0x33` | `0x03` | 根目录项越界 |
| `0x34` | `0x03` | 簇链成环 |
| `0x35` | `0x03` | EOC 异常 / 簇号越界 |
| `0x36` | `0x03` | 文件长度不足 |
| `0x37` | `0x03` | BMP 签名非 BM |
| `0x38` | `0x03` | BMP DIB 头长度不足 40 |
| `0x39` | `0x03` | BMP 尺寸非 640×480 |
| `0x3A` | `0x03` | BMP planes / bpp / compression 不合法 |
| `0x3B` | `0x03` | BMP 像素偏移或长度越界 |
| `0x3C` | `0x03` | 合法图片少于 4 幅 |
| `0x41` | `0x04` | SDRAM 初始化失败 |
| `0x42` | `0x04` | SDRAM 写回读校验失败 |
| `0x71` | `0x07` | WAV 非 RIFF / WAVE |
| `0x72` | `0x07` | WAV 非 PCM（format code ≠ 1） |
| `0x73` | `0x07` | WAV 采样率非 48 kHz |
| `0x74` | `0x07` | WAV 非 16 bit 或非立体声 |
| `0x75` | `0x07` | WAV 缺失（同编号文件不存在） |
| `0x76` | `0x07` | 音频环形缓冲写溢出 |

> 变更说明：v1.0 曾把细分码直接当作对外码使用（`0x10`–`0x60` 分段方案），
> 与手册表 9-3 冲突，已在 v1.1 改为"对外主码 + 内部细分码"双层结构。

---

## 七、决策记录

| 编号 | 决策点 | 结论 | 理由 | 日期 |
|---|---|---|---|---|
| D-1 | `file_index` 索引表的对外形式 | **单口查表式**：`sel_slot` + `sel_first_clus` / `sel_size` / `sel_valid`；另用 `file_valid[3:0]` 暴露全貌 | `slot_writer` 顺序写槽，同一时刻只需当前槽信息；综合即 4:1 mux，最省资源；槽数变化只改位宽 | — |
| D-2 | 像素 FIFO 读出方式 | **FWFT（Show-Ahead）**，`OUT_REG = Disable` | 从结构上消灭"画面整体右移 / 行首缺像素"这一最难查的故障；A 侧无需计算总延迟 L；参考工程像素读路径已验证该配置可用；25.175MHz 像素质相对 125MHz mem_clk 很慢，组合路径不构成关键路径 | — |
| D-3 | 帧交换跨域手段 | toggle 电平翻转 + mailbox 锁存 | 手册 7.15；单拍脉冲跨域必然丢事件 | — |
| D-4 | 槽地址语义 | 全部使用逻辑字节地址，物理地址转换只发生在 `mem_ctrl` | 手册 7.6.2；换 wrapper 版本时全链地址无需改动 | — |
| D-5 | 错误码结构 | **双层**：对外码沿用手册表 9-3（`0x01`–`0x09`），B 链内部另设 `err_detail[7:0]` 细分码随事件一起送 | 手册表 9-3 是团队冻结口径，不能自行扩展；但 `0x03` 一个码覆盖十几种失败无法调试与留证 | v1.1 |
| D-6 | 音频 CDC FIFO 读出方式 | **FWFT**，与像素 FIFO 统一 | 与 D-2 同理；全链只保留一种 FIFO 语义，降低 A/C 双方理解成本与出错面 | v1.1 |
| D-7 | WAV 接受条件 | 只收 **PCM format code 1 / 48 kHz / 16 bit / 立体声**；其余一律对外码 `0x07` 并回退提示音 | 手册 8.6 明确该接受条件由 B 保证；采样率不符时无法用 48 kHz 节拍播放 | v1.1 |
| D-8 | 音频环形缓冲实现位置 | 放在 SDRAM `AUDIO_RING` 区（`0x280000`，256 KiB），B 独占读写 | 手册 7.16.3 与 2-3 地址表；SD 慢读与 48 kHz 连续消费必须解耦 | v1.1 |
| D-9 | "命名冲突"的定性与处理范围 | 只修**真不一致**（4 处文件名/归类与现结构不符）+ 补结构缺口（2 个头文件、2 个 CRC 通用件）；**不做**全量照搬参考目录树。并且把"同一个常量有多份副本"当作比"名字"更严重的问题来修 | ① 宏与裸标识符是两个命名空间（`` `FRAME_WIDTH `` 与 `parameter FRAME_WIDTH` 不会编译冲突），所以"命名冲突"这个说法本身需要更正；② 同一个地址/几何量有 4 份副本，改一处漏一处才是真正的上板风险；③ 本项目自定原则反对一次建 150 个空 RTL | v1.7 |
| D-10 | 公共 CRC 的形态 | `crc16_ccitt` / `crc7` 都做成**纯组合、无状态**的"下一拍值"步进器，不挂 valid/ready | 两个调用方用法不同：`sd_sector_reader` 逐字节收（1 级），`frame_writer` 一次吃 4 字节（4 级级联）；带状态就会有一方不得不在外面再拼时序。要流式使用，外面挂一个累加寄存器即可 | v1.7 |

### 被否决的方案（留档，避免重开讨论）

| 方案 | 否决理由 |
|---|---|
| `file_first_clus` 用 4 个独立端口 | 相比扁平总线只是把"数组切片"换成"手写 4 路 case"，并未省掉选择逻辑，却要付出端口膨胀 + 改槽数就要改所有例化点的代价 |
| 同步读（Normal）像素 FIFO | 必须精确预取 L 拍，L 依赖 IP 配置与两域时钟关系，换版本要重算，是最容易导致画面右移的方案 |
| 细分错误码直接作对外码（v1.0 做法） | 与手册表 9-3 冲突，会让 UART 侧和 C 的可靠性链对不上码表，已改为双层结构 |
| 音频走外部 I²S Codec（老版手册做法） | 声音不进 HDMI 流，终端枚举不到音频设备，**不满足 B04**；手册 8.6 已作技术纠错 |
| 音频直接由 B 打包进 HDMI 数据岛 | 越过 B 的职责边界（7.17）；ACR / Audio InfoFrame / 样本包属 A/C |

---

## 八、待确认项

| 编号 | 待确认内容 | 影响方 | 状态 |
|---|---|---|---|
| O-1 | `bmp_unpack` 的 RGB565 转换是**舍入**还是**截断** | A / B | 待定 |
| O-2 | 像素读 FSM 的行前预取策略：需要预取几拍（FWFT 下 L≈0，但 SDRAM 突发边界仍需覆盖） | A / B | 待实测 |
| O-3 | `mem_arbiter` 突发长度（建议 16 或 32 word） | B | 待定 |
| O-4 | SD 各等待态超时拍数：已给初值（响应 160k 拍 = 1.6ms，数据令牌 10M 拍 = 100ms，ACMD41 总轮询 200M 拍 = 2s，卡忙 25M 拍 = 250ms），需实测正常路径最大耗时后回填 | B / C | 已给初值，待实测 |
| O-5 | `swap_ctrl` 握手超时 `TIMEOUT_N` | A / C | 待定 |
| O-6 | 是否需要 E01 转场（滑动切换）所需的第二组读带宽 | A / B | 待定 |
| O-7 | 音频链路（B04）的 WAV 解析端口定义 | B / C | **已定义**，见 §3.6（v1.1） |
| O-8 | 音频轨读取与 BMP 装载如何分时复用 `file_stream` 与 `sd_sector_reader` 的调度顺序 | B | 待定 |
| O-9 | 为满足"图像提交与首个新音频样本相差不超过一帧"，切图前需预取多少对样本（按 60fps 一帧估算约 800 对） | B / C | 待实测 |
| O-10 | `pcm_ring` 环形容量的最终取值（当前按取满 256 KiB 设计，是否留一部分给 WORK 区未定） | B | 待定 |
| O-11 | `sd_sector_reader` 目前只实现 CMD17 单扇区；CMD18 多扇区读（含 STOP_TRANSMISSION）未实现，`rd_len` 必须为 1，否则明确报错。带宽优化阶段再补 | B | 待实现 |

---

## 九、变更历史

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | — | 初版：B 链 12 个模块接口 + A/B 边界 + 地址表 + 错误码表 | B |
| v1.1 | — | 新增 §3.6 音频链（`wav_parser` / `pcm_ring` / `audio_cdc_fifo` / PCM Sample Interface），关闭 O-7；`file_index` 增加 WAV 索引口；错误码改为"对外主码 + 内部细分码"双层结构（修正与手册表 9-3 的冲突）；CDC 约定补充音频域两行并统一 FIFO 复位极性警告；新增决策 D-5–D-8 | B |
| v1.2 | — | **落地阶段 1–5 实现**（`safevision/rtl`）：`spi_master` 的 `cs_n` 由输出改为**输入**、`clk_div` 放宽到 16bit；新增「SD 控制器 ↔ spi_master 字节总线」共用接口约定与两条实测踩坑记录（位计数口径、轮询态首发字节）；新增 `uart_tx` 登记；O-4 给出超时初值；O-11 登记 CMD18 未实现。仿真回归 13 项全通过（`safevision/sim/run_sim.ps1`） | B |
| v1.3 | — | **阶段 6 首块落地**：新增 `rtl/fs/fat32_boot_parser.v`（BPB 解析 + FAT32 判别位 + 派生地址计算），补全 §6.2 的 FAT/目录/簇链/BMP 细分码定义；卡模型升级为支持**多扇区内容**（`vol` 数组 + `mk_fat32_dbr`/`vol_set_le` 工具）；新增 `tb_fat32_boot_parser.v`（26 项断言，含签名错/非 FAT32/每扇区非 512 三个负向分支与恢复测试）。三个 testbench 合计 59 项断言全通过。新增 `docs/B链-待办与硬件验证清单.md`、`docs/B链-原理讲解-入门版.md` | B |
| v1.4 | — | **阶段 6 第二块落地**：新增 `rtl/fs/fat32_directory_scanner.v`（根目录遍历 + 四类跳过规则 + 跨扇区/跨簇 + 判环越界）；新增 `tb_fat32_directory_scanner.v`（57 项断言）。**接口修正**：`fat32_directory_scanner.ent_name` 由 `[10:0]`（11 bit，明显笔误）改为 `[87:0]`（11 Byte = 88 bit）；明确 `ent_index` 为"含跳过项的槽位号"、`scan_done` 为"结束即置位（成败都算）"、`dir_bad` 只表示结构异常。**新增全链约定**：从 `sd_sector_reader` 收字节必须用 `data_valid && data_ready` 门控。**新增实测踩坑**：FAT 入口是小端、高 4 bit 保留位需掩掉。卡模型新增 `mk_dir_entry` / `mk_dir_fill` 目录项构造工具。四个 testbench 合计 **116 项断言全通过** | B |
| v1.5 | — | **命名对齐**（新增「命名迁移表」）：目录树改为 `rtl/{include,common,storage,media}` + `verification/{unit,models}` + `tools`；`sd_init_fsm`→`sd_initializer`、`sd_sector_rd`→`sd_sector_reader`、`fat32_mount`→`fat32_boot_parser`、`dir_scan`→`fat32_directory_scanner`、`sd_card_model`→`sd_spi_card_model`；`sd_defines.vh` 拆成 `safevision_defs.vh` + `fault_code_defs.vh`。**阶段 7 落地**：新增 `fat32_cluster_walker.v`（簇链跟踪，被 `fat32_directory_scanner` 与 `file_streamer` **共用同一份**，消除 v1.4 的重复判环逻辑）、`file_streamer.v`（接管原 `file_stream`）、`media/bmp_parser.v`（接管原 `bmp_check`）。新增 TB：`tb_file_streamer.sv`(49 项)、`tb_bmp_parser.sv`(41 项)。**新增实测踩坑 3 条**：① 下游取走字节的清零逻辑必须放在状态机之外，否则扇区末字节锁存后 `valid` 永不清、死等兜底超时；② 文件末字节正好落在扇区末字节时 `stop_pending` 要按同拍值判定，否则白跳一次簇、误报 `DET_FS_SHORT`；③ BMP 多字节字段同为小端。六个 testbench 合计 **206 项断言全通过** | B |
| v1.6 | — | **阶段 8–16 落地**（B 链主体完成）。新增 `rtl/memory/`：`mem_ctrl.v`（SDRAM IP wrapper，对外只暴露逻辑字节地址）、`frame_address_gen.v`（`slot_base+(y*W+x)*BPP`，行步长参数化）、`frame_writer.v`（一帧严格 307200 像素 + 抽样 CRC + `slot_valid`）、`frame_buffer_manager.v`（冻结地址表全 `localparam`，原子提交 `active_slot/slot_base/generation`）、`memory_arbiter.v`（固定优先级 + 单次占用上限 + 最长等待提权，防饥饿）、`video_read_dma.v`（水位驱动突发预取）、`frame_swap_ctrl.v`（`IDLE→WAIT_VBLANK→COMMIT→WAIT_ACK`，超时进 SAFE 保持画面）、`frame_swap_cdc.v`（toggle 同步 + mailbox 锁存）、`memory_bandwidth_monitor.v`。新增 `rtl/common/`：`rv_skid_buffer.v`、`sync_fifo.v`（`almost_full` 反压）、`fifo_health_monitor.v`（历史最低水位 + underflow/overflow）、`error_report.v`。新增 `verification/models/frame_memory_model.sv`（行为级，8 MiB/2M×32bit）。**阶段 6 收尾**：`file_index.v`（编号扫描 + 数字后缀排序 + 索引表冻结，新增 `idx_clear` 输入用于重扫）。新增 TB：`tb_file_index`(60)、`tb_common_fifo`(58)、`tb_frame_writer`(28)、`tb_frame_swap`(30)。**媒体格式层收尾**：`media/bmp_unpack.v`（BGR888→RGB565，`ROUNDING` 参数对应待确认项 O-1，行步长按公式算，`top_down` 双向统一成左上原点，按"像素数 == w×h"收尾）、`media/wav_parser.v`（RIFF/fmt/data 小端解析，**fmt 与 data 之间的未知块按 chunk size 跳过**，只收 PCM/2ch/48k/16bit）。新增 `tb_media`(75)。**错误码补登记**：`ERR_WAV`(0x07) 与 `DET_WAV_*`(0x71–0x76) 原先只写在本文档 §6.1/§6.2/D-7，代码里缺，已补进 `rtl/include/fault_code_defs.vh`（此前 `wav_parser` 只能临时用 `ERR_MEDIA_INVALID`，现已对齐文档）。十一个 testbench 合计 **457 项断言全通过** | B |
| v1.7 | — | **逐项核对命名，修掉最后 7 处真不一致 + 补 10 个缺口**（详见「命名迁移表」下的两个子表）。**重命名 4 处**：`wav_reader`→`media/wav_parser`、`fifo_health_monitor` 从 `common/` 移到 `memory/`、`sdram_model`→`models/frame_memory_model`、`tb_mem_write`→`tb_frame_writer`（文件+module+全仓引用+TB+脚本一次改净，对外契约不变）。**补头文件**：`rtl/include/pixel_format_defs.vh`（像素格式+帧几何+**冻结四槽地址表唯一来源**）、`rtl/include/event_code_defs.vh`。**★ 真正的结构性问题（比"名字"严重）**：同一个常量在 4 个模块里各存了一份副本——`frame_buffer_manager`（7 个地址+SLOT/LINE/FRAME 步长）、`frame_writer`（帧几何 6 个）、`frame_address_gen`（2 个）、`video_read_dma`（3 个），另有 `tb_frame_writer` 抄了两处期望值。现已全部改为引用 `` `SV_`` 宏，**parameter 一律保留**（几何量必须能被顶层覆盖），改地址从此只改一个文件。**★ 概念更正**：此前把这件事描述为"宏与 parameter 命名冲突"是**错的**——Verilog 宏只在写成 `` `名字 `` 时才展开，裸标识符不进宏展开，两者不会编译冲突（已用编译验证）；加 `SV_` 前缀是为了可读性。真正的问题是常量多副本。**补公共件**：`rtl/common/crc16_ccitt.v`、`rtl/common/crc7.v`（纯组合无状态步进器，见 D-10），并让 `sd_sector_reader`（删掉自己那份 `crc16_next` 函数，改例化 1 级）与 `frame_writer`（删掉 `crc16_next`+`crc16_word` 两个函数，改为大端 4 级级联）复用同一份实现。**补 TB**：新增 `tb_crc`(12，把 `SD_CRC_CMD0/8` 的 0x4A/0x43 反推出来钉死在对数上，并验 CRC16 XMODEM 标准向量 `123456789`→0x31C3)、`tb_fat32_cluster_walker`(33，`fat32_cluster_walker` 此前只随编译，**判 EOC/越界/判环三条收尾分支从未被仿真跑过**，本 TB 用伪 FAT 扇区直接驱动并覆盖跨扇区寻址)。**拆分 TB**（只搬位置不改断言）：`tb_frame_swap`→`tb_memory_arbiter`(7)+`tb_frame_swap_ctrl`(23)，`tb_media`→`tb_bmp_unpack`(44)+`tb_wav_parser`(31)。**回归 502 项断言 / 15 个 testbench 全通过**。另：把交付口径写成显式规则——新增「文档同步义务」表（本文档 + 待办清单 + 原理讲解 + README 四者的更新触发条件）、补一份真正的 `README.md`（仓库结构、跑仿真方法、状态总览、硬约定）、并把"开发基准＝手册 V2.0 / 三份文档必须同步"写进项目规则文件，避免后续会话遗忘。另补 §一「语言子集」一行（**`rtl/**` 一律 `.v` + Verilog-2001 子集，`verification/**` 用 `.sv` 允许 SystemVerilog**），并登记远端仓库改名：`desktop-tutorial` → `Safe_Vision_FPGA_2026` | B |
| v1.8 | — | **引入队友的项目管理覆盖包（目录骨架 + 管理文档），并把它的过期内容改对**。新增骨架目录：`.github/`（PR/缺陷/工作项模板）、`docs/{architecture,interfaces,requirements,management,verification,release}/`、`evidence/`（需求→测试→原始证据，7 类索引）、`safevision/{platform,build,assets}`、`safevision/rtl/{video,audio,control,safety,top}`、`safevision/verification/{subsystem,system,board}`、`safevision/tools/check_repo.ps1`（目录与 `run_sim.ps1` 引用自检，不需要 ModelSim）；`rtl/safety/` 是结构之外的补充（看门狗/故障/应急从 `control` 分出）。**这些目录只有 README 与命名计划，没有任何功能代码**（ADR-0001「只创建目录及说明，不生成假 RTL」）；文件落点规则见新增的 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)。`.gitignore` 换为覆盖包版本：白名单增加 `!/.github/` `!/evidence/`，新增排除 `*.lic` `*.key` `*.pem` `__pycache__/`，并允许 `evidence/**` 下的 `.log`/`.vcd` 原始证据进库。**接口契约、地址表、错误码、RTL 与 TB 全部未变，回归仍 502 项断言 / 15 个 testbench 全通过**（目录自检 `LAYOUT PASS`）。**★ 覆盖包按旧快照（48 个跟踪文件 / 27 个 RTL）制作，带进来的文档有多处过期，已逐项改对**：`module_registry.md` 里 `rtl/common/fifo_health_monitor.v`→`rtl/memory/…`、`rtl/media/wav_reader.v`→`wav_parser.v`，并补登 `crc16_ccitt.v`/`crc7.v`/`pixel_format_defs.vh`/`event_code_defs.vh`（RTL 27→29）；`test_matrix.md` 的 `tb_media`→`tb_bmp_unpack`+`tb_wav_parser`、`tb_mem_write`/`tb_frame_swap`→`tb_frame_writer`/`tb_memory_arbiter`/`tb_frame_swap_ctrl` 并补 `tb_fat32_cluster_walker`/`tb_crc`（TB 11→15）；`system_design.md` 的 `sdram_model.sv`→`frame_memory_model.sv`；`traceability.md` 的 `wav_reader`→`wav_parser`；断言数 457→502；`WORK_ITEMS.md` 里"待办清单仍有旧路径"的指控已作废（v1.7 已修）。另修本文件 §3.1 的 `实现: rtl/sd/spi_master.v` → `rtl/storage/spi_master.v`（真实过期路径），以及 `bmp_unpack.v` 注释里指向已不存在 TB 的 `tb_media` → `tb_bmp_unpack`。**另（同日追加）**：① **结构基准变更**——结构基准改为本仓库 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)，原参照物作废，且全仓对它的引用（含 RTL 头注释、模块小节标题、表头列名与历史行里的出处标注）已一并清除；② **全仓文档去绝对路径**：覆盖包带进来的本机路径（如 `D:\modeltech64_10.7\win64`）改为按变量名 `$MSIM_BIN` 描述，文档树根由队友本地的 `Safe_Vision_FPGA_2026/` 改为 `<仓库根>/`，`f:\...\` 占位路径改为相对路径。约定：**文档里只用仓库相对路径** | B |
| v1.9 | 2026-09-30 | 增补 A 板级 `clock_reset_ctrl` 的信号名、有效电平、时钟域、两拍释放和局部复位隔离；保持 B 链接口不变。PLL/IP 与板级时序待接入验证。 | A |
| v1.10 | 2026-10-02 | **新增 §3.7 板级 bring-up 顶层 `top_stage5_sector_rd`**（阶段 5 最小验证，不属产品链）：端口 / 引脚 / 网络名对照表、`CLK_FREQ/BAUD/TARGET_LBA/POWERUP_CYC` 参数、**50 MHz 不接 PLL 的 bring-up 取舍**（`SD_DIV_INIT=124` → 200 kHz、`SD_DIV_FAST=1` → 12.5 MHz、超时拍数墙上时间翻倍）、两 SD 模块共用一条 SPI 总线的 `init_done` 二选一与 `sd_ncs` 取与、以及 UART 反压握手口径。**B 链既有端口、地址表、错误码一字未变。** 同时写入 `pin.adc` / `timing.sdc`（引脚逐个按 `2_FPGA.pdf` / `6_EX_DEVICE.pdf` 核对，并与厂商同器件例程交叉验证）；`uart_txd = D12`（网络名 `TXD`）**已由开发板手册的串口引脚分配表 + 图2-10 CH340G 原理图确认为 FPGA 发送脚**（板载 USB-UART，无需外接模块）。新增 `tb_top_stage5_sector_rd.sv`（T1–T4，顶层仿真：完整命令序列 / CMD17 参数 1000 / 512 Byte 逐字节与卡模型一致 / 顶层到成功态），B 回归升至 **507 项断言 / 16 个 testbench**。另把 `run_sim.ps1` 的 ModelSim 路径改为 `-ModelSimBin` 参数 + `MSIM_BIN` 环境变量（与 `run_clock_sim.ps1` 同口径，删除写死的本机路径）。
**★ 同日修复 TD 综合才暴露的多驱动问题**：`sd_initializer.v` 与 `sd_sector_reader.v` 的 `bdata` 同时被「字节引擎」和「主状态机」两个 `always` 块赋值（字节引擎复位分支多写了一次 `bdata <= 8'hFF`）。**ModelSim 编译/仿真都不报错**（两个 always 块写同一 reg 在仿真里只是竞争），TD 综合 elaborate 时直接报 `HDL-8007 net 'bdata[7]' is constantly driven from multiple places` 并把该模块降级成黑盒。已把该复位赋值收归主状态机（单一驱动源），全仓静态复查确认没有同类问题。**接口与行为不变**，回归仍 507 项全 PASS。
**另（同日追加）**：`TARGET_LBA` 的**默认值从 `32'd1000` 改为 `32'd8192`**（端口/参数名/位宽都没变，只改默认值）：实测本机 TF 卡的**分区从物理扇区 8192 开始**，原定的 LBA 1000 落在分区前的空隙里、读出来是 512 个 `0x00`，两边全零会让逐字节比对失去证明力；改用分区首扇区 = FAT32 引导扇区（非零、可识别）。电脑侧参考值存 `evidence/board/lba8192_pc_20261002.bin`。同时修正待办清单 M-5 的预期值（bring-up 跑 50 MHz，SCLK 应为 200 kHz / 12.5 MHz，是 400 kHz / 25 MHz 的一半）。 | B |
| v1.11 | 2026-10-02 | **新增 §3.2.1「卷基址约定」与 `rtl/storage/mbr_parser.v`**（阶段 6）。缘由是**板级实测逼出来的**：FAT32 层内部一律用【卷内相对 LBA】（`fat32_boot_parser` 写死读 0 号扇区），但真实 TF 卡是分区的（实测本卡分区起始 = 物理扇区 8192，卡 0 号扇区是 MBR），直连必然 `mount_error`。约定：**FAT32 层不碰分区偏移，卷基址由 `mbr_parser` 解析并只在板级顶层加一次**（`sd_sector_reader` 地址 = 相对 LBA + `vol_base_lba`）。`mbr_parser` 对"无 0x55AA 签名 / 分区项为空 / 起始 LBA=0"三种情况**不报错**，按无分区表回退（`vol_base_lba=0`），只透传 SD 层错误；分区表字段为**小端**（`446+8..11` 起始 LBA、`446+12..15` 扇区数）。新增 `tb_mbr_parser.sv`（T1 有效 MBR / T2 无签名 / T3 空表项 / T4 起始 LBA=0，7 项断言），回归 **507 → 514 项断言 / 16 → 17 个 testbench，全 PASS**。**B 链既有模块的端口与行为一字未变**（不动已绿的 TB，只在顶层做一次加法）。 | B |
| v1.12 | 2026-10-02 | **新增板级顶层 `platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v`**（阶段 6–7）：上电 → SD 初始化 → `mbr_parser` → `fat32_boot_parser` → `fat32_directory_scanner`(+`fat32_cluster_walker`) → `uart_tx`(115200) 发**纯 ASCII 报告**。该顶层是 §3.2.1 卷基址约定的**唯一落地处**：`rd_addr_to_reader = bus_rd_addr + vol_base_lba`（`bus_rd_addr` 由状态在 mbr / boot / scanner / walker 四个请求方之间 mux；MBR 那一轮 `vol_base_lba` 尚为 0，同一加法器正好落卡 0 号扇区）。**引脚与 `pin.adc` 不变**（沿用 `clk`/`rst_n`/`sd_*`/`uart_txd`/`led[3:0]`，无新增引脚）。报告格式：纯 ASCII、大写十六进制、定宽、`\r\n` 行尾，形如 `MBR=.. BASE=..` / `BPS=.. SPC=.. NFAT=..` / `FATLBA=.. DATALBA=.. ROOTLBA=..` / `TOTSEC=.. TOTCLUS=..` / `ENT=..` / `E <idx> <11字节8.3名 hex> <attr> <first_clus> <size>` / `DONE`（失败为 `ERR=xx`）——**刻意全 ASCII，以规避串口工具文本模式把 `≥0x80` 字节换成 `U+FFFD` 的有损转换**。新增 `tb_top_stage6_fat32_mount.sv`（16 项断言）；`sd_spi_card_model` 增加 `VOL_BASE` 参数（默认 0 时行为逐项等价）以模拟分区卡。回归 **514 → 530 项断言 / 17 → 18 个 TB，全 PASS**。 | B |
| v1.13 | 2026-10-02 | **板级顶层 `top_stage6_fat32_mount` 两项收尾（M-10 的两个"外观项"）+ 新增连读阶段（M-6/M-8）。** ① **修报告头位宽错误**：`hdr_bits` 声明成 `[1471:0]`（184 Byte），但六段实际只有 `21+42+25+51+34+10 = 183` Byte，Verilog 在 MSB 侧补零 ⇒ 整份报告多一个前导 `0x00`（板上 450 = 1 NUL + 183 + 260 + 6 已证实）。改为 `[1463:0]` / `HDR_BYTES=183`，并对每段（HDR/ENT/RPT/ERR/DONE）保留"逐段相加 = 声明字节数"的核对注释。② **行尾改显式字节**：全部 `"\r\n"` → `8'h0D, 8'h0A`。**实测更正**：旧记录说"ModelSim 把 `\r` 当 0D、TD 当 0x72"——用 vlog 10.7 亲测，**ModelSim 也把字符串里的 `\r` 编成 `0x72`（字母 r）**，旧 TB 用同一转义所以"错得一样"、仿真自洽通过；板子上才是 `72 0A`。改显式字节后仿真与硬件都是真 CR。③ **新增 §3.8**：`RPT_N`（默认 `16'd100`）参数 + 连读阶段（M-6「同一 LBA 连读 100 次」/ M-8「拔卡不挂死」）——复用共享 `sd_sector_reader`（顶层第 5 个读请求方）、**卷基址仍只加一次**、连读阶段 `data_ready` 恒 1 排空 512 Byte、**失败也不提前退出**（跑满 `RPT_N` 次）、任一次超时/CRC16 错计 `BAD` 且末行改发 `ERR=02`；报告新增 `RPT=<total> OK=<ok> BAD=<bad>` 行，LED 新增 `9 = 连读进行中`。`tb_top_stage6_fat32_mount.sv` 扩到 **26 项断言**（含字节数 372/374、无前导 0x00、每行 CRLF、健康卡 `RPT OK=100 BAD=0`、拔卡场景在有限时间内进 ST_ERR 且 `ERR=02`）。回归 **530 → 540 项断言，18 个 TB 全 PASS**。**B 链既有模块的端口与行为一字未变**。 | B |
| v1.14 | 2026-10-02 | **新增 §3.9 板级顶层 `top_sdram_loopback`**（阶段 9 第一步 / 手册 7.9「SDRAM 先跑官方 Demo」）：把厂商 SDRAM 控制器接上，上电 → 等 PLL 锁定 → 等 IP 初始化完成 → 写图案 → 落地等待 → 读回比对 → UART 发**定长 71 Byte 纯 ASCII 报告**（`SV-SDRAM-LOOP` / `INIT=/LOCK=` / `W=/R=/CAP=/BAD=` / `DONE`，显式 `8'h0D`/`8'h0A`）。★ 三处新事实写进文档：① **EG4S20 的 SDRAM 是封装内硬核**（`EG_PHY_SDRAM_2M_32`，2M×32），55 根信号不出引脚 ⇒ `pin.adc` **不需要也不应该**加 SDRAM 引脚；② 应用侧协议：写是逐 word `App_wr_en`、读是**延迟应答式**（`Sdr_rd_en` 才是取数时刻），`Sdr_busy`/`Sdr_init_ref_vld` 在例程里纯直通从不参与判断，应用侧只需自负「突发留间隔 + 读写不重叠」；③ **本顶层没有 TB 也进不了回归** —— 控制器真正实现在三个**安路 RSA 加密**的 `sdr_*.enc.v` 里，只能由 TD 解密，验收只有"上板读报告"一条路。同时把厂商 IP 落进 `ip/sdram/`（应用级 `sdram.v` + `global_def.v` + 三个 `.enc.v` + `sdram.ipc`）与 `ip/pll/`（`sys_pll`/`video_pll`）。★ 纠一个我上一步的复制错误：例程里**有两个同名 `sdram` 模块**，`IP/sdram.v` 是引脚级 PHY 外壳（例程顶层没用、`.al` 里也没登记），`SD/sdram.v` 才是被 `sdram U3(...)` 例化的应用级控制器；本仓库只保留后者。★ `timing.sdc` 新增 `derive_clocks`：接了 PLL 之后不加它，125 MHz 域就没有时钟定义、**STA 会是假通过**。TD 工程 `safevision.al` 已登记上述文件并把 `TOP_MODULE` 切到 `top_sdram_loopback`（回退只需改回 `top_stage5_sector_rd`）。回归不变：**540 项断言 / 18 个 TB，全 PASS**；`check_repo.ps1` → `LAYOUT PASS`；新顶层过 `vlog` 编译检查。 | B |
| v1.15 | 2026-10-02 | **§3.9 补上验收结果：阶段 9 第一步（手册 7.9「SDRAM 先跑官方 Demo」）板级通过（条目 M-11-PASS）**。位流 22:01:24 下载后 UART 收到 **71 Byte**：`SV-SDRAM-LOOP` / **`INIT=01 LOCK=01`** / **`W=1000 R=1000 CAP=1000 BAD=0000`** / `DONE`，与设计值**一字不差**（真 CRLF、无前导 `0x00`）。含义：`Sdr_init_done` 在 16 ms 超时窗内到齐；**`sys_pll` 锁定成功**（顺带证明"顶层把 C0 留空"不影响 `FEEDBK_PATH=CLKC0_EXT` 的反馈支路）；写 4096 word / 发 4096 次读命令 / **收齐 4096 word**（控制器一条读命令都没丢）；**32 bit 数据逐字比对零错** ⇒ 32 位数据线与 16 KB 连续区间的地址译码全部正确。★ 本轮同时解决/记录的四件事：① **TD 的 `.al` 只是上次保存的快照、跑综合用的是内存状态**（双向都踩过：改磁盘 `.al` 不生效，GUI 保存又覆盖磁盘）；判定只信 `syn_1/run.log` 的 `elaborate -top`；② **TD 对"约束里出现顶层不存在的端口"是报错**（`HDL-1492`/`USR-8168`），故 `pin.adc` 拆成"公共 6 条 + `[SD-ONLY]` 4 条"，且两者的生效方式不同（`read_adc` 每次 Run 都读、`.al` 要重开 TD）；③ **"全局 SWNS 为负"的判定口径**（本例 -6.826 ns 100% 出在厂商硬核 PAD 路径，自研组全绿，厂商参考设计同数 -6.565）；④ 自研薄点：fabric 最差路径仅 +0.130 ns。**接口、字段、报告格式一字未改**；回归 540 项不变。 | B |


| v1.16 | 2026-10-03 | **系统 PLL 去重（A 的 `sv_system_pll` 收编 B 的 `sys_pll`）**。两套 PLL 输出频率相同（100/125 MHz），仅电气参数（A: Medium/13/4，B: High/29/2）与 B 独有的 C2 = 125 MHz@180° 不同。做法：**在 A 的 `sv_system_pll` 上新增 C2@180°**（`CLKC2_DIV 8` / `CLKC2_CPHASE 3` / `CLKC2_FPHASE 0`，`.ipc` 加 id=2 的 clock），**C0/C1 电气参数一字不动**；`top_sdram_loopback` 改为实例化 `sv_system_pll`；`safevision.al` 登记 `../ip/pll/sv_system_pll.v`；**删除 `ip/pll/sys_pll.v` / `sys_pll.ipc`**。`check_pll_profiles.py` 放宽为"按文件里是否有 `CLKC2_DIV` 判定输出集合 + 系统 PLL 的 C2 允许 180°"（相位判据在 0° 时与原文逐字等价，A 的其它 PLL 与 C0/C1 判据未放宽）；实跑 `check_pll_profiles.py` 输出 `result` 字段为 `PASS`。★ **B 链 RTL / 接口 / 错误码一字未改**，回归仍 **540 项 / 18 个 TB 全 PASS**；`check_repo.ps1` → `LAYOUT PASS`。★ **已重新综合 + 复测 M-11（2026-10-03 17:26:55）**：报文与 M-11 逐字节相同，证据条目 **M-11-PASS-2**（stage 9 的 PLL 电气参数随 A 变了） | B |

## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](clock_video_implementation.md)，端口/时钟域见 [A接口补充](A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](A_PUSH_SCOPE_20261002.md)。

## A 阶段十接口补充（v1.17，2026-10-03）

`video_pipeline` 在 pixel_clk 域将像素、x/y、hsync/vsync/de、pixel_valid、line_start/frame_start/active_frame_start 和 hblank/vblank 作为一个 bundle 无条件逐拍推进；全部端口统一 LATENCY 拍，默认 1，LATENCY=0 为组合旁路。默认像素宽度 24；接 B 的 RGB565 显式设置 PIXEL_WIDTH=16，坐标默认 12 位。低有效本域复位清空全链，置同步为不活动电平、消隐为 1。所有数据输入均须已完成 CDC 且同拍对齐；de 与 pixel_valid 独立。

完整端口名、精确采样边沿约定、逐级账本、与 B 的控制事件接线边界及实际测试结果见 [A_stage10_latency.md](A_stage10_latency.md)。原 B/C 接口、原始扫描 frame_start、四槽地址表和 B 上板顶层保持现行协议。该模块不是 FIFO、Frame Reader 或完整 HDMI 顶层。

| 版本 | 日期 | 接口变更 | 负责人 |
|---|---|---|---|
| v1.17 | 2026-10-03 | 新增 A 的 video_pipeline 固定 LATENCY 拍接口；全部像素/标签同拍，登记两个 TB、仿真入口和工程源文件。保留 B/C 既有端口与顶层。 | A |
| v1.18 | 2026-10-04 | 新增 A 基础四模块、测试图、同步字库、状态/坐标文字及四级 OSD；图形前端 RGB888，同域配置，全部扫描标签统一延迟 4 拍。B/C 产品接口、RGB565、地址表与回环顶层不变。详见 A_stages1_9.md。 | A |
