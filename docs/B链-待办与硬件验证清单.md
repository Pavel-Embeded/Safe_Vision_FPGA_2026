# B 链 · 待办与硬件验证清单

> 用途：板子还没到，把"现在就能做"和"板到之后必须做"分开列清楚，避免到货后手忙脚乱。
> 维护：每完成一项打勾，并注明日期与实测数据。
> 关联文档：[../README.md](../README.md)（仓库总览）、[interface_spec.md](interface_spec.md)（接口冻结依据）、[B链-原理讲解-入门版.md](B链-原理讲解-入门版.md)

> ★ **本文件属于"文档三件套"，改代码后必须同步**：阶段状态、回归断言数、已知未完成项
> 有任何变化，都要回来改这里（触发条件表见 [interface_spec.md](interface_spec.md) 的
> 「文档同步义务」）。开发功能以《赛题一对标学习与开发手册_V2.0.pdf》为准（工作区根目录、
> 不进仓库）；**目录结构以本仓库 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) 为准**。

---

## 零、当前状态总览

| 项 | 状态 |
|---|---|
| 阶段 1（SPI 地基） | 已完成并仿真通过 |
| 阶段 2（SPI 主机） | 已完成并仿真通过 |
| 阶段 3（SD 初始化 CMD0/CMD8/ACMD41/CMD58） | 已完成并仿真通过 |
| 阶段 4（每态独立超时） | 已完成并仿真通过 |
| 阶段 5（CMD17 单扇区读 + CRC16） | 已完成并仿真通过 |
| 阶段 6 首块（FAT32 挂载与 BPB 解析 `fat32_boot_parser`） | 已完成并仿真通过 |
| 阶段 6 第二块（根目录遍历 `fat32_directory_scanner`） | 已完成并仿真通过 |
| 阶段 7 第一块（簇链跟踪 `fat32_cluster_walker`） | 已完成并仿真通过（v1.7 起有专属 TB，此前只随编译） |
| 阶段 7 第二块（字节流 `file_streamer`） | 已完成并仿真通过 |
| 阶段 7 第三块（BMP 头校验 `bmp_parser`） | 已完成并仿真通过 |
| 阶段 6 剩余（编号扫描 + 索引表 `file_index`） | 已完成并仿真通过 |
| 阶段 8（FIFO 水位 / 切分缓冲 / 健康度统计） | 已完成并仿真通过 |
| 阶段 9（SDRAM wrapper `mem_ctrl` + 行为模型） | 已完成并仿真通过（真实 PHY 用官方 IP，见 §三） |
| 阶段 10（帧缓存地址映射 + 帧写入 `frame_writer`） | 已完成并仿真通过 |
| 阶段 11（突发传输策略） | 已完成并仿真通过 |
| 阶段 12（带宽与 FIFO 水位实测计数器） | 已完成并仿真通过 |
| 阶段 13（仲裁器 `memory_arbiter`，含防饥饿） | 已完成并仿真通过 |
| 阶段 14（双缓冲与槽所有权 `frame_buffer_manager`） | 已完成并仿真通过 |
| 阶段 15（帧交换握手 `frame_swap_ctrl` + `frame_swap_cdc`） | 已完成并仿真通过 |
| 阶段 16（错误上报 `error_report`） | 已完成并仿真通过（五类故障注入待整机） |
| **目录树与命名已按本项目结构核对完成** | **已完成**（v1.7 逐项核对收尾：修掉最后 4 处重命名 + 补 2 个头文件与 2 个 CRC 通用件；v1.8 引入队友的目录骨架。见 interface_spec「命名迁移表」）。另修掉"同一个常量在 4 个模块各存一份副本"的结构性问题（改地址现在只改 `rtl/include/pixel_format_defs.vh`） |
| 媒体格式层（`bmp_unpack` BGR→RGB565 / `wav_parser`） | 已完成并仿真通过 |
| 目录骨架与管理文档（`.github/` + `docs/` 子目录 + `evidence/` + `platform/` 等） | **已建立骨架**（v1.8 引入队友的项目管理覆盖包）。只有 README 占位与命名计划，**无功能代码**；落点规则见 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) |
| 目录自检脚本 `safevision/tools/check_repo.ps1` | 已接入（不需要 ModelSim，输出 `LAYOUT PASS` 才算过） |
| 板级顶层 `top_stage5_sector_rd.v`（阶段 5 最小验证） | 未开始（见 §2.3） |
| 整机集成（`safevision_core` / `safevision_top`） | 未开始（A 负责） |
| **上板实测** | **未开始（等板子）** |

