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
| 板级 TD 工程 `platform/anlogic_eg4s20_hx4s20c/project/safevision.al` | **全流程已跑通**（器件 EG4S20BG256；35 条设计文件全为相对路径；`TOP_MODULE = top_stage5_sector_rd`；`constraint_1` 已挂 `pin.adc` + `timing.sdc`）。**综合 → 布局 → 布线 → 位流一次通过**：Setup WNS **+11.297 ns**、Hold WNS **+0.046 ns**、**违反端点 0**（906 端点 / 3480 路径），50 MHz 约束下报告 Fmax **114.9 MHz**；资源 IO 11/188、LUT 814/19600、REG 434/19600、BRAM/DSP 0。位流 `safevision.bit` 已生成。原始报告留证在 [evidence/reports/INDEX.md](../evidence/reports/INDEX.md)（TC-Q-STA） |
| 板级顶层 `platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v`（阶段 5 最小验证） | **已写、仿真通过、且上板跑通**（`tb_top_stage5_sector_rd` 5 项断言；板上 LED = `8` 成功，M-9 通过） |
| 引脚约束 `pin.adc` / 时序约束 `timing.sdc` | **已写并核对**（引脚来源：开发板手册的串口/LED/按键引脚表 + `2_FPGA.pdf` / `6_EX_DEVICE.pdf` + 厂商同器件例程，三处一致；`timing.sdc` 为单一 50 MHz 时钟域第一版）。`uart_txd = D12` **已确认为 FPGA 发送脚**（板载 CH340G，无需外接 USB-TTL） |
| 整机集成（`safevision_core` / `safevision_top`） | 未开始（A 负责） |
| **上板实测** | **已开始**：阶段 5 的 **M-9 通过**（512/512 逐字节一致）；M-5/M-6/M-7/M-8 与阶段 6–16 的板级项待做 |

仿真回归：`safevision\tools\run_sim.ps1`，**514 项断言全部 PASS**（17 个 testbench）：

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
| **合计** | | **514** |

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
| M-6 | **连读 100 次** | 同一 LBA 连续读 100 次，UART 每次都回传，电脑脚本比对 | 手册 7.5 过关标准 |
| M-7 | **多卡兼容** | 至少 3 张不同品牌/容量的卡都跑通 | 兼容性留证 |
| M-8 | 拔卡 / 坏卡行为 | 运行中拔卡，确认有限时间内进错误态且不挂死；插回后能恢复 | 手册 7.4 过关标准 |
| M-9 | 单扇区读 + 电脑侧比对 | ★★ **通过（2026-10-02）**：工具改用 **HEX 文本导出**（无 `EF BF BD`），解码后 512 字节与 `evidence/board/lba8192_pc_20261002.bin` **SHA-256 完全相同**（`e470416567d512c0…`），非零字节 372 个也一致。证据见 `evidence/board/INDEX.md` 条目 **M-9-PASS** | 阶段 5 验收 ✅ |

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