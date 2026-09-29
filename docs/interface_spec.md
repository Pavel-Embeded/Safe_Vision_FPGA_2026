# SafeVision B 链接口规范（interface_spec）

> 本文档是 **B 链（数据存储与数据搬运）** 与 A、C 的**冻结接口依据**。
> 任何一方改接口，必须先改本文档、再改 RTL，并通知对接人。
> 联调时以本文档为准，不以口头约定为准。

## 文档信息

| 项 | 内容 |
|---|---|
| 项目 | 安视 SafeVision · 赛题一 HDMI 多媒体播放与应急视听疏散终端 |
| 平台 | 康芯 HX4S20C 开发板 / 安路 EG4S20BG256 |
| 版本 | v1.7（阶段 1–16 已实现并通过仿真；命名按《工业级模块化架构蓝图》§4 逐项核对完成） |
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

**开发基准**：《赛题一对标学习与开发手册_V2.0.pdf》（工作区根目录，不进仓库）
——功能取舍、阶段节奏、验收口径一律以它为准。
**结构基准**：《工业级模块化架构蓝图.pdf》§4 的仓库树——新增文件前先确认它落在
蓝图哪个目录；蓝图里有而本项目**有意不做**的目录见下方"未采纳蓝图的部分"。

### 命名迁移表（手册名 → 工程名）

> 依据《工业级模块化架构蓝图》§1.3：「迁移表必须保留下来，便于把手册需求、
> 旧提交和新模块对应起来」。v1.5 起 B 链文件名与 module 名已按蓝图 §4 对齐。
> **对外契约（信号名、错误码）不随改名变化**，A / C 侧无需改动。

| 手册 / 旧名 | 工程名（蓝图 §4） | 说明 |
|---|---|---|
| `rtl/common/sd_defines.vh` | `rtl/include/safevision_defs.vh` + `rtl/include/fault_code_defs.vh` | 通用定义与错误码登记拆开，`safevision_defs.vh` 已 include 后者 |
| `rtl/stage1/shift_reg.v` | `rtl/common/shift_reg.v` | 阶段 1 教学件，**产品链未例化**；蓝图无对应项，暂放 common |
| `rtl/stage1/spi_byte_rx.v` | `rtl/common/spi_byte_rx.v` | 同上 |
| `rtl/common/uart_tx.v` | `rtl/common/uart_tx.v` | 不变 |
| `rtl/sd/spi_master.v` | `rtl/storage/spi_master.v` | 仅目录变，名字保留 |
| `rtl/sd/sd_init_fsm.v` | `rtl/storage/sd_initializer.v` | |
| `rtl/sd/sd_sector_rd.v` | `rtl/storage/sd_sector_reader.v` | |
| `rtl/fs/fat32_mount.v` | `rtl/storage/fat32_boot_parser.v` | |
| `rtl/fs/dir_scan.v` | `rtl/storage/fat32_directory_scanner.v` | |
| （新增） | `rtl/storage/fat32_cluster_walker.v` | 簇链跟踪，被下面两者共用 |
| `file_stream`（原计划） | `rtl/storage/file_streamer.v` | |
| `bmp_check`（原计划） | `rtl/media/bmp_parser.v` | 蓝图把媒体解析放在 `rtl/media/` |
| `safevision/sim/tb_stage5.v` | `verification/unit/tb_sd_sector_reader.sv` | |
| `safevision/sim/tb_stage4_timeout.v` | `verification/unit/tb_sd_initializer.sv` | |
| `safevision/sim/tb_stage6_mount.v` | `verification/unit/tb_fat32_boot_parser.sv` | |
| `safevision/sim/tb_stage6_dir.v` | `verification/unit/tb_fat32_directory_scanner.sv` | |
| `safevision/sim/sd_card_model.v` | `verification/models/sd_spi_card_model.sv` | |
| `safevision/sim/run_sim.ps1` | `safevision/tools/run_sim.ps1` | work/ 库建在 `verification/` 下 |

#### v1.7 追加的重命名（按蓝图 §4 逐项核对后修掉的最后 4 处不一致）