仿真回归：`safevision\tools\run_sim.ps1`，**502 项断言全部 PASS**（15 个 testbench）：

| testbench | 覆盖 | 断言数 |
|---|---|---|
| `tb_sd_sector_reader.sv` | SD 初始化 + CMD17 单扇区读 + 逐字节比对 | 13 |
| `tb_sd_initializer.sv` | 慢卡 / v1.x 卡 / 拔卡 / 恢复 | 20 |
| `tb_fat32_boot_parser.sv` | BPB 解析 + 3 个负向分支 | 26 |
| `tb_fat32_directory_scanner.sv` | 跳过规则 + 跨簇 + 判环 + 越界 + 反压 | 57 |
| `tb_fat32_cluster_walker.sv` | 正常跳簇 / EOC 边界（0x0FFFFFF8 与 0x0FFFFFF7）/ 越界 / **跨 FAT 扇区寻址** / 判环 / SD 错透传 / 读超时 / done 单拍 | 33 |
| `tb_file_streamer.sv` | 簇链→字节流 + 跨簇 + 成环 + 越界 + 反压 + 空文件 | 49 |
| `tb_bmp_parser.sv` | BMP 头 5 类校验 + 调色板跳过 + top-down + 反压 | 41 |
| `tb_file_index.sv` | 乱序→升序 / 只留最小 4 幅 / 不足 4 幅 / 非法名 / WAV 配对与串号 | 60 |
| `tb_common_fifo.sv` | skid 反压保持 / FIFO 水位与 almost_full / 最低水位 / underflow / 带宽 / 错误不丢 | 58 |
| `tb_crc.sv` | CRC16 XMODEM 标准向量与 4 级级联等价 / **CRC7 反推 CMD0=0x4A、CMD8=0x43 并与宏对照** | 12 |
| `tb_bmp_unpack.sv` | BMP BGR→RGB565 纯色与邻色 / 行填充 / 双向方向 / 反压 / 像素数不足与超限 | 44 |
| `tb_wav_parser.sv` | WAV 未知块跳过 / 样本打包顺序 / 四类拒收 | 31 |
| `tb_frame_writer.sv` | 一帧写入 + 四个角与中点地址抽查 / 多一个少一个 / slot_valid 时序 / 越界 | 28 |
| `tb_memory_arbiter.sv` | 仲裁最坏场景与防饥饿 / 单次占用上限 / 三类 starvation 计数为 0 | 7 |
| `tb_frame_swap_ctrl.sv` | 帧交换四态 / 两类超时进 SAFE / 原子切换 / CDC mailbox 预稳定 | 23 |
| **合计** | | **502** |

> v1.7 的 4 处拆分类改动（`tb_frame_swap`→2 个、`tb_media`→2 个）**只搬位置、不改断言**，
> 拆分前后断言数逐项守恒（30→7+23，75→44+31）。

---

## 一、现在就能做（不需要板子）

### 1.1 先把器材备齐

- [ ] **TF 卡**：建议准备 **≥2 张不同品牌**（金士顿 / 闪迪 / 杂牌各一），容量 4–32 GB。
      理由：SD 卡兼容性是现场最容易翻车的点，手册也要求"至少两台带声显示设备"这种兼容性留证思路。
