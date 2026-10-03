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
| 阶段 5（CMD17 单扇区读 + CRC16） | **仿真通过，且上板实测通过**（M-9：512/512 逐字节一致，见 evidence/board 的 M-9-PASS） |
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
| 板级 TD 工程 `platform/anlogic_eg4s20_hx4s20c/project/safevision.al` | **全流程已跑通**（器件 EG4S20BG256；设计文件全为相对路径；`constraint_1` 已挂 `pin.adc` + `timing.sdc`）。阶段 5 那次：**综合 → 布局 → 布线 → 位流一次通过**，Setup WNS **+11.297 ns**、Hold WNS **+0.046 ns**、**违反端点 0**（906 端点 / 3480 路径），50 MHz 约束下报告 Fmax **114.9 MHz**；资源 IO 11/188、LUT 814/19600、REG 434/19600、BRAM/DSP 0。原始报告留证在 [evidence/reports/INDEX.md](../evidence/reports/INDEX.md)（TC-Q-STA）。★ **当前 `TOP_MODULE = top_sdram_loopback`**（2026-10-02 切，本行上面的数字是阶段 5 顶层的，不是它的） |
| 板级顶层 `platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v`（阶段 5 最小验证） | **已写、仿真通过、且上板跑通**（`tb_top_stage5_sector_rd` 5 项断言；板上 LED = `8` 成功，M-9 通过） |
| 引脚约束 `pin.adc` / 时序约束 `timing.sdc` | **已写并核对**（引脚来源：开发板手册的串口/LED/按键引脚表 + `2_FPGA.pdf` / `6_EX_DEVICE.pdf` + 厂商同器件例程，三处一致；`timing.sdc` 为单一 50 MHz 时钟域第一版）。`uart_txd = D12` **已确认为 FPGA 发送脚**（板载 CH340G，无需外接 USB-TTL） |
| 整机集成（`safevision_core` / `safevision_top`） | 未开始（A 负责） |
| 厂商 IP 落库（阶段 9 前置） | **已落地**（2026-10-02）：`ip/sdram/`（应用级 `sdram.v` + `global_def.v` + 三个安路加密 `sdr_*.enc.v` + `sdram.ipc`）、`ip/pll/`（`sv_system_pll` / `sv_video_*_pll` / `sv_audio_pll`）。**加密件按用户决定随仓库提交**，版权与来源见该目录 `README.md`。★ 例程里有两个同名 `sdram` 模块，本仓库只保留被顶层例化的应用级那个 |
| 板级顶层 `platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v`（阶段 9 第一步 / 手册 7.9） | ★★ **已写、已综合（位流 22:01:24）、且上板通过（2026-10-02）**：报告 `INIT=01 / LOCK=01 / W=1000 R=1000 CAP=1000 BAD=0000 / DONE`（71 Byte，条目 **M-11-PASS**）。★ 无 TB、进不了回归（控制器是加密 IP，不可仿真）—— 上板步骤见 §2.4.2。★ **2026-10-03 PLL 去重后已于去重版位流复测通过**：报文与 M-11 逐字节相同（`INIT=01 LOCK=01 / W=1000 R=1000 CAP=1000 BAD=0000 / DONE`），证据条目 **M-11-PASS-2** |
| **上板实测** | **阶段 1–7 与阶段 9 第一步均已通过**：M-9（512/512 逐字节）、M-10（卷基址/BPB/目录）、**M-6（连读 100 次）**、M-8a（无卡有界退出）、**M-11（SDRAM 回环 `BAD=0000`）**。。待做：M-5（可用 ChipWatcher 复核 SCLK）、**M-7（3 张不同品牌卡）**、**M-8「连读中途拔卡」**、M-10 精确拍数、阶段 10–16 板级项（须等 A 的整机） |

仿真回归：`safevision\tools\run_sim.ps1`，**540 项断言全部 PASS**（18 个 testbench）：

| testbench | 覆盖 | 断言数 |
|---|---|---|
| `tb_sd_sector_reader.sv` | SD 初始化 + CMD17 单扇区读 + 逐字节比对 | 13 |
| `tb_mbr_parser.sv` | **MBR 分区表 / 卷基址**：有效 MBR（起始 8192 小端）/ 无 0x55AA 签名 / 空表项 / 起始 LBA=0 | 7 |
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
| `tb_top_stage5_sector_rd.sv` | **板级 bring-up 顶层**：自动初始化序列 / CMD17 参数 1000 / 512 Byte 经 UART 逐字节与卡模型一致 / 顶层进成功态 | 5 |
| `tb_top_stage6_fat32_mount.sv` | **阶段 6–7 板级顶层**：★ 卷基址只加一次（FAT32 层的 LBA 0 必须落到卡 LBA = 分区基址）/ MBR 分区表 / BPB 几何 / 目录项（名称·属性·大小）/ UART 纯 ASCII 报告内容（含**字节数、无前导 `0x00`、每行 CRLF** 三条 Task-1 回归）/ **连读汇总 `RPT=`**（健康卡 `OK=total BAD=0`）/ **拔卡场景**（有限时间内进 `ST_ERR`、末行 `ERR=02`、LED=错误主码低 4 位）/ 顶层进成功态 | 26 |
| **合计** | | **540** |

> v1.7 的 4 处拆分类改动（`tb_frame_swap`→2 个、`tb_media`→2 个）**只搬位置、不改断言**，
> 拆分前后断言数逐项守恒（30→7+23，75→44+31）。

---

## 一、现在就能做（不需要板子）

### 1.1 先把器材备齐

- [ ] **TF 卡**：建议准备 **≥2 张不同品牌**（金士顿 / 闪迪 / 杂牌各一），容量 4–32 GB。
      理由：SD 卡兼容性是现场最容易翻车的点，手册也要求"至少两台带声显示设备"这种兼容性留证思路。
- [ ] **读卡器**（能插电脑，用于写测试素材 + 事后比对）
- [ ] **HDMI 线 + 带喇叭的显示器/电视**（B04 要用；阶段 5 还用不到，但迟早要买，越早确认越好）
- [ ] ~~**USB 转串口模块**（CH340 / CP2102 均可）~~ **不需要了**：板上自带 USB-UART（CH340G，位号 U41），
      插一根 USB 线即可（见 §2.2「上板步骤」）。若手边已有外接模块，也可以留着当备用。
- [ ] **杜邦线**若干（板载 SD 卡座若已焊好可省）

### 1.2 TF 卡测试素材准备

- [ ] 把 TF 卡格式化成 **FAT32**（不要 exFAT，不要 NTFS）
- [ ] 用 `7_lab_ex_2026_nosoft\example\lab_ex4_tf\doc\convert\convert_images_to_bmp.py`
      把几张图转成 **640×480、24bit、非压缩 BMP**
- [ ] 准备 4 张 + 1 张故意做坏的图（比如把 BMP 头改几个字节），用于验证"坏图跳过不中断扫描"
- [x] **电脑侧参考扇区已读出并保存**（2026-10-02 完成）：`evidence/board/lba8192_pc_20261002.bin`
      （512 B，SHA-256 `E4704165…C426EEE`）。
      ★ **原计划的 LBA 1000 要换掉**：实测这张 TF 卡的分区从**物理扇区 8192**（4 MB）开始，
      所以 **LBA 1000 落在"MBR 之后、分区之前"的空隙里，读出来是 512 个 0x00** ——
      两边都全零的话"逐字节比对"几乎证明不了数据通路（数据通路坏成常数 0 也会"通过"）。
      因此改用 **LBA 8192 = 分区首扇区 = FAT32 引导扇区（DBR）**：内容非零且可识别
      （开头 `eb 58 90 "MSDOS5.0"`、第 11–12 字节 `00 02` = 512 B/扇区、结尾 `55 aa`）。
      `top_stage5_sector_rd.v` 的 `TARGET_LBA` 默认值已相应改为 `32'd8192`。
      ★ **读法（重要）**：Windows 的**卷句柄偏移是从分区开头算的**，所以物理 LBA 8192 正好
      等于**卷 `G:` 的偏移 0**，不需要管理员权限；反过来，用 `\\.\G:` 偏移 512000 读到的
      **不是** LBA 1000（那是分区内的另一个位置）。若要按原计划读物理 LBA 1000，得用
      HxD「打开物理磁盘」或管理员权限，但因为预计全 0，不作为主基准。

### 1.3 做引脚规划（查原理图，不写代码）

**2026-10-02 已完成**。引脚逐个核对，来源按权威性排序：
① **开发板手册**《HX4S20开发板手册-HDL版2410.pdf》的官方引脚表（串口表 `RXD=F12`/`TXD=D12`、
独立 LED 表 `LED1..4 = A4/A3/C10/B12`、独立按键表 `KEY1=A2`）；
② 原理图 `2_FPGA.pdf`（引脚号 ↔ 网络名）、`6_EX_DEVICE.pdf`（SD 卡座 / LED / 按键页）；
③ 厂商同器件（EG4S20BG256）例程 `7_lab_ex_2026_nosoft/example/lab_ex4_tf` 的 `pin.adc`。
三者对 `clk` / `sd_*` 完全一致。结果已写入
`safevision/platform/anlogic_eg4s20_hx4s20c/constraints/pin.adc`：

| 端口 | FPGA 引脚 | 原理图网络名 | 依据 | 说明 |
|---|---|---|---|---|
| `clk` | **R7** | `FPGA_GCLK` | `2_FPGA.pdf` | 板载 50 MHz 晶振；bring-up 不接 PLL |
| `rst_n` | **A2** | `KEY_1` | `2_FPGA.pdf` + `6_EX_DEVICE.pdf` | 独立按键，低有效；板上已有 10K 上拉，约束里再加内部 PULLUP |
| `sd_dclk` | **A14** | `FPGA_SD_CLK` | 两张图一致 | SPI SCLK |
| `sd_mosi` | **A13** | `FPGA_SD_CMD` | 两张图一致 | SPI MOSI |
| `sd_miso` | **B14** | `FPGA_SD_D0` | 两张图一致 | SPI MISO；**外部上拉情况未在可读的原理图文本中确认**，暂按厂商例程取 `PULLTYPE = NONE` |
| `sd_ncs` | **A12** | `FPGA_SD_D3` | 两张图一致 | CD/DAT3 当 SPI 片选（低有效） |
| `led[3:0]` | **A4 / A3 / C10 / B12** | `LED0`…`LED3` | `2_FPGA.pdf` + `6_EX_DEVICE.pdf` | 显示顶层状态码 |
| `uart_txd` | **D12**（已确认） | `TXD` | 开发板手册串口引脚表 + 图2-10 CH340G 原理图 | ★ **已确认是 FPGA 的发送脚**：板载 USB-UART（CH340G，位号 U41），手册串口引脚表给出 `RXD=F12` / `TXD=D12`；图2-10 显示 CH340G 的 pin2（芯片 TXD）接网络 `RXD`、pin3（芯片 RXD）接网络 `TXD`，**两线交叉**→网络名按 FPGA 视角命名，故 `TXD`(D12) 是 FPGA 输出、驱动 CH340 的输入，**不存在双向争用**。上板只需插 USB 线，开 COM 口 115200 8N1，**不需要外接 USB-TTL 模块** |

