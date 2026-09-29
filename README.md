# SafeVision（安视）· 赛题一 B 链

> 全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 赛道 · 赛题一
> 《HDMI 多媒体播放与应急视听疏散终端》—— 平台：康芯 HX4S20C / 安路 EG4S20BG256

本仓库是参赛作品的 **B 链（数据存储链 / 数据搬运）** 工程：把 TF 卡里的图片与音频，
按确定性的时序搬进 SDRAM 帧缓存，交给 A 链显示、C 链处理输入与故障。

```
        ┌──────────────── 本仓库范围（B 链）────────────────┐
TF 卡 ──┤ SPI/SD → FAT32 → 媒体解析 → SDRAM 帧缓存 → 仲裁/DMA ├──▶ 交给 A 显示
        └──────────────────────────────────────────────────┘
```

---

## 一、这个仓库里有什么、没有什么

本仓库**只放"人写的"源码与文档**。`.gitignore` 用的是**白名单**写法：顶层除
`safevision/`、`docs/`、`README.md`、`.gitignore` 外全部忽略。原因是工作区里还有约
**6.9 GB** 不进仓库的东西：

| 被排除的目录 / 文件 | 大小 | 为什么排除 |
|---|---|---|
| `1_安路开发工具和常用软件/` | 4.5 GB | 安路 TD 安装包与驱动 |
| `2_Example/` | 970 MB | 厂商示例工程 |
| `7_lab_ex_2026_nosoft/` | 1.2 GB | 赛方参考例程（赛题指南要求作品架构与参考实例不同，不得照抄） |
| `3_原理图/` `4_芯片手册/` `6_EG4S20数据手册/` `8_FPGA学习资料/` `9_康芯开发板使用手册及实验平台/` | — | 手册、原理图、学习资料 |
| `*.pdf` `*.docx` | — | 赛方手册与选题指南（版权在赛方） |

> 因此 **clone 本仓库不会得到赛方手册与原理图**，需要向队内索取。

---

## 二、目录结构

结构对齐《工业级模块化架构蓝图》§4 的仓库树约定；`rtl/` 按"平台无关件 / 存储 / 媒体 /
内存"分层，`verification/` 单元测试与模型分开，`docs/` 只放文档。

```
safevision/
├── rtl/
│   ├── include/                      所有 `define` 常量（唯一来源，禁止在别处再抄一份）
│   │   ├── safevision_defs.vh        总入口：时钟/超时/SPI/SD/FAT 常量（已 include 下面三个）
│   │   ├── fault_code_defs.vh        错误码：对外主码 ERR_* + 内部细分码 DET_*
│   │   ├── pixel_format_defs.vh      像素格式 + 帧几何 + ★冻结四槽地址表（唯一来源）
│   │   └── event_code_defs.vh        正常事件码与源标识
│   ├── common/                       平台无关通用件（不碰 SD，也不碰内存）
│   │   ├── uart_tx.v                 调试串口发送（512 字节回传比对用）
│   │   ├── sync_fifo.v               同域 FIFO（almost_full 反压 / data_count）
│   │   ├── rv_skid_buffer.v          切开 ready 长组合路径的切分缓冲
│   │   ├── error_report.v            错误事件汇聚（不允许丢弃，带溢出计数）
│   │   ├── crc16_ccitt.v             CRC16-CCITT(XMODEM) 字节步进（纯组合，无状态）
│   │   ├── crc7.v                    SD 命令 CRC7 字节步进（纯组合，无状态）
│   │   ├── shift_reg.v               阶段 1 教学件，产品链未例化
│   │   └── spi_byte_rx.v             阶段 1 教学件，产品链未例化
│   ├── storage/                      SPI / SD / FAT32 / 文件流
│   │   ├── spi_master.v              SPI mode0 位引擎（cs_n 是输入，由上层控制）
│   │   ├── sd_initializer.v          CMD0 → CMD8 → ACMD41 → CMD58，每态独立超时
│   │   ├── sd_sector_reader.v        CMD17 单扇区读 512 Byte + CRC16 比对
│   │   ├── fat32_boot_parser.v       DBR/BPB 解析 + FAT32 判别位 + 派生地址
│   │   ├── fat32_directory_scanner.v 根目录遍历 + 四类跳过规则 + 跨簇
│   │   ├── fat32_cluster_walker.v    簇链跟踪（EOC / 越界 / 判环），被下面两者共用
│   │   ├── file_streamer.v           簇链 → 连续字节流
│   │   └── file_index.v              编号扫描 + 数字后缀排序 + 索引表冻结
│   ├── media/                        媒体格式解析
│   │   ├── bmp_parser.v              BMP 头 5 类校验 + 调色板跳过 + top-down
│   │   ├── bmp_unpack.v              BGR888 → RGB565 打包（含行填充处理）
│   │   └── wav_parser.v              RIFF/fmt/data 解析（只收 PCM/2ch/48k/16bit）
│   └── memory/                       SDRAM / 帧缓存 / 仲裁 / 帧交换
│       ├── mem_ctrl.v                SDRAM IP wrapper（对外只暴露逻辑字节地址）
│       ├── frame_address_gen.v       逻辑字节地址公式 slot_base+(y*W+x)*BPP
│       ├── frame_writer.v            写一帧 307200 像素 + 抽样 CRC + 置 slot_valid
│       ├── frame_buffer_manager.v    槽所有权 / active_slot / generation（原子提交）
│       ├── memory_arbiter.v          固定优先级 + 单次占用上限 + 最长等待提权（防饥饿）
│       ├── video_read_dma.v          水位驱动突发预取
│       ├── frame_swap_ctrl.v         帧交换状态机（超时进 SAFE，保持画面）
│       ├── frame_swap_cdc.v          toggle 同步 + mailbox 锁存
│       ├── memory_bandwidth_monitor.v 带宽计数器
│       └── fifo_health_monitor.v     历史最低水位 + underflow/overflow
├── verification/
│   ├── models/                       行为级模型（不是 RTL）
│   │   ├── sd_spi_card_model.sv      SPI 卡模型（可构造多扇区内容与故障）
│   │   └── frame_memory_model.sv     帧缓存模型（8 MiB / 2M×32bit，带 backdoor 读）
│   └── unit/                         单元测试台（每个被测件一个，断言名即规格）
└── tools/
    └── run_sim.ps1                   回归脚本：编译 + 跑全部 testbench + 汇总断言数
docs/
├── interface_spec.md                 ★接口冻结依据（改接口必须先改它）
├── B链-原理讲解-入门版.md             概念层：为什么这么设计（面向只懂一点电路基础）
└── B链-待办与硬件验证清单.md           板子到货后照着做的实测清单与排查顺序
```