- [ ] **读卡器**（能插电脑，用于写测试素材 + 事后比对）
- [ ] **HDMI 线 + 带喇叭的显示器/电视**（B04 要用；阶段 5 还用不到，但迟早要买，越早确认越好）
- [ ] **USB 转串口模块**（CH340 / CP2102 均可）——阶段 5 靠它把 512 字节回传到电脑比对
- [ ] **杜邦线**若干（板载 SD 卡座若已焊好可省）

### 1.2 TF 卡测试素材准备

- [ ] 把 TF 卡格式化成 **FAT32**（不要 exFAT，不要 NTFS）
- [ ] 用 `7_lab_ex_2026_nosoft\example\lab_ex4_tf\doc\convert\convert_images_to_bmp.py`
      把几张图转成 **640×480、24bit、非压缩 BMP**
- [ ] 准备 4 张 + 1 张故意做坏的图（比如把 BMP 头改几个字节），用于验证"坏图跳过不中断扫描"
- [ ] **用电脑侧工具读出 LBA=1000 的内容并保存**（阶段 5 比对要用）：
      Windows 下可用 HxD（磁盘 → 打开物理磁盘 → 定位到 1000×512 = 512000 字节偏移）
      建议保存为 `lba1000_pc.bin`，后面和 FPGA 回传的 512 字节逐字节比对

### 1.3 做引脚规划（查原理图，不写代码）

