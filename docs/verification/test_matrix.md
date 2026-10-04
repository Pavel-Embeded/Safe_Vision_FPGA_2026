# 测试矩阵

## 已有 B 单元 Testbench（源文件盘点）

| 测试文件 | 覆盖主题 | 当前证明范围 |
|---|---|---|
| `tb_sd_initializer.sv`、`tb_sd_sector_reader.sv` | SD 初始化/读扇区 | 行为模型仿真 |
| `tb_mbr_parser.sv` | MBR 分区表解析 / 卷基址（有效 MBR、无签名、空表项、起始 LBA=0） | 行为模型仿真 |
| `tb_fat32_boot_parser.sv`、`tb_fat32_directory_scanner.sv`、`tb_fat32_cluster_walker.sv` | 挂载、目录、簇链（EOC/越界/判环） | 行为模型仿真 |
| `tb_file_streamer.sv`、`tb_file_index.sv` | 簇链流与索引 | 行为模型仿真 |
| `tb_bmp_parser.sv`、`tb_bmp_unpack.sv`、`tb_wav_parser.sv` | BMP/WAV 解析与像素 | 行为模型仿真 |
| `tb_common_fifo.sv`、`tb_crc.sv` | FIFO/反压/错误、CRC7 与 CRC16 | 行为模型仿真 |
| `tb_frame_writer.sv`、`tb_memory_arbiter.sv`、`tb_frame_swap_ctrl.sv` | 帧写/仲裁/帧交换 | SDRAM 行为模型仿真 |
| `tb_framebuffer_loopback_core.sv` | **阶段 10 帧缓存回环核心**（`framebuffer_loopback_core` + `mem_read_burst`，内部例化既有 `frame_writer`/`video_read_dma`/`mem_ctrl`/`sync_fifo`）：整帧 640×480 写入 → 整帧读回 → **逐像素比对零错**（LFSR 图案覆盖全 16 位）/ 抽样 CRC / `slot_valid` / 定长 208 Byte 报告逐字节（含 **地址斜坡探针 A 匹配位图 `AM/AF/AV` + 探针 C/B 抽样回读**，2026-10-03 起）/ **探针写值 = 字地址** / **探针段内写地址严格连续** | SDRAM 行为模型（`frame_memory_model`）仿真 |
| `tb_sdram_app_adapter.sv` | **板级突发桥适配器**（`sdram_app_adapter`，逐字事务口 ↔ 厂商 `sdram` 的 App_* 口）。★ TB 内含**厂商 app 口模型**（按 M-11 已验形态：en 连发时**每拍采样地址**、每拍一条读命令、延迟 `RD_LAT` 拍按 **1:1** 返回）：写 32 个连续字（值=地址）→ 读 32 个连续字（**跨两次预取**）逐字相等 / **写突发与读突发期间地址必须每拍 +1**（D2/D4，**旧版适配器过不了这两条**）/ 非 16 对齐基址（0x1035）写 4 读 4 / **缓冲未排空时跳到缓冲外地址（D7，正是板上暴露的那个场景）** / 等 ready 与 rdata_valid 零超时 | 厂商 App 口行为模型（TB 内建） |
| `tb_sdr_pat_gen.sv` | **SDRAM 测试图案生成器**（`sdr_pat_gen`，纯组合）：稀疏扫描（步长 2049）1024 个图案**两两不同**（单射）/ 连续扫描 1024 个两两不同 / 稀疏扫描时 **4 个字节各自都取到 ≥2 个值** / **21 位地址每一位单独翻转都改图案（无死位）** / mode 0 五个已知值 / 地址 0 图案非 0（mode 0/1/2）/ ★ **反向对照：把旧公式也算一遍，确认它在稀疏扫描下只有 2 种图案**（证明判据抓得到那个 bug）/ **mode 1（LFSR）也是单射** / **mode 2/3/4/5 八个已知值**（walking-1 / walking-0 / 全0全1 / 相邻位交替）。★ 为什么必须有：写侧读侧用同一个生成器，**"图案没区分度"在板上会表现为 `BAD=0000` 通过**，只有本 TB 能抓（2026-10-04 它还抓出"xorshift 的 0 是不动点 ⇒ 某地址会输出全 0"这个真缺陷） | 纯组合，无需行为模型 |
| `tb_top_sdram_loopback.sv` | **板级 SDRAM 回环顶层（带桩仿真）** —— 用 `vendor_ip_stub` 顶掉两个编译不了的单元后，该顶层**第一次进回归**：自建 125 MHz 采样 UART 8N1 接收模型。**阶段 1**（`ROUNDS=3` 三轮全过）：报告**恰好 190 Byte** / **逐字节一致**（含 `RND=00000003/00000003 PAT=2` ⇒ **soak 轮次与图案模式轮换真的生效**）/ `led=8`；**阶段 2**（在 `0x2805` 注入 1 bit 错）：**只跑 1 轮就出报告**（fail-fast）/ `BAD=0001` / **`BAD0=00000001:002805 E=88002805 A=88002804`**（轮次:地址 精确定位）/ `led=3`。★ 只验我们自己的逻辑（状态机/soak/报告/地址/图案），不验 SDRAM 协议 | 厂商 IP 仿真桩（`vendor_ip_stub`，理想存储器 + 故障注入钩子） |
| `tb_top_stage5_sector_rd.sv` | 板级 bring-up 顶层：完整命令序列、CMD17 参数、512 Byte 经 UART 逐字节、顶层进成功态 | SD 行为模型 + UART 接收模型仿真 |
| `tb_top_stage6_fat32_mount.sv` | **阶段 6–7 板级顶层**：卷基址只加一次（FAT32 层 LBA 0 → 卡 LBA = 分区基址，直接断言卡模型收到的 `o_arg`）/ MBR 分区表 / BPB 几何 / 目录项 / UART **ASCII 报告**内容（**字节数 372/374、无前导 `0x00`、每行 CRLF**）/ **连读汇总 `RPT=`**（健康卡 `OK=total BAD=0`；连读中拔卡 → 有限时间内进 `ST_ERR`、末行 `ERR=02`、LED=错误主码低 4 位）/ 顶层进成功态 | SD 行为模型（`VOL_BASE` 参数模拟分区卡）+ 文本 UART 接收模型 |

