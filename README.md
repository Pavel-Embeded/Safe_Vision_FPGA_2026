# SafeVision FPGA 2026

> 全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 赛道 · 赛题一
> 《HDMI 多媒体播放与应急视听疏散终端》—— 平台：康芯 HX4S20C / 安路 EG4S20BG256

面向康芯 HX4S20C / 安路 EG4S20BG256 的三人 FPGA 工程。本仓库采用
**可移植业务 RTL + 板级适配 + 分层验证 + 可追溯证据** 的组织方式。当前已有
**B 链（数据存储链 / 数据搬运）的 RTL 与单元仿真**；A/C 链、板级工程和整机联调仍需开发。

> ★ **任何目录或文件名的存在都不代表功能已经实现。** 本仓库里大量目录只是"落点"
> （只有 README 或占位说明），真正可综合、可上板、通过验收的功能以验证证据为准。

---

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

本仓库负责其中的 **B 链**：

```text
        ┌──────────────── 本仓库范围（B 链）────────────────┐
TF 卡 ──┤ SPI/SD → FAT32 → 媒体解析 → SDRAM 帧缓存 → 仲裁/DMA ├──▶ 交给 A 显示
        └──────────────────────────────────────────────────┘
```

---

## 一、这个仓库里有什么、没有什么

本仓库**只放"人写的"源码与文档**。`.gitignore` 用的是**白名单**写法：顶层除
`.github/`、`docs/`、`safevision/`、`evidence/`、`README.md`、`.gitignore` 外全部忽略。
原因是工作区里还有约 **6.9 GB** 不进仓库的东西：

| 被排除的目录 / 文件 | 大小 | 为什么排除 |
|---|---|---|
| `1_安路开发工具和常用软件/` | 4.5 GB | 安路 TD 安装包与驱动 |
| `2_Example/` | 970 MB | 厂商示例工程 |
| `7_lab_ex_2026_nosoft/` | 1.2 GB | 赛方参考例程（赛题指南要求作品架构与参考实例不同，不得照抄） |
| `3_原理图/` `4_芯片手册/` `6_EG4S20数据手册/` `8_FPGA学习资料/` `9_康芯开发板使用手册及实验平台/` | — | 手册、原理图、学习资料 |
| `*.pdf` `*.docx` | — | 赛方手册与选题指南（版权在赛方） |

> 因此 **clone 本仓库不会得到赛方手册与原理图**，需要向队内索取。
> 另：工作区里的 `SafeVision_项目管理结构\` 是队友交付的项目管理覆盖包，
> **不在白名单里，不会进仓库**（它是应用它的脚本的输入，不是仓库内容）。

---

## 二、目录结构

结构以 [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) 为准（由队友的项目管理架构确立，
原引自《工业级模块化架构蓝图》§4，**2026-09-29 起蓝图不再作为结构依据**）；`rtl/` 按"平台无关件 / 存储 / 媒体 /
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
│  │  ├─ video/                     [骨架] A：时序、帧读取、合成与 OSD
│  │  ├─ audio/                     [骨架] C：音频调度与优先级
│  │  ├─ control/                   [骨架] C：按键、播放状态、事件
│  │  ├─ safety/                    [骨架] C：故障、看门狗与降级控制
│  │  └─ top/                       [骨架] A：不含板级引脚的系统核心
│  ├─ platform/                     [骨架] 板级适配层
│  │  ├─ anlogic_eg4s20_hx4s20c/    [骨架] 板级顶层、IP、约束、TD 工程
│  │  └─ sim/                       [骨架] 非厂商仿真适配层
│  ├─ build/                        [骨架] 文件清单、参数配置、构建说明
│  ├─ assets/                       [骨架] 可再生字体、图案、SD 测试素材说明
│  ├─ verification/
│  │  ├─ models/                    行为级模型（sd_spi_card_model.sv / frame_memory_model.sv）
│  │  ├─ unit/                      单元测试台（15 个，每个被测件一个，断言名即规格）
│  │  ├─ subsystem/                 [骨架] SD→帧缓存、缓存→HDMI 等联调
│  │  ├─ system/                    [骨架] 三链整机、故障与长稳
│  │  └─ board/                     [骨架] 上板步骤与采集脚本
│  └─ tools/
│      ├─ run_sim.ps1               B 链回归：编译 + 跑全部 testbench + 汇总断言数
│      └─ check_repo.ps1            目录与 run_sim 引用自检（不需要 ModelSim）
```