参考 `3_原理图\开发板原理图\` 下的 PDF，把下面这些端口的位置先抄进一张表：

| 信号 | 原理图来源 | 说明 |
|---|---|---|
| `clk` | `2_FPGA.pdf` | 板载晶振，本轮用 50MHz 输入给 PLL |
| `rst_n` | `4_GPIO.pdf` | 复位按键，注意板上有没有外部上拉 |
| `sd_ncs / sd_dclk / sd_mosi / sd_miso` | `6_EX_DEVICE.pdf` | TF 卡座，**注意 MISO 是否需要外部上拉** |
| `uart_txd` | `4_GPIO.pdf` | 选一个空闲 IO 接到 USB-串口模块的 RXD |
| `led[3:0]`（可选） | `4_GPIO.pdf` | 用来显示状态码，比 UART 更直观 |

**为什么现在做**：引脚资源紧张（BG256 封装，最多 193 个用户 IO），事后硬塞容易冲突。
把表填好后，`pin.adc` 的编写就只是抄写，不会卡住进度。

### 1.4 复习手册的过关自测（建议逐条打勾）

这几条是你自己判断"我真的会了没有"的标准，别跳：

- [ ] 阶段 1：能默写 `sreg <= {sreg[6:0], miso_d}`，说清为什么 8 拍后先到的比特在 bit7
- [ ] 阶段 2：能画出 `spi_master` 状态图，说出每一位在哪个沿被采样
- [ ] 阶段 3：能默画初始化流程，解释 CMD0 / ACMD41 / CMD17 各自为什么不可省
- [ ] 阶段 4：能说出为什么"每个等待态要独立超时出口"，而不是全模块共用一个计数器
- [ ] 阶段 5：能解释"数据令牌 0xFE"和"CRC 的 2 个字节"分别在哪一步，漏了会怎样

### 1.5 和队友对齐（趁没板子，先把接口吵清楚）

- [ ] 把 [interface_spec.md](interface_spec.md) 发给 A、C 各读一遍，重点看 §3.1（SD 总线）、§4（A/B 边界）、§5（地址表）、§6（错误码）
- [ ] 确认 A 的像素 FIFO 选 **FWFT**（决策 D-2）没有异议
- [ ] 确认 C 的 UART 命令/日志要不要复用我们的 `uart_tx`（目前只有发送，收要另加）
- [ ] 一起定掉这几个待确认项（越早越好，改起来越便宜）：
      - O-1 `bmp_unpack` 的 RGB565 转换是**舍入**还是**截断**
      - O-3 `mem_arbiter` 突发长度（建议 16 或 32 word）
      - O-7 音频链路的 `track_id` 编号规则（SV0001.BMP ↔ SV0001.WAV）

---

## 二、板子到了之后必须做

### 2.1 工具链打通（第一天就会卡住的地方）

- [ ] 按 `1_安路开发工具和常用软件\必须看！！重要！安装前必看！\安路TD开发工具软件安装教程.docx` 装 TD
- [ ] 装 license（`Anlogic.lic`），确认 TD 能识别 EG4S20BG256
- [ ] **驱动签名问题**：Win10/11 要按 `Win10、Win11解决驱动签名问题.pdf` 处理，
      否则下载器认不到 FPGA，会白白浪费半天
- [ ] 下载器能识别到器件（这一步过了再往下走）

### 2.2 建第一块可下载的工程（阶段 5 最小验证）

- [ ] 新建 TD 工程，器件选 **EG4S20BG256**（Family = EG4）
- [ ] 加文件（注意 **include 路径** 要指向 `rtl/include`，否则 `safevision_defs.vh` 找不到）：
      ```
      rtl/include/safevision_defs.vh   (头文件，加到工程 include 路径；它会 include 同目录的
                                        fault_code_defs.vh / pixel_format_defs.vh / event_code_defs.vh)
      rtl/common/uart_tx.v
      rtl/storage/spi_master.v
      rtl/storage/sd_initializer.v
      rtl/storage/sd_sector_reader.v
      rtl/top/top_stage5_sector_rd.v   ← 还没写，见 §2.3 待办
      ```
      > 路径按本项目结构（[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)）：`rtl/include/` 放头文件、
      > `rtl/storage/` 放 SPI/SD/FAT、板级顶层将来放 `rtl/top/`（该目录现在还没建，写顶层时新建）。
      > 旧文档里的 `rtl/sd/` `rtl/common/safevision_defs.vh` 是 v1.5 改名前的路径，已作废。
- [ ] 约束文件：按 §1.3 的表写 `pin.adc`，时序约束 `timing.sdc` 先只写
      `create_clock -name clk -period 20 [get_ports {clk}]`（50MHz）
- [ ] 综合 + 布局布线，看报告：时序是否收敛、有无多驱动/未约束端口警告

### 2.3 还没写的东西（板到之前最好补上）

- [ ] `rtl/top/top_stage5_sector_rd.v`——板级顶层，功能：
      - 上电延时 → 拉高 `init_start` → 等 `init_done`
      - `init_done` 后自动发起一次 `rd_en`，`rd_addr = 32'd1000`
      - 把 512 字节按顺序灌进 `uart_tx`（115200）
      - 状态码输出到 LED / 数码管（`dbg_state` 直连即可）
- [ ] 写完后在仿真里先跑通（把 UART 输出接到一个 UART 接收模型，确认 512 字节顺序正确）

### 2.4 必做的实测项（每一项都要回填到 [interface_spec.md](interface_spec.md)）

| 编号 | 测什么 | 怎么测 | 回填到 |
|---|---|---|---|
| M-1 | **正常路径最大耗时** | 在 `M_RESP` 等待态埋计数器，用 ChipWatcher 抓若干次操作的最大值，× 裕量系数 | `safevision_defs.vh` 的 `SD_TO_RESP`、O-4 |
| M-2 | 数据令牌等待耗时 | 同上，抓 `S_TOKEN` 状态的计数值 | `SD_TO_DATA`、O-4 |
| M-3 | ACMD41 轮询总时长 | 抓从第一次 ACMD41 到 ready 的拍数（不同品牌卡差异很大） | `SD_TO_ACMD41`、O-4 |
| M-4 | 上电到 `init_done` 的时间 | 示波器或 LED 翻转计时 | 启动速度留证（E04） |
| M-5 | 实际 SCLK 频率 | 示波器量 `sd_dclk`，确认初始化段 ≈400kHz、数据段 ≈25MHz | 接口文档备注 |
| M-6 | **连读 100 次** | 同一 LBA 连续读 100 次，UART 每次都回传，电脑脚本比对 | 手册 7.5 过关标准 |
| M-7 | **多卡兼容** | 至少 3 张不同品牌/容量的卡都跑通 | 兼容性留证 |
| M-8 | 拔卡 / 坏卡行为 | 运行中拔卡，确认有限时间内进错误态且不挂死；插回后能恢复 | 手册 7.4 过关标准 |
| M-9 | 单扇区读 + 电脑侧比对 | 与 `lba1000_pc.bin` 逐字节比对，**一个字节都不能差** | 阶段 5 验收 |