**为什么现在做**：引脚资源紧张（BG256 封装，最多 193 个用户 IO），事后硬塞容易冲突。
表已填好，`pin.adc` 是照抄结果。

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

- [x] **工程已建好并配好第一版**：`safevision/platform/anlogic_eg4s20_hx4s20c/project/safevision.al`
      （TD 6.2，器件 **EG4S20BG256**，`IncludeDir = ../../../rtl/include`）。
      35 条设计文件已加入（含板级顶层与 `reset_sync.v`），**全部是相对路径**（`../../../rtl/...`），
      队友 clone 后直接可用，不需要重新添加文件；`TOP_MODULE = top_stage5_sector_rd`，
      `constraint_1` 已挂 `pin.adc` + `timing.sdc`。
- [x] ★ **确认 TOP_MODULE 指向板级顶层**（2026-10-02 已在 `.al` 里写入）。工程刚建时顶层默认落在 `crc7` 上，
      TD 做依赖分析时把其余 32 个模块全标了 `AutoExcluded`——**这时候点综合只会综合出一个 8 行的 CRC 模块**。
      **仍需在 TD GUI 里点一次依赖分析/自动包含，确认 `spi_master` / `sd_initializer` / `sd_sector_reader` /
      `uart_tx` / `crc7` / `crc16_ccitt` / `reset_sync` 都没有被标成 `AutoExcluded`**。
      → **2026-10-02 已核对**：`safevision_Runs/syn_1/run.log` 里 `elaborate -top top_stage5_sector_rd`
      依次 elaborate 了 `top_stage5_sector_rd` / `reset_sync` / `sd_initializer` / `sd_sector_reader` /
      `crc16_ccitt` / `spi_master(CLK_FREQ=50000000)` / `uart_tx(CLK_FREQ=50000000)`，闭包完整，
      **没有被误排除**（`.al` 里 `spi_master.v` 仍留着 `AutoExcluded` 标记，但 TD 实际 elaborate 了它，
      标记与实际不一致属 TD 记账问题，不影响综合；想让它一致就再点一次全量依赖分析）。
      唯一需要 `crc7.v` 的地方是 `tb_crc`，bring-up 顶层用不到它，被排除是对的。
- [x] **把约束文件加进 FileSet `constraint_1`（ConstrainFiles）**：`pin.adc` + `timing.sdc`（2026-10-02 已在 `.al` 里登记）。
      源文件放 `safevision/platform/anlogic_eg4s20_hx4s20c/constraints/`。加进去之前，
      综合/布线是不带任何引脚与时序约束的。
- [x] **综合 + 布局布线，看报告**（2026-10-02 完成）：时序是否收敛、有无多驱动/未约束端口警告。
      → **时序收敛**：Setup WNS **+11.297 ns** / Hold WNS **+0.046 ns**，**违反端点 0**（906 端点 / 3480 路径），
      50 MHz 约束下报告 **Fmax 114.9 MHz**；资源 IO 11/188、LUT 814/19600、REG 434/19600、BRAM/DSP 0。
      → **无多驱动报错**（首轮的 `HDL-8007` 已随修复消失，`syn_1/run.log` 里再无 `black box`）；
      未约束端口只有**故意留空的 I/O 路径**（`sd_dclk`/`sd_mosi`/`sd_ncs`/`uart_txd`/`sd_miso`，STA 覆盖率 99.53%）。
      → **位流 `safevision.bit` 已生成**。原始报告（STA 原文、布线/布局 QoR、综合日志、资源）已复制到
      `evidence/reports/`，索引见 [evidence/reports/INDEX.md](../evidence/reports/INDEX.md)（条目 TC-Q-STA）。
      → **注意**：Hold（removal）余量只有 **0.046 ns**，为正但很薄，来源是 `reset_sync` 输出的复位树；
      以后在复位域里加寄存器或提频要重测。

#### 上板步骤（位流已就绪，2026-10-02）

1. 插好 TF 卡。参考值**已经读好了**：`evidence/board/lba8192_pc_20261002.bin`
   （物理 **LBA 8192** = 卷 `G:` 偏移 0 = FAT32 引导扇区，512 B，SHA-256 `E4704165…C426EEE`）。
2. 下载器接好、TD 能识别到器件（§2.1）。
3. **先重新综合**（`TARGET_LBA` 默认值刚从 `1000` 改成 `8192`，现有的
   `safevision_Runs/best_result/safevision.bit` 还是旧值那次构建的产物，不能直接用）：
   syn_1 → phy_1 → 生成位流，然后在 TD 里下载。
4. **先看板上 4 个 LED**（`led[3:0]` 的状态码，按 A4/A3/C10/B12 = LED1..LED4）：
   `1` 上电等待 → `2` 发初始化 → `3` 等 `init_done` → `4` 发读请求 → `5` 传输中 → `8` 成功。
   其它值＝失败，显示的是**错误主码低 4 位**，排查见 §2.6 第 12 条。
5. **插 USB 线 → 这里最容易卡住**：板上有**两个** USB 口 —— 下载位流用的是 **USB-JTAG**（AL-LINK），
   收数据要用**另一个标着 `USB-UART` 的 Type-C 口**（板载 CH340G）。**两个口都要插线**，
   而且顺序有讲究：先把 USB-UART 线插好、确认 COM 口出现，再（必要时）重新下载位流，
   最后才跑采集脚本 + 按复位键（插拔线可能让 JTAG 下载的位流掉电丢失）。
   怎么确认是哪个口：电脑上应该多出一个 `USB-SERIAL CH340 (COMx)`：
   ```powershell
   Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match 'CH340|USB-SERIAL' } | Select-Object Name, Status
   ```
   **只看到一堆"蓝牙链接上的标准串行 (COMx)"就说明 UART 那根线还没插**（蓝牙串口不是板子）。
   没出现 CH340 → 装 CH340 驱动（厂家包里有）；带黄色感叹号 → 按 `Win10、Win11解决驱动签名问题.pdf` 处理。
6. **采集 512 字节：用现成脚本 `safevision/verification/board/capture_uart_512.ps1`**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\safevision\verification\board\capture_uart_512.ps1 -Port COM5
   ```
   它会：列端口 → 打开 **115200 8N1 无流控** → 清掉残留字节 → 提示你按复位键 →
   收满 512 字节 → 存成**原始二进制**（默认 `evidence/board/uart_capture_<时间戳>.bin`）→
   与参考值逐字节比对，全对打印 `PASS` 并返回 0。
   ★ **顺序很重要**：512 字节只在**复位后**发一次、约 45 ms 就发完（115200）。LED 停在 `8`
   就说明那一轮早就结束了。所以**先让脚本开始等，再按复位键**（KEY_1 = A2）。
   ★ **不要用"串口助手 + 文本模式另存"**：那会把字节变成文本，且**不可逆**。
   2026-10-02 真实踩坑：Serial Debug 存成 `.txt` 后，凡是 `≥0x80` 的字节全被替换成
   **`EF BF BD`**（U+FFFD 的 UTF-8 编码），512 字节变成 **740 字节**，高位字节**再也无法还原**。
   要么用本脚本，要么在工具里选 **HEX / 二进制导出**。
7. 与 `evidence/board/lba8192_pc_20261002.bin` **逐字节比对**（512 B，SHA-256 `E4704165…C426EEE`），
   一个字节都不能差（M-9 = 阶段 5 验收）。脚本会自动做这件事；第一眼也可以自己认：
   开头 `eb 58 90` + `MSDOS5.0` 文本，结尾 `55 aa`。
8. 想再跑一轮：**按复位键**（KEY_1 = A2）。本顶层跑一轮就停在成功/失败态，不会循环。

#### LED 状态码速查（★ 高电平点亮：引脚高 = 灯亮，见原理图「4 bit LED」= 引脚→1K→LED 阳极→GND）

| LED4 LED3 LED2 LED1 | 码 | 含义 |
|---|---|---|
| **亮 . . .** | `1000` = 8 | **成功**（初始化 → 读扇区 → 512 Byte 经 UART 发完，CRC16 也对上） |
| . 亮 . 亮 | `0101` = 5 | 传输中（512 Byte 正在发） |
| . 亮 . . | `0100` = 4 | 已发读请求 |
| . . 亮 亮 | `0011` = 3 | 等 `init_done` |
| . . 亮 . | `0010` = 2 | 发初始化请求 |
| . . . 亮 | `0001` = 1 | 上电等待 |
| 其它 | — | 失败，显示**错误主码低 4 位**：`1`=SD 初始化失败、`2`=读超时/CRC 错、`3`=媒体非法、`7`=WAV |

> `1`/`2`/`3`/`4`/`5` 都是**低位**亮（LED1~LED3 那侧），只有 `8` 是**最高位**亮（**单独 LED4**）。
> 所以"只有 LED4 亮"就是成功。（位序：`led[3]`→LED4，`led[2]`→LED3，`led[1]`→LED2，`led[0]`→LED1。）

> UART 一个字节都没收到时，先看 LED 有没有到 `8`：到了 `8` 说明 SD 那一侧已经没问题，
> 问题在串口侧（选错 COM 口 / 被别的程序占用 / 波特率不是 115200 8N1）。

> 路径按本项目结构（[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)）：头文件在 `rtl/include/`，
> SPI/SD/FAT 在 `rtl/storage/`；**板级顶层、约束、IP、TD 工程统一归
> `safevision/platform/anlogic_eg4s20_hx4s20c/`**（其下 `rtl/` / `constraints/` / `ip/` / `project/`）。
> 只有**不带引脚的可移植 core** 才放 `rtl/top/`。
> 旧文档里的 `rtl/sd/`、`rtl/common/safevision_defs.vh`、`rtl/top/top_stage5_sector_rd.v`
> 都是引入新结构之前的路径，**已作废**。
>
> ★ 工程文件（`.al`）是**源文件**、必须版本管理：`.gitignore` 早先误把 `*.al` 当生成物忽略，
> 会让整个工程文件静默进不了仓库，现已修正。TD 的运行期垃圾（`*.lock.f`、`log/`、`td_*.logw`）
> 已单独忽略。

### 2.3 还没写的东西（板到之前最好补上）

- [x] **板级顶层** `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v`
      ——阶段 5 最小验证专用（**2026-10-02 已写**），功能：
      - 上电延时 → 拉高 `init_start` → 等 `init_done`
      - `init_done` 后自动发起一次 `rd_en`，`rd_addr = TARGET_LBA`（默认 `32'd8192` = 分区首扇区/FAT32 DBR）
      - 把 512 字节按顺序灌进 `uart_tx`（115200）
      - 状态码输出到 LED（`led[3:0]`：1/2/3/4/5/8，失败显示错误主码低 4 位）
      > 它直接接引脚、不属产品链，所以放 `platform/.../rtl/`（这里才是板级层）。
      > 产品顶层是 A 侧的 `platform/.../rtl/safevision_top.v`；不带引脚的可移植 core
      > 才是 `rtl/top/safevision_core.v`。
      > ★ 它**不接 PLL**，全部逻辑跑板载 50 MHz（bring-up 先排除 IP 变量）；取舍见
      > [interface_spec.md](interface_spec.md) §3.7。