现有 B 回归为 **588 项断言 / 22 个 Testbench / 2 个行为模型 + 1 个厂商 IP 仿真桩**，`run_sim.ps1` 输出 `TOTAL PASS=588 FAIL=0`。`run_sim.ps1` 的 ModelSim 目录来自 `-ModelSimBin` 参数或 `MSIM_BIN` 环境变量（与 `run_clock_sim.ps1` 同口径，脚本里不再写死本机路径）；换机器时设好这两者之一即可重跑，并把日志放 `evidence/sim/`。

> ★ **`models/vendor_ip_stub.sv` 是"仿真桩"，不是行为模型**：它只把两个 ModelSim 编译不了的
> 单元（加密 `sdr_*.enc.v`、`EG_PHY_PLL` 宏）顶掉，好让 `top_sdram_loopback` 能进回归。
> 里面的 SDRAM 是**理想存储器**（真存真取，但**不模拟协议**：初始化/刷新/CAS/突发窗口/
> 地址每拍自增都不建模，也永远不会报协议错）⇒ **桩里的 `BAD=0000` 是构造保证的，
> 不能当板级结论**。它还带一个**故障注入**钩子（`STUB_ERR_ADDR`/`STUB_ERR_XOR`），
> 只用于让 TB 验证顶层的"出错立即停 + BAD0 定位"。

## A/B 集成 SDRAM 应用层专用仿真（2026-10-04）

`safevision/tools/run_sdram_loopback_sim.ps1` 使用 ModelSim SE-64 10.7 对当前 selector 版 `top_sdram_loopback.v` 与 `tb_sdram_loopback.sv` 执行回归：编译 **0 error / 0 warning**，六个回环/故障场景全部 PASS；覆盖 21-bit 地址签名及 190 Byte UART 报告。该应用层仿真不模拟加密 SDRAM 控制器、真实 DQ、刷新/CAS 或 AC 时序，不能替代 TD routed STA 或板级 soak。可再生运行日志留在本地构建输出目录，不作为提交证据。

## 待新增验证门槛

| ID | 层 | 判据 | 主责 |
|---|---|---|---|
| TC-A-CLOCK | unit/static/board | `tb_clock_reset_ctrl.sv` 检查九路复位异步断言、各域两拍同步释放、锁定丢失与局部复位隔离；板级另核 PLL 频率、约束、STA 和上电波形 | A |
| TC-A-TIMING | unit/board | 各模式行/场周期、de/x/y 与实机输出 | A |
| TC-B-TOP | unit/board | `tb_top_stage5_sector_rd.sv` 检查顶层自动完成初始化、CMD17 参数、512 Byte 经 UART 逐字节一致、顶层进成功态。★ **板级部分已通过（2026-10-02）**：实物 UART 回传 512 Byte 与 `evidence/board/lba8192_pc_20261002.bin`（物理 LBA 8192 = FAT32 引导扇区）**SHA-256 完全相同**，板上 LED 状态码 = `8`；见 `evidence/board/INDEX.md` 条目 M-9-PASS | B ✅ |
| TC-AB-PIXEL | subsystem/board | 固定帧首像素、数据/同步对齐、欠载安全色 | A+B |
| TC-AB-SWAP | subsystem/board | 仅消隐期切槽；超时保持旧帧；无撕裂 | A+B |
| TC-C-CTRL | unit/board | 消抖、事件优先级、模式转移 | C |
| TC-C-SAFE | subsystem/system | 媒体复位不影响安全画面；首故障保留 | A+C |
| TC-AC-AUDIO | subsystem/board | HDMI PCM/报警优先、欠载零样本、兼容显示器 | A+C |
| TC-Q-STA | static | WNS/WHS 与约束覆盖、资源预算 | A |
| **TC-Q-STA（B 的 bring-up 顶层实跑，2026-10-02）** | static | `top_stage5_sector_rd` + `pin.adc` + `timing.sdc` 的综合→布局→布线→位流全流程通过：Setup WNS +11.297 ns / Hold WNS +0.046 ns、违反端点 0、Fmax 114.9 MHz；资源 IO 11/188、LUT 814/19600、REG 434/19600。原始报告见 `evidence/reports/`（索引 TC-Q-STA）。**未覆盖**：I/O delay（故意留空，待 M-5/M-6 实测） | B |
| TC-R-LONG | system/board | 视频 60 分钟、音频 30 分钟、计数和水位原始序列 | A+B+C |