> **M-3 特别提醒**：不同品牌卡的 ACMD41 轮询时长差异可达几十倍，这也是为什么
> 现在的超时值只是"推导 + 裕量"，必须实测后才敢冻结。

### 2.5 存储链的实测项（阶段 8–16，板到后按序补）

> 这些项的共同特点：**仿真里全是"理想值"，只有上板才知道真数**。手册 7.12 明确
> 规定"报告里只接受一种结论形式：用计数器统计一段时间内实际完成搬运的数据量，
> 除以时间得到控制器持续带宽，并同时给出该时段的 FIFO 最低水位"。

| 编号 | 测什么 | 怎么测 | 回填到 |
|---|---|---|---|
| M-10 | **SDRAM 初始化时间** | 上电到 `init_done` 的拍数 | `mem_ctrl` 参数、启动速度留证 |
| M-11 | **SDRAM 读写回环** | 官方 Demo 写一帧再读回，逐字节比对（这是用 SDRAM 前的第一步，别跳） | 阶段 9 验收 |
| M-12 | **持续带宽（关键）** | `memory_bandwidth_monitor` 的 `rd_bytes_total` / `wr_bytes_total` ÷ 时间；跑 ≥10 分钟 | 手册 7.12 的"有效带宽"结论、O-4 邻近项 |
| M-13 | **FIFO 最低水位** | `fifo_health_monitor.min_level`，与上一条同时段采集 | 手册 7.12 要求成对给出；水位阈值标定 |
| M-14 | **underflow / overflow 计数** | 连续跑 60 分钟，两个计数必须都为 0 | 表 7-4 的验收门槛 |
| M-15 | **仲裁饥饿** | 构造"显示读持续请求"最坏场景，看 `starvation_cnt` 是否为 0、帧写入能否按时完成 | 阶段 13 验收 |
| M-16 | **帧交换超时行为** | 人为不给 `swap_ack`，确认 `swap_error` 拉高、**当前显示块保持不变、画面不黑** | 阶段 15 验收；`TIMEOUT_N` 按最大帧周期加裕量 |
| M-17 | **`active_slot` 只在消隐段变** | ChipWatcher 抓 `active_slot` 与 `frame_start`，确认改变只发生在消隐入口 | 阶段 15 过关自测原话 |
| M-18 | **撕裂检查** | 连续 100 次切换录屏，逐帧看有无横向错位；`tear_count` 必须为 0 | 阶段 14 过关自测 |
| M-19 | **五类故障注入** | 拔卡 / 坏图 / 坏文件系统 / FIFO 人为欠载 / SDRAM 写失败，**均不卡死** | 手册 7.16.2 过关自测 |

> **M-12/M-13 必须成对给出**，只报带宽不报水位等于没测——因为带宽够但水位贴地，
> 说明系统已经在 underflow 边缘，随机一次刷新抖动就会花屏。

### 2.6 上板调试的排查顺序（出问题时按这个顺序找）