- [x] 写完后在仿真里先跑通（把 UART 输出接到一个 UART 接收模型，确认 512 字节顺序正确）
      ——**2026-10-02 已做**：`tb_top_stage5_sector_rd.sv`（T1 完整命令序列 / T2 CMD17 参数 1000 /
      T3 512 Byte 经 UART 逐字节与卡模型一致 / T4 顶层进成功态），5 项断言全通过。

### 2.4 必做的实测项（每一项都要回填到 [interface_spec.md](interface_spec.md)）

| 编号 | 测什么 | 怎么测 | 回填到 |
|---|---|---|---|
| M-1 | **正常路径最大耗时** | 在 `M_RESP` 等待态埋计数器，用 ChipWatcher 抓若干次操作的最大值，× 裕量系数 | `safevision_defs.vh` 的 `SD_TO_RESP`、O-4 |
| M-2 | 数据令牌等待耗时 | 同上，抓 `S_TOKEN` 状态的计数值 | `SD_TO_DATA`、O-4 |
| M-3 | ACMD41 轮询总时长 | 抓从第一次 ACMD41 到 ready 的拍数（不同品牌卡差异很大） | `SD_TO_ACMD41`、O-4 |
| M-4 | 上电到 `init_done` 的时间 | 示波器或 LED 翻转计时 | 启动速度留证（E04） |
| M-5 | 实际 SCLK 频率 | 示波器量 `sd_dclk`。★ 注意 bring-up 版跑 50 MHz（不接 PLL），所以**初始化段应为 200 kHz、数据段 12.5 MHz**（= `safevision_defs.vh` 里按 100 MHz 推导的 400 kHz / 25 MHz 的**一半**；`SD_DIV_INIT=124` / `SD_DIV_FAST=1`）。整机接 PLL 后再按 400 kHz / 25 MHz 复核。★ **没有示波器也能间接确认晶振频率**：`uart_tx` 的分频是按 50 MHz 算的（`DIV = 50M/115200 = 434`），本次 512 字节在电脑侧按 115200 8N1 **完整无误地收到**（M-9 通过），说明实际时钟频率落在 **±2% 内就是 50 MHz**（否则字节会错位）。`sd_dclk` 的精确频率建议以后用 TD 的 ChipWatcher 抓 `div_cnt`/`sclk_r` 复核，不必强求示波器 | 接口文档备注 |
| M-6 | **连读 100 次** | ★ 顶层已内置**连读阶段**（`RPT_N`，默认 100）：挂载 + 扫目录后自动对同一 LBA（根目录扇区）连读 100 次，每次由 `sd_sector_reader` 的 CRC16 判好坏，报告出一行 `RPT=0064 OK=0064 BAD=0000`。步骤见 §2.4.1 | 手册 7.5 过关标准；证据回填 `evidence/board/` |
| M-7 | **多卡兼容** | 至少 3 张不同品牌/容量的卡各跑一轮，电脑侧先独立解析每张卡的分区表与 DBR 作基准；报告里的**几何行本就应逐卡不同**——"三张卡报告一模一样"反而是失败。步骤见 §2.4.1 | 兼容性留证 |
| M-8 | 拔卡 / 坏卡行为 | 运行中拔卡：LED 显示错误主码低 4 位（应为 `2`），报告末行 `ERR=02`，且**有限时间内**停住不挂死；按复位键重插后能重跑。★ 仿真已在 TB 里覆盖（连读中拔卡 → 进 `ST_ERR`、`ERR=02`、`RPT BAD=100`）。步骤见 §2.4.1 | 手册 7.4 过关标准 |
| M-9 | 单扇区读 + 电脑侧比对 | ★★ **通过（2026-10-02）**：工具改用 **HEX 文本导出**（无 `EF BF BD`），解码后 512 字节与 `evidence/board/lba8192_pc_20261002.bin` **SHA-256 完全相同**（`e470416567d512c0…`），非零字节 372 个也一致。证据见 `evidence/board/INDEX.md` 条目 **M-9-PASS** | 阶段 5 验收 ✅ |

> **M-3 特别提醒**：不同品牌卡的 ACMD41 轮询时长差异可达几十倍，这也是为什么
> 现在的超时值只是"推导 + 裕量"，必须实测后才敢冻结。

### 2.4.1 M-6 / M-7 / M-8 上板操作步骤（连读 / 多卡 / 拔卡）

前提：位流用的是 `top_stage6_fat32_mount`（TD 工程 `TOP_MODULE` 已指向它），串口按
§2.2 第 5–6 步接好（板载 USB-UART，**115200 8N1**）；采集用
`safevision/verification/board/capture_uart_512.ps1`，或串口工具里选 **HEX / 二进制导出**
（**不要用文本模式**，见 §2.6 第 14 条）。健康卡整份报告固定 **476 Byte**
（`183 + 5×52 + 27 + 6`），末行 `DONE`。

**M-6（同一 LBA 连读 100 次）**

1. 插卡 → 重新综合下载 → 按复位键（KEY_1 = A2）。
2. 收整份报告，等 `DONE`。看最后两行：
   - 健康：`RPT=0064 OK=0064 BAD=0000` + `DONE`。`OK == total` ⇒ 100 次连读**每一次**
     的 CRC16 都通过。
   - 有 `BAD != 0`（末行会变成 `ERR=02`）⇒ 出现了偶发读错，按 §2.6 第 4–6 条查。
3. 留证：原始报告存 `evidence/board/`，在 `INDEX.md` 记一条（`RPT=` 行值 + SHA-256 +
   板上 LED 码 + 日期）。
4. 结论口径（手册 7.5）：**"同一 LBA 连续 100 次 CMD17，CRC16 全部通过，OK=100 BAD=0"**。

**M-7（≥3 张不同品牌的卡）**

1. 准备 ≥3 张卡（如金士顿 / 闪迪 / 杂牌各一），**都格式化成 FAT32**，每张都放 4–5 个
   `SV000x.BMP`（否则 `ENT=` 会不同——那也要记录，但先分清是"卡不同"还是"内容不同"）。
2. ★ **每张卡先在电脑侧独立解析一遍**：`Get-Partition` 看分区起始扇区，再把该物理扇区的
   512 Byte 存成参考二进制，据此算出这一张卡的
   `BASE / SECS / BPS / SPC / NFAT / FATLBA / DATALBA / ROOTLBA / TOTSEC / TOTCLUS` 基准。
3. 逐卡：插卡 → 复位 → 收 476 Byte 报告 → 与**该卡自己的**电脑侧基准逐字段对账。
4. ★ **重点**：几何行**本来就应当逐卡不同**（分区起始 / 簇大小 / FAT 大小都不一样）。
   "三张卡报告一模一样"反而说明读的是旧值或路径被写死了，是**失败**。跨卡唯一应相同的，
   是格式（长度 / 行数 / CRLF 行尾）与末行的 `RPT OK=total BAD=0` / `DONE`。
5. 留证：每张卡一份报告 + 对应电脑侧基准，各自在 `INDEX.md` 记一条（注明品牌 / 容量）。

**M-8（拔卡 / 坏卡）**

1. 先跑一轮正常（M-6）确认健康。
2. **在连读阶段进行中拔卡**（LED 停在 `9` 时拔；也可以直接用一张认不到的坏卡上电）。
   要点是"运行中失去卡"，不是插拔本身。
3. 期望（**有限时间内**，不挂死）——因为 reader 每个等待态都有自己的超时
   （`SD_TO_RESP` / `SD_TO_DATA`），连读的**每一次读独立计时**，顶层还有兜底超时：
   - 报告 `RPT=` 行的 `BAD` 等于拔卡后失败的那几次，末行显示 `ERR=02`；
   - 板上 `led[3:0]` 显示**错误主码低 4 位 = 2**（不是成功态的 `8`）；
   - 不会永远停在某个中间码上。
4. 拔卡后插回，**按复位键**，应能重新完整跑通一轮（回到 `DONE`，LED = `8`）。
5. 留证：把"拔卡那一轮"的报告与 LED 码记进 `INDEX.md`——这是手册 7.4 的过关证据。

### 2.4.2 SDRAM 官方 Demo 回环上板步骤（阶段 9 第一步 / 手册 7.9，2026-10-02）

对应顶层：`platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v`（接口见
[interface_spec.md](interface_spec.md) §3.9）。**这条路径不能仿真**——厂商 SDRAM 控制器是
安路 RSA 加密 IP（`sdr_*.enc.v`），只能由 TD 解密，所以没有 TB、也进不了回归，
**验收只有"上板读报告"一条路**。

> ★★ **2026-10-02 已通过（条目 M-11-PASS）**。位流 22:01:24 下载后收 **71 Byte**：
> `SV-SDRAM-LOOP` / `INIT=01 LOCK=01` / **`W=1000 R=1000 CAP=1000 BAD=0000`** / `DONE`，
> **与设计值一字不差**。⇒ 阶段 9 的"先证明厂商硬核能用"在实物上完成。
> 下面是**重跑/复现**用的步骤（换参数、重做验证时照走）。