**为什么同时有 `.v` 和 `.sv`**（项目自定约定，出自早期架构评审，不是随手选的）：

| 位置 | 扩展名 | 语言子集 | 理由 |
|---|---|---|---|
| `rtl/**` | `.v` | **Verilog-2001 子集** | 要过安路 TD 的综合/布线。TD 对 SystemVerilog 只部分支持且有版本差异，用厂商保证支持的子集才不会出现"仿真过了、综合报错或综合出不同电路"。另外 `wire`/`reg` 比 `logic` 更能让人看出"这是网线还是寄存器" |
| `rtl/include/**` | `.vh` | 宏定义 | 头文件 |
| `verification/**` | `.sv` | 允许 SystemVerilog | TB 不综合，只跑在 ModelSim 里，不受 TD 限制；`vlog` 按扩展名自动选语言版本 |

> 说实话：目前 `.sv` 文件的内容**几乎全是 Verilog-2001 写法**（全仓只有一个 `fork/join`，
> 而它本身就是 Verilog-2001 就有的）。扩展名按这个分工走了，内容是保守派写法——
> 这是可接受的，但别因为看到 `.sv` 就以为里面有 `logic`/`always_ff` 或断言。
> **新增 RTL 一律 `.v`；不要把 `.sv` 放进 `rtl/`**（那会进 TD 综合）。

**已建骨架、尚无功能代码**（项目自定原则：先建落点和命名计划，不生成假 RTL）：
`rtl/{video,audio,control,safety,top}`、`platform/`、`build/`、`assets/`、
`verification/{subsystem,system,board}`、`evidence/` 都只放 README 或占位说明，没有功能
RTL。A 链（视频与顶层集成）与 C 链（控制与音频）各自独立实现。

**有意不创建**（同样出自项目自定原则「三人团队不要模仿大公司堆叠复杂框架」）：
`rtl/csr/`（CSR 总线）、`rtl/diagnostics/`、`rtl/platform/`（板级适配已放在
`safevision/platform/`）、formal 验证、nightly CI、HIL、release manifest、HAL、
Codec I²C 控制。理由留档在 [interface_spec.md](docs/interface_spec.md) 的命名迁移表下方。

---

## 三、怎么跑仿真

环境：ModelSim SE-64 10.7（脚本顶部的 `$MSIM_BIN` 指向 ModelSim 安装目录，**换机器必须改它**，
见 [run_sim.ps1](safevision/tools/run_sim.ps1)）。

```powershell
powershell -ExecutionPolicy Bypass -File safevision\tools\run_sim.ps1
```

脚本会 `vlib work` → 编译全部 RTL 与 testbench → 逐个 `vsim` 运行 → 汇总
`[PASS]`/`[FAIL]` 计数。**最终 `FAIL` 必须是 0**，否则脚本以非零退出码结束。

> ★ 维护脚本时注意：**`run_sim.ps1` 必须保持纯 ASCII 注释**。PowerShell 5.1 在没有 BOM
> 时按 ANSI 解码 `.ps1`，中文注释会把后面的引号"吃掉"导致解析失败。中文注释写在 RTL 里。

新增模块 / 新增 testbench 时，把文件分别加进脚本的 `$RTL` / `$SIM` / `$TBS` 三个列表。

**现有 B 回归**与目录自检（目录自检不需要 ModelSim）：

```powershell
powershell -ExecutionPolicy Bypass -File .\safevision\tools\check_repo.ps1
```

`check_repo.ps1` 核对必需目录/文件是否存在，并解析 `run_sim.ps1` 里的 `$RTL/$SIM/$TBS`
引用是否有断链；输出 `LAYOUT PASS` 才算通过。