1. **SCLK 完全没动静** → 先看 `cs_n` 有没有拉低；再看 `spi_master` 的 `tx_valid/tx_ready` 握手
2. **SCLK 有但读回全 0xFF** → 卡没进 SPI 模式，查 CMD0 是否发出、CRC 字节是否为 0x95
3. **CMD8 之后就没响应了** → 查 CMD8 的 CRC 字节是否为 0x87、参数是否为 0x000001AA
4. **能初始化但读数据全错** → 大概率是位序（MSB first）或 SCLK 相位（应该在上升沿采样）
5. **读出的数据偶发错位** → 查数据令牌 0xFE 之后有没有把 512 字节数满、CRC 的 2 字节有没有吃掉
6. **跑一会儿就卡死** → 查超时计数器有没有在进等待态时清零（手册 7.4 的经典坑）
7. **能读扇区但图片显示错位 / 斜切** → 查帧缓存地址公式：`slot_base + (y*640+x)*2`，最容易漏乘"每像素 2 字节"，或者把行步长写死成图像宽度
8. **画面整体右移或左边有黑边** → 像素 FIFO 的读出模式/预取提前量错了（手册 7.8 的技术纠错：读地址一到不等于 de 有效）
9. **画面偶发花屏、而且是跑一段时间才出现** → 先查 FIFO 最低水位是不是贴地（`fifo_health_monitor.min_level`），再查 SDRAM 刷新是否被省掉
10. **画面上下错位 / 一半旧一半新** → 帧交换没有在垂直消隐期原子切换，或者 `active_slot` 与 `slot_base` 不是同时更新的
11. **帧写入把显示读饿死** → 查仲裁的两条硬约束（单次占用上限、最长等待提升）有没有实现

---

## 三、已知的"未完成项"（别当成 bug）

| 项 | 说明 | 什么时候做 |
|---|---|---|
| CMD18 多扇区读 | `sd_sector_reader` 目前只支持 CMD17，`rd_len` 必须为 1，否则明确报错。多扇区读需要额外的 STOP_TRANSMISSION。连带影响：`fat32_directory_scanner` 现在只能"一个扇区一次 CMD17"，根目录越大读得越碎 | 带宽优化阶段（对应 O-11） |
| 超时值未实测 | `safevision_defs.vh` 里的超时是"规范推导 + 裕量"，仿真时用 `SIM_FAST_TO` 缩小以便跑到超时分支 | 板到后执行 M-1~M-3 |
| 板级顶层 | `top_stage5_sector_rd.v` 还没写 | 见 §2.3 |
| 引脚约束 | `pin.adc` 还没写 | 见 §1.3 |
| 根目录簇链跟随 | **已解决**：阶段 7 抽出 `fat32_cluster_walker.v`，`fat32_directory_scanner` 与 `file_streamer` 共用同一份 | 已完成 |
| `file_index` | **已完成**：编号扫描 + 数字后缀排序 + 索引表冻结 + WAV 配对 | 已完成 |
| **SDRAM 真实 IP 未接** | 仿真用行为模型 `verification/models/frame_memory_model.sv`（不建模 tRCD/CL/tRP/tRFC 与刷新，**不能用于长稳评估**）。真实 PHY 按手册 7.9「第一版不要手写，直接跑通官方 Demo」用安路官方 IP，替换 `mem_ctrl` 内部实现即可 | 板到后（M-10/M-11） |
| **异步 FIFO 用官方 IP** | `sync_fifo.v` 只覆盖同域；跨时钟域（`mem_clk→pixel_clk`、`mem_clk→audio_clk`）用安路软 FIFO（`SHOW_AHEAD=Enable`、`OUT_REG=Disable`）。**禁止手写异步 FIFO** | 整机集成时 |
| **音频链 B04 还剩两块** | `wav_parser` **已完成**；还差 `pcm_ring`（SDRAM `AUDIO_RING` 环形缓冲，解耦慢读与连续消费）与 `audio_cdc_fifo`（`mem_clk→audio_clk`，用安路软 FIFO FWFT）。手册 8.6 要求音频必须走 HDMI 数据岛，**不走外部 I²S Codec** | 见 §三 |
| **媒体格式层** | **已收尾**：`bmp_unpack`（BGR888→RGB565、行填充、方向归一化，`ROUNDING` 参数待 O-1 定夺）与 `wav_parser`（RIFF 解析 + 未知块跳过）。顺带补登记了 `ERR_WAV`(0x07) 与 `DET_WAV_*`(0x71–0x76) —— 原先只写在 interface_spec，代码里缺 | 已完成 |
| **WAV 出错后不排空** | 出错即停收，交上层 abort / 回退提示音（手册 D-7 要求"回退提示音"）。当前实现不主动排空剩余字节 | 整机集成时确认 |
| `bmp_unpack` 的舍入方式未定 | `ROUNDING` 参数（0=截断 / 1=舍入+饱和）已做成参数，等 A/C 一起定（interface_spec 待确认项 O-1） | 与 A/C 定 |
| `bmp_parser` 坏文件要排空整条流 | 校验不通过时当前实现会把该文件剩余字节全部排空（只丢不外送），坏文件大时浪费时间。可加一个 `abort` 输入让上游提前收工 | 有空再做 |
| **帧交换未与 A 联仿** | `frame_swap_ctrl` / `frame_swap_cdc` 只做了 B 侧自测（23 项断言），没有和 A 的像素域一起跑过。这是 A/B 第一次真正协同，**建议优先联调** | 与 A 约定时间 |
| **整机集成未做** | `safevision_core.v`（子系统互连）与 `safevision_top.v`（板级）由 A 负责；B 侧模块已就绪但还没接进子系统 | A 负责 |
| **结构对齐后遗留** | `rtl/common/shift_reg.v` / `spi_byte_rx.v` 是阶段 1 教学件、产品链未例化，现结构无对应项，暂放 `rtl/common/` | 有空再清理 |

