# 测试矩阵

## 已有 B 单元 Testbench（源文件盘点）

| 测试文件 | 覆盖主题 | 当前证明范围 |
|---|---|---|
| `tb_sd_initializer.sv`、`tb_sd_sector_reader.sv` | SD 初始化/读扇区 | 行为模型仿真 |
| `tb_fat32_boot_parser.sv`、`tb_fat32_directory_scanner.sv`、`tb_fat32_cluster_walker.sv` | 挂载、目录、簇链（EOC/越界/判环） | 行为模型仿真 |
| `tb_file_streamer.sv`、`tb_file_index.sv` | 簇链流与索引 | 行为模型仿真 |
| `tb_bmp_parser.sv`、`tb_bmp_unpack.sv`、`tb_wav_parser.sv` | BMP/WAV 解析与像素 | 行为模型仿真 |
| `tb_common_fifo.sv`、`tb_crc.sv` | FIFO/反压/错误、CRC7 与 CRC16 | 行为模型仿真 |
| `tb_frame_writer.sv`、`tb_memory_arbiter.sv`、`tb_frame_swap_ctrl.sv` | 帧写/仲裁/帧交换 | SDRAM 行为模型仿真 |
| `tb_top_stage5_sector_rd.sv` | 板级 bring-up 顶层：完整命令序列、CMD17 参数、512 Byte 经 UART 逐字节、顶层进成功态 | SD 行为模型 + UART 接收模型仿真 |

现有 B 回归为 **507 项断言 / 16 个 Testbench / 2 个行为模型**，`run_sim.ps1` 输出 `TOTAL PASS=507 FAIL=0`。`run_sim.ps1` 的 ModelSim 目录来自 `-ModelSimBin` 参数或 `MSIM_BIN` 环境变量（与 `run_clock_sim.ps1` 同口径，脚本里不再写死本机路径）；换机器时设好这两者之一即可重跑，并把日志放 `evidence/sim/`。

## 待新增验证门槛

| ID | 层 | 判据 | 主责 |
|---|---|---|---|
| TC-A-CLOCK | unit/static/board | `tb_clock_reset_ctrl.sv` 检查九路复位异步断言、各域两拍同步释放、锁定丢失与局部复位隔离；板级另核 PLL 频率、约束、STA 和上电波形 | A |
| TC-A-TIMING | unit/board | 各模式行/场周期、de/x/y 与实机输出 | A |
| TC-B-TOP | unit/board | `tb_top_stage5_sector_rd.sv` 检查顶层自动完成初始化、CMD17 参数、512 Byte 经 UART 逐字节一致、顶层进成功态；板级另核实物 UART 回传与电脑侧 `lba1000_pc.bin` 逐字节比对（待办清单 M-9） | B |
| TC-AB-PIXEL | subsystem/board | 固定帧首像素、数据/同步对齐、欠载安全色 | A+B |
| TC-AB-SWAP | subsystem/board | 仅消隐期切槽；超时保持旧帧；无撕裂 | A+B |
| TC-C-CTRL | unit/board | 消抖、事件优先级、模式转移 | C |
| TC-C-SAFE | subsystem/system | 媒体复位不影响安全画面；首故障保留 | A+C |
| TC-AC-AUDIO | subsystem/board | HDMI PCM/报警优先、欠载零样本、兼容显示器 | A+C |
| TC-Q-STA | static | WNS/WHS 与约束覆盖、资源预算 | A |
| TC-R-LONG | system/board | 视频 60 分钟、音频 30 分钟、计数和水位原始序列 | A+B+C |

编号为工程补充，最终与手册固定 TC 编号映射后再冻结；当前没有填入“通过”的证据。

TC-A-CLOCK 的 TB 源文件与 `safevision/tools/run_clock_sim.ps1` 已建立，并已在本机运行通过（`clock/reset checks: 88 pass, 0 fail`）。既有 B 回归已在本机重跑，**507 项断言 / 16 个 Testbench 全 PASS**（含新增的板级顶层 TB）；本页所有"行为模型仿真"结论仍不等于上板验收。
