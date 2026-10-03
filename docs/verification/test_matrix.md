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
| `tb_top_stage5_sector_rd.sv` | 板级 bring-up 顶层：完整命令序列、CMD17 参数、512 Byte 经 UART 逐字节、顶层进成功态 | SD 行为模型 + UART 接收模型仿真 |
| `tb_top_stage6_fat32_mount.sv` | **阶段 6–7 板级顶层**：卷基址只加一次（FAT32 层 LBA 0 → 卡 LBA = 分区基址，直接断言卡模型收到的 `o_arg`）/ MBR 分区表 / BPB 几何 / 目录项 / UART **ASCII 报告**内容（**字节数 372/374、无前导 `0x00`、每行 CRLF**）/ **连读汇总 `RPT=`**（健康卡 `OK=total BAD=0`；连读中拔卡 → 有限时间内进 `ST_ERR`、末行 `ERR=02`、LED=错误主码低 4 位）/ 顶层进成功态 | SD 行为模型（`VOL_BASE` 参数模拟分区卡）+ 文本 UART 接收模型 |

现有 B 回归为 **558 项断言 / 20 个 Testbench / 2 个行为模型**，`run_sim.ps1` 输出 `TOTAL PASS=558 FAIL=0`。`run_sim.ps1` 的 ModelSim 目录来自 `-ModelSimBin` 参数或 `MSIM_BIN` 环境变量（与 `run_clock_sim.ps1` 同口径，脚本里不再写死本机路径）；换机器时设好这两者之一即可重跑，并把日志放 `evidence/sim/`。

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
