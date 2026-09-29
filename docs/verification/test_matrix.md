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

现有 B 回归为 **502 项断言 / 15 个 Testbench / 2 个行为模型**，`run_sim.ps1` 输出 `TOTAL PASS=502 FAIL=0`。`run_sim.ps1` 顶部的 `$MSIM_BIN` 是本机 ModelSim 路径，换机器需改后重跑，并把日志放 `evidence/sim/`。

## 待新增验证门槛

| ID | 层 | 判据 | 主责 |
|---|---|---|---|
| TC-A-TIMING | unit/board | 各模式行/场周期、de/x/y 与实机输出 | A |
| TC-AB-PIXEL | subsystem/board | 固定帧首像素、数据/同步对齐、欠载安全色 | A+B |
| TC-AB-SWAP | subsystem/board | 仅消隐期切槽；超时保持旧帧；无撕裂 | A+B |
| TC-C-CTRL | unit/board | 消抖、事件优先级、模式转移 | C |
| TC-C-SAFE | subsystem/system | 媒体复位不影响安全画面；首故障保留 | A+C |
| TC-AC-AUDIO | subsystem/board | HDMI PCM/报警优先、欠载零样本、兼容显示器 | A+C |
| TC-Q-STA | static | WNS/WHS 与约束覆盖、资源预算 | A |
| TC-R-LONG | system/board | 视频 60 分钟、音频 30 分钟、计数和水位原始序列 | A+B+C |

编号为工程补充，最终与手册固定 TC 编号映射后再冻结；当前没有填入“通过”的证据。