编号为工程补充，最终与手册固定 TC 编号映射后再冻结；当前没有填入“通过”的证据。

TC-A-CLOCK 的 TB 源文件与 `safevision/tools/run_clock_sim.ps1` 已建立，并已在本机运行通过（`clock/reset checks: 88 pass, 0 fail`）。既有 B 回归已在本机重跑，**540 项断言 / 18 个 Testbench 全 PASS**（含板级顶层 TB 与新增的 `tb_mbr_parser`、`tb_top_stage6_fat32_mount`）；本页所有"行为模型仿真"结论仍不等于上板验收。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](../clock_video_implementation.md)，端口/时钟域见 [A接口补充](../A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](../A_PUSH_SCOPE_20261002.md)。


## A 阶段 1–9 已执行验证（2026-10-04）

| 新 TB/检查 | 已执行范围 |
|---|---|
| `tb_a_basics` | 16,616 项，默认/单值计数、暂停、两级同步去抖、边沿、FSM；默认阈值变异必失败 |
| `tb_pattern_generator` | 12,930,420 项，BASE/HD 全图案及双向箭头、单像素边框、越界 |
| `tb_font8x16_rom` | 53,407 项，同步/全地址、独立字模点、四状态/BCD/全部 12 位坐标文字 |
| `tb_osd_overlay` | 14,013 个 bundle，FPS:60、任意起点、动态配置、边界/复位、统一 4 拍 |
| `tb_a_graphics_frontend` | BASE 状态、BASE 坐标、HD 状态三个完整帧，RGB/坐标/9 标签全比较 |
| TD 字库 | 完整 ROM 映射 4 块 9K BRAM，综合网表 INIT 回读 4096/4096 字节 |
| TD 内部 STA | 基础/BASE/HD setup 与 hold 裕量均正；PLL 健康与 I/O 预算项仍开放 |

既有 clock/video 5 功能 + 41 参数场景、B 18 TB/540 项、阶段十两个 TB 全通过。56 个共享工程源文件完成 TD 合编/布局布线/位流生成，但 SDRAM setup −6.826 ns 尚未收敛。详情与运行入口见 [A 阶段 1–9](../A_stages1_9.md)；不上传长报告，不构成硬件/HDMI 验收。

## [更新 2026-10-04] A/B SDRAM 回环检查器回归

在本次 UART selector 两级切分之前，`safevision/tools/run_sdram_loopback_sim.ps1` 的 ModelSim 10.7 fallback 曾通过：21-bit mode 0 签名对全部 2,097,152 个 word 地址独立反解，连续 256 word 覆盖全部 DQ 0/1，旧版 2048-stride 公式负对照精确得到两个别名；六个应用级场景覆盖 4096 连续、B 1024/2049 sparse 正常、A 强制高位地址 alias、DQ31 故障、丢失最后返回、初始化超时，并逐字节比对 190 Byte UART 报告。使用独立 PLL/sdram stubs，不模拟加密控制器、真实 DQ、刷新/CAS 或 AC/PVT。该历史 PASS **不覆盖**之后的两级 selector RTL。

B `run_sim.ps1` 全回归基线为 **588 PASS / 0 FAIL**。2026-10-04 最新 selector RTL 的独立索引映射检查为 190/190 PASS，但专用仿真再次尝试时未能启动：本机没有目标 XSim 2018.3，`MSIM_BIN` 未配置，故本轮无 HDL compile/TB 结果。同期已完成 TD reroute 与独立 postroute STA：C1→C1 setup `+0.113 ns`、0/2517 setup 违例，整板 setup 仍 `−6.826 ns`；未生成位流、未上板。历史 B soak 与 A `d6f40a6` STA 不属于同一 build，不能代替当前集成版本验收。详见 [SDRAM/PLL 核查](../docs/B链-SDRAM接口与PLL时序核查.md)。
