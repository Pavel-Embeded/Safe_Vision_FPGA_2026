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
| 版本 | v1.35（保留 v1.34 的 A 阶段11–15 补充契约；**新增 B 侧的应答**：[B链-整机集成-存储侧接线表.md](B链-整机集成-存储侧接线表.md) —— 把 A 的两段要求落成 14 根线的逐根接线表、单位、时序语义与"不该做什么"；并订正 `frame_swap_ctrl` 的误导注释、统一突发长度口径为 64） |
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
       BASE_ADDR(21'd0) TEST_WORDS(21'd1024) ADDR_SHIFT(11) ADDR_LOWSTEP(1)
       ROUNDS(32'd27_000_000) BURST_N(128) BURST_GAP(16)
       WR_DRAIN_CYC(512) RD_WAIT_TO_CYC(200_000)
```

**时钟**：板载 50 MHz → `sv_system_pll`：C0 = 100 MHz（外部业务端口留空，wrapper 内反馈保持连接）、C1 = 125 MHz = SDRAM 侧
`Clk`、C2 = 125 MHz **180° 相移** = `Clk_sft`。`timing.sdc` 因此新增 `derive_clocks`
（**不加的话 125 MHz 域无时钟定义、STA 是假通过**）。
**全部逻辑（含 `uart_tx`）跑 125 MHz 单域，刻意不做 CDC**：当前 B soak 报告 190 Byte，UART 仍是低速串行链路；把 `uart_tx` 也挂 125 MHz（`DIV = 125e6/115200 = 1085`，误差 0.006%）比引入跨时钟域更少变量。⇒ 本顶层**只有一个逻辑时钟域**。

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

**数据检查与测试图案**：mode 0 使用完整 21-bit 可逆签名；mode 1–5 轮换 LFSR、walking-1、walking-0、全 0/全 1 及相邻位交替。`sdr_pat_gen` 是唯一图案源，写/读两侧传地址和模式。比较流水先锁样本，再锁四个 byte-lane mismatch，最后提交 BAD/BAD0；`ST_RDWAIT` 等 `checked_cnt` 排空后才转态。UART 使用寄存器字节预取，在反压下保持 valid/data，报告索引只在握手成功后推进。当前源码默认参数为 1024 word、stride 2049、`ROUNDS=27,000,000`（约 10 分钟），报告 190 Byte；`ROUNDS=161,000,000` 是约 60 分钟的历史板测配置，不是当前源码默认值。原 M-11 的 71 Byte 与后续 B soak 报告是不同历史构建，不能混为当前 build 证据。

`ADDR_SHIFT=0, ADDR_LOWSTEP=0` 是连续步长 1；`BASE_ADDR=0`、`ADDR_SHIFT=11`、`ADDR_LOWSTEP=1`、`TEST_WORDS=1024` 是 stride 2049 的稀疏抽样。地址跨越 2M-word 范围，但不是每个 bank/row/column 或全部存储单元都逐一访问。详见 [SDRAM/PLL 核查修正版](B链-SDRAM接口与PLL时序核查.md)。本次 A+B 合并后构建尚需重新回归、STA 与板测，历史 B soak 不自动验收新 RTL。

**LED 状态码**：`1` 上电等待 / `2` 等 SDRAM 初始化 / `3` 写图案 / `4` 等写落地 /
`5` 发读命令 / `6` 等读回收齐 / `7` 发报告 / `8` 成功；失败显示错误主码低 4 位。

**报告格式（定长 190 Byte，纯 ASCII，显式 `8'h0D`/`8'h0A` 行尾）**
★ 2026-10-04 的两次扩容：71 → 136（加**配置行**与**首个错点行**）→ **190**
（加**轮次/图案模式行**与**累计搬运量行**，并给 `BAD0` 加上**轮次**）。

```text
行1  SV-SDRAM-LOOP                                 (13 + CRLF = 15 Byte)
行2  INIT=<2hex> LOCK=<2hex>                       (5+2+6+2  + CRLF = 17 Byte)
行3  CFG=<2hex><1hex> BASE=<6hex> N=<6hex>         (4+3+6+6+3+6 + CRLF = 30 Byte)
行4  RND=<8hex>/<8hex> PAT=<1hex>                  (4+8+1+8+5+1 + CRLF = 29 Byte)
行5  W=<4hex> R=<4hex> CAP=<4hex> BAD=<4hex>       (31 + CRLF = 33 Byte)
行6  TOT=<10hex>                                   (4+10 + CRLF = 16 Byte)
行7  BAD0=<8hex>:<6hex> E=<8hex> A=<8hex>          (42 + CRLF = 44 Byte)
行8  DONE                                          (4 + CRLF = 6 Byte)
```

- 行3 `CFG` = `ADDR_SHIFT`(2 位 hex) + `ADDR_LOWSTEP`(1 位 hex)；`BASE` = 起始 word 地址；
  `N` = **每轮** `TEST_WORDS`。**这些字段让采集件自描述**。
- 行4 `RND` = 已跑轮数 / 总轮数（`ROUNDS` 参数）；`PAT` = 本轮**图案模式**（0..5，含义见
  `rtl/memory/sdr_pat_gen.v` 头注）。
- 行5 `W/R/CAP/BAD` 都是**本轮**的计数。
- 行6 `TOT` = **累计比对字数**（40 位，不随轮次重置）⇒ 就是手册 7.12 要求的
  "用计数器统计一段时间内实际完成搬运的数据量"口径。
- 行7 `BAD0` = **首个不符发生在第几轮 : 哪个地址**（无错时哨兵 `FFFFFFFF:FFFFFF`）；
  `E` = 该地址**期望值**；`A` = 该地址**实际读回值**。

**soak（`ROUNDS` 参数）**：把「写 → 等落地 → 读 → 等收齐」当一轮重复 `ROUNDS` 轮，
**每轮换一种图案模式**（0..5 循环）。★ **出错立即停（fail fast）**：某轮不一致就不再跑
后面的轮次，直接出报告 —— 报告里的 `RND` 就是**出错那一轮**，不必等 soak 跑完。
`ROUNDS = 1` = 单轮行为；当前源码默认 `ROUNDS=27,000,000`（约 10 分钟）。★ 轮时长 **实测 ≈ 22 µs**（2790 拍 @125 MHz，1024 word
稀疏扫描）⇒ `ROUNDS ≈ 目标秒数 × 45_000`；**60 分钟约需 `ROUNDS = 1.6e8`**（32 位参数
上限 4.29e9 轮 ≈ 26 小时）。★ **soak 期间"没有输出"就是好消息**：出错会立刻出报告。

**默认参数 = 单轮全片稀疏扫描**：`ADDR_SHIFT=11` + `ADDR_LOWSTEP=1` + `TEST_WORDS=1024`
⇒ 步长 `(1<<11)+1 = 2049`，1024 个点铺满整个 2M word 空间。理想报告为
`CFG=0B1 BASE=000000 N=000400` / `RND=00000001/00000001 PAT=0` /
`W=0400 R=0400 CAP=0400 BAD=0000` / `TOT=0000000400` /
`BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000`。

> ★ 步长为什么是 `(1<<ADDR_SHIFT) + ADDR_LOWSTEP` 而不是纯 2 的幂：**纯 2 的幂步长会把
> 低位地址位固定住**（步长 2048 时 `a[10:0]` 恒为 0），列地址与行低位根本没被激励；
> 加 1 之后 `k*2049 = (k<<11)+k` ⇒ **每个地址位都在变**。旧的「连续扫描」=
> `ADDR_SHIFT=0, ADDR_LOWSTEP=1`（步长 1）。
> ★ 约束：`BASE_ADDR + (TEST_WORDS-1)*STRIDE` 必须 < 2^21，否则地址回绕、测试无意义。

判定：`W == R == CAP == TEST_WORDS` 且 `BAD == 0000` 才算过；`CAP < W` 说明有读命令没返回
（控制器丢命令），`CAP == W` 但 `BAD != 0` 才是真的数据错 —— 此时**先看 `BAD0/E/A`**。

**错误主码**（本顶层局部，非 §6 的团队对外错误码）：`01` = SDRAM 初始化超时（独立计数器）、
`02` = 读回不齐（独立计数器）、`03` = 数据不一致。

**★ 关于仿真**（2026-10-04 起口径变了，注意）：

- 厂商 SDRAM 控制器的真正实现是 `ip/sdram/sdr_as_ram.enc.v` 等三个**安路 RSA 加密**文件
  （IEEE-1735 `pragma protect`），PLL 则是 TD 的 `EG_PHY_PLL` 宏 —— 两者 ModelSim **都编译不了**。
  所以**顶层本身没有直连真 IP 的 TB**，**协议层面的验收方式只有上板 + 读 UART 报告**。
- ★ **应用侧检查器有两套分离的回归入口，勿把模型混编**：
  1. B/ModelSim：`run_sim.ps1` 编译 `vendor_ip_stub.sv` 与 `tb_top_sdram_loopback.sv`；22 项图案测试 + 8 项顶层测试覆盖 6 模式、190 Byte soak 报告、轮次、fail-fast、第二轮 `BAD0` 定位。
  2. A/XSim：`run_sdram_loopback_sim.ps1` 使用 TD PLL functional model 和独立应用侧 `sdram` 模型；检查 mode 0 全 21-bit 签名反解、DQ 位覆盖、连续/稀疏 loopback、地址别名、最高 DQ 位翻转、初始化与缺失读返回超时及 UART 报告。
  两套测试各自有同名仿真替代模块 `sdram`；**不要放进同一个编译库**。A testbench 针对当前合并 soak top，不能保留旧 71 Byte 的预期；B-only 顶层 TB 仍单独检查 190 Byte 报告。
- ★★ **仿真效力边界**：A/B 模型都不模拟真实加密控制器、物理 DQ、刷新/CAS 实际行为或 AC/PVT 时序；应用侧 `BAD=0000` 不是 SDRAM 完整性证明。整合后的新 RTL 还必须重新运行对应仿真、重新综合布线，并用匹配的位流上板复测。

**IP 落点与来源**：`safevision/platform/anlogic_eg4s20_hx4s20c/ip/sdram/`
（`sdram.v` 应用级外壳 + `global_def.v` + 三个 `.enc.v` + `sdram.ipc`）、
`ip/pll/`（`sv_system_pll` / `sv_video_*_pll` / `sv_audio_pll`；系统 PLL 于 2026-10-03 去重为唯一一份）。均来自厂商例程包（工作区参考材料，本身不进仓库），
详见该目录 `README.md`。★ 例程里**有两个同名 `sdram` 模块**：`IP/sdram.v` 是引脚级 PHY 外壳
（例程顶层没用它），`SD/sdram.v` 才是被 `sdram U3(...)` 例化的应用级控制器 —— 两者不能同时
进同一个 TD 工程。本仓库只保留后者。

### 3.10 板级 bring-up 顶层 `top_stage10_framebuffer`（阶段 10 帧缓存回环）

```text
时钟域 : mem_clk 125 MHz（单一域）
职责   : 把一个 640x480 RGB565 帧写进 SDRAM 0 号槽，再整帧读回逐像素比对，
         经 UART 发纯 ASCII 报告；不是产品顶层 safevision_top.v

clk(R7,50MHz) / rst_n(A2) / uart_txd(D12) / led[3:0]     板级引脚（无 sd_*）
```

内部：`sv_system_pll`（C1=125M 逻辑、C2=125M@180° 给 SDRAM `Clk_sft`）+ `reset_sync`
→ `framebuffer_loopback_core`（可仿真核心：LFSR 源 → `frame_writer` → `mem_ctrl` →
`video_read_dma` 经 `mem_read_burst` → 像素 FIFO → 自检，见 §3.4）
→ `sdram_app_adapter`（通用 req/ready ↔ 厂商 `sdram` 的 App_* 口）→ 厂商 `sdram`
→ `uart_tx`（125 MHz 域，115200）。

报告（定长 **208 Byte**，纯 ASCII，行尾显式 `8'h0D`/`8'h0A`）：
`SV-FB-LOOP` / `INIT=<hh>` / `WR=<hhhhhh> CRC=<hh> SV=<hh>` / `RD=<hhhhhh> BAD=<hhhhhh>` /
`W0=<hhhhhhhh> W1=<hhhhhhhh>`（前 2 个读回 word）/
**`AM=<hhhhhhhh>`（地址斜坡探针 A：32 个回读的匹配位图，bit N=1 表示第 N 个等于期望）** /
**`AF=<hh>`（首个不符的序号，`FF` = 全对）** / **`AV=<hhhhhhhh>`（该序号上实际读回的值）** /
**`C0..C3=<hhhh>`（探针 C：字 0x1004 起 4 个回读值，低 16 位）** /
**`B0..B3=<hhhh>`（探针 B：字 0x1035 起 4 个回读值，低 16 位）** /
`BF=<hhhhhh>`（首个不符像素索引，0 = 全对）/ `DONE`。
判据（自比）：`INIT=01` 且 `WR=RD=04B000`（307200）且 `CRC=01` 且 `SV=01` 且 `BAD=000000` 且
`W0=59C3ACE1 W1=670FB387` 且 **`AM=FFFFFFFF`、`AF=FF`、`AV=00000000`** 且
**`C0..C3=1004/1005/1006/1007`** 且 **`B0..B3=1035/1036/1037/1038`** 且 `BF=000000`。

★ **地址斜坡探针（2026-10-03，取代旧的 `SC=` 固定图案自检）**：写进去的**值 = 它自己的
字地址**，所以回读值直接就是"这份数据当初被写在哪个地址" ⇒ 一次上板即可读出错位量 / 步长 / 丢没丢。
· 探针 A：字节 `0x4000`（字地址 `0x1000`，**16 对齐**）起连续写 32 个 word（= 两段 16 字写突发），
  再从同一基址顺序读回 32 个 —— 但**不存回读数**（那要 512 个寄存器、会把 125 MHz 的报告通路
  时序打穿），改为**边读边与期望值比对**，只报 `AM/AF/AV` 三个数；
· 探针 C：A 读完后**另起一次预取**只读 4 个字（字 `0x1004` 起）。
  ★ 这是**区分"写错"还是"读错"的关键**：读侧若"一次突发内只推进 4 个字"，任何新突发的**前 4 个**
  总是对的 ⇒ C 回读的就是字 `0x1004..0x1007` 的**真实内容**（C=1004..1007 ⇒ 写侧正常；
  C=1000..1003 ⇒ **写侧**也错）；
· 探针 B：字节 `0x40D4`（字 `0x1035`，**≠16 对齐**）起写 4 个、读回 4 个（"非对齐基址"对照）。
★ C/B 两行只报低 16 位（探针地址都在 `0x1000~0x1038`，低 16 位足以唯一识别；全局判据是 `BAD`）。
★ 三个探针都在帧槽 0 内，随后被整帧写入覆盖。

★ `framebuffer_loopback_core` 的报告索引为 9 位**倒计数**取值，索引里**不含减法器**。
**STA 记录**：2026-10-03 那一版用 `RPT_LEN-1-rpt_sel` 的加法器 + 2832 bit 向量 + 512 个回读
寄存器，自研组 `clkc[1]→clkc[1]` 从 **+0.030 ns 掉到 −1.083 ns / 475 个违例端点**（最差路径全在
`ra_reg → rpt_vec 选择 → u_uart_tx/shifter`）；改为"边读边比对 + 16 位抽样 + 208 Byte 向量"后重做。
★ 2026-10-03 晚再收一刀：208 Byte 报告 mux 由"1664 bit 向量 + 变址选取"改成
**13 块 × 16 Byte 两级 mux + 一块 16 Byte 的块寄存器**（第 1 级 13:1×128bit → `blk_q`；
第 2 级 16:1×8bit → `rep_data`），把"大 mux → 跨芯片送 `uart_tx`"的长走线切在中间。
★ 同日第三刀：report18 复算后自研组只剩 **−0.081 ns / 2 违例端点**，且这两条路径都是
`rpt_idx → 9 位减法器（4 级 ADDER）→ rpt_dn[5]（扇出 **195**）→ 块 mux`（那个减法器本来只给
状态机算 `rpt_idx-1`，却被综合塞进了**块选择端**）。改法 = **块号提前一拍存进 5 位寄存器
`blk_nxt`**（恒 = `block(rpt_idx-1)`，只在"下一字节跨块"时 -1）⇒ 关键路径变成
`blk_nxt（寄存器）→ 块 mux → blk_q`，减法器退回成**只喂 5 个 bit** 的轻负载路径。
★ **对外的 `rep_valid` / `rep_data` 接口与延迟都不变**（无额外 priming 拍：`blk_q` / `blk_nxt`
与 `rpt_idx` 在同一时钟边沿更新），**报告字节流逐字节不变**（`tb_framebuffer_loopback_core` 的 T9 守住）。
★ report19 复算确认第 3 刀**生效**：块 mux 路径 **−0.081 → +0.058 ns（通过）**；但自研组的全局最差
换到了**适配器的突发基址 / 读命令计数通路**（`rfbase` / `wbase` / `rcmd_i`，`sdram_app_adapter.v`），
−0.218 ns / 3 违例端点。⇒ 自研组现有**约 10 条路径挤在 0.25 ns 以内**，**本顶层（bring-up 自测顶层）
已决定收手**，时序债留到**整机集成后在 A 的 `safevision_top` 上重跑 STA**（详见
`docs/B链-待办与硬件验证清单.md` §2.5 的"决策"）。

★ **本顶层含安路加密 SDRAM IP ⇒ 无 TB、进不了 ModelSim 回归**；其可仿真部分
（`framebuffer_loopback_core` + `mem_read_burst`）由 `tb_framebuffer_loopback_core.sv` 覆盖（11 项）；
**适配器 `sdram_app_adapter` 本身不含加密件，另有 `tb_sdram_app_adapter.sv` 覆盖（7 项）**，
上板步骤见 `docs/B链-待办与硬件验证清单.md` §2.5。
★ 新事实（写进本仓，供后续复用）：厂商 `sdram` 的应用口是**脉冲式**（`App_wr_en`/`App_rd_en`
连发、地址**每拍自增**、`Sdr_rd_en` 单拍应答数据），与 `mem_ctrl` 的通用 req/ready 口**协议不同**，
中间必须有 `sdram_app_adapter`；`memory_arbiter` 的读通道按"`ready` 与 `data_valid` 同拍"
设计，**不能**直接接 `mem_ctrl`/`frame_memory_model`（会少收 1 拍）。
★ **突发形态唯一正确写法 = 照抄 M-11**（`top_sdram_loopback.v`，板上跑通 4096 连续 word、
`BAD=0000`）：**`App_*_en` 连发 N 拍 + `App_*_addr` 每拍自增 + 突发之间静默若干拍 +
读侧按 1:1 收响应**。
★ **已定案（2026-10-03 板上实测 + 单元 TB 双证）**：上一版适配器把**读预取的地址推进挂在
`Sdr_rd_en` 上**（应答延迟窗内地址被"钉住"不前进），板上表现为**一次 16 字预取里只有前 4 个
读回是对的、第 5 个起回到起点值**（`A0..A3=1000 1001 1002 1003`、`A4..AF` 重复这 4 个），
与帧级 `BAD` 恰为 **3/4**（= 每 4 个读回只有 1 个对）完全吻合。⇒ 读引擎已按 M-11 形态重写
（发命令/收响应两条独立计数 + 1:1 配对 + `RB_GAP=16` 静默），并由 `tb_sdram_app_adapter.sv`
守住"**连发期间地址必须每拍自增**"这条约束。
★ **2026-10-03 晚（第 3 轮板上报文 + 单元 TB）再修三处** —— 都在 `sdram_app_adapter.v`：
① **未命中就要起预取**（触发条件不得要求 `rcnt==0`）：否则"跳到缓冲外的地址、而缓冲还没排空"
   会**永久死等**（板上实测：探针 C 只取了 4 个 ⇒ 缓冲还剩 12 个 ⇒ 探针 B 读 `0x1035` 死等 ⇒
   看门狗 `ERR=06` 直接出报告 ⇒ 报文 `B0..B3=0000` 且 `WR=000000`，整帧写入全被跳过）。
   同一处 bug 也会在**整帧读的第一笔**发作（帧从 word 0 起，而缓冲里还是探针区的数据）。
② 命中判据改用寄存器 **`rexp`**（缓冲里下一个待供给字的地址）代替 `rbase + rhead`
   ⇒ **去掉一个 32 位加法器**（report15 里它经 `ready` 进核内状态机成了最差路径 −1.562 ns、
   `Logic Level 7` 含 `ADDER=2`）。
③ 读侧 `ready` 改成**寄存器输出 `r_go`**（`r_go <= r_serve && !r_go`，供给提交挂在 `r_go` 上）
   ⇒ 把"适配器内部 → 核内状态机"这条长组合路径切成两段；**写侧 ready 不经过它，写握手时序不变**。
   ★ 注意 `r_go` 与 `!r_go` 的自门控是必须的：否则一次供给会被连续给两拍 ready（重复供给）。

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


| v1.16 | 2026-10-03 | **系统 PLL 去重（A 的 `sv_system_pll` 收编 B 的 `sys_pll`）**。两套 PLL 输出频率相同（100/125 MHz），仅电气参数（A: Medium/13/4，B: High/29/2）与 B 独有的 C2 = 125 MHz@180° 不同。做法：**在 A 的 `sv_system_pll` 上新增 C2@180°**（`CLKC2_DIV 8` / `CLKC2_CPHASE 3` / `CLKC2_FPHASE 0`，`.ipc` 加 id=2 的 clock），**C0/C1 电气参数一字不动**；`top_sdram_loopback` 改为实例化 `sv_system_pll`；`safevision.al` 登记 `../ip/pll/sv_system_pll.v`；**删除 `ip/pll/sys_pll.v` / `sys_pll.ipc`**。`check_pll_profiles.py` 放宽为"按文件里是否有 `CLKC2_DIV` 判定输出集合 + 系统 PLL 的 C2 允许 180°"（相位判据在 0° 时与原文逐字等价，A 的其它 PLL 与 C0/C1 判据未放宽）；实跑 `check_pll_profiles.py` 输出 `result` 字段为 `PASS`。★ **B 链 RTL / 接口 / 错误码一字未改**，回归仍 **540 项 / 18 个 TB 全 PASS**；`check_repo.ps1` → `LAYOUT PASS`。**待重新综合 + 复测 M-11**（stage 9 的 PLL 电气参数随 A 变了） | B |

| v1.17 | 2026-10-03 | **新增 §3.10 阶段 10 板级顶层 `top_stage10_framebuffer` + 三个新模块**（`rtl/memory/framebuffer_loopback_core.v`、`rtl/memory/mem_read_burst.v`、板级 `sdram_app_adapter.v`）：整帧 640×480 写入 → 整帧读回 → 逐像素比对 → 定长 73 Byte ASCII 报告。★ 两条**新事实**：① 厂商 `sdram` 的应用口是脉冲式，与 `mem_ctrl` 的通用 req/ready 口协议不同，需 `sdram_app_adapter` 桥接；② **`memory_arbiter` 的读通道按"`ready` 与 `data_valid` 同拍"设计**，直接接 `mem_ctrl`/`frame_memory_model` 会**每 16 word 突发少收 1 拍**（读方永久等待）——故阶段 10 用 `mem_read_burst`（一次 1 个在途请求）替代，`memory_arbiter` 的读路径留给阶段 13 重新对接。**B 链既有端口/地址表/错误码一字未改**；新增 `tb_framebuffer_loopback_core.sv`（9 项），回归 **540 → 549 项断言 / 18 → 19 个 TB，全 PASS**。板级顶层含加密 IP 故无 TB、未上板。 | B |

| v1.18 | 2026-10-03 | **阶段 10 定位用「地址斜坡探针」取代旧的固定图案自检（仅 `framebuffer_loopback_core.v`）**。把 `S_RAMP` 从"向 4 个连续地址写 1111/2222/3333/4444 再读回"换成**写进去的值 = 它自己的字地址**的两个探针：① 探针 A：字节 `0x4000`（字地址 `0x1000`，**16 对齐**）起连续写 **32** 个 word（值 `0x1000..0x101F`，正好两段 16 字写突发），再从同一基址**顺序读回 16** 个；② 探针 B：字节 `0x40D4`（字地址 `0x1035`，**≠16 对齐**）起写 **4** 个、读回 **4** 个，用以区分"整段偏移"与"突发边界/漏斗式缓冲"。回读值直接就是"这份数据当初被写在哪个地址" ⇒ 一次上板即可读出**错位量 / 步长 / 丢没丢**。报告 **149 → 354 Byte**（删 `SC=`，加 `A0..AF=` 与 `B0..B3=`）；报告索引改为**倒计数**（`rpt_vec[8*rpt_idx +: 8]`、`rpt_idx` 9 位、从 353 递减），目的是**去掉索引里的减法器**（上一版 `RPT_LEN-1-rpt_sel` 的加法器曾被 STA 点名为最薄路径）。探针全程加**无进展看门狗**（`mem_error` 或连续 1e6 拍无 `ready`/`rdata_valid` ⇒ `ERR=06`，沿用既有"mem 超时"码），保证上板有界（原本探针挂住会只停在 LED=1 且不出报告）。★ **对外接口 / 地址表 / 错误码一字未改**。★ 动机证据：整帧仍有 ≈3/4 像素错，且 `BAD=038400` 恰为帧总 word 数 153600 的**精确 3/4**、`W0/W1` 与核心 LFSR 逐步推算完全一致（前 2 个 word 的写读都对）；而 `BF=00000A` 与"从 word 0 开始的周期 4"不自洽 ⇒ 单点索引不可靠，必须用斜坡。回归 **549 → 551 项断言 / 19 个 TB 全 PASS**（`tb_framebuffer_loopback_core` 9 → 11 项：新增 T10「探针写值 = 字地址（36 word）」与 T11「探针段内地址严格连续、两段基址 = 0x1000 / 0x1035」）。 | B |

| v1.19 | 2026-10-03 | **阶段 10 定案 + 两处修复（`framebuffer_loopback_core` 报告瘦身 / `sdram_app_adapter` 读引擎重写）+ 适配器首次进回归**。① **板上探针判决**：新报告（354 Byte）实测 `AM` 之前的信息为 —— `A0..A3=1000 1001 1002 1003` 对、**`A4..AF` 又重复回这 4 个值**，而 `B0..B3=1035..1038` 全对 ⇒ **一次连续读突发里读地址只推进 4 个字就回绕**，与帧级 `BAD=038400`（恰为 153600 的 **3/4** = 每 4 个读回只有 1 个对）完全吻合；`W0/W1` 仍与核心 LFSR 逐步推算一致 ⇒ 写侧数据与前 2 个 word 的读通路正常。② **根因**：适配器上一版把**读预取的地址推进挂在 `Sdr_rd_en` 上**（厂商应答延迟窗内地址"钉住"不前进），违反"连发期间地址每拍自增"这条唯一被 M-11 验证过的形态。**读引擎已按 M-11 重写**（发命令/收响应两条独立计数 + 1:1 配对 + `RB_GAP=16` 突发间静默），写引擎本就是 M-11 形态故未改。③ **报告瘦身**：删掉 512 个回读寄存器，探针 A 改为**边读边比对**只报 `AM`（32 位匹配位图）/`AF`（首个不符序号）/`AV`（该处回读值），新增**探针 C**（非零偏移 4 字，用来区分"写错/读错"），C/B 各只报低 16 位 ⇒ 报告 **354 → 208 Byte**、报告向量 **2832 → 1664 bit**、报告寄存器 **640 → 199 个**。这一步是**修 STA 回归**：00 时那版把自研组 `clkc[1]→clkc[1]` 从 +0.030 ns 打到 **−1.083 ns / 475 个违例端点**（最差路径全在 `ra_reg → rpt_vec 选择 → u_uart_tx/shifter`）。④ **适配器首次进回归**：`sdram_app_adapter.v` 加入 `run_sim.ps1` 的 `$RTL`，并新增 `tb_sdram_app_adapter.sv`（6 项断言；TB 内含"厂商 app 口模型"，按 M-11 形态建模：en 连发时每拍采样地址、每拍一条读命令、延迟 `RD_LAT` 拍按 **1:1** 返回）⇒ 守住"**连发期间地址必须每拍自增**"，**旧版适配器在本 TB 下过不了 D4/D5**。★ 该 TB 同时记录了三类"TB 自己的握手坑"：阻塞赋值后同 delta 读组合 ready、`while(!rdy)` 遇 X 误判、以及在 negedge（而非握手上升沿）撤 `req` 导致握手丢失/重复接受。★ **对外接口 / 地址表 / 错误码一字未改**；回归 **551 → 557 项断言 / 19 → 20 个 TB，全 PASS**；`check_repo.ps1` → `LAYOUT PASS`。 | B |

| v1.20 | 2026-10-03 | **阶段 10 第 3 轮：读侧修复在板上得到验证，另修三处（含一处死锁 + STA 最差路径）。** ① **板上报文（208 Byte，ID 205358）确认读侧根因已根治**：`AM=FFFFFFFF`（**32 个回读全对，且跨了两次预取**）、`AF=FF`、`AV=00000000`、`C0..C3=1004/1005/1006/1007`（探针 C ⇒ 写侧正常）。② 但同一条报文暴露**我引入的新死锁**：`B0..B3=0000` 且 `WR=000000 CRC=00 SV=00` ⇒ 探针 B 读 `0x1035` 时缓冲里还留着探针 C 未取完的 12 个字，"**跳到缓冲外地址但缓冲没排空**"不会触发新预取 ⇒ 永久死等 ⇒ 探针无进展看门狗 1e6 拍后 `ERR=06` 直接出报告，B 与整帧被跳过（同一 bug 也会在整帧读的第一笔发作）。**修法**：预取触发条件去掉 `rcnt==0`（未命中即可重预取）。③ **STA**：report15（208 Byte 报告）自研组 `clkc[1]→clkc[1]` = **−1.562 ns / 312 违例 / 3691 端点**（对比 report14 的 −1.083 / 475 / 4445 ⇒ 报告瘦身让**端点与违例数明显下降**，但**最差路径换成了适配器自己的 `rbase + rhead` 32 位加法器**经 `ready` 进核内状态机）。**修法**：命中判据改用寄存器 `rexp`（去掉该加法器）+ 读侧 `ready` 改寄存器输出 `r_go`（切断"适配器内部→核内状态机"长组合路径；写侧 ready 不变）。④ `tb_sdram_app_adapter.sv` 新增 **D7「缓冲没排空时跳变地址」**（正是上一版能过、板上暴露的场景）⇒ 6 → **7 项**。⑤ **对外接口 / 地址表 / 错误码一字未改**；回归 **557 → 558 项 / 20 个 TB 全 PASS**。**待办**：TD 重新综合（**必须确认自研组 SWNS ≥ 0**）→ 下载 → 期望 `WR=04B000 CRC=01 SV=01`、`BAD=000000`、`AM=FFFFFFFF`、`B0..B3=1035..1038`。 | B |

| v1.21 | 2026-10-03 | **★★★ 阶段 10 帧缓存回环「板上验收通过」**。208 Byte 报文（ID 211030）**全部判据一次通过**：`INIT=01` / `WR=04B000 CRC=01 SV=01`（整帧 307200 像素写完）/ **`RD=04B000 BAD=000000`（整帧读回逐像素零错）** / `W0=59C3ACE1 W1=670FB387` / **`AM=FFFFFFFF`、`AF=FF`、`AV=00000000`**（探针 A：32 个回读全对、跨两次预取）/ **`C0..C3=1004/1005/1006/1007`**（探针 C）/ **`B0..B3=1035/1036/1037/1038`**（探针 B）/ `BF=000000` / `DONE`。⇒ **从"整帧 3/4 像素错"到零错闭环完成**：根因（适配器读预取地址未每拍自增）由「地址斜坡探针」定案并修复，中途自引入的一处死锁（缓冲没排空时跳到缓冲外地址不重预取）也一并修掉并有 TB 用例守着。**STA 四版记分**（自研组 `clkc[1]→clkc[1]`）：report13 **+0.030 / 0 违例 / 3023 端点** → report14 **−1.083 / 475 / 4445** → report15 **−1.562 / 312 / 3691** → **report16 −0.992 / 31 / 3709**。**时序仍差约 1 ns**：最差路径已从"报告 mux / 适配器加法器"移到 `u_core/st → amask/bw 的变址译码 → 报告寄存器 CE`（`bw[0]_b1[15]` 这条网单独占 2.9 ns）。**本轮把回读收集由"变址写数组"改成"纯移位"**（`amask` 每比对一次右移一位塞入、`cwq/bwq` 每收一个 word 左移 16 位）⇒ 32 路/4 路译码器及其高扇出网一起消失；`framebuffer_loopback_core.v` 的报告侧改读固定位段，**报告字节流逐字节不变**（回归 558 项全 PASS 守住）。**对外接口 / 地址表 / 错误码一字未改**。 | B |

| v1.22 | 2026-10-03 | **阶段 10 收时序：208 Byte 报告 mux 由"1664 bit 向量 + 变址选取"改成"13 块 × 16 Byte 两级 mux + 块寄存器"（仅 `framebuffer_loopback_core.v`）。** 动因 = TD 复算（report17）显示自研组 `clkc[1]→clkc[1]` 已从 −0.992 ns / 31 违例端点收到 **−0.386 ns / 6 违例端点 / Fmax 119.246 MHz**，但 6 条违例里 **4 条终止在 `u_uart_tx/shifter_reg`**，最差路径 `rpt_idx → rpt_vec 变址 mux → uart shifter` 数据路径 8.106 ns、**net 占 71%**、`rpt_idx[4]` 扇出 **47** —— 代价在"一条 208:1 的大 mux 被摊平进 `uart_tx`、输出端要横跨芯片"，不在逻辑层级。**做法**：第 1 级 `rpt_idx → 块选择（13:1 × 128bit）→ blk_q`（块号 k = `rpt_idx[8:4]`，**位**偏移 = `{k,7'b0}`）；第 2 级 `blk_q → 块内字节选择（16:1 × 8bit）→ rep_data`。★ **逐字节等价**：`rpt_idx` 逐字节递减 ⇒ 同块内 `rpt_idx[8:4]` 恒定；`blk_q` 与 `rpt_idx` **在同一个时钟边沿更新**（装"下一字节"所在的块）⇒ **恒 ready（TB `rep_ready=1'b1`、报告逐拍流出）也正确**，无需额外的 priming 拍。★ **对外 `rep_valid` / `rep_data` 的接口与延迟都不变**，报告字节流逐字节不变（`tb_framebuffer_loopback_core` 的 T8/T9 守住）。★ **实现中踩到的坑并已修**：块 mux 的位偏移必须按 **128 位/块** 步进（`{k,7'b0}`），第一版误写成 `{k,4'b0000}`（= k×16 **位**）⇒ 回归 **T9 逐字节断言立刻 FAIL**（而 T8 的"208 Byte"计数仍是对的）—— 印证"报告通路必须逐字节断言，不能只数长度"。回归 **558 项 / 20 个 TB 全 PASS**。**待办**：TD 再复算一次确认自研组 SWNS ≥ 0。 | B |

| v1.23 | 2026-10-03 | **阶段 10 收时序第 3 刀：块号改成寄存器 `blk_nxt`（仅 `framebuffer_loopback_core.v`）。** 动因 = TD 复算（report18）：自研组 `clkc[1]→clkc[1]` 已收到 **−0.081 ns / 2 违例端点 / 3948 端点**（report17 是 −0.386 / 6 / 3676），报告 mux 两级化把**报告通路那 4 条违例全干掉了**；但剩下的 2 条路径都是 `rpt_idx → 9 位减法器（4 级 ADDER，0.92 ns）→ `rpt_dn[5]`（**扇出 195**，1.73 ns）→ 块 mux → `blk_q``。那个 `rpt_dn = rpt_idx - 9'd1` 本来只给状态机算下一个索引，却被综合塞进了**块 mux 的选择端**，于是"9 位借位链 + 195 扇出的长网"全压在关键路径上（数据路径 7.801 ns，net 占 64%）。**改法**：把块号**提前一拍算好存进 5 位寄存器 `blk_nxt`**（恒等于 `block(rpt_idx-1)`，只在"下一字节正好跨块"即 `rpt_idx[3:0]==1` 时 -1）⇒ 关键路径变成 `blk_nxt（寄存器）→ 块 mux → blk_q`，**减法器退回成只喂 5 个 bit 的轻负载路径**。★ 仍是**逐字节等价**：`blk_nxt` 与 `blk_q` 在同一时钟边沿更新，恒 ready（TB `rep_ready=1'b1`）下也正确；**对外 `rep_valid`/`rep_data` 接口与延迟一字未改**。回归 **558 项 / 20 个 TB 全 PASS**。**待办**：TD 复算（report19）确认自研组 SWNS ≥ 0；若仍差，下一根杠杆 = 块宽 16 Byte → 8 Byte（选择扇出减半）。 | B |

| v1.24 | 2026-10-03 | **阶段 10 时序：第 3 刀生效、最差路径换人，决定"收手"（转推进整机集成）。** ① **report19（TD 复算）**：自研组 `clkc[1]→clkc[1]` = **−0.218 ns / 3 违例端点 / 3982 端点**（report18 是 −0.081 / 2 / 3948）。② **第 3 刀（`blk_nxt`）确实修好了它的目标路径**：块 mux 那条从 **−0.081 ns 变成 +0.058 ns（通过）**。③ **但全局最差换到了适配器**：`u_adapter` 的**突发基址 / 读命令计数**通路（`rfbase` / `wbase` / `addr[17]` / `rcmd_i`，`sdram_app_adapter.v` 44/106/124 行），**−0.218 ns / 数据路径 7.938 ns / net 占 69% / 扇出 51**（2 个端点）；第 3 条是 `ramp_to → ramp_addr[17].ce` **−0.029 ns**。⇒ 自研组现有**约 10 条路径挤在 0.25 ns 以内**（已跑到预算 99% 的典型形态）。④ **决策：本顶层（bring-up 自测顶层）就此收手，不再做 RTL 微调** —— 它不会交付（产品顶层是 A 的 `safevision_top`），`framebuffer_loopback_core` 也是自测夹具；剩下两条都是慢逻辑（报告序列化在 115200 下每字节隔约 8680 拍、适配器突发基址建立），不是吞吐瓶颈；且收益递减（475 → 31 → 6 → 2 → 3）。⑤ **时序债的还法**：整机集成后在 A 的顶层重跑 STA；若报告通路仍关键 ⇒ 用**有理由的 `set_multicycle_path`**（数据在几千拍内稳定），**不用 `set_false_path` 刷绿**；若适配器通路仍关键 ⇒ 那是要交付的真逻辑，值得单独优化。⑥ **接口 / 地址表 / 错误码一字未改**；回归 **558 项 / 20 个 TB 全 PASS**。 | B |

| v1.25 | 2026-10-04 | **回应 A 的阶段十审查：SDRAM `C1↔C2` 与 PLL `USR-6135` 两条遗留项完成核查，判定口径修正。** ① **路径事实**（`report19.txt`）：读侧 `C2→C1` **−6.826 ns / 32 端点**，`Logic Level 0`、**`cell 100% / net 0%`、扇出 0**、起止都是 PAD（`u_sdram/sdram.dq[*]` → `u_sdram/sdram_syn_1.bpad`）⇒ **纯 PAD↔PAD，我们的 fabric 完全没有参与**；写侧 `C1→C2` **−2.787 ns / 32 端点**，`Logic Level 1 (PAD=1)`，起点是**厂商控制器内部寄存器**（`u_sdram/u2_ram/u2_wrrd/col_en_reg`）。两者的 budget 都只有 **4.000 ns**（因 C2 相对 C1 移相 180°）。★ **因此此前"全局 −6.826 ns 100% 出自硬核 PAD 路径"的说法不准确**，准确说法是"**厂商 SDRAM 控制器与封装内 SDRAM 的接口路径**"；但工程结论相同：**RTL 不可改**。② **厂商对照（新增证据）**：厂商出货例程 `lab_ex5_i2s` 的 `final_timing.rpt` 有**同名同结构**路径组（`sys_pll_m0/pll_inst.clkc[2] → ext_mem_clk`，**−6.565 / 32 / 32**，同 4.000 ns 预算、同 `sdram.dq[*]` 终点、`clkc[2]` 同样未命名且扇出 1），厂商例程**自身 fabric 组也有小违例**（−0.144 / 2、−0.127 / 1、−0.998 / 1）⇒ 厂商带着同样的数字出货。**按 A 的标准这只是旁证，不是豁免依据。** ③ **`USR-6135`**：我们 `sv_system_pll` 的 `FEEDBK_MODE("NORMAL") / FEEDBK_PATH("CLKC0_EXT")` 与厂商**完全相同**，但我们的 **C0（100 MHz）扇出 = 0（悬空）**，厂商把 C0 当 `sd_card_clk` 用、**扇出 451** ⇒ `CLKC0_EXT` 要求 C0 走外部（全局）网络绕回 `fbclk`，C0 悬空时反馈无实际负载、工具判 local **有据可依**（解释了 A 看到的"物理报告 vs 时序检查"矛盾 —— 前提不同）。候选改法 (a)/(b)/(c) 见核查文档，**B 不单方面改**。④ **判定口径修正**（同步进项目规则 §7 末条）：按 `Logic Level` / `cell%·net%` / `Max Fanout` / 起止点判物理归属，分"纯 PAD↔PAD"、"厂商控制器寄存器→PAD"、"fabric 组"三类；**fabric 组必须修**；**厂商同数不能单独作豁免依据**；**不许 `set_false_path` 刷绿**。⑤ **实物证据**（已有）：M-11（4096 word `BAD=0000`）+ 阶段 10（**307200 word 逐像素零错**），写读两方向都覆盖；**局限：单板单温度点、非厂商全模式图案、无长时间 soak**。⑥ **新增文档** `docs/B链-SDRAM接口与PLL时序核查.md`。**接口 / 地址表 / 错误码一字未改**。 | B |

| v1.26 | 2026-10-04 | **§3.9 `top_sdram_loopback` 改版：报告 71 → 136 Byte + 默认改「全片稀疏扫描」+ 图案生成抽成可仿真模块（回归 558 → 569）。** ① **修掉一个真问题**：原顶层里的 `pat_of` **只用了 `a[11:4]` 与 `a[7:0]`**，而稀疏扫描的被测地址是 `a = k<<11`（`a[10:0]` 恒为 0、`a[11:4]` 只剩最低位）⇒ **1024 个测试点只可能得到 2 种图案**，"全片扫描"几乎什么都证明不了。★ 这类错误**写读自比发现不了**（写侧读侧同一个函数，错得一样照样 `BAD=0000`）。② **图案生成抽成 `rtl/memory/sdr_pat_gen.v`**（无引脚、纯组合，可进回归）：映射 `b0=a[7:0]^a[20:16]`、`b1=a[15:8]`、`b2={3'b0,a[20:16]}`、`b3=b0^b1^b2^0xA5` —— **单射**（可反解 `a[20:0]`）；新增 `tb_sdr_pat_gen.sv`（**11 项**，含 T7 **反向对照**：把旧公式也算一遍、确认它只有 2 种图案 ⇒ 证明判据抓得到）。③ **步长改为 `STRIDE = (1<<ADDR_SHIFT) + ADDR_LOWSTEP`**，默认 `11 + 1 = 2049`：纯 2 的幂步长会把低位地址位固定住（步长 2048 时 `a[10:0]` 恒 0）⇒ 列地址与行低位没被激励；加 1 后 `k*2049=(k<<11)+k` ⇒ 每个地址位都在变。旧连续扫描 = `ADDR_SHIFT=0, ADDR_LOWSTEP=1`。④ **报告 71 → 136 Byte**：新增 `CFG=hhx BASE=hhhhhh N=hhhhhh`（**自描述**）与 `BAD0=hhhhhh E=hhhhhhhh A=hhhhhhhh`（**首个错点**的地址/期望/实际，`FFFFFF`=无错）。⑤ **报告索引改 8 位倒计数**（`rpt_vec[{rpt_idx,3'b0} +: 8]`）：**不含减法器**，避免重蹈阶段 10 那条 `RPT_LEN-1-idx` 减法器被综合进 mux 选择端的最差路径。⑥ **引脚 / 接口 / 错误码一字未改**；回归 **558 → 569 项 / 20 → 21 个 TB 全 PASS**。**待办**：重新综合 → 烧板 → 对账（期望 `CFG=0B1 BASE=000000 N=000400` / `W=0400 R=0400 CAP=0400 BAD=0000` / `BAD0=FFFFFF E=00000000 A=00000000`）。 | B |

| v1.27 | 2026-10-04 | **把"不可仿真"的 SDRAM 顶层拉进回归：新增仿真桩 `vendor_ip_stub` + `tb_top_sdram_loopback`（5 项），136 Byte 报告**逐字节仿真验证过**（回归 569 → 574）。** ① **动机**：`top_sdram_loopback.v` 例化的两个单元 ModelSim 编译不了（加密 `sdr_*.enc.v` + TD 的 `EG_PHY_PLL` 宏），所以它历史上**完全没有 TB**；而本轮刚把报告 71 → 136 Byte 并改了索引方式 —— **这类改动以前只能烧一次板才知道对不对**。② **做法**：`verification/models/vendor_ip_stub.sv`（**仿真桩**，明确标注"不是厂商行为模型"）—— PLL 桩给 125 MHz 方波；SDRAM 桩是"理想存储器"（读命令延迟 4 拍后按 **1:1** 回 `Sdr_rd_en` + 该地址数据，数据由同一份 `sdr_pat_gen` 算出）。`tb_top_sdram_loopback.sv` 自建 125 MHz 采样 UART 8N1 接收模型，断言：报告**恰好 136 Byte** / **逐字节与期望串一致** / **`CFG=0B1 BASE=000000 N=000400`** / **`BAD0=FFFFFF E=00000000 A=00000000`** / **`led=8`**。③ 该顶层与桩分别加入 `run_sim.ps1` 的 `$RTL` / `$SIM`。④ ★ **TB 自己的一个坑已记档**：`got` 里"第 0 个收到的字节在最高位"，取"流字节 [a..b]"的切片基址要按**末字节 b** 算（`got[8*(135-b) +: 8*(b-a+1)]`）—— 按首字节算会把顺序倒过来，表现为**整串比对通过、单行比对失败**（用一个秒级 scratch 仿真打切片才定位）。⑤ ★★ **效力边界**：桩不模拟初始化/刷新/CAS/突发窗口/地址每拍自增，读数据按地址算出 ⇒ **桩里的 `BAD=0000` 是构造保证的，不是数据完整性证明**；**SDRAM 协议与数据完整性仍只认 M-11 / 阶段 10 的上板实测**。⑥ **接口 / 引脚 / 错误码一字未改**；回归 **574 项 / 22 个 TB 全 PASS**。 | B |

| v1.28 | 2026-10-04 | **§3.9 补上「全片稀疏扫描」的板级验收结果（条目 M-11-PASS-3）**：采集解码后 **136 字节**，**逐字节与设计值一致** —— `SV-SDRAM-LOOP` / `INIT=01 LOCK=01` / **`CFG=0B1 BASE=000000 N=000400`** / **`W=0400 R=0400 CAP=0400 BAD=0000`** / **`BAD0=FFFFFF E=00000000 A=00000000`** / `DONE`；真 CRLF、无前导 `0x00`。⇒ 步长 2049 × 1024 点铺满整个 2M word 空间（4 个 bank、全部行/列地址位都被激励）**读回全部正确** ⇒ **行/体/列地址译码在实物上验证通过**。★ **报告自证**：`CFG=0B1` 与 136 Byte 格式只存在于新版 RTL ⇒ 同时证明综合采用了含 `sdr_pat_gen.v` 的新代码。★ 本轮修掉一个"看起来在测、其实几乎没测"的真问题（旧图案公式在步长 2^11 下 1024 点只有 2 种图案）。**接口 / 格式 / 引脚 / 错误码一字未改**；归档 `evidence/board/`（HEX `AA0F261E…`；解码后 136 B `5BE3B939…`）。 | B |

| v1.29 | 2026-10-04 | **§3.9 做「扩展图案 + soak」：报告 136 → 190 Byte，新增 `ROUNDS` 参数与 6 种图案模式（回归 574 → 588）。** ① **6 种图案模式**（`sdr_pat_gen` 加 `mode` 输入，逐轮轮换）：`0 ADDR`（地址派生，单射 ⇒ 治地址译码）/ `1 LFSR`（xorshift32，双射 ⇒ 压数据线串扰）/ `2 WALK1`、`3 WALK0`（单根数据线为 1/0 在走 ⇒ 治线间粘连）/ `4 ALT`（全 0 全 1 交替 ⇒ 最坏功耗图案）/ `5 ADJ`（相邻位反向 ⇒ 压相邻线耦合）。② **soak（`ROUNDS`）**：把「写→等落地→读→等收齐」当一轮重复 N 轮、每轮换模式；`TOT`（40 位，不重置）累计搬运量 ⇒ 手册 7.12 的"实际搬运数据量"口径。★ **出错立即停（fail fast）**，报告 `RND` 即出错轮次。★ 轮时长**实测 ≈ 22 µs**（2790 拍 @125 MHz）⇒ `ROUNDS ≈ 目标秒数 × 45_000`；60 分钟约 `ROUNDS=1.6e8`。★ **soak 期间"没有输出"就是好消息**（出错会立刻出报告）。③ **报告 136 → 190 Byte**：加 `RND=hhhhhhhh/hhhhhhhh PAT=h` 与 `TOT=hhhhhhhhhh`，`BAD0` 加**轮次**（`BAD0=hhhhhhhh:hhhhhh E=… A=…`，无错哨兵 `FFFFFFFF:FFFFFF`）。④ **仿真桩改成"真存真取"**（`vendor_ip_stub` 由"按地址算图案"改成 2M×32 bit 理想存储器）—— 顶层现在有 6 种模式，桩不可能去猜当前用哪种；并加**故障注入**钩子供 TB 验 fail-fast。⑤ **带桩 TB 扩到 8 项**：阶段 1（`ROUNDS=3`）验报告逐字节 + `RND=3/3 PAT=2`（soak 与模式轮换生效）+ `led=8`；阶段 2（注入 1 bit 错）验只跑 1 轮就停 + `BAD=0001` + **`BAD0=00000001:002805 E=88002805 A=88002804`**（轮次:地址 定位）+ `led=3`。⑥ **★ TB 抓出一个真缺陷**：**xorshift 的 0 是不动点** ⇒ 原"地址**异或**播种"会让某个地址输出**全 0**（最弱图案、掩盖"数据线卡死在 0"）⇒ 改**加非零常数**播种。⑦ **引脚 / 接口 / 错误码一字未改**；回归 **588 项 / 22 个 TB 全 PASS**。**待办：改 `ROUNDS` 重新综合 → 烧板跑 soak → 按待办清单 §2.4.2 步 7b 对账**。 | B |

| v1.30 | 2026-10-04 | **§3.9 回读比对改四级流水（修自研组时序违例）；soak 首轮上板报异常报文（未通过）。** ① **现象**：soak 首轮（`ROUNDS=450000`，位流 11:16）采集 190 Byte —— `RND=00000002/0006DDD0 PAT=1` / `W=R=CAP=0400` / **`BAD=0001`** / `TOT=0000000800` / **`BAD0=FFFFFFFF:FFFFFF`（无错哨兵）**。★ 按 RTL，`bad_cnt` 自增与 `bad0_set` 置位在**同一拍同一分支** ⇒ **两者不可能同时成立**。② **定位**：报文确认来自新构建（`elaborate -top top_sdram_loopback` + `elaborate module sdr_pat_gen`）；**仿真里复现不了**该矛盾（带桩 TB 制造"第 2 轮 1 字不符"时 `BAD0` 正常）；**布线后 STA 找到真问题** —— `clkc[1]→clkc[1]` = **SWNS −3.591 ns / 90 违例端点 / 1431 端点，Fmax 86.274 MHz**，最差路径正是 `cap_cnt → 地址加法 → sdr_pat_gen(mode1 xorshift/mux) → 32 位比较 → bad0_exp[*].ce`（**11.311 ns**、Logic Level 8、net 占 66%）⇒ **`BAD0` 没锁存极可能是时序违例**，`BAD=1` 真伪待定。③ **修复（`top_sdram_loopback.v`）**：回读比对拆 **4 级流水** —— Stage0 响应采样（锁 `sample_{addr,mode,data}`，`cap_cnt/tot_cnt++`）→ Stage1 期望图案（`sample_*` 经 `sdr_pat_gen` 算，锁 `expect_pat`）→ Stage2 比较（结果锁 `cmp_bad`，诊断锁 `cmp_{addr,exp,act}`）→ Stage3 提交（`checked_cnt++`/`bad_cnt++`/首次错写 `bad0_*`）；**`ST_RDWAIT` 出口由 `cap_cnt >= TEST_WORDS` 改为 `checked_cnt >= TEST_WORDS`**（等流水排空，否则会在流水未完时切 `pat_mode` / 发报告）。④ **验证**：回归 **588 项 / 22 个 TB 全 PASS**、`LAYOUT PASS`；`tb_top_sdram_loopback` **8/8**（阶段 2 已改成"**第 2 轮 mode 1 注入 1 bit 错**"，断言 `RND=2/3 PAT=1`、`BAD=0001`、`BAD0=00000002:002805 E=64F2D804 A=64F2D805` —— 正好覆盖板上失败场景）。⑤ **★ 结论**：**这次 soak 既不算通过、也不能当成"发现真实存储错误"**；**报告格式 / 引脚 / 接口 / 错误码一字未改**。**待办：重新综合 + 布线（看自研组 SWNS 是否转正）→ 烧 10 秒版复测**。⑥ 证据归档：`evidence/board/` 条目 **SOAK-R1-ANOMALY**（HEX `8D60E7A2…`；解码后 190 B `081D82C7…`）；交接文档重建 `docs/B链-交接-给下一位Agent.md`。 | B |

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
| v1.32 | 2026-10-04 | 整合 A d6f40a6 与 B SDRAM bring-up：完整 21-bit 签名、byte compare pipeline、UART 预取与应用层 TB；保留 B 6 模式 soak/190 Byte 诊断报告。ModelSim B 回归及集成应用层 ModelSim 用例通过；XSim、TD STA 与新构建板测待执行。 | A+B |

## 存储联调修正（远端提交 db4acfa，2026-10-04）

本节记录 db4acfa 引入的存储握手、DMA 突发及帧交换确认修正；具体接口契约与原提交说明保持如下，并与本文件的 A/B 集成及 soak 参数说明并存。

- `memory_arbiter`：突发 ACK 后留一拍准备首字；每个命令仅在 `mem_req && mem_ready` 的时钟边沿被接受，停顿时保持地址/模式。读通道的 `busy` 保持到最后一个 `mem_rdata_valid` 响应返回，之后才能切换通道。下游须按序返回每个已接受读命令的一个响应。若永久丢失响应，需要故障管理执行复位/恢复；本接口没有新增响应超时输出。饥饿事件先寄存再计数，`rd_starve_cnt/wr_starve_cnt` 比事件晚一拍更新，以缩短 125 MHz 控制路径。
- 写数据发送方应在所属通道的 `busy && mem_req && mem_ready && mem_wr` 成立时推进一个 word；`mem_req && !mem_ready` 期间保持 `wr_data/sd_wdata`。这些握手量由装配层连接；`wr_ack/sd_ack` 仍只确认整个突发，不是逐 word 确认。SD 的读/写模式在 grant 时锁存。
- `video_read_dma`：收集与输出索引宽度由 `BURST_WORDS` 决定；支持默认 16 以及 64 word 等合法配置。最后一次突发按剩余帧长度缩短，按本次长度预留 FIFO 空间。最后一个注册的 FIFO 写脉冲被消费后，再读水位；`done` 在整帧像素已送入 FIFO 后出现。接受 ACK 同拍的首个读响应。
- DMA 参数约束：`1 <= BURST_WORDS <= 65535`、`1 <= PIX_DEPTH <= 65535`、`2*BURST_WORDS <= PIX_DEPTH`、`1 <= LOW_WATER <= PIX_DEPTH`。FIFO 水位必须是写时钟域的有效计数；只能由本 DMA 写入该 FIFO。当前帧几何仍为 640×480 RGB565，未扩展为 HD 存储格式。
- `frame_swap_ctrl`：在 WAIT_VBLANK/COMMIT 中到达的确认会被保存；确认与帧边界同拍也可完成握手，但 `active_commit` 仍必须在帧边界发生。默认 `TIMEOUT_N=5_000_000`，100 MHz 为 50 ms，125 MHz 为 40 ms；其他帧率/时钟需按最大等待与 CDC 裕量覆盖参数。无帧边界或无确认仍超时进入 SAFE，复位会清除保存的确认。

复现与回归入口：`safevision/tools/run_memory_protocol_sim.ps1`。7 个新增 TB 包括 `tb_memory_arbiter_backpressure`、`tb_memory_arbiter_read_latency`、`tb_video_read_dma_burst64`、`tb_frame_swap_vblank_ack`、`tb_frame_swap_default_timeout`、`tb_memory_arbiter_protocol`、`tb_video_read_dma_integration`。默认同时验证修正代码的 PASS 与 `d6f40a6` 旧代码的 5 个预期失败；可用 `-SkipNegativeControls` 只运行修正代码。XSim/Git 工具路径可通过参数指定。

验证范围（db4acfa 原提交）：7 项新回归、15 种逐字仲裁协议场景、4 个完整帧/1,228,800 个像素；B 既有 18 TB/540 项回归仍通过。不能替代 SDRAM 物理 AC、真实 HDMI、整机 CDC 或上板验收。原有测试入口和队友 TB 保留。

| v1.33 | 2026-10-04 | 在 A/B v1.32 集成基础上合入 db4acfa：登记 memory arbiter 命令/读响应握手、DMA 帧尾/FIFO 水位/早到 ACK、帧交换确认与默认超时修正。合并后完整回归、TD STA 与板测待复验。 | A+B |


## A 阶段11–15补充契约（v1.34，2026-10-05）

新增接口及本轮验证见 [A_stages11_15.md](A_stages11_15.md)。基线 `b50ac4f`；不修改 B/C 已有 RTL、端口、测试或 B 的 `safevision.al`。

- 显示集成入口 `a_video_display_core`：`sys_clk` 承担 B 槽mailbox/C配置，`mem_clk` 承担 B DMA读口和FIFO写端，`pixel_clk` 承担扫描、FIFO读端、图层合成。`rst_n` 必须共同断言，内部每域同步释放；整个邮箱/FIFO组不支持一端独立复位后保留另一端旧数据。
- B 将既有 `frame_swap_ctrl` 的 `swap_req/frame_index/slot_id/generation/crc_ok` 接到 `swap_req_b/mb_*_b`；必须保持payload直到A确认。A返回的 `frame_start_evt_b/swap_ack_evt_b` 是sys域单拍，直接接既有B控制器，不要再次转toggle。A仅在原始垂直消隐更新active slot/generation/index；无效CRC不提交、不ACK。A对 `frame_swap_cdc` 的事件额外等一拍才取其新payload。
- A `rd_*` 原样接 B `memory_arbiter` 的Video Read口：地址按字节，`rd_len`按32bit word，默认64。ACK确认整个突发，`rd_data_valid`每拍确认一个按序word；B的busy维持到所有响应返回。新帧先停发新请求并排空旧响应，再清本地DMA/FIFO，不复位共享仲裁器/SDRAM。
- 官方像素FIFO遵循D-2：32写16读、低16先读、FWFT、输出无额外寄存。现B DMA16bit像素经独立packer成32bit word，不修改DMA。AW10实际2046pixel容量；`mem_fifo_pixels`是mem域保守水位（含半word与4pixel余量），不是像素域直接计数。
- `cfg_valid&&cfg_ready`在sys域捕获整组OSD enable/mode/fps/sd/origin/foreground；源侧保持valid和全部字段直到握手。mailbox到像素域整组生效，mode枚举/状态文字沿用已有A显示契约；若C产品枚举不同，由装配层映射。诊断输出 `pix_*` 与 `mem_*` 的域由前缀明示，送给C总线前另做CDC。
- 应急输入 `emergency_rgb/emergency_valid` 已属于pixel域，参考原始 `scan_x/scan_y/scan_de`，输入延迟0；阶段16负责图形/安全策略。不要把sys域三根应急控制线直接接此RGB层。最终RGB888从原始扫描延迟5拍：Normal=1，OSD=4，Emergency=0，对齐到4再合成1拍。最终所有同步、de、坐标与RGB同拍；`de`不受欠流/invalid暂停。
- 存储格式保持四槽640×480 RGB565。BASE直接显示；HD扫描1280×720，将640×480画面居中（320,120）。不把640图像假称为原生HD帧，不擅改B容量、地址或格式。Reader独立HD整帧测试与集成letterbox测试分别登记。

本轮：7个A新增TB通过，64份真实A+B RTL同库编译；实际B DMA/arbiter/swap + 官方FIFO联调BASE/HD，欠流后的本帧剩余像素安全色、下一帧恢复；B18TB/540检查、存储7TB+5旧码负对照、A1–10、时钟5功能+41参数及SDRAM应用层回归通过。TD内部探针BASE setup/hold +0.838/+0.011ns，HD +1.004/+0.021ns，125/100MHz及两种像素时钟与有界CDC已检查。未替代SDRAM物理AC、PLL补偿健康、真实HDMI、整板引脚预算或上板验收；既有SDRAM −6.826ns路径仍是未关闭问题。

| v1.34 | 2026-10-05 | 新增A阶段11–15独立接口及集成核心；保持B/C冻结端口；登记FWFT容量/单位、B换帧与突发接线、C配置邮箱、5拍图层延迟、BASE/HD格式与验证边界。 | A |

| v1.35 | 2026-10-05 | **B 对 v1.34 补充契约的应答：新增 [B链-整机集成-存储侧接线表.md](B链-整机集成-存储侧接线表.md)。** 把 A 的两段要求落成**可执行的逐根接线**：① **存储器读口 7 根**（`rd_req`/`rd_addr[31:0]`/`rd_len[15:0]`/`rd_ack`/`rd_busy`/`rd_data[31:0]`/`rd_data_valid`）—— 与 B `memory_arbiter` 的 Video Read 口**同名同宽、方向互补、单位一致**（地址 = 逻辑**字节**地址；`rd_len` = **32bit word 数**，集成取值 **64**）⇒ **直连**，且**两侧同在 `mem_clk` 域、不需要同步器**；② **帧交换口 7 根** —— B 的 `frame_swap_ctrl` 与 A 的 core 互为对端，**`frame_swap_cdc` 已由 A 的 `a_video_display_core` 例化**（`a_video_display_core.v:43`）⇒ **B 侧不要再例化一份**；A 的 `frame_start_evt_b`/`swap_ack_evt_b` **已是边沿检测过的单拍脉冲，不要再转 toggle**。③ 文档含**时序语义 11 条**、**"不该做什么" 6 条**（每条都有真实教训）、**复位约定**（三域各自 `reset_sync`，`rst_n` 共同断言）、**与契约条款的逐条对照**（全部一致）、**验证状态表**、**5 项未决**。④ 同时订正两处误导性注释：`frame_swap_ctrl.v` 把 `swap_ack` 写成"A→B toggle 的边沿事件"（实际是已取边沿的单拍，易被读成"还得自己再检测一次"）；`memory_arbiter.v` 头注写"O-3 建议 16 或 32 word"（与集成实取值 64 不一致）。⑤ **接口/端口/引脚一字未改**，只补文档与注释。 | B |
