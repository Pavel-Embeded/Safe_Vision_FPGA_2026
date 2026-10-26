> V3 当前离线交付（2026-10-16）：BASE 640×480与HD 1280×720完整功能均已完成清洁构建、全角时序与位流生成，源码提交为9d40698。见[验收报告](docs/v3/release_9d40698.md)、[两份位流](artifacts/v3/release_9d40698/README.md)、[完整交付包](artifacts/v3/SafeVision_V3_release_9d40698.zip)。113项原生正向及28项语义负控通过；实体板卡验收待验。
>
> V3 GUI入口：[BASE工程](safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/base/safevision_v3_base.al)与[HD工程](safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/hd/safevision_v3_hd.al)。下文保留队友原来的safevision_top基线与历史位流说明，不是V3发布状态。新版本没有继承旧位流的实体板测结论。

> 历史基线状态（2026-10-11 仓库收敛后）：`main` 只保留最新一版代码，默认构建就是板级
> 验证过的配置（40 MHz 存储时钟 + 验证过的 +10 ns 相位 + 细化版 dm 释放）。
> 构建与复现方式、产物指纹、已知问题见 [构建与复现](docs/B链-构建与复现.md)；
> 本次删除了什么、为什么、怎么找回，见 [仓库收敛说明](docs/仓库收敛说明_20261011.md)。
> 下文早期阶段说明与历史板测记录按各自版本解释。

# SafeVision FPGA 2026

2026-10-09 板级白屏修复入口：[修复与验证报告](docs/verification/AB_WHITE_SCREEN_REPAIR_20261009.md)。
历史图片显示工程为 `safevision/platform/anlogic_eg4s20_hx4s20c/project/safevision.al`
（顶层 `safevision_top`，HDMI B）；准备与构建命令见该目录 README。
下文部分初期状态说明保留历史背景，当前 A/B 能力与验收状态以本轮报告为准。

> 全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 赛道 · 赛题一
> 《HDMI 多媒体播放与应急视听疏散终端》：平台：康芯 HX4S20C / 安路 EG4S20BG256

面向康芯 HX4S20C / 安路 EG4S20BG256 的三人 FPGA 工程。本仓库采用
可移植业务 RTL + 板级适配 + 分层验证 + 可追溯证据 的组织方式。初期阶段已有
B 链（数据存储链 / 数据搬运）的 RTL 与单元仿真；A/C 链、板级工程和整机联调仍需开发。

目录或文件名的存在不代表功能已实现。当时许多目录只有 README 或占位说明，是否可综合、可上板及已验收，须查对应验证证据。


## 从哪里开始

1. 看 [项目目录说明](docs/PROJECT_STRUCTURE.md)：目录用途、文件归属、现状与计划。
2. 看 [系统架构](docs/architecture/system_design.md) 和 [模块登记表](docs/architecture/module_registry.md)。
3. 跨人对接以现有 [B 链接口规范](docs/interface_spec.md) 为基线；新增 A/C 契约先按 [接口模板](docs/interfaces/interface_template.md) 评审。
4. 工作顺序看 [项目管理](docs/management/README.md) 与 [待办](docs/management/WORK_ITEMS.md)。
5. 测试与交付看 [验证矩阵](docs/verification/test_matrix.md)、[证据索引](evidence/README.md)、[发布规范](docs/release/README.md)。

## 系统数据流

```text
SD/TF → FAT32/文件流 → BMP/WAV → SDRAM/四槽 ──→ 帧读取/视频合成 → HDMI
                                           ↘ 音频调度/优先级 ──→ HDMI 音频
按键/UART/报警 → 控制事件/故障管理 ──────────→ 安全画面/应急选择
```

本仓库负责其中的 B 链：

```text
        ┌──────────────── 本仓库范围（B 链）────────────────┐
TF 卡 ──┤ SPI/SD → FAT32 → 媒体解析 → SDRAM 帧缓存 → 仲裁/DMA ├──▶ 交给 A 显示
        └──────────────────────────────────────────────────┘
```


## 一、这个仓库里有什么、没有什么

本仓库只放"人写的"源码与文档。`.gitignore` 用的是白名单写法：顶层除
`.github/`、`docs/`、`safevision/`、`evidence/`、`README.md`、`.gitignore` 外全部忽略。
原因是工作区里还有约 6.9 GB 不进仓库的东西：