| 旧名 | 工程名（蓝图 §4） | 说明 |
|---|---|---|
| `rtl/media/wav_reader.v` | `rtl/media/wav_parser.v` | 蓝图 media 下统一用 `*_parser`（`bmp_parser`/`wav_parser`），`wav_reader` 是唯一例外 |
| `rtl/common/fifo_health_monitor.v` | `rtl/memory/fifo_health_monitor.v` | 它监测的是帧缓冲/FIFO 水位，属 memory 分类，不是平台无关件 |
| `verification/models/sdram_model.sv` | `verification/models/frame_memory_model.sv` | 它建的是"帧缓存视图"（8 MiB/2M×32bit），不是 SDRAM 器件模型 |
| `verification/unit/tb_mem_write.sv` | `verification/unit/tb_frame_writer.sv` | 被测件已叫 `frame_writer`，TB 同名；`tb_mem_write` 是阶段 9 的旧称 |

#### v1.7 新增文件（补蓝图缺口，不是改名）

| 新增 | 蓝图出处 | 说明 |
|---|---|---|
| `rtl/include/pixel_format_defs.vh` | §4 `rtl/include/` | 像素格式 + 帧几何 + **冻结四槽地址表**的唯一来源（见 §五） |
| `rtl/include/event_code_defs.vh` | §4 `rtl/include/` | 事件码/源标识定义（与 `fault_code_defs.vh` 分工：后者是错误码，前者是正常事件） |
| `rtl/common/crc16_ccitt.v` | §4 `rtl/common/` | CRC16-CCITT(XMODEM) 字节步进。此前 `sd_sector_reader` 与 `frame_writer` **各写了一份同名函数**，收敛成一份 |
| `rtl/common/crc7.v` | §4 `rtl/common/` | SD 命令 CRC7 字节步进，配 `tb_crc` 把 `SD_CRC_CMD0/8` 两个魔数钉死在对数上 |
| `verification/unit/tb_crc.sv` | §4 `verification/unit/` | CRC7/CRC16 单元测试（12 项） |
| `verification/unit/tb_memory_arbiter.sv` | §4 `verification/unit/` | 由 `tb_frame_swap.sv` 拆出（仲裁部分 7 项） |
| `verification/unit/tb_frame_swap_ctrl.sv` | §4 `verification/unit/` | 由 `tb_frame_swap.sv` 拆出（帧交换+跨域 23 项） |
| `verification/unit/tb_bmp_unpack.sv` | §4 `verification/unit/` | 由 `tb_media.sv` 拆出（BMP 解包 44 项） |
| `verification/unit/tb_wav_parser.sv` | §4 `verification/unit/` | 由 `tb_media.sv` 拆出（WAV 解析 31 项） |
| `verification/unit/tb_fat32_cluster_walker.sv` | §4 `verification/unit/` | 新增：`fat32_cluster_walker` 此前只随编译、**判 EOC/越界/判环三条收尾分支从未被仿真跑过**（33 项） |

> 拆分类改动（`tb_frame_swap`→2 个、`tb_media`→2 个）**只搬位置、不改断言**：
> 断言名字与判据逐字保留，拆分前后合计断言数不变（30 → 7+23，75 → 44+31）。

**未采纳蓝图的部分（有意为之，不视为缺陷）**：150+ 文件的完整目录树、formal
（SymbiYosys）、nightly 多随机种子 CI、HIL 自动化、release manifest、CSR 总线、
HAL 抽象层、Codec I²C 配置。理由见蓝图 §4.1「不要一开始创建 150 个空 RTL」与
§19「对三人团队而言，最合适的目标不是模仿大公司堆叠复杂框架」。

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
| 错误上报 | 统一走 `error_report` → Control Event Interface（`evt_type` / `evt_value` / `evt_valid` / `evt_full`），溢出计数在 C 侧 | 10.2.4 |

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
实现   : safevision/rtl/sd/spi_master.v

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

### 3.3 格式层（学习阶段 7）

#### fat32_cluster_walker（阶段 7 新增，蓝图 §5.2）

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
  正式顶层由 file_request_arbiter 统一调度（蓝图 §5.2）。