**有意未创建**（不是缺陷，见蓝图 §4.1「不要一开始创建 150 个空 RTL」）：
`rtl/video/` `rtl/control/` `rtl/audio/` `rtl/csr/` `rtl/top/` `rtl/diagnostics/`
`rtl/platform/`，以及 formal / nightly CI / HIL / release manifest。
A 链（视频与顶层集成）与 C 链（控制与音频）各自独立实现。

---

## 三、怎么跑仿真

环境：ModelSim SE-64 10.7（脚本里默认路径 `D:\modeltech64_10.7\win64`，换机器改
[run_sim.ps1](safevision/tools/run_sim.ps1) 顶部的 `$MSIM_BIN`）。

```powershell
powershell -ExecutionPolicy Bypass -File safevision\tools\run_sim.ps1
```

脚本会 `vlib work` → 编译全部 RTL 与 testbench → 逐个 `vsim` 运行 → 汇总
`[PASS]`/`[FAIL]` 计数。**最终 `FAIL` 必须是 0**，否则脚本以非零退出码结束。

> ★ 维护脚本时注意：**`run_sim.ps1` 必须保持纯 ASCII 注释**。PowerShell 5.1 在没有 BOM
> 时按 ANSI 解码 `.ps1`，中文注释会把后面的引号"吃掉"导致解析失败。中文注释写在 RTL 里。

新增模块 / 新增 testbench 时，把文件分别加进脚本的 `$RTL` / `$SIM` / `$TBS` 三个列表。

---

## 四、当前状态

| 项 | 状态 |
|---|---|
| 手册学习阶段 1–16 | **全部落地并仿真通过** |
| 媒体格式层（BMP 解析/解包、WAV 解析） | 已完成并仿真通过 |
| 目录树与命名对蓝图 §4 | 已完成（含"同一常量多副本"的结构性收敛） |
| 仿真回归 | **502 项断言 / 15 个 testbench 全 PASS** |
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

另外 `interface_spec.md` 里的**命名迁移表**是手册旧名 ↔ 工程名的对应关系，以及
"有意不采纳蓝图"的留档，改目录结构时一并维护。

---

## 六、几条必须背下来的硬约定

这些是**实测踩出来的**，不是理论。完整清单见原理讲解 §13.4。

1. **从上游收数据必须用 `valid && ready` 双判**，只判 `valid` 会把同一字节吃掉多次。
2. **"下游取走数据"的清零逻辑放在状态机之外**，否则最后一个字节锁存那一拍正好跳态，
   `valid` 再没人清，直接死等超时。
3. **多字节字段（FAT 入口、BMP 头）是小端**；SD 命令参数是**大端**。两者不能混。
4. **每个"等外部回应"的状态都要有独立超时出口**。没有超时在硬件上等于永久死机。
5. **`slot_valid` 未置位不许读该槽**。这条把"半张图进画面"在结构上排除。
6. **冻结地址表与帧几何只能来自 `rtl/include/pixel_format_defs.vh`**，业务模块里
   禁止出现裸物理地址或第二份地址副本。
7. **公共算法（CRC16/CRC7）只用 `rtl/common/` 那一份**，不要在模块里再写一遍。
8. **禁止手写异步 FIFO**，跨时钟域用安路软 FIFO IP。

---

## 七、分支与协作

- 主分支 `main`。B 链改动直接进 `main`；A / C 各自有自己的目录，互不改动对方文件。
- 提交信息用 ASCII（避免控制台编码乱码），内容说明"为什么改"而不只是"改了什么"。
- 接口变更走 interface_spec 的变更历史表登记，并在表里注明版本号。