---

## 四、当前状态

| 项 | 状态 |
|---|---|
| 手册学习阶段 1–16 | **全部落地并仿真通过** |
| 媒体格式层（BMP 解析/解包、WAV 解析） | 已完成并仿真通过 |
| 目录树与命名 | 已按本项目结构（PROJECT_STRUCTURE.md）核对完成（含"同一常量多副本"的结构性收敛） |
| 仿真回归 | **502 项断言 / 15 个 testbench / 2 个行为模型，全 PASS** |
| 板级顶层 `top_stage5_sector_rd.v` | 未开始（见待办清单 §2.3） |
| 引脚约束 `pin.adc` / 时序约束 `timing.sdc` | 未开始（见待办清单 §1.3） |
| 上板实测（M-1 ~ M-19） | **未开始，等板子** |
| 整机集成 `safevision_core.v` / `safevision_top.v` | A 负责 |

各 testbench 的覆盖与断言数见 [B链-待办与硬件验证清单.md](docs/B链-待办与硬件验证清单.md) §零。

---

## 五、文档三件套（改代码必须同步改文档）

| 文档 | 什么时候必须更新 |
|---|---|
| [interface_spec.md](docs/interface_spec.md) | **任何信号名 / 有效电平 / 时钟域 / 延迟 / 异常策略变更**。接口先于联调存在，改接口必须先改这里并通知对接人 |
| [B链-待办与硬件验证清单.md](docs/B链-待办与硬件验证清单.md) | 阶段状态、回归断言数、已知未完成项发生变化时 |
| [B链-原理讲解-入门版.md](docs/B链-原理讲解-入门版.md) | 设计取舍发生变化、或新增了值得交接给下一位的概念解释时 |

> 这三份 B 链文档（`docs/interface_spec.md`、`docs/B链-待办与硬件验证清单.md`、
> `docs/B链-原理讲解-入门版.md`）**暂时留在 `docs/` 根目录，不要搬进任何子目录**：
> 它们是多处引用的交付物，搬动会打断引用。

另外 `interface_spec.md` 里的**命名迁移表**是手册旧名 ↔ 工程名的对应关系，以及
"有意不采纳的部分"的留档，改目录结构时一并维护。

---

## 六、几条必须背下来的硬约定

这些是**实测踩出来的**，不是理论。完整清单见原理讲解 §13.4。

1. **从上游收数据必须用 `valid && ready` 双判**，只判 `valid` 会把同一字节吃掉多次。
2. **"下游取走数据"的清零逻辑放在状态机之外**，否则最后一个字节锁存那一拍正好跳态，
   `valid` 再没人清，直接死等超时。
3. **多字节字段（FAT 入口、BMP 头、WAV）是小端**；SD 命令参数是**大端**。两者不能混。
4. **每个"等外部回应"的状态都要有独立超时出口**。没有超时在硬件上等于永久死机。
5. **`slot_valid` 未置位不许读该槽**。这条把"半张图进画面"在结构上排除。
6. **冻结地址表与帧几何只能来自 `rtl/include/pixel_format_defs.vh`**，业务模块里
   禁止出现裸物理地址或第二份地址副本。
7. **公共算法（`crc16_ccitt.v` / `crc7.v`）只用 `rtl/common/` 那一份**，不要在模块里再写一遍。
8. **禁止手写异步 FIFO**，跨时钟域用安路软 FIFO IP。

---

## 七、分支与协作

- 远端仓库：<https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026>，分支 `main`
  （2026-09-29 由 `desktop-tutorial` 改名而来；旧地址会重定向，但本地 `origin` 已指向新地址）。
- 主分支 `main`。B 链改动直接进 `main`；A / C 各自有自己的目录，互不改动对方文件。
  功能分支按 `feat/<模块>`、修复按 `fix/<问题>` 命名。
- 提交信息用 ASCII（避免控制台编码乱码），内容说明"为什么改"而不只是"改了什么"。
- 接口变更走 `interface_spec.md` 的变更历史表登记，并在表里注明版本号。