```

#### file_streamer（阶段 7 落地；原 `file_stream`，按蓝图 §5.2 改名）

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
      **valid=1 且 ready=0 时 data/sof/eof 必须保持**（蓝图 §7.2）；
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

#### bmp_parser（阶段 7 落地；原 `bmp_check`，按蓝图 §5.2 改名）

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
audio_clk           in   1     C 提供（audio_mclk 12.288 MHz = 256 × Fs）
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
| D-9 | "命名冲突"的定性与处理范围 | 只修**真不一致**（4 处文件名/归类与蓝图 §4 不符）+ 补蓝图缺口（2 个头文件、2 个 CRC 通用件）；**不做**全量照搬蓝图目录树。并且把"同一个常量有多份副本"当作比"名字"更严重的问题来修 | ① 宏与裸标识符是两个命名空间（`` `FRAME_WIDTH `` 与 `parameter FRAME_WIDTH` 不会编译冲突），所以"命名冲突"这个说法本身需要更正；② 同一个地址/几何量有 4 份副本，改一处漏一处才是真正的上板风险；③ 蓝图 §4.1 自己反对一次建 150 个空 RTL | v1.7 |
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
| v1.5 | — | **命名按《工业级模块化架构蓝图》§4 对齐**（新增「命名迁移表」）：目录树改为 `rtl/{include,common,storage,media}` + `verification/{unit,models}` + `tools`；`sd_init_fsm`→`sd_initializer`、`sd_sector_rd`→`sd_sector_reader`、`fat32_mount`→`fat32_boot_parser`、`dir_scan`→`fat32_directory_scanner`、`sd_card_model`→`sd_spi_card_model`；`sd_defines.vh` 拆成 `safevision_defs.vh` + `fault_code_defs.vh`。**阶段 7 落地**：新增 `fat32_cluster_walker.v`（簇链跟踪，被 `fat32_directory_scanner` 与 `file_streamer` **共用同一份**，消除 v1.4 的重复判环逻辑）、`file_streamer.v`（接管原 `file_stream`）、`media/bmp_parser.v`（接管原 `bmp_check`）。新增 TB：`tb_file_streamer.sv`(49 项)、`tb_bmp_parser.sv`(41 项)。**新增实测踩坑 3 条**：① 下游取走字节的清零逻辑必须放在状态机之外，否则扇区末字节锁存后 `valid` 永不清、死等兜底超时；② 文件末字节正好落在扇区末字节时 `stop_pending` 要按同拍值判定，否则白跳一次簇、误报 `DET_FS_SHORT`；③ BMP 多字节字段同为小端。六个 testbench 合计 **206 项断言全通过** | B |
| v1.6 | — | **阶段 8–16 落地**（B 链主体完成）。新增 `rtl/memory/`：`mem_ctrl.v`（SDRAM IP wrapper，对外只暴露逻辑字节地址）、`frame_address_gen.v`（`slot_base+(y*W+x)*BPP`，行步长参数化）、`frame_writer.v`（一帧严格 307200 像素 + 抽样 CRC + `slot_valid`）、`frame_buffer_manager.v`（冻结地址表全 `localparam`，原子提交 `active_slot/slot_base/generation`）、`memory_arbiter.v`（固定优先级 + 单次占用上限 + 最长等待提权，防饥饿）、`video_read_dma.v`（水位驱动突发预取）、`frame_swap_ctrl.v`（`IDLE→WAIT_VBLANK→COMMIT→WAIT_ACK`，超时进 SAFE 保持画面）、`frame_swap_cdc.v`（toggle 同步 + mailbox 锁存）、`memory_bandwidth_monitor.v`。新增 `rtl/common/`：`rv_skid_buffer.v`、`sync_fifo.v`（`almost_full` 反压）、`fifo_health_monitor.v`（历史最低水位 + underflow/overflow）、`error_report.v`。新增 `verification/models/frame_memory_model.sv`（行为级，8 MiB/2M×32bit）。**阶段 6 收尾**：`file_index.v`（编号扫描 + 数字后缀排序 + 索引表冻结，新增 `idx_clear` 输入用于重扫）。新增 TB：`tb_file_index`(60)、`tb_common_fifo`(58)、`tb_frame_writer`(28)、`tb_frame_swap`(30)。**媒体格式层收尾**：`media/bmp_unpack.v`（BGR888→RGB565，`ROUNDING` 参数对应待确认项 O-1，行步长按公式算，`top_down` 双向统一成左上原点，按"像素数 == w×h"收尾）、`media/wav_parser.v`（RIFF/fmt/data 小端解析，**fmt 与 data 之间的未知块按 chunk size 跳过**，只收 PCM/2ch/48k/16bit）。新增 `tb_media`(75)。**错误码补登记**：`ERR_WAV`(0x07) 与 `DET_WAV_*`(0x71–0x76) 原先只写在本文档 §6.1/§6.2/D-7，代码里缺，已补进 `rtl/include/fault_code_defs.vh`（此前 `wav_parser` 只能临时用 `ERR_MEDIA_INVALID`，现已对齐文档）。十一个 testbench 合计 **457 项断言全通过** | B |
| v1.7 | — | **按蓝图 §4 逐项核对命名，修掉最后 7 处真不一致 + 补 10 个缺口**（详见「命名迁移表」下的两个子表）。**重命名 4 处**：`wav_reader`→`media/wav_parser`、`fifo_health_monitor` 从 `common/` 移到 `memory/`、`sdram_model`→`models/frame_memory_model`、`tb_mem_write`→`tb_frame_writer`（文件+module+全仓引用+TB+脚本一次改净，对外契约不变）。**补头文件**：`rtl/include/pixel_format_defs.vh`（像素格式+帧几何+**冻结四槽地址表唯一来源**）、`rtl/include/event_code_defs.vh`。**★ 真正的结构性问题（比"名字"严重）**：同一个常量在 4 个模块里各存了一份副本——`frame_buffer_manager`（7 个地址+SLOT/LINE/FRAME 步长）、`frame_writer`（帧几何 6 个）、`frame_address_gen`（2 个）、`video_read_dma`（3 个），另有 `tb_frame_writer` 抄了两处期望值。现已全部改为引用 `` `SV_`` 宏，**parameter 一律保留**（几何量必须能被顶层覆盖），改地址从此只改一个文件。**★ 概念更正**：此前把这件事描述为"宏与 parameter 命名冲突"是**错的**——Verilog 宏只在写成 `` `名字 `` 时才展开，裸标识符不进宏展开，两者不会编译冲突（已用编译验证）；加 `SV_` 前缀是为了可读性。真正的问题是常量多副本。**补公共件**：`rtl/common/crc16_ccitt.v`、`rtl/common/crc7.v`（纯组合无状态步进器，见 D-10），并让 `sd_sector_reader`（删掉自己那份 `crc16_next` 函数，改例化 1 级）与 `frame_writer`（删掉 `crc16_next`+`crc16_word` 两个函数，改为大端 4 级级联）复用同一份实现。**补 TB**：新增 `tb_crc`(12，把 `SD_CRC_CMD0/8` 的 0x4A/0x43 反推出来钉死在对数上，并验 CRC16 XMODEM 标准向量 `123456789`→0x31C3)、`tb_fat32_cluster_walker`(33，`fat32_cluster_walker` 此前只随编译，**判 EOC/越界/判环三条收尾分支从未被仿真跑过**，本 TB 用伪 FAT 扇区直接驱动并覆盖跨扇区寻址)。**按蓝图拆 TB**（只搬位置不改断言）：`tb_frame_swap`→`tb_memory_arbiter`(7)+`tb_frame_swap_ctrl`(23)，`tb_media`→`tb_bmp_unpack`(44)+`tb_wav_parser`(31)。**回归 502 项断言 / 15 个 testbench 全通过**。另：把交付口径写成显式规则——新增「文档同步义务」表（本文档 + 待办清单 + 原理讲解 + README 四者的更新触发条件）、补一份真正的 `README.md`（仓库结构、跑仿真方法、状态总览、硬约定）、并把"开发基准＝手册 V2.0 / 结构基准＝蓝图 §4 / 三份文档必须同步"写进项目规则文件，避免后续会话遗忘 | B |