| 步 | 做什么 | 看什么 |
|---|---|---|
| 1 | ✅ **工程文件已对齐（2026-10-02 已完成）**：`safevision.al` 里已登记 `../ip/sdram/` 5 个 + `../ip/pll/sv_system_pll.v` + `../rtl/top_sdram_loopback.v`（共 46 条 File 条目、路径全部可达、`CompileOrder` 1–44 无重复），`TOP_MODULE = top_sdram_loopback`。★ 已在 `syn_1/run.log` 里看到 **`elaborate -top top_sdram_loopback`**，证明 TD 真的采用了它 | 工程文件表里能看到那 7 条；`TOP_MODULE` = `top_sdram_loopback` |
| 1b | ⚠ 提醒：**`.al` 谁写的不重要，TD 内存里是什么才决定综合结果** —— 2026-10-02 21:41 在 GUI 里点过一次"保存工程"，把 `.al` 覆盖成了内存里的阶段 6–7 快照（新加的 7 条全丢）。后来通过"关闭 TD（选【否】不保存）→ 重开"才让 TD 采纳修好的 `.al`。**以后在 TD 里保存前，先确认文件表里仍有那 7 条** | — |
| 2 | **确认 `constraints/pin.adc` 的 `[SD-ONLY]` 四条处于注释状态**（`sd_dclk`/`sd_mosi`/`sd_miso`/`sd_ncs`）。这三个顶层**没有** `sd_*` 端口，而 TD 对"约束里出现顶层不存在的端口"是**报错**：`HDL-1492 Failed to find pin sd_dclk in model top_sdram_loopback` + `USR-8168 ... is not a valid ADC command`，随即 `PRJ-5013 Run syn_1 failed`。★ **`read_adc` 是每次 Run 都执行的命令，改完 `.adc` 直接重综合即可、不用关 TD** | `pin.adc` 里那四行是 `#set_pin_assignment ...` |
| 3 | **重新综合**（这次多了 5 个 IP 文件 + `sv_system_pll` + `derive_clocks`，旧位流不含它们） | `syn_1/run.log` 里必须是 **`elaborate -top top_sdram_loopback`**（不是 stage6！）；`HDL-8007` / `black box` 必须为 0；`sv_system_pll` / `sdram` 要真的 elaborate |
| 4 | 下载位流 | — |
| 5 | 看 `led[3:0]` | `2` 等 SDRAM 初始化 → `3` 写 → `4` 等落地 → `5` 发读 → `6` 等收齐 → `7` 发报告 → **`8` = 成功** |
| 6 | 插 USB，开 COM 口 **115200 8N1**，收 **71 Byte**（★ 报告头是 `SV-SDRAM-LOOP`，不是 `SAFEVISION B STAGE6`） | 用 **HEX / 二进制**导出（★ 别用文本模式，`≥0x80` 会被换成 `EF BF BD`） |
| 7 | 对账 | 期望 `INIT=1 LOCK=1` / `W=1000 R=1000 CAP=1000 BAD=0000` / 末行 `DONE` |
| 8 | 按复位键可重跑（整条序列从 `ST_POWER` 重来） | — |
| 9 | 留证 | 把 71 Byte 存 `evidence/board/` 并在 `INDEX.md` 记一条；把 STA 报告按 `evidence/reports/` 规则记 `TC-Q-STA-4` |

> ★ 换回阶段 5/6 顶层（跑 M-7 多卡 / M-8 拔卡）时，别忘了把 `pin.adc` 那四行行首的 `#` 去掉，
> 否则 `sd_*` 会变成**未约束引脚**（TD 可能自动分配 = 位流静默错误，比报错更难查）。

**失败对照**（LED 显示错误主码低 4 位）：

| LED | 错误码 | 含义 | 先怀疑什么 |
|---|---|---|---|
| `1` | `ERR=01` | SDRAM 初始化一直不完成（`Sdr_init_done` 没来） | ① `sv_system_pll` 反馈支路：`sv_system_pll` 是 `FEEDBK_PATH=CLKC0_EXT`，反馈经过 C0 的 BUFG，而本顶层把 C0 留空了 —— 若始终锁不上，把 C0 接出来给一个真实负载再试；② 复位：`Rst` 是高有效、已与 `pll_locked` 相与；③ 加密件是否被 TD 正常解密 |
| `2` | `ERR=02` | 读命令发了但返回不齐（`CAP < W`） | 读突发节奏太密（调小 `BURST_N` 或调大 `BURST_GAP`）；或读写没真正错开（调大 `WR_DRAIN_CYC`） |
| `3` | `ERR=03` | 返回数量对但数据不对（`BAD != 0`） | 相位/采样：`Clk_sft` 的 180° 相移没生效（不能用反相器代替）；或地址译码问题（试 `ADDR_SHIFT=11` + `TEST_WORDS=1024` 扫全片） |

**★ 两个概念别搞反**：报告里的 `W` 是**我们发出的写使能拍数**、`R` 是**我们发出的读命令数**、
`CAP` 是**控制器返回的有效 word 数**。`W == R == CAP` 只说明"命令都被受理了"，
**数据对不对要看 `BAD`**。三者不等才是"控制器丢了命令"。

### 2.5 存储链的实测项（阶段 8–16，板到后按序补）

> 这些项的共同特点：**仿真里全是"理想值"，只有上板才知道真数**。手册 7.12 明确
> 规定"报告里只接受一种结论形式：用计数器统计一段时间内实际完成搬运的数据量，
> 除以时间得到控制器持续带宽，并同时给出该时段的 FIFO 最低水位"。

| 编号 | 测什么 | 怎么测 | 回填到 |
|---|---|---|---|
| M-10 | **SDRAM 初始化时间** | 上电到 `init_done` 的拍数 | ✅ **定性已通过（2026-10-02）**：`top_sdram_loopback` 报告 `INIT=01` ⇒ 在 16 ms 超时窗（`INIT_TO_CYC = 2_000_000` @125 MHz）内到齐；**精确拍数仍未测**（需 ChipWatcher 抓 `Sdr_init_done`） |
| M-11 | **SDRAM 读写回环** | 官方 Demo 写一帧再读回，逐字节比对（这是用 SDRAM 前的第一步，别跳） | ✅ **已通过（2026-10-02，条目 M-11-PASS）**：写 4096 word → 读回 4096 word → **`BAD=0000` 零错**；`W=R=CAP=1000`、71 Byte 报告与设计值一字不差。★ 已覆盖 16 KB 连续区间；**全片稀疏扫描（`ADDR_SHIFT=11` + `TEST_WORDS=1024`）建议补做**，以覆盖行/体地址译码 |
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
12. **LED 卡住 / UART 一个字节都收不到** → 先看板上 `led[3:0]` 的状态码：
    `1` 上电等待、`2` 发初始化请求、`3` 等 `init_done`、`4` 发读请求、`5` 传输中、`8` 成功；
    其余值表示失败，显示的是**错误主码低 4 位**。
    - 卡在 `3`：SD 初始化没过 → 按上面第 1–4 条查（SCLK、CMD0 的 CRC=0x95、CMD8 的 CRC=0x87）
    - 到 `8` 但电脑收不到：先确认串口工具选的是板载 USB-UART 的那个 COM 口、**115200 8N1**，
      再看电脑侧有没有别的程序占着该串口；`uart_txd`（D12）已经确认是 FPGA 发送脚（见 §1.3）
13. ★ **TD 综合报 `net 'xxx' is constantly driven from multiple places`（HDL-8007/9007）**
    → 不是引脚问题，是 RTL 里**同一个 `reg` 被两个 `always` 块赋值**。
    **ModelSim 编译和仿真都不报错**（仿真里只是竞争，谁最后写谁赢），所以单元 TB 全绿也可能带着这个错——
    这正是"必须真跑一次 TD 综合"的理由。
    真实案例（2026-10-02）：`sd_initializer.v` / `sd_sector_reader.v` 的 `bdata` 本应只由主状态机驱动，
    但字节引擎的复位分支里多写了一次 `bdata <= 8'hFF`，TD elaborate 直接把该模块降级成黑盒。
    修法：把那个复位赋值收归主状态机（保证一个 `reg` 只有一个驱动源）。
    查法：TD 报的 "found another driver here in 文件(行)" 就是第二个 `always` 块的起始行，两边一起看。
14. ★ **收到的 512 字节里出现一堆 `EF BF BD`，文件比 512 长（例如 740）**
    → **不是 FPGA 的问题，是串口工具"文本模式"保存毁掉了高位字节**。
    `EF BF BD` 是 **U+FFFD（替换字符）的 UTF-8 编码**：工具把字节流当文本解码，凡是不是合法
    UTF-8 的字节（基本就是 `≥0x80` 那些）全被替换成它，**不可逆**。
    判定方法（也是本次的证明方式）：把参考 512 字节按"UTF-8 解码（errors=replace）再编码"
    变换一次，若结果与采集文件**逐字节相同**，就说明 FPGA 发的是对的、纯粹是保存方式的问题。
    修法：**用二进制方式采集**（`safevision/verification/board/capture_uart_512.ps1`），
    或在串口工具里选 HEX / 二进制导出。
    （2026-10-02 真实案例：512 → 740 字节，141 个 `≥0x80` 的字节被替换。）
15. ★ **`top_stage6` 的报告开头多一个 `0x00`（字节数比预期多 1）**
    → 报告头的**声明位宽比实际内容多 1 字节**：`hdr_bits` 曾写成 `[1471:0]`（184 Byte），
    而六段实际只有 `21+42+25+51+34+10 = 183` Byte，Verilog 在 **MSB 侧补零**，
    于是先发出一个 `0x00`、整份报告后移一字节（板上 450 = 1 NUL + 183 + 260 + 6）。
    修法：按**真实字节数**声明（183 → `[1463:0]`），并保留「报告各段字节数逐段相加
    = 声明字节数」的核对注释（v1.13 已修）。
16. ★ **报告每行行尾是 `72 0A`（字母 r + LF）而不是 `0D 0A`**
    → 源码里用了字符串转义 `"...\r\n"`。**ModelSim vlog 10.7 与 TD 6.2 都不把字符串里的
    `\r` 当转义**，二者都把 `"DONE\r\n"` 编成 `44 4F 4E 45 72 0A`。之所以仿真"看起来是对的"，
    是因为旧 TB 也用同一个转义、**两边错得一样**，自洽通过。
    修法：行尾**写显式字节** `8'h0D, 8'h0A`（v1.13 已改，RTL 与 TB 都是显式字节）。
    这条与项目规则 §5 第 11 条是同一类"仿真与综合不一致"。
17. ★ **`RPT=` 行的 `BAD` 不为 0 / 末行是 `ERR=02`**
    → 连读阶段有若干次 CMD17 超时或 CRC16 校验失败。正常卡（刚跑过 M-6）出现这种情况，
    优先按第 4–6 条查（位序 / SCLK 相位 / 数据令牌与 CRC 字节有没有数满、超时计数器
    有没有在进等待态时清零）。**拔卡那一轮**出现 `BAD != 0`（末行 `ERR=02`、LED=`2`）
    是**预期**行为，不是故障——那正是 M-8 要看的证据。

---

## 三、已知的"未完成项"（别当成 bug）