| 被排除的目录 / 文件 | 大小 | 为什么排除 |
|---|---|---|
| `1_安路开发工具和常用软件/` | 4.5 GB | 安路 TD 安装包与驱动 |
| `2_Example/` | 970 MB | 厂商示例工程 |
| `7_lab_ex_2026_nosoft/` | 1.2 GB | 赛方参考例程（赛题指南要求作品架构与参考实例不同，不得照抄） |
| `3_原理图/` `4_芯片手册/` `6_EG4S20数据手册/` `8_FPGA学习资料/` `9_康芯开发板使用手册及实验平台/` | — | 手册、原理图、学习资料 |
| `*.pdf` `*.docx` | — | 赛方手册与选题指南（版权在赛方） |

> 因此 clone 本仓库不会得到赛方手册与原理图，需要向队内索取。
> 另：工作区里的 `SafeVision_项目管理结构\` 是队友交付的项目管理覆盖包，
> 不在白名单里，不会进仓库（它是应用它的脚本的输入，不是仓库内容）。


## 二、目录结构

结构以 [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) 为准（由队友的项目管理架构确立）；
`rtl/` 按"平台无关件 / 存储 / 媒体 /
内存"分层，`verification/` 单元测试与模型分开，`docs/` 只放文档。标 `[骨架]` 的目录
只有 README 或占位说明，尚无功能代码。

```
<仓库根>/
├─ .github/                         PR / 缺陷 / 工作项模板（骨架）
├─ .gitignore                       白名单：只跟踪源码、文档与可复核证据
├─ README.md                        项目入口、能力与阅读顺序
├─ docs/
│  ├─ PROJECT_STRUCTURE.md          目录用途与文件归属
│  ├─ interface_spec.md             B 链冻结接口基线（留在根目录，勿搬）
│  ├─ B链-原理讲解-入门版.md          概念层：为什么这么设计（留在根目录，勿搬）
│  ├─ B链-待办与硬件验证清单.md        板级实测清单与排查顺序（留在根目录，勿搬）
│  ├─ architecture/                 系统图、模块登记表、可移植边界
│  ├─ interfaces/                   新接口模板与评审规则
│  ├─ requirements/                 B01–B04 / E01–E05 追踪
│  ├─ management/                   分工、待办、ADR、变更记录
│  ├─ verification/                 验证策略与测试矩阵
│  └─ release/                      构建冻结、提交与回滚规则
├─ evidence/                        [骨架] 需求→测试→原始证据与索引
├─ safevision/
│  ├─ rtl/
│  │  ├─ include/                   所有 `define` 常量（唯一来源，禁止在别处再抄一份）
│  │  │   ├─ safevision_defs.vh     总入口：时钟/超时/SPI/SD/FAT 常量（已 include 下面三个）
│  │  │   ├─ fault_code_defs.vh     错误码：对外主码 ERR_* + 内部细分码 DET_*
│  │  │   ├─ pixel_format_defs.vh   像素格式 + 帧几何 + 冻结四槽地址表（唯一来源）
│  │  │   └─ event_code_defs.vh     正常事件码与源标识
│  │  ├─ common/                    平台无关通用件（不碰 SD，也不碰内存）
│  │  │   ├─ uart_tx.v              调试串口发送（512 字节回传比对用）
│  │  │   ├─ sync_fifo.v            同域 FIFO（almost_full 反压 / data_count）
│  │  │   ├─ rv_skid_buffer.v       切开 ready 长组合路径的切分缓冲
│  │  │   ├─ error_report.v         错误事件汇聚（不允许丢弃，带溢出计数）
│  │  │   ├─ crc16_ccitt.v          CRC16-CCITT(XMODEM) 字节步进（纯组合，无状态）
│  │  │   ├─ crc7.v                 SD 命令 CRC7 字节步进（纯组合，无状态）
│  │  │   ├─ shift_reg.v            阶段 1 教学件，产品链未例化
│  │  │   └─ spi_byte_rx.v          阶段 1 教学件，产品链未例化
│  │  ├─ storage/                   SPI / SD / FAT32 / 文件流
│  │  │   ├─ spi_master.v           SPI mode0 位引擎（cs_n 是输入，由上层控制）
│  │  │   ├─ sd_initializer.v       CMD0 → CMD8 → ACMD41 → CMD58，每态独立超时
│  │  │   ├─ sd_sector_reader.v     CMD17 单扇区读 512 Byte + CRC16 比对
│  │  │   ├─ mbr_parser.v           MBR 分区表 → 卷基址（分区起始 LBA），供板级顶层换算地址
│  │  │   ├─ fat32_boot_parser.v    DBR/BPB 解析 + FAT32 判别位 + 派生地址
│  │  │   ├─ fat32_directory_scanner.v 根目录遍历 + 四类跳过规则 + 跨簇
│  │  │   ├─ fat32_cluster_walker.v 簇链跟踪（EOC / 越界 / 判环），被下面两者共用
│  │  │   ├─ file_streamer.v        簇链 → 连续字节流
│  │  │   └─ file_index.v           编号扫描 + 数字后缀排序 + 索引表冻结
│  │  ├─ media/                     媒体格式解析
│  │  │   ├─ bmp_parser.v           BMP 头 5 类校验 + 调色板跳过 + top-down
│  │  │   ├─ bmp_unpack.v           BGR888 → RGB565 打包（含行填充处理）
│  │  │   └─ wav_parser.v           RIFF/fmt/data 解析（只收 PCM/2ch/48k/16bit）
│  │  ├─ memory/                    SDRAM / 帧缓存 / 仲裁 / 帧交换
│  │  │   ├─ mem_ctrl.v             SDRAM IP wrapper（对外只暴露逻辑字节地址）
│  │  │   ├─ frame_address_gen.v    逻辑字节地址公式 slot_base+(y*W+x)*BPP
│  │  │   ├─ frame_writer.v         写一帧 307200 像素 + 抽样 CRC + 置 slot_valid
│  │  │   ├─ frame_buffer_manager.v 槽所有权 / active_slot / generation（原子提交）
│  │  │   ├─ memory_arbiter.v       固定优先级 + 单次占用上限 + 最长等待提权（防饥饿）
│  │  │   ├─ video_read_dma.v       水位驱动突发预取
│  │  │   ├─ frame_swap_ctrl.v      帧交换状态机（超时进 SAFE，保持画面）
│  │  │   ├─ frame_swap_cdc.v       toggle 同步 + mailbox 锁存
│  │  │   ├─ memory_bandwidth_monitor.v 带宽计数器
│  │  │   └─ fifo_health_monitor.v  历史最低水位 + underflow/overflow
│  │  ├─ video/                     [模块目录] A：时序、帧读取、合成与 OSD；功能 RTL 待写
│  │  ├─ audio/                     [骨架] C：音频调度与优先级
│  │  ├─ control/                   [骨架] C：按键、播放状态、事件
│  │  ├─ safety/                    [骨架] C：故障、看门狗与降级控制
│  │  └─ top/                       [模块目录] A：safevision_core/，功能 RTL 待写
│  ├─ platform/                     [部分 RTL] 板级适配层
│  │  ├─ anlogic_eg4s20_hx4s20c/
│  │  │  ├─ rtl/clock/              复位控制（reset_sync / clock_reset_ctrl，A）
│  │  │  ├─ rtl/top_stage5_sector_rd.v      板级 bring-up 顶层（接引脚，阶段 5，不接 PLL）
│  │  │  ├─ rtl/top_stage6_fat32_mount.v    bring-up 顶层（阶段 6–7，FAT32 挂载 + 目录扫描）
│  │  │  ├─ rtl/top_sdram_loopback.v        bring-up 顶层（阶段 9 第一步，SDRAM 回环，接 PLL）
│  │  │  ├─ constraints/            pin.adc + timing.sdc（已按原理图核对；含 derive_clocks）
│  │  │  ├─ project/safevision.al   TD 6.2 工程（TOP_MODULE = top_sdram_loopback）
│  │  │  └─ ip/                     厂商 IP：sdram/（应用级控制器 + 3 个安路加密 .enc.v）、pll/（sv_system_pll / sv_video_*_pll / sv_audio_pll）
│  │  └─ sim/                       [骨架] 非厂商仿真适配层
│  ├─ build/                        [骨架] 文件清单、参数配置、构建说明
│  ├─ assets/                       [骨架] 可再生字体、图案、SD 测试素材说明
│  ├─ verification/
│  │  ├─ models/                    行为级模型（sd_spi_card_model.sv / frame_memory_model.sv）
│  │  ├─ unit/                      单元测试台（B 18 个 + A clock 1 个；含板级顶层 TB）
│  │  ├─ subsystem/                 [骨架] SD→帧缓存、缓存→HDMI 等联调
│  │  ├─ system/                    [骨架] 三链整机、故障与长稳
│  │  └─ board/                     上板采集脚本（capture_uart_512.ps1：UART 512 Byte 回传 + 与参考值比对）
│  └─ tools/
│      ├─ run_sim.ps1               B 链回归：编译 + 跑全部 testbench + 汇总断言数
│      └─ check_repo.ps1            目录与 run_sim 引用自检（不需要 ModelSim）
```

为什么同时有 `.v` 和 `.sv`（项目自定约定，出自早期架构评审，不是随手选的）：

| 位置 | 扩展名 | 语言子集 | 理由 |
|---|---|---|---|
| `rtl/**` | `.v` | Verilog-2001 子集 | 要过安路 TD 的综合/布线。TD 对 SystemVerilog 只部分支持且有版本差异，用厂商保证支持的子集才不会出现"仿真过了、综合报错或综合出不同电路"。另外 `wire`/`reg` 比 `logic` 更能让人看出"这是网线还是寄存器" |
| `rtl/include/**` | `.vh` | 宏定义 | 头文件 |
| `verification/**` | `.sv` | 允许 SystemVerilog | TB 不综合，只跑在 ModelSim 里，不受 TD 限制；`vlog` 按扩展名自动选语言版本 |

当时 `.sv` 文件几乎都使用 Verilog-2001 写法，全仓仅有一个 `fork/join`，该语法也属于 Verilog-2001。`.sv` 扩展名用于区分验证文件，不表示文件已采用 `logic`、`always_ff` 或断言。新增 RTL 使用 `.v`，不将 `.sv` 放进会进入 TD 综合的 `rtl/`。

A 模块目录与当前代码：`rtl/video/` 下按 Video Timing、Pattern Generator、Graphics ROM、OSD、Pipeline、Frame Reader、Compositor、Safe Scene、Emergency MUX、CDC 建立独立文件夹；`rtl/top/safevision_core/` 已建。板级 `rtl/` 下已建 `clock/`、`pixel_fifo/`、`hdmi/`、`chipwatcher/`、`safevision_top/`，`ip/` 下已建 PLL/FIFO/BRAM/HDMI 落点。`platform/.../rtl/clock/` 有 `reset_sync.v` 与 `clock_reset_ctrl.v` 功能 RTL；`platform/.../rtl/top_stage5_sector_rd.v`（B 的阶段 5 板级 bring-up 顶层）与 `constraints/{pin.adc,timing.sdc}` 也已落地；其余 A 目录只有 README。详细路径见 [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)。C 的骨架、`build/`、`assets/`、`verification/{subsystem,system,board}`、`evidence/` 仍是规划落点。

有意不创建（同样出自项目自定原则「三人团队不要模仿大公司堆叠复杂框架」）：
`rtl/csr/`（CSR 总线）、`rtl/diagnostics/`、`rtl/platform/`（板级适配已放在
`safevision/platform/`）、formal 验证、nightly CI、HIL、release manifest、HAL、
Codec I²C 控制。理由留档在 [interface_spec.md](docs/interface_spec.md) 的命名迁移表下方。


## 三、怎么跑仿真

环境：ModelSim SE-64 10.7。ModelSim 的 `win64` 目录从 `-ModelSimBin` 参数拿，
省略时回退到 `MSIM_BIN` 环境变量：脚本里不再写死任何本机路径，
两个入口（`run_sim.ps1` / `run_clock_sim.ps1`）用同一套口径：

```powershell
# 任一方式：
$env:MSIM_BIN = "D:\path\to\modeltech64_10.7\win64"
powershell -ExecutionPolicy Bypass -File safevision\tools\run_sim.ps1

powershell -ExecutionPolicy Bypass -File safevision\tools\run_sim.ps1 -ModelSimBin D:\path\to\modeltech64_10.7\win64
```

脚本会 `vlib work` → 编译全部 RTL 与 testbench → 逐个 `vsim` 运行 → 汇总
`[PASS]`/`[FAIL]` 计数。最终 `FAIL` 必须是 0，否则脚本以非零退出码结束。

> 想一次跑完所有验证入口？用 `run_all.ps1`（2026-10-05 新增）
> ```powershell
> powershell -ExecutionPolicy Bypass -File safevision\tools\run_all.ps1
> ```
> 它依次跑本机能跑的入口，跑不了的明确报 `SKIP`（并说明缺什么），绝不报 PASS；
> 只有 `RESULT: ALL PASS` 才 exit 0。
> 工程现在有 12 个 `run_*.ps1` 入口、跨两套工具链（ModelSim + XSim/Vivado，外加 TD STA），
> 而 `run_sim.ps1` 完全不含 A 的 9 个 `tb_a_*` ⇒ "B 侧绿了"≠"整机绿了"。
> 逐条清单见 [docs/verification/test_matrix.md](docs/verification/test_matrix.md) 的"验证入口总清单"。
> 本机实测（2026-10-05）：`PASS=4 FAIL=0 SKIP=7`（本机有 ModelSim + TD，没有 Vivado；
> 跳过的 7 项全是 XSim 入口）。本地干活可用 `-AllowSkip`；
> 发布 / 交接前必须用严格模式跑，只有 `ALL PASS` 才算过。

> 维护脚本时注意：`run_sim.ps1` 必须保持纯 ASCII 注释。PowerShell 5.1 在没有 BOM
> 时按 ANSI 解码 `.ps1`，中文注释会把后面的引号"吃掉"导致解析失败。中文注释写在 RTL 里。

新增 B 链模块 / testbench（含板级 bring-up 顶层）时，把文件分别加进本脚本的
`$RTL` / `$SIM` / `$TBS` 三个列表，否则文件等于死文件。

A clock 的 RTL/TB 用独立入口（同一套 `-ModelSimBin` / `MSIM_BIN` 口径），并已在本机运行通过（`clock/reset checks: 88 pass, 0 fail`）：

```powershell
powershell -ExecutionPolicy Bypass -File .\safevision\tools\run_clock_sim.ps1 -ModelSimBin <ModelSim的win64目录>
```

现有 B 回归与目录自检（目录自检不需要 ModelSim）：

```powershell
powershell -ExecutionPolicy Bypass -File .\safevision\tools\check_repo.ps1
```

`check_repo.ps1` 核对必需目录/文件是否存在，并解析 `run_sim.ps1` 里的 `$RTL/$SIM/$TBS`
引用是否有断链；输出 `LAYOUT PASS` 才算通过。


## 四、当前状态

| 项 | 状态 |
|---|---|
| 手册学习阶段 1 至 16 | 全部落地并仿真通过 |
| 媒体格式层（BMP 解析/解包、WAV 解析） | 已完成并仿真通过 |
| 目录树与命名 | 已按本项目结构（PROJECT_STRUCTURE.md）核对完成（含"同一常量多副本"的结构性收敛） |
| B 链仿真回归 | 618 项断言 / 24 个 testbench / 2 个行为模型 + 1 个厂商 IP 仿真桩，全 PASS（已在本机重跑） |
| 板级顶层 `top_stage5_sector_rd.v` | 已写、仿真通过、上板跑通（板上 LED = `8`；`tb_top_stage5_sector_rd` 5 项断言） |
| 板级顶层 `top_stage6_fat32_mount.v` | 已写 + 仿真通过（阶段 6 至 7）：上电 → SD 初始化 → `mbr_parser` → `fat32_boot_parser` → `fat32_directory_scanner`(+walker) → UART 发纯 ASCII 报告；卷基址只在此顶层加一次（见 [interface_spec §3.2.1](docs/interface_spec.md)）。磁盘上的 `.al` 现为阶段 5 配置，本模块当前未登记进工程（见 [module_registry.md](docs/architecture/module_registry.md) 的说明） |
| 板级顶层 `top_sdram_loopback.v` | 旧版已上板通过（M-11-PASS）；A/B 当前集成源码尚待重新回归、STA 与板测：50 MHz → `sv_system_pll`（125 MHz + 180°）→ 厂商 SDRAM 控制器 → 写图案 / 读回比对 → UART 发定长报告。实测 `INIT=01 LOCK=01` / `W=1000 R=1000 CAP=1000 BAD=0000` / `DONE`，与设计值逐字节一致（`evidence/board/` 条目 M-11-PASS）。应用层回归：B 的 `run_sim.ps1`（ModelSim）全量 22 TB / 588 项通过；合并后的 A/B `tb_sdram_loopback.sv` 也通过 ModelSim fallback 六场景及 21-bit 穷举。A XSim 专用入口因本机缺少 XSim 2018.3 未执行。两种模型均不模拟真实 SDRAM AC。当前集成版已重跑 TD Routed STA：全局 setup −6.826 ns（65 个端点），自研 `clkc[1]→clkc[1]` 报告路径 +0.113 ns / 0 违例（2517 端点）（2026-10-05 订正：这里原先误抄成修复前的旧值 `−0.094 ns`；`−0.094 → +0.113` 是"两级报告选择器"那次修复的 before→after，修复后的值才是当前值。来源 `project/report22.txt`，2026-10-04 20:53，顶层 `top_sdram_loopback`），全局 setup 仍 `−6.826 ns`（来自 `clkc[2]→clkc[1]` 的 SDRAM 读回路径，32 个违例端点；另有 `clkc[1]→clkc[2]` 写侧 −2.859 ns / 32 端点），故仍不收敛；尚无匹配位流或合并版板测。TD 工程 `TOP_MODULE` 设为 `top_sdram_loopback`。2026-10-03：PLL 去重（B 的 `sys_pll` 并入 A 的 `sv_system_pll`）后已重新综合 + 复测通过，报文与 M-11 逐字节相同（条目 M-11-PASS-2）。2026-10-04 改版（M-11 补测「全片稀疏扫描」+「扩展图案 + soak」）：报告 71 → 190 Byte（加 `CFG` 自描述、`RND/PAT` 轮次与图案模式、`TOT` 累计搬运量、`BAD0` 首个错点含轮次），B 旧版参数使用 `ADDR_SHIFT=11 + ADDR_LOWSTEP=1 + TEST_WORDS=1024`（步长 2049 的 1024 个稀疏样本跨越近乎完整地址范围，不等于逐 word 全容量测试）；新增 `ROUNDS` soak（重复 N 轮、每轮换一种图案模式、出错立即停）与 6 种图案模式（地址派生 / LFSR / walking-1 / walking-0 / 全0全1 / 相邻位交替）；测试图案抽成可仿真的 `rtl/memory/sdr_pat_gen.v` + `tb_sdr_pat_gen`（22 项）：因为旧图案公式在稀疏扫描下只有 2 种图案（写读自比看不出来）。此前本地 B soak 构建的全片稀疏扫描与 10 秒 / 10 分钟 / 约 60 分钟 soak 均板测零错（汇总见待办清单 §2.4.2）；这些结果不自动验收 A `d6f40a6` 后的合并 RTL。A/B 合并版应用回归已通过，但最新 TD routed 仍有全局 setup −6.826 ns 与自研报告路径 −0.094 ns；未生成新位流、未进行合并版板测 |
| 板级顶层 `top_stage10_framebuffer.v` | 已写 + 已上板 bring-up（2026-10-03，阶段 10 帧缓存回环）：`framebuffer_loopback_core`（可仿真，11/11 PASS）+ `sdram_app_adapter`（通用口↔厂商 App 口，6/6 PASS，有单元 TB）+ 厂商 `sdram` + `uart_tx`。2026-10-03 板上验收通过：整帧 307200 像素逐像素零错（`WR=RD=04B000`、`BAD=000000`），三个地址斜坡探针全对（`AM=FFFFFFFF`、`C0..C3=1004..1007`、`B0..B3=1035..1038`）。四轮推进：第 2 轮用「地址斜坡探针」定案（一次连续读突发里读地址只推进 4 个字就回绕，帧级 `BAD` 恰为 3/4）⇒ 读引擎按 M-11 形态重写；第 3 轮验证读侧已根治（`AM=FFFFFFFF` 32/32 全对、跨两次预取；探针 C 全对），但暴露我引入的一处死锁（缓冲没排空时跳到缓冲外地址不重预取 ⇒ `B=0000` + `WR=000000`）⇒ 已修 + 补 TB 用例 D7。报告瘦身为 208 Byte 修 STA（违例端点 475 → 312），最差路径换成适配器的 32 位加法器 ⇒ 已用寄存器 `rexp` + 读侧 ready 寄存器化切掉。待重新综合（务必确认自研组 SWNS ≥ 0）+ 复测，步骤见 `docs/B链-待办与硬件验证清单.md` §2.5 |
| 厂商 IP 落库 | 新增（2026-10-02）：`ip/sdram/`（应用级 `sdram.v` + `global_def.v` + 3 个安路加密 `sdr_*.enc.v` + `sdram.ipc`）、`ip/pll/`（`sv_system_pll` / `sv_video_*_pll` / `sv_audio_pll`）。EG4S20 的 SDRAM 是封装内硬核（2M×32），信号不出引脚 ⇒ `pin.adc` 不需要 SDRAM 引脚 |
| 阶段 1 至 5 上板验收 | 已通过（2026-10-02）：实物 UART 回传 512 Byte 与电脑侧参考 SHA-256 完全相同（M-9，见 [evidence/board/INDEX.md](evidence/board/INDEX.md) 的 M-9-PASS） |
| 引脚约束 `pin.adc` / 时序约束 `timing.sdc` | 已写并核对（引脚来自开发板手册官方表 + 原理图 + 厂商例程，三处一致）；`uart_txd=D12` 已确认为 FPGA 发送脚，板载 USB-UART 可直接用 |
| TD 工程 `project/safevision.al` | 综合 → 布局 → 布线 → 位流全跑通并已上板（`TARGET_LBA=8192` 那次构建，2026-10-02 17:29 下载成功）；时序收敛（Setup WNS +11.297 ns / Hold WNS +0.046 ns，违反端点 0，50 MHz 下 Fmax 114.9 MHz），资源 IO 11/188、LUT 814/19600、REG 434/19600。该时序/资源报告（TC-Q-STA）对应的是 `TARGET_LBA=1000` 的构建，重综合后建议补一条证据 |
| 上板实测（M-1 ~ M-19） | 阶段 1 至 7 + 阶段 9 第一步已通过：M-9（512/512 逐字节）、M-10（卷基址/BPB/目录 5 项）、M-6（连读 100 次）、M-8a（无卡有界退出）、M-11 历史 B 构建（稀疏扫描及三档 soak `BAD=0000`；A d6f40a6 合并版待复测）。待做：M-5/M-7/M-8「连读中途拔卡」/M-10 精确拍数/阶段 10 至 16（须等 A 的整机）。步骤见 [B链-待办与硬件验证清单.md](docs/B链-待办与硬件验证清单.md) §2.2 / §2.4.2 |
| 整机集成 `safevision_core.v` / `safevision_top.v` | A 负责 |
| A 板级时钟复位 | `reset_sync.v` 与 `clock_reset_ctrl.v` 已写并仿真通过（88 项）；PLL IP/约束/板级实测待完成 |

各 testbench 的覆盖与断言数见 [B链-待办与硬件验证清单.md](docs/B链-待办与硬件验证清单.md) §零。


## 五、文档三件套（改代码必须同步改文档）

| 文档 | 什么时候必须更新 |
|---|---|
| [interface_spec.md](docs/interface_spec.md) | 任何信号名 / 有效电平 / 时钟域 / 延迟 / 异常策略变更。接口先于联调存在，改接口必须先改这里并通知对接人 |
| [B链-待办与硬件验证清单.md](docs/B链-待办与硬件验证清单.md) | 阶段状态、回归断言数、已知未完成项发生变化时 |
| [B链-原理讲解-入门版.md](docs/B链-原理讲解-入门版.md) | 设计取舍发生变化、或新增了值得交接给下一位的概念解释时 |

> 这三份 B 链文档（`docs/interface_spec.md`、`docs/B链-待办与硬件验证清单.md`、
> `docs/B链-原理讲解-入门版.md`）暂时留在 `docs/` 根目录，不要搬进任何子目录：
> 它们是多处引用的交付物，搬动会打断引用。

另外 `interface_spec.md` 里的命名迁移表是手册旧名 ↔ 工程名的对应关系，以及
"有意不采纳的部分"的留档，改目录结构时一并维护。


## 六、几条必须背下来的硬约定

这些是实测踩出来的，不是理论。完整清单见原理讲解 §13.4。

1. 从上游收数据必须用 `valid && ready` 双判，只判 `valid` 会把同一字节吃掉多次。
2. "下游取走数据"的清零逻辑放在状态机之外，否则最后一个字节锁存那一拍正好跳态，
   `valid` 再没人清，直接死等超时。
3. 多字节字段（FAT 入口、BMP 头、WAV）是小端；SD 命令参数是大端。两者不能混。
4. 每个"等外部回应"的状态都要有独立超时出口。没有超时在硬件上等于永久死机。
5. `slot_valid` 未置位不许读该槽。这条把"半张图进画面"在结构上排除。
6. 冻结地址表与帧几何只能来自 `rtl/include/pixel_format_defs.vh`，业务模块里
   禁止出现裸物理地址或第二份地址副本。
7. 公共算法（`crc16_ccitt.v` / `crc7.v`）只用 `rtl/common/` 那一份，不要在模块里再写一遍。
8. 禁止手写异步 FIFO，跨时钟域用安路软 FIFO IP。
9. 一个 `reg` 只能有一个驱动源（同一个 `always` 块），连复位赋值也算。
   ModelSim 对"两个 `always` 块写同一个 `reg`"不报错（仿真里只是竞争），
   但 TD 综合会报 `net 'x' is constantly driven from multiple places` 并把模块降级成黑盒。
   推论：仿真全部通过 ≠ 能综合：改完 RTL 一定要真跑一次 TD 综合。
   （2026-10-02 真实踩问题：`sd_initializer` / `sd_sector_reader` 的 `bdata`。）


## 七、分支与协作

- 远端仓库：<https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026>，分支 `main`
  （2026-09-29 由 `desktop-tutorial` 改名而来；旧地址会重定向，但本地 `origin` 已指向新地址）。
- 主分支 `main`。B 链改动直接进 `main`；A / C 各自有自己的目录，互不改动对方文件。
  功能分支按 `feat/<模块>`、修复按 `fix/<问题>` 命名。
- 提交信息用 ASCII（避免控制台编码乱码），内容说明"为什么改"而不只是"改了什么"。
- 接口变更走 `interface_spec.md` 的变更历史表登记，并在表里注明版本号。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](docs/clock_video_implementation.md)，端口/时钟域见 [A接口补充](docs/A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](docs/A_PUSH_SCOPE_20261002.md)。

## A 阶段十：数拍与标签对齐（2026-10-03）

新增 `video_pipeline.v`、`tb_video_pipeline.sv`、`tb_video_pipeline_timing.sv` 和 `run_video_pipeline_sim.ps1`：验证任意固定延迟、手册 1+2+1=4 拍链路、RGB565 接口、整帧扫描与中途复位。两个新 TB 全部通过；A/B 源文件合编、TD 的 45 条工程源 RTL 综合通过。`safevision.al` 仅登记新模块，仍使用 B 的 `top_sdram_loopback`，不包含仿真 TB。

独立 BASE/HD 验证顶层内部布局布线时序无负裕量；已有 PLL 反馈网络告警和板级 I/O 预算仍开放，尚不能称整机签核。端口、数拍约定、运行命令和验收边界见 [A阶段十说明](docs/A_stage10_latency.md)。本次只交付源代码、TB、仿真入口与必要接口/工程登记，不上传运行日志或时序记录。


## A 阶段 1 至 9 发布补充（2026-10-04）

已新增基础四模块、五种测试图/单像素框、同步 ASCII 字库、状态/坐标文字和四级 OSD 图形前端；5 个新 TB、ROM 初始化回读、BASE/HD 内部 STA 通过，原 B 18 TB/540 项和阶段十回归通过。B/C RTL 及 B 回环顶层保持现行版本，`.al` 只增加 A 源文件，当前 56 个条目。源码与复现方法见 [A 阶段 1 至 9](docs/A_stages1_9.md)。原 SDRAM 负裕量与 PLL 健康告警仍开放，未完成上板/HDMI 验收；功能完成不等于整机烧录验收。

## B 阶段 9：A/B 集成 UART selector 时序修复（2026-10-04）

`top_sdram_loopback.v` 的 190 Byte 报告选择器已改为两级（行寄存、行内取字节），Routed C1→C1 setup 从 `−0.094 ns` 改善为 `+0.113 ns`，0/2517 违例端点，Fmax 126.791 MHz。全局 setup 仍 `−6.826 ns`（SDRAM DQ），hold `+0.030 ns`；因此不是整板时序通过。当前 selector 版已用 ModelSim SE-64 10.7 跑过专用应用层仿真：编译 0 error/0 warning、六场景 PASS；独立索引对照另通过 190/190 项。当前源码尚未生成匹配位流或上板。TD GUI/上板操作由用户完成，后续 10 分钟 soak 通过核验后再讨论 push。详见 [SDRAM/PLL 时序核查 §7.2](docs/B链-SDRAM接口与PLL时序核查.md) 和 [待办清单 §2.4.2](docs/B链-待办与硬件验证清单.md)。