---

## 四、变更记录

| 日期 | 变更 |
|---|---|
| — | 初版：阶段 1–5 仿真通过后整理 |
| — | 阶段 6 首块 `fat32_boot_parser` + 四类异常分支测试通过后更新 |
| — | 阶段 6 第二块 `fat32_directory_scanner` 通过后更新（回归 116 项；登记两条真实踩坑：字节消费必须 `valid && ready` 门控、FAT 入口是小端且高 4 bit 需掩掉） |
| — | 阶段 7 通过后更新（回归 206 项）。同时按《工业级模块化架构蓝图》§4 全仓改名：`rtl/{include,common,storage,media}` + `verification/{unit,models}` + `tools`，回归全绿未回归。新登记三条踩坑：清零逻辑要放状态机之外、文件末字节落在扇区末字节时的同拍判定、BMP 字段同为小端 |
| — | **阶段 8–16 + 阶段 6 收尾通过后更新（回归 382 项）**。新增 `rtl/memory/` 全套（SDRAM wrapper、帧缓存地址、帧写入、仲裁、DMA 读、双缓冲、帧交换、带宽监视）、`rtl/common/`（切分缓冲、同步 FIFO、FIFO 健康度、错误上报）、`frame_memory_model.sv` 行为模型、`file_index.v`。新增 §2.5 存储链实测项 M-10~M-19、§2.6 排查顺序扩到 11 条、"未完成项"表补上 SDRAM 真实 IP / 异步 FIFO / 音频链 / 帧交换联调 / 整机集成 |
| — | **阶段 8–16 全部落地 + 媒体层收尾后更新（回归 457 项）**。补 `bmp_unpack` / `wav_parser` / `file_index` / `error_report`，补登记 `ERR_WAV` 与 `DET_WAV_*` 错误码 |
| — | **v1.7：按蓝图 §4 逐项核对命名后更新（回归 502 项 / 15 个 TB）**。① 重命名 4 处（`wav_parser`、`memory/fifo_health_monitor`、`frame_memory_model`、`tb_frame_writer`）；② 补 `rtl/include/pixel_format_defs.vh`（**冻结地址表唯一来源**）与 `event_code_defs.vh`；③ **修掉"同一个常量在 4 个模块各存一份副本"**（帧几何/地址表全部改为引用 `` `SV_`` 宏，parameter 保留）；④ 补 `rtl/common/crc16_ccitt.v` / `crc7.v`，`sd_sector_reader` 与 `frame_writer` 各自那份重复的 CRC 函数删掉改为例化；⑤ 新增 `tb_crc`(12)、`tb_fat32_cluster_walker`(33，**该模块的判 EOC/越界/判环三条收尾分支此前从未被仿真跑过**)；⑥ 按蓝图拆 TB：`tb_frame_swap`→`tb_memory_arbiter`+`tb_frame_swap_ctrl`，`tb_media`→`tb_bmp_unpack`+`tb_wav_parser`（只搬位置不改断言）。**概念更正**：此前说的"宏与 parameter 命名冲突"是误判——宏只在写成 `` `名字 `` 时展开，两者不会冲突（已编译验证） |
| — | **补交付口径与文档同步规则**。① 新增"文档同步义务"说明（本文件属文档三件套，状态/回归数/未完成项变化必须回来改）；② 补一份真正的 `README.md`（目录结构、跑仿真方法、状态总览、硬约定、有意未创建的目录）；③ 修正 §2.2 里 v1.5 改名前的过期路径（`rtl/common/safevision_defs.vh` → `rtl/include/…`、`rtl/sd/` → `rtl/storage/`）；④ 把"开发基准＝手册 V2.0 / 结构基准＝蓝图 §4"写进 interface_spec 与项目规则文件 |
| — | **v1.8：引入队友的项目管理覆盖包（目录骨架 + 管理文档），并把它的过期内容改对**。新增 `.github/` 模板、`docs/` 六个子目录（architecture/interfaces/requirements/management/verification/release）、`evidence/` 七类证据索引、`safevision/{platform,build,assets}`、`rtl/{video,audio,control,safety,top}`、`verification/{subsystem,system,board}`、`tools/check_repo.ps1` —— **全部只有 README 占位，无功能代码**。`.gitignore` 换成覆盖包版本（白名单加 `!/.github/` `!/evidence/`，多排除 `*.lic`/`*.key`/`*.pem`）。**接口/RTL/TB/回归数一字未变，仍 502 项断言 / 15 个 TB**，目录自检 `LAYOUT PASS`。覆盖包是按旧快照（48 文件 / 27 RTL）做的，带进来的过期内容已逐项改对：**27→29 个 RTL、11→15 个 TB、457→502 项断言**、`fifo_health_monitor` 归 `memory/`、`wav_reader`→`wav_parser`、`sdram_model`→`frame_memory_model`、`tb_media`/`tb_mem_write`/`tb_frame_swap` 拆名、并作废"待办清单仍有 `rtl/sd` 旧路径"的指控（v1.7 已修）。另修 `interface_spec` §3.1 的 `rtl/sd/spi_master.v` → `rtl/storage/…` 与 `bmp_unpack.v` 注释里的 `tb_media` → `tb_bmp_unpack` |
| — | **结构基准变更 + 全仓文档去绝对路径**。① **《工业级模块化架构蓝图.pdf》不再作为结构依据**，改以本仓库 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) 为准，蓝图降为历史设计参考（迁移表/变更历史里的"蓝图 §x"是历史出处）；② 清掉覆盖包带进来的本机绝对路径——文档里的 ModelSim 安装路径改为按变量名 `$MSIM_BIN` 描述，文档树根由 `Safe_Vision_FPGA_2026/` 改为 `<仓库根>/`，`run_sim.ps1` 用法注释与原理讲解里的 `f:\...\` 占位改为相对路径。新约定：**文档里只用仓库相对路径** |