| 项 | 说明 | 什么时候做 |
|---|---|---|
| CMD18 多扇区读 | `sd_sector_reader` 目前只支持 CMD17，`rd_len` 必须为 1，否则明确报错。多扇区读需要额外的 STOP_TRANSMISSION。连带影响：`fat32_directory_scanner` 现在只能"一个扇区一次 CMD17"，根目录越大读得越碎 | 带宽优化阶段（对应 O-11） |
| 超时值未实测 | `safevision_defs.vh` 里的超时是"规范推导 + 裕量"，仿真时用 `SIM_FAST_TO` 缩小以便跑到超时分支 | 板到后执行 M-1~M-3 |
| 板级顶层 | **已解决**：`top_stage5_sector_rd.v` 已写，并新增 `tb_top_stage5_sector_rd.sv` 在仿真里跑通（5 项断言）；仍未上板 | 已做 |
| 引脚约束 | **已解决**：`pin.adc` 与 `timing.sdc` 已写并登记进 TD 工程；`uart_txd = D12` 已确认为 FPGA 发送脚 | 已做 |
| `uart_txd` 物理落点 | **已解决（2026-10-02）**：开发板手册串口引脚表（`RXD=F12`/`TXD=D12`）+ 图2-10 CH340G 原理图（两线交叉）确认 `D12` 是 FPGA 发送脚、对接板载 USB-UART，无需外接 USB-TTL。`pin.adc` 保持不变 | 已完成 |
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
| — | 阶段 7 通过后更新（回归 206 项）。同时按新结构全仓改名：`rtl/{include,common,storage,media}` + `verification/{unit,models}` + `tools`，回归全绿未回归。新登记三条踩坑：清零逻辑要放状态机之外、文件末字节落在扇区末字节时的同拍判定、BMP 字段同为小端 |
| — | **阶段 8–16 + 阶段 6 收尾通过后更新（回归 382 项）**。新增 `rtl/memory/` 全套（SDRAM wrapper、帧缓存地址、帧写入、仲裁、DMA 读、双缓冲、帧交换、带宽监视）、`rtl/common/`（切分缓冲、同步 FIFO、FIFO 健康度、错误上报）、`frame_memory_model.sv` 行为模型、`file_index.v`。新增 §2.5 存储链实测项 M-10~M-19、§2.6 排查顺序扩到 11 条、"未完成项"表补上 SDRAM 真实 IP / 异步 FIFO / 音频链 / 帧交换联调 / 整机集成 |
| — | **阶段 8–16 全部落地 + 媒体层收尾后更新（回归 457 项）**。补 `bmp_unpack` / `wav_parser` / `file_index` / `error_report`，补登记 `ERR_WAV` 与 `DET_WAV_*` 错误码 |
| — | **v1.7：逐项核对命名后更新（回归 502 项 / 15 个 TB）**。① 重命名 4 处（`wav_parser`、`memory/fifo_health_monitor`、`frame_memory_model`、`tb_frame_writer`）；② 补 `rtl/include/pixel_format_defs.vh`（**冻结地址表唯一来源**）与 `event_code_defs.vh`；③ **修掉"同一个常量在 4 个模块各存一份副本"**（帧几何/地址表全部改为引用 `` `SV_`` 宏，parameter 保留）；④ 补 `rtl/common/crc16_ccitt.v` / `crc7.v`，`sd_sector_reader` 与 `frame_writer` 各自那份重复的 CRC 函数删掉改为例化；⑤ 新增 `tb_crc`(12)、`tb_fat32_cluster_walker`(33，**该模块的判 EOC/越界/判环三条收尾分支此前从未被仿真跑过**)；⑥ 拆分 TB：`tb_frame_swap`→`tb_memory_arbiter`+`tb_frame_swap_ctrl`，`tb_media`→`tb_bmp_unpack`+`tb_wav_parser`（只搬位置不改断言）。**概念更正**：此前说的"宏与 parameter 命名冲突"是误判——宏只在写成 `` `名字 `` 时展开，两者不会冲突（已编译验证） |
| — | **补交付口径与文档同步规则**。① 新增"文档同步义务"说明（本文件属文档三件套，状态/回归数/未完成项变化必须回来改）；② 补一份真正的 `README.md`（目录结构、跑仿真方法、状态总览、硬约定、有意未创建的目录）；③ 修正 §2.2 里 v1.5 改名前的过期路径（`rtl/common/safevision_defs.vh` → `rtl/include/…`、`rtl/sd/` → `rtl/storage/`）；④ 把"开发基准＝手册 V2.0 / 结构基准＝仓库目录结构"写进 interface_spec 与项目规则文件 |
| — | **v1.8：引入队友的项目管理覆盖包（目录骨架 + 管理文档），并把它的过期内容改对**。新增 `.github/` 模板、`docs/` 六个子目录（architecture/interfaces/requirements/management/verification/release）、`evidence/` 七类证据索引、`safevision/{platform,build,assets}`、`rtl/{video,audio,control,safety,top}`、`verification/{subsystem,system,board}`、`tools/check_repo.ps1` —— **全部只有 README 占位，无功能代码**。`.gitignore` 换成覆盖包版本（白名单加 `!/.github/` `!/evidence/`，多排除 `*.lic`/`*.key`/`*.pem`）。**接口/RTL/TB/回归数一字未变，仍 502 项断言 / 15 个 TB**，目录自检 `LAYOUT PASS`。覆盖包是按旧快照（48 文件 / 27 RTL）做的，带进来的过期内容已逐项改对：**27→29 个 RTL、11→15 个 TB、457→502 项断言**、`fifo_health_monitor` 归 `memory/`、`wav_reader`→`wav_parser`、`sdram_model`→`frame_memory_model`、`tb_media`/`tb_mem_write`/`tb_frame_swap` 拆名、并作废"待办清单仍有 `rtl/sd` 旧路径"的指控（v1.7 已修）。另修 `interface_spec` §3.1 的 `rtl/sd/spi_master.v` → `rtl/storage/…` 与 `bmp_unpack.v` 注释里的 `tb_media` → `tb_bmp_unpack` |
| — | **结构基准变更 + 全仓文档去绝对路径 + 清除旧参照物引用**。① **结构基准改为本仓库 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)**，原参照物作废，全仓对它的引用（RTL 头注释、模块小节标题、表头列名、历史行里的出处标注）已一并清除；② 清掉覆盖包带进来的本机绝对路径——文档里的 ModelSim 安装路径改为按变量名 `$MSIM_BIN` 描述，文档树根由 `Safe_Vision_FPGA_2026/` 改为 `<仓库根>/`，`run_sim.ps1` 用法注释与原理讲解里的 `f:\...\` 占位改为相对路径。新约定：**文档里只用仓库相对路径** |
| 2026-10-02 | **板级 bring-up 第一版落地**：① 新增板级顶层 `platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v`（上电延时 → SD 初始化 → 读 LBA=1000 → 512 Byte 经 UART 回传；两 SD 模块共用一份 `spi_master`，按 `init_done` 二选一；**不接 PLL，全跑板载 50 MHz**）；② 新增 `constraints/pin.adc`（引脚逐个按 `2_FPGA.pdf` / `6_EX_DEVICE.pdf` 核对，并与厂商同器件例程交叉验证）与 `constraints/timing.sdc`（单一 50 MHz：`create_clock -period 20`）；③ TD 工程 `safevision.al` 把 `TOP_MODULE` 从 `crc7` 改为 `top_stage5_sector_rd`，加入顶层与 `reset_sync.v`，并把两约束挂到 `constraint_1`；④ **新增顶层 TB `tb_top_stage5_sector_rd.sv`**（T1 完整命令序列 / T2 CMD17 参数 1000 / T3 512 Byte 经 UART 逐字节与卡模型一致 / T4 顶层进成功态）→ 回归 **502 → 507 项断言 / 15 → 16 个 TB，全 PASS**；⑤ **`run_sim.ps1` 的 ModelSim 路径改为 `-ModelSimBin` 参数 + `MSIM_BIN` 环境变量**（与 `run_clock_sim.ps1` 同口径，删掉写死的本机路径；`check_repo.ps1` 的自检正则同时扩到 `../platform/`）。**待办**：`uart_txd` 物理落点复核（暂取 D12）、TD 里确认依赖分析没误标 `AutoExcluded` |
| 2026-10-02 | **第一次在 TD 里跑依赖分析 + 综合，暴露并修掉一个真 bug**：① **TD 报 `HDL-8007 net 'bdata[7]' is constantly driven from multiple places`**（`sd_initializer.v(120)` + `sd_sector_reader.v(137)`）——这两个模块的 `bdata` 本应只由主状态机驱动，但字节引擎的复位分支里多写了一次 `bdata <= 8'hFF`，两个 `always` 块写同一个 `reg`。**ModelSim 编译/仿真都不报错（回归 507 项全绿也带着它走），TD elaborate 直接把两个模块降级成黑盒**。已把该复位赋值收归主状态机；另写了一遍全仓静态复查（同一 `reg` 出现在 >1 个 `always`/`initial` 块）确认其余 29 个 RTL 没有同类问题。② **`AutoExcluded` 已核对**：`safevision_Runs/syn_1/run.log` 显示 `elaborate -top top_stage5_sector_rd` 把闭包内 7 个模块全部 elaborate 到了，没有被误排除（只有 `crc7.v` 被排除，而它只被 `tb_crc` 用，正确）。③ **`uart_txd = D12` 确认**：开发板手册《HX4S20开发板手册-HDL版2410.pdf》的串口引脚表（`RXD=F12`/`TXD=D12`）+ 图2-10 CH340G 原理图（CH340 pin2→网络 `RXD`、pin3→网络 `TXD`，**两线交叉**）证明网络名按 FPGA 视角命名，`D12` 是 FPGA 发送脚、对接**板载 USB-UART**，**不需要外接 USB-TTL 模块**。④ 新增排查条目 §2.6-13（多驱动只在 TD 报、仿真不报）。⑤ `.gitignore` 增加 TD 运行产物 `*_Runs/` 与 `*.logw` |
| 2026-10-02 | **TD 全流程跑通，位流已生成，可以上板**：修掉多驱动问题后重新综合 → 布局 → 布线 → 位流**一次通过**。**Setup WNS +11.297 ns / Hold WNS +0.046 ns，违反端点 0**（906 端点 / 3480 路径）；50 MHz 约束下报告 **Fmax 114.9 MHz**（余量很大，说明 bring-up 这版逻辑很浅）；资源 **IO 11/188、LUT 814/19600、REG 434/19600、BRAM 0、DSP 0、slices 436（4.45%）**；IO 计数 11 与顶层 11 个端口一致 ⇒ **`pin.adc` 已生效**。`syn_1/run.log` 中 `HDL-8007/9007` 与 `remains a black box` **全部消失**（对比同日早先那次失败的 elaborate）。**原始报告留证**：新建 `evidence/reports/` 条目 TC-Q-STA，复制了 TD 布线后 STA 原文（`final_timing.rpt`）、布线/布局 QoR、综合日志、综合后资源，并在 `evidence/reports/INDEX.md` 记录 SHA-256 与结论（`.bit` 因全局忽略不进仓库，只记存在与生成时间）。**新增 §2.2「上板步骤」**（7 步：插卡 → 下载 → 看 LED 状态码 → 插 USB 开 COM 口 115200 8N1 收 512 Byte → 与 `lba1000_pc.bin` 逐字节比对 → 按复位键重跑）。**唯一遗留的隐患**：Hold（removal）余量 0.046 ns 很薄，源头是 `reset_sync` 输出的复位树，以后在复位域加寄存器或提频需重测；`uart_txd` 等 I/O 路径仍故意未约束（等 M-5/M-6 实测） |
| 2026-10-02 | **改掉比对基准：LBA 1000 → LBA 8192**。读卡器（`Get-Disk` 磁盘 2，卷 `G:` 标签 `HX4S20C`，FAT32，7.38 GB）实测：分区**从物理扇区 8192 开始**，所以原定的**物理 LBA 1000 落在分区前的空隙里、读出来是 512 个 `0x00`** —— 两边全零会让逐字节比对失去证明力。改用**分区首扇区 = FAT32 引导扇区（DBR）**：内容非零、可识别（`eb 58 90 "MSDOS5.0"`…`55 aa`）。参考值存 `evidence/board/lba8192_pc_20261002.bin`（512 B，SHA-256 `E4704165…C426EEE`），已在 `evidence/board/INDEX.md` 记条目 **REF-LBA8192**（含设备、分区表、读法与两个概念陷阱）。`top_stage5_sector_rd.v` 的 `TARGET_LBA` 默认值改为 `32'd8192`；`tb_top_stage5_sector_rd.sv` **刻意保留 1000**（它显式传参，验的是"给定 LBA 原样送出"这条通用性质，断言一字未动），回归仍 **507/507 PASS**。**同时修正 M-5 的预期值**：bring-up 跑 50 MHz 不接 PLL，SCLK 应为**初始化段 200 kHz / 数据段 12.5 MHz**（是 `safevision_defs.vh` 按 100 MHz 推导的 400 kHz / 25 MHz 的一半）。**与此同时 `TC-Q-STA` 那份证据对应的是 LBA=1000 的构建，需要重新综合一次以对齐。** |
| 2026-10-02 | **上板第一次实测：LED 状态码 = 8（成功），并新增上板采集脚本**。① 位流下载成功后板上 **只有 LED4 长亮**。查原理图「4 bit LED」确认 LED 接法是 `FPGA 引脚 → 1K（RN17）→ LED 阳极 → 阴极 → GND`，即**高电平点亮**；我们的状态码里只有 `4'h8`（`1000`）是最高位亮 ⇒ **LED4 单独亮 = 8 = 成功态**（SD 初始化 + CMD17 读 LBA 8192 + 512 Byte 经 UART 发完 + CRC16 对上）。② 收不到数据的原因定位：电脑上只有 **4 个蓝牙串口**（COM3/4/8/9），**没有 CH340** ⇒ **板载 USB-UART 那个口没插线**（下载位流用的是 USB-JTAG，是另一个口）。③ 新增 **`safevision/verification/board/capture_uart_512.ps1`**：列端口 → 115200 8N1 无流控 → 清残留 → 提示按复位键 → 收满 512 Byte → 存**原始二进制**（默认 `evidence/board/uart_capture_<时间戳>.bin`）→ 与参考值逐字节比对，全对打印 `PASS` 返回 0（已在本机验证端口枚举与错误分支正常）。④ §2.2「上板步骤」补到 8 步 + 新增 **LED 状态码速查表**（含接线极性与位序 `led[3]`→LED4），并写明**两个 USB 口的顺序**和"先让脚本等、再按复位键"（512 Byte 只在复位后发一次、45 ms 发完）。⑤ 「USB 转串口模块不需要买」那条已在 §1.1 划掉。 |
| 2026-10-02 | **第二次上板：拿到 UART 数据，但被串口工具的文本模式有损转换**。用户用 Serial Debug 助手存出 `Serial Debug 2026-10-02 175226.txt`（740 B），HxD 里出现大量 `EF BF BD`。**严格验证**：把参考 512 字节按"当 UTF-8 文本解码（非法字节→U+FFFD）再编码"变换一次，得到 **740 字节且与采集文件逐字节完全相同** ⇒ **FPGA 发出的就是参考原文，链路全对**；损失全部来自保存方式（参考里 141 个 `≥0x80` 的字节被替换，512→740，不可逆）。可逐字节确认 371 个 `<0x80` 字节；ASCII 串 `MSDOS5.0` / `NO NAME    FAT32` / `BOOTMGR` / `Disk error` / `Press any key to restart` 全对。**M-9 标记为"数据已证明正确、尚需一次二进制采集"**。证据存 `evidence/board/uart_capture_20261002_175226_textmode_mangled.txt`（740 B，SHA-256 `0B350785…`），索引条目 **CAP-M9-01**。新增排查条目 **§2.6-14**（`EF BF BD` 的识别与判定方法），并在 §2.2 第 6 步写明这个坑。 |
| 2026-10-02 | **★ M-9 通过 —— 阶段 1–5 的实物验收完成**。重新导出改为 **HEX 文本**（无任何 `EF BF BD`），1536 B = 512 个 `XX ` 记号；解码成 512 字节后与参考 `lba8192_pc_20261002.bin` **SHA-256 完全相同**（`e470416567d512c0…`），非零字节 372 个也一致 ⇒ **512/512 逐字节一致**。至此实物验证覆盖：SPI 位序与 SCLK 相位、`CMD0`/`CMD8` 的 CRC7、`CMD55`+`ACMD41`+`CMD58`、`CMD17` 的 LBA 大端字节序、512 Byte 数据通路、CRC16 比对。证据：`evidence/board/uart_capture_20261002_175836.bin`（512 B，与参考同哈希）+ 原始导出 `uart_capture_20261002_175836_hextext.txt`（1536 B），索引条目 **M-9-PASS**。另：**M-5 不再强依赖示波器** —— `uart_tx` 的分频按 50 MHz 算，512 字节能在 115200 下完整收到即说明实际时钟在 ±2% 内就是 50 MHz；`sd_dclk` 精确频率可用 TD 的 ChipWatcher 复核。**下一步候选**：M-6（连读 100 次，需在顶层加连读计数）/ M-7（多卡）/ M-8（拔卡恢复）/ 把 bring-up 顶层往上推一层做阶段 6–7 的板级验证（读 DBR+BPB、扫根目录）/ SDRAM 官方 Demo 读写回环（手册 7.9）。 |
| 2026-10-02 | **★ 为阶段 6–7 板级验证补上"卷基址"这块（`mbr_parser`）—— 这是板级实测逼出来的真缺口**。读代码发现 `fat32_boot_parser` 写死 `sd_rd_addr <= 32'd0`（TB 也有断言 `T11.3 挂载读的是 0 号扇区`），即**整个 FAT32 层假设"卷从 0 号扇区开始"（超级软盘格式）**；但真实 TF 卡是分区的（本卡分区起始 = 物理扇区 8192，卡 0 号扇区是 MBR）⇒ 直接接上去必然 `mount_error`。新增 **`rtl/storage/mbr_parser.v`**：读卡 0 号扇区，按**小端**解析分区 0 的起始 LBA（`446+8..11`）与扇区数（`446+12..15`），给出 `has_mbr` / `vol_base_lba` / `part_secs`；对"无 `0x55AA` 签名 / 分区项为空 / 起始 LBA=0"三种情况**不报错**、按无分区表回退为 0，只透传 SD 层错误。**约定写进 interface_spec §3.2.1**：FAT32 层永远不碰分区偏移，**卷基址只在板级顶层加一次**。新增 `tb_mbr_parser.sv`（T1 有效 MBR 起始 8192 / T2 无签名 / T3 空表项 / T4 起始 LBA=0，**7 项断言**）⇒ 回归 **507 → 514 项断言 / 16 → 17 个 TB，全 PASS**（既有 TB 与 RTL 端口一字未动）。interface_spec 升 **v1.11**。**下一步**：写阶段 6–7 的板级顶层（上电 → init → `mbr_parser` → `fat32_boot_parser` → `fat32_directory_scanner` → UART 回传文本报告比对）。 |
| 2026-10-02 | **★ 阶段 6–7 板级顶层已写 + 仿真通过（未上板）**：`platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v` 串起 上电 → SD 初始化 → `mbr_parser` → `fat32_boot_parser` → `fat32_directory_scanner`(+`fat32_cluster_walker`)，最后经 `uart_tx`(115200) 发**纯 ASCII 报告**（`KEY=HEX` 每行一项，末行 `DONE`）——★ 用 ASCII 是刻意的：连"文本模式把高位字节换成 `EF BF BD`"那个坑都绕过去了，串口助手直接可读、也可被采集脚本按字节比对。**卷基址只加一次**（`rd_addr_to_reader = bus_rd_addr + mbr_vol_base`；MBR 那一轮基址还是 0，所以同一加法器正好落到卡 0 号扇区，无需特例）。卡模型加 `VOL_BASE` 参数（默认 0 时**逐项等价**，老 TB 行为不变）以便模拟分区卡。新增 `tb_top_stage6_fat32_mount.sv`（**16 项断言**，含"FAT32 层 LBA 0 必须落到卡 LBA = 分区基址"这条关键断言）⇒ 回归 **514 → 530 项断言 / 17 → 18 个 TB，全 PASS**；`check_repo.ps1` → `LAYOUT PASS`；**多驱动静态扫描全仓 0 个文件有问题**。TD 工程已登记新顶层（`TOP_MODULE = top_stage6_fat32_mount`，含 `mbr_parser.v` 与 `top_stage6_fat32_mount.v` 两条设计文件）。**待办**：TD 重新综合（确认无 `HDL-8007` / 无 `AutoExcluded`）→ 下载 → 采 UART 报告并与电脑侧独立解析的基准对账。 |
| 2026-10-02 | **★★ TD 综合抓到第二个"仿真抓不到"的真问题：组合除法器导致时序违例，已修复。** 阶段 6-7 顶层综合后 **SWNS = -85.399 ns**（负 = 建立违例）、**28 / 4684 端点违例**、**Fmax 仅 9.488 MHz**（约束 50 MHz）。最长路径落在 `fat32_boot_parser.v:255` 的 `total_clus <= (...) / spc`：**Verilog 除法运算符被综合成组合除法阵列**（Logic Level **100**、ADDER **68**、105 ns）。**修复**：该分支已被 `spc_ok`（`(spc & (spc-1)) == 0`）保证 `spc` 是 **2 的幂**，故改为 `>> w_log2_spc`（`log2` 用一个 3 位优先编码器求）—— **对无符号数逐值等价**，所以接口、行为、断言一字未改，回归仍 **530 / 530 FAIL=0**。全仓扫查除法/取模：`uart_tx` 的是 `localparam`（编译期折叠）、`bmp_unpack` 的 `/4` 与 `frame_writer` 的 `% SAMPLE_STRIDE` 都是 2 的幂（变移位/掩码），**真凶只有这一处**。**教训两条**：① 可综合 RTL 禁用除法/取模（已写进项目规则 §5 第 10 条）；② **"某个顶层时序通过"推不出"它没实例化的模块也能综合"** —— 阶段 5 那次能过，纯粹因为那个顶层没接 FAT32 层。**证据**：`evidence/reports/sta_stage6_fat32_mount_20261002.txt`（节选 10.8 KB；原始 868456 B 未入库），索引条目 **TC-Q-STA-2**。**待办：重新综合，确认 SWNS 转正**（若仍有其它长路径，按同一节奏继续）。 |
| 2026-10-02 | **★★★ 阶段 6–7 板级验收通过（M-10）+ 时序转正 —— 一天里从"炸了"到"过了"。** ① **时序**：重新综合后 **SWNS = +6.042 ns**（原 -85.399）、**STNS = 0**（违例端点 0）、HWNS = +0.030 ns；R-Period **13.958 ns** ⇒ **Fmax 71.644 MHz**（约束 50 MHz，余量约 30%）；**关键路径 Max-Level 从 100 降到 12** —— 这就是"组合除法阵列被移除"的直接证据。证据 `evidence/reports/sta_stage6_fat32_mount_20261002_1959.txt`，索引条目 **TC-Q-STA-3**。② **上板（M-10，阶段 6–7 验收）**：位流 20:01 下载后板上 LED = 成功态 8；UART 报告 450 Byte 与电脑侧基准 `evidence/board/stage6_expected_report_pc_20261002.txt` **逐项对账通过** —— `MBR=00000001`、**`BASE=00002000`（★ 卷基址在实物上成立：FAT32 层的"卷 0 号扇区"确实落到卡的物理扇区 8192，这正是这一轮补的那个缺口）**、`SECS=00ECC000`、`BPS=0200`、`SPC=08`、`NFAT=02`、`FATLBA=000009DE`、`DATALBA=00008000`、`ROOTLBA=00008000`、`TOTSEC=00ECC000`、`TOTCLUS=001D8800`、`ENT=0005`、5 个目录项（`SV0001..SV0005.BMP`，name/attr/首簇/size **全对**，size 均 `000E1036`=921654）、末行 `DONE`。证据 `evidence/board/uart_report_stage6_20261002_200159_hex.txt`（HEX 导出 1350 B），索引条目 **M-10-PASS**。③ **对账中发现两处偏差，都记档**：(a) `ent_index` 是 **0-based** 目录槽号，**我的基准初版按 1-based 记、写错了**（实物 0009/0019/001A/001B/001C，比基准少 1），已按实物更正基准并写明 —— 这就是"电脑侧基准也要被实物检验"的意义；(b) 每行行尾是 **`72 0A`（字母 r + LF）而不是 `0D 0A`（CR+LF）**：**源码写的是 Verilog 字符串 `"...\r\n"`，源码没错**，但这**不是"仿真与综合不一致"，是转义写错了**：★ **Verilog-2001 的转义表里根本没有 `\r`**（只有 `\n` `\t` `\\` `\"` 和八进制 `\ddd`），所以 `"...\r\n"` 在 **TD 与 ModelSim 里都**编成 `72 0A`（字母 r + 换行）；老 TB 之所以通过，是因为 **TB 用同一个错误转义构造期望值、两边错得一样**（这条教训比坑本身更重要：**仿真全绿连"RTL 与 TB 对约定理解一致"都证明不了**）。已改为显式字节 `8'h0D, 8'h0A`，并记进项目规则 §7 工具坑与 §5 第 11 条。属纯外观瑕疵，不影响判定。④ 另有一个**待确认的 0x00 前缀**（可能是采集工具产物，也可能是发射端多打一拍），不影响正文；下次采集顺手确认。**下一步**：修那两个外观项（`\r` 转义、0x00 前缀）→ 或直接推进 M-6/M-7/M-8 / SDRAM 官方 Demo 回环。 |
| 2026-10-02 | **★ 修掉 M-10 的两个"外观项"，并加上 M-6/M-8 的连读阶段（回归 530 → 540）。** ① **`0x00` 前缀的根因确认**：`top_stage6` 的 `hdr_bits` 声明成 `[1471:0]`（184 Byte），但报告头六段实际只有 `21+42+25+51+34+10 = 183` Byte，Verilog 在 MSB 侧补零 ⇒ 整份报告多一个前导 `0x00`（板上 450 = 1 NUL + 183 + 260 + 6 与之完全吻合）。改为 `[1463:0]` / `HDR_BYTES=183`，并对 HDR/ENT/RPT/ERR/DONE 每段保留「逐字节相加 = 声明字节数」的核对注释。② **`\r` 转义**：RTL 全部 `"\r\n"` → 显式字节 `8'h0D, 8'h0A`。★ **实测更正了此前的判断**：用 vlog 10.7 亲测，**ModelSim 也不把字符串里的 `\r` 当转义**（`"DONE\r\n"` 得到 `44 4F 4E 45 72 0A`），旧 TB 用同一转义所以"两边错得一样"、仿真自洽通过；真机上才是 `72 0A`。改显式字节后仿真与硬件都发真 CR。③ **新增连读阶段（M-6 / M-8）**：新参数 `RPT_N`（默认 `16'd100`）；挂载 + 扫目录后，复用**同一个** `sd_sector_reader`（顶层第 5 个读请求方）对同一 LBA（根目录扇区）连读 `RPT_N` 次，**卷基址仍只加一次**，连读阶段 `data_ready` 恒 1 排空 512 Byte，每次的成败由 reader 自带 CRC16/超时判定。**失败也不提前退出**（跑满 `RPT_N` 次：报告长度固定、能区分"1 次坏"与"全坏"、拔卡时每读由 reader 出口兜底必然有界）。报告新增一行 `RPT=<total:4hex> OK=<ok:4hex> BAD=<bad:4hex>`，`BAD!=0` 时末行改发 `ERR=02`；LED 新增 `9 = 连读进行中`。④ `tb_top_stage6_fat32_mount.sv` 扩到 **26 项断言**（两个场景：健康卡 `RPT OK=100 BAD=0`、字节数 372、无前导 0x00、每行 CRLF；连读中拔卡 → 字节数 374、`RPT OK=0 BAD=100`、末行 `ERR=02`、LED=`2`、停 `ST_ERR` 不挂死）。⑤ **文档**：interface_spec 新增 **§3.8**（`top_stage6` 端口/参数/报告格式）升 v1.13；本清单补 **§2.4.1** M-6/M-7/M-8 上板步骤、**§2.6 第 15–17 条**排查、M-6/M-7/M-8 行改写。回归 **540 项断言 / 18 个 TB 全 PASS**，`check_repo.ps1` → `LAYOUT PASS`。**下一步**：按 §2.4.1 上板跑 M-6/M-7/M-8（需重新综合，报告从 450 变 476 Byte、末行前多一行 `RPT=`）。 |
| 2026-10-02 | **厂商 IP 落库 + 写阶段 9 第一步的 SDRAM 回环顶层（`top_sdram_loopback`）。** ① **IP 落库**：`ip/sdram/`（应用级 `sdram.v` + `global_def.v` + **三个安路加密 `sdr_*.enc.v`** + `sdram.ipc`）+ `ip/pll/`（`sys_pll` / `video_pll`）。加密件按用户决定**随仓库提交**，版权/来源/唯一一处前导行改动都写在该目录 `README.md` 里。② **纠一个复制错误**：例程里**有两个同名 `sdram` 模块** —— `IP/sdram.v` 是引脚级 PHY 外壳（端口 `ras_n/cas_n/dq…`，例程顶层**没用它**、`.al` 里也没登记），`SD/sdram.v` 才是被 `sdram U3(...)` 例化的**应用级控制器**；本仓库只保留后者。③ **新事实：EG4S20 的 SDRAM 是封装内硬核**（`EG_PHY_SDRAM_2M_32`，2M×32 = 8 MB），55 根信号不出引脚 ⇒ **`pin.adc` 不需要也不该有** SDRAM 引脚（厂商例程同样一条都没有，这不是遗漏）。④ **应用侧协议**照例程：写是逐 word `App_wr_en`；读是**延迟应答式**（`Sdr_rd_en` 才是取数时刻）；`Sdr_busy`/`Sdr_init_ref_vld` 在例程里**纯直通、从不参与判断** ⇒ 应用侧只需自负「突发留间隔 + 读写不重叠」。⑤ **新顶层** `platform/anlogic_eg4s20_hx4s20c/rtl/top_sdram_loopback.v`：50 MHz → `sys_pll`（C1=125M 给 SDRAM、C2=125M@180°）；**全部逻辑含 `uart_tx` 跑 125 MHz 单域，刻意不做 CDC**；写图案（`pat_of` 把地址摊到 32 bit）→ 落地等待 → 读回比对 → 发**定长 71 Byte 纯 ASCII 报告**（`SV-SDRAM-LOOP` / `INIT=/LOCK=` / `W=/R=/CAP=/BAD=` / `DONE`，显式 `8'h0D`/`8'h0A`）；两个等待态各挂独立超时（`ERR=01` 初始化超时 / `ERR=02` 读回不齐 / `ERR=03` 数据不一致）。⑥ **`timing.sdc` 加 `derive_clocks`** —— 接了 PLL 不加它，125 MHz 域就没有时钟定义、**STA 会是假通过**。⑦ **`.al` 已登记 7 条新文件并把 `TOP_MODULE` 切到 `top_sdram_loopback`**（回退只需改回 `top_stage5_sector_rd`）。★ **顺带发现一处需要你确认的不一致**：磁盘上的 `safevision.al` 现在只有**阶段 5** 的配置（`TOP_MODULE = top_stage5_sector_rd`，且 `mbr_parser.v` / `top_stage6_fat32_mount.v` **不在设计文件表里**），与"M-10 已用阶段 6 顶层上板验收通过"的记录对不上 —— 应是那次验收后把工程回退成了阶段 5；我这一轮是在这个阶段 5 配置上继续加的。⑧ **本顶层无 TB、进不了回归**（控制器是加密 IP，只能 TD 解密），上板步骤见新增的 **§2.4.2**。回归不变 **540 项 / 18 个 TB 全 PASS**；`check_repo.ps1` → `LAYOUT PASS`；新顶层过 `vlog` 编译检查。**下一步**：TD 重新综合（确认有 `sys_pll`/`sdram`、无 `HDL-8007`）→ 下载 → 采 71 Byte 报告对账 `W=R=CAP=1000 BAD=0000`。 |
| 2026-10-02 | **★ 查明"顶层回退到阶段 5"的真相 + M-6 复采确认（证据同哈希）。** 用户在 21:29:55 又采了一份报告（HEX 1428 B），解码 **476 Byte**，SHA-256 `31A4D727…4E8769` —— **与 20:52 的 `uart_report_m6_20261002_205218_hex.txt` 逐字节相同**，故不重复归档（只在 `evidence/board/INDEX.md` 记一段说明）。**这份复采的价值在于坐实了一件重要的事**：TD 在 **21:25:40–21:26:48** 跑了一次完整流程并生成位流，而 `project/safevision_Runs/syn_1/run.log` 写的是 **`elaborate -top top_stage6_fat32_mount`**、`syn_1/safevision.prj` 里 **`TOP_MODULE = top_stage6_fat32_mount` 且文件表中没有任何 `ip/` 文件**。⇒ ① **板子上跑的是阶段 6–7 设计，SDRAM 回环顶层至今没有被综合过**；② **根因是 TD 运行时用的是【内存里的工程状态】，不是磁盘上的 `.al`** —— 磁盘 `.al` 的 `TOP_MODULE` 当时已被改成 `top_sdram_loopback`，但那个正在运行的 TD 会话（进程 `td`，**19:34:49 启动**）是从更早的状态打开的，根本没读我改过的文件。③ **磁盘 `.al` 从来没保存过阶段 6 的登记**：`top_stage6_fat32_mount.v` / `mbr_parser.v` 是在 GUI 内存会话里加的、**没回写 `.al`**，所以 `.al` 一直是更早的**阶段 5 快照** —— 文档里以前写的"TD 工程已登记新顶层（`TOP_MODULE = top_stage6_fat32_mount`）"**描述的是 GUI 状态而不是工程文件**，属表述错误，已更正（见 `module_registry.md`）。④ **已把磁盘 `.al` 修成完整超集**：补回丢掉的 `mbr_parser.v` / `top_stage6_fat32_mount.v`，加上本轮的 `ip/sdram/` 5 个 + `ip/pll/sys_pll.v` + `rtl/top_sdram_loopback.v`，共 9 条，**每条路径都用 `Test-Path` 验证过存在**。⑤ ⚠ **重要操作提醒**：只要那个 TD 会话还在，**在 GUI 里"保存工程"就会用内存状态覆盖磁盘 `.al`、把本轮 9 条登记全部冲掉**。正确做法见 §2.4.2 步 1（在 GUI 里手动添加这 7 条文件 + 设 `TOP_MODULE`，再保存）或关闭 TD 后重开。⑥ **阶段判定**：阶段 **1–7 板级全部通过**（M-9 / M-10 / M-6 / M-8a），但因 ⑤ 的操作风险，**SDRAM 回环（阶段 9 第一步）尚未上板**。 |
| 2026-10-02 | **★ 阶段 9 首次综合：`.al` 采纳成功，但被 `pin.adc` 的 SD 引脚拦住 —— 已修。** ① **`.al` 生效**：`syn_1/run.log` 里出现 **`elaborate -top top_sdram_loopback`**（此前一直是 `top_stage6_fat32_mount`）⇒ 关闭 TD（选【否】）后重开这条路的办法有效，TD 采纳了修好的 `.al`。② **综合失败的唯一根因**：`pin.adc` 第 56–59 行给 `sd_dclk`/`sd_mosi`/`sd_miso`/`sd_ncs` 指定了引脚，但 `top_sdram_loopback` **没有这些端口**（SDRAM 是封装内硬核，不用 TF 卡）。**TD 对此是报错不是警告**：`USR-8168 ERROR: set_pin_assignment { sd_dclk } {...} in ../../../constraints/pin.adc(56) is not a valid ADC command`（GUI 侧另报 `HDL-1492 Failed to find pin sd_dclk in model top_sdram_loopback`），随后 `PRJ-5013 Run syn_1 failed`。③ **修法**：把 `pin.adc` 明确分成两段 —— **公共 6 条**（`clk`/`rst_n`/`uart_txd`/`led[3:0]`，三个 bring-up 顶层都有，恒定生效）+ **`[SD-ONLY]` 4 条**（只有阶段 5/6 顶层有，用 SDRAM 顶层时必须注释）。这是**厂商自己的惯例**（例程 `pin.adc` 里未用的信号就是 `#` 注释掉的）。★ 好消息：**`read_adc` 是每次 Run 都执行的命令**（日志里可见 `RUN-1002 : start command "read_adc ..."`），所以改完 `.adc` **直接重新综合即可，不用关 TD**。④ **其余告警全是无害的**，不要被吓到：`HDL-5007 concat with unsized literal`（6 条，在厂商 `.enc` 文件内部）、`HDL-5917 Input port ... not connected`（1 条，在 `sdr_as_ram.enc.v` 内部实例上）、以及 4 条 `*.vh will not be compiled since it is not included by any other file`（`top_sdram_loopback` 不 include 任何 `.vh`，自然如此）。⑤ 文档：`constraints/README.md` 新增「`[SD-ONLY]` 开关」整节；本清单 §2.4.2 加步 2 并重排步骤。 |
| 2026-10-02 | **★ 阶段 9 综合跑通、位流已生成；STA 的负余量查明是厂商硬核 PAD 路径，不是我们的逻辑。** ① `pin.adc` 修完后重跑：**`read_adc` 无错**、`elaborate -top top_sdram_loopback`、**place → route → bitgen 全过**，位流 `phy_1/safevision.bit`（629639 B，22:01:24）。② STA（**新证据条目 TC-Q-STA-4**）报 `SWNS -6.826 ns / STNS -297.306 ns / HWNS +0.046 / HTNS 0.000`，**但全局 64 个违例端点恰好 = `clkc[1]→clkc[2]`（-2.787/32）+ `clkc[2]→clkc[1]`（-6.826/32）两组之和** —— 这两组里**没有任何 fabric 寄存器**（**`clkc[2]` 扇出 = 1**，只接 `u_sdram.Clk_sft`），违例"路径"`Logic Level 0`、`cell 100% / net 0%`，起止点是硬核 PAD（`u_sdram/sdram.dq[*]` / `u_sdram/sdram_syn_*.bpad`）。**厂商自己的参考设计报同一个数：`lab_ex4_tf` 的 `final_timing.rpt` = `SWNS -6.565 / STNS -297.430`**。③ **我们能控制的路径组全绿**：`clkc[1]→clkc[1]`（自研 818 端点）**+0.130 ns / 0 违例**、Min Period 7.870 ⇒ **Fmax 127.065 MHz**；`clk→clkc[1]` +1.232、`clk→clk` +18.390；Hold +0.046 / 0 违例；`Period Check WNS 0.000`。④ **自己的遗留薄点**：最差 fabric 路径只有 **+0.130 ns**，出在 `top_sdram_loopback.v` 的 `rpt_vec[8*(RPT_LEN-1-rpt_sel) +: 8]`（568 bit 向量变址选取，`Logic Level 7` 含 `ADDER=2`、扇出 39、net 62%）—— 能过但薄，以后再动这个顶层要重看（可选优化：把报告按段拆成小 case，或改成倒计数索引以去掉减法器）。⑤ **判定口径已写进项目规则 §7 最后一条**：全局 SWNS 为负时，先看 Clock Summary 的**扇出与分组**，再看违例是否落进"我们自己的组"，最后拿厂商参考设计对表；**不急着加 `set_false_path` 刷绿**。⑥ 证据：`evidence/reports/sta_sdram_loopback_20261002_2201_excerpt.txt`（节选 11902 B），索引条目 **TC-Q-STA-4**。**下一步：下载上板**（预期报告头 `SV-SDRAM-LOOP`，`W=R=CAP=1000 BAD=0000`）。 |
| 2026-10-02 | **★★★ 阶段 9 第一步通过（M-11）—— 厂商 SDRAM 硬核在本工程里跑通了。** 位流 22:01:24 下载后 UART 收到 **71 Byte**（HEX 导出），解码后与设计值**一字不差**：`SV-SDRAM-LOOP` + CRLF / `INIT=01 LOCK=01` + CRLF / **`W=1000 R=1000 CAP=1000 BAD=0000`** + CRLF / `DONE` + CRLF；**真 CRLF**、**无前导 `0x00`**。逐项含义：`INIT=01` ⇒ `Sdr_init_done` 在 16 ms 超时窗内到齐；**`LOCK=01` ⇒ `sys_pll` 锁定成功 —— ★ 这顺带证伪了我上一轮提的那个担心**（顶层把 `sys_pll` 的 C0 留空会不会破坏 `FEEDBK_PATH=CLKC0_EXT` 的反馈支路；实测没问题，例程的音频 PLL 也是这么留空的）；`W=R=CAP=1000` ⇒ 写了 4096 word、发了 4096 次读命令、**收齐 4096 word**（说明控制器一条读命令都没丢）；**`BAD=0000` ⇒ 32 bit 数据逐字比对零错**。⇒ 加密 SDRAM 控制器能初始化、能写、能按序读回；**32 位数据线与 16 KB 连续区间的地址译码全部正确**（图案 `pat_of` 把地址摊到 4 个字节，所以这 4096 个值覆盖了全部 32 根数据线）。★ **本轮一并解决的四件事**：① `.al` 的"磁盘快照 ≠ TD 内存状态"（关 TD 选【否】再重开才生效，判定只信 `run.log` 的 `elaborate -top`）；② `pin.adc` 的 `[SD-ONLY]` 开关（TD 对顶层不存在的端口**报错**；`read_adc` 每次 Run 都执行，改完直接重综合）；③ STA 全局 SWNS 为负的**判定口径**（100% 出在硬核 PAD 路径，自研组全绿，厂商参考设计同数）；④ 顺带发现自己的薄点（fabric 最差路径仅 +0.130 ns，出在 `rpt_vec` 变址选取）。**证据**：`evidence/board/uart_report_sdram_loopback_20261002_221625_hex.txt`，条目 **M-11-PASS**。**下一步候选**：`ADDR_SHIFT=11 + TEST_WORDS=1024` 做全片稀疏扫描（覆盖行/体译码）/ M-7 多卡 / M-8 连读中途拔卡 / 把 SDRAM 接进帧缓存链（阶段 10–16，须等 A 的整机）。 |
| 2026-10-03 | **★ 系统 PLL 去重：A 的 `sv_system_pll` 收编 B 的 `sys_pll`，删除 `sys_pll.*`。** 两套 PLL 频率相同（100/125 MHz），只差电气参数（A: Medium/13/4；B: High/29/2）与 B 独有的 C2 = 125 MHz@180°。做法：**在 A 的 `sv_system_pll` 上加 C2@180°**（`CLKC2_DIV 8` / `CPHASE 3` / `FPHASE 0`；`.ipc` 加 id=2），**C0/C1 电气参数取 A 的不动**；`top_sdram_loopback` 实例化改 `sv_system_pll`；`safevision.al` 登记 `../ip/pll/sv_system_pll.v`；删除 `ip/pll/sys_pll.v` / `.ipc`。`check_pll_profiles.py` 放宽为「按 `CLKC2_DIV` 是否有来定输出集合 + 系统 PLL 的 C2 允许 180°」（0° 判据与原文逐字等价）⇒ 实跑 `PASS`。回归 **540 项 / 18 个 TB 全 PASS**、`LAYOUT PASS`。★ **已重新综合 + 复测（2026-10-03 17:26:55）通过**：报文与 M-11 **逐字节相同**（71 Byte、`INIT=01 LOCK=01 / W=1000 R=1000 CAP=1000 BAD=0000 / DONE`），证据条目 **M-11-PASS-2** ⇒ 去重未改变 SDRAM 回环行为。 |
