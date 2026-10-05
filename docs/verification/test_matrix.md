# 测试矩阵

## ★★ 验证入口总清单（"跑哪些脚本才算过"）—— 2026-10-05 新增

> **为什么要有这一节**：工程已经长到 **12 个 `run_*.ps1` 入口**、跨 **两套工具链**
> （ModelSim 与 XSim/Vivado）外加两套 TD STA 流程。没有总清单时，**"我这部分绿了"很容易
> 只是"我这台机器刚好能跑的那一半绿了"** —— 而 **`run_sim.ps1`（B 主回归）完全不含 A 的 9 个
> `tb_a_*`**，这一点最容易被误读。

**总入口：`safevision/tools/run_all.ps1`（新增）**
- 依次跑**本机能跑的**入口，跑不了的**明确报 `SKIP`（并说明缺什么），绝不报 PASS**
- **只有 `RESULT: ALL PASS` 才 exit 0**；有 SKIP 时输出 `INCOMPLETE` 并列出被跳过的项
- 本地干活可用 `-AllowSkip`（`FAIL=0` 即 exit 0，但结果行仍写 `INCOMPLETE`）
- **发布/交接前必须用严格模式（不带 `-AllowSkip`）跑，只有 `ALL PASS` 才算过**

| # | 入口 | 工具链 | 覆盖什么 | 通过判据 |
|---|---|---|---|---|
| 1 | `run_sim.ps1` | **ModelSim** | **B 链主回归**：23 个 TB / **604 项断言** | 末行 `TOTAL PASS=n FAIL=0`；`FAIL≠0` 时 exit 1 |
| 2 | `run_clock_sim.ps1` | **ModelSim** | 时钟/复位检查（`tb_clock_reset_ctrl`，88 项） | 日志含 `clock/reset checks: N pass, 0 fail` 且 exit 0 |
| 3 | `run_b_xsim_compat.ps1` | **XSim** | 复用 B 的源/TB 列表在 XSim 上跑 18 个 B TB（**A 阶段1–10 源码同库编译**） | 见脚本内判据 |
| 4 | `run_memory_protocol_sim.ps1` | **XSim** | 7 个专用 TB（仲裁协议/背压/读延迟、swap 默认超时/vblank-ack、`video_read_dma` burst64/集成）+ **负对照**（`-SkipNegativeControls` 可跳） | 见脚本内判据 |
| 5 | `run_sdram_loopback_sim.ps1` | **XSim 优先 / ModelSim 兜底** | `tb_sdram_loopback`（**A 的**独立应用层模型：21-bit 签名反解、地址混叠、初始化/读返回超时） | 见脚本内判据 |
| 6 | `run_a_stage1_9_sim.ps1` | **XSim** | A 阶段 1–9：5 个 TB | 见脚本内判据 |
| 7 | `run_a_stage11_15_sim.ps1` | **XSim** | A 阶段 11–15：**9 个 TB**，含**全工程唯一的 A↔B 端到端 TB** `tb_a_video_display_core`（A 真实 core + B 真实 `memory_arbiter`/`frame_swap_ctrl`，BASE+HD） | 日志含 `PASS <tb>:` 且无 `Fatal:`/`ERROR:` |
| 8 | `run_video_pipeline_sim.ps1` | **XSim** | A 视频流水线：2 个 TB | 见脚本内判据 |
| 9 | `run_video_clock_sim.ps1` | **XSim + TD + Python** | 时钟/视频子系统：5 个 TB | 见脚本内判据 |
| 10 | `run_pll_feedback_equivalence.ps1` | **XSim + TD + git** | PLL 反馈接线修复**前后**的功能等价性（跨提交对照） | 见脚本内判据 |
| 11 | `run_a_display_sta.ps1` | **TD（STA）** | A 显示核心**内部探针**的布线后 STA（`base` + `hd`） | `PASS A display internal routed STA <mode>: setup=… hold=…`；`SWNS/HWNS < 0` 即抛错 |
| 12 | **`run_all.ps1`** | 聚合 | 依次跑上面能跑的 | `RESULT: ALL PASS` 才 exit 0 |

### ★ 本机实际能跑哪些（2026-10-05 用 `run_all.ps1 -AllowSkip` **实测**）

**工具链实测**：**ModelSim 有**（`D:\modeltech64_10.7\win64`）、**TD 有**
（`D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`）、**Vivado/XSim 没有**
（脚本里 `-XSimBin` 的默认值 `D:\Xilinx\...` 是 **A 的机器**上的路径）。

**实测结果：`PASS=4  FAIL=0  SKIP=7`**

| 结果 | 入口 | 说明 |
|---|---|---|
| ✅ PASS | #1 `run_sim.ps1` | `TOTAL PASS=618 FAIL=0` |
| ✅ PASS | #2 `run_clock_sim.ps1` | 88 项全过 |
| ✅ PASS | #5 `run_sdram_loopback_sim.ps1` | 走 **ModelSim 兜底**（这个入口不一定要 XSim） |
| ✅ PASS | #11 `run_a_display_sta.ps1` | ★ **本机装了 TD ⇒ A 的显示核心内部 STA 在本机也能跑** |
| ⛔ SKIP | #3 #4 #6 #7 #8 #9 #10 | **都需要 Vivado/XSim；B 这台机器没装** |

⇒ **"B 侧绿了"仍不等于整机绿了**：含**全工程唯一 A↔B 端到端 TB** 的 #7、以及 #3 #4 #6 #8 #9 #10
**共 7 项必须拿到有 Vivado/XSim 的机器上跑（也就是 A 那台）**。

**★★ 两台机器的路径不要混（2026-10-05 订正）**：

| 路径 | 属于谁的机器 | 用途 |
|---|---|---|
| `D:\Xilinx\Vivado\2018.3\bin` | **A 的机器** | 所有 `run_*_xsim*` / `run_a_*` 脚本的 `-XSimBin` **默认值** |
| `D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116` | **B 的机器（本项目主开发机）** | TD（综合/布局布线/STA）、`run_a_display_sta.ps1` |
| `D:\modeltech64_10.7\win64` | **B 的机器** | ModelSim（`run_sim.ps1` 等） |

★ 我先前把 `D:\Xilinx` 说成"本机路径"并据此断言"本机只有 ModelSim"——**错了**：
那只是**脚本里的默认值（A 的机器）**，而 B 这台机器**装了 TD**（在 `D:\Anlogic`），
所以 #11 在本机实测 PASS。**引用路径时务必注明"谁的机器"。**

### ★ 三条最容易误读的地方

1. **`run_sim.ps1` 不含 A 的 9 个 `tb_a_*`** ⇒ 它 `TOTAL PASS=604 FAIL=0` **不代表 A 的模块通过**。
2. **全工程唯一的 A↔B 端到端 TB 是 A 的 `tb_a_video_display_core.sv`**（在 #7 里），
   它要 XSim ⇒ **本机跑不了**。B 侧另有一条 `tb_ab_storage_contract.sv`（16 项，在 #1 里）
   做**契约守门**，两者互补、不可互相替代。
3. **A 的 `run_a_display_sta.ps1` 测的是"A 显示核心内部探针"的 STA**，
   **不是** `top_sdram_loopback` 的整板 STA；后者的数字见本页下面的报告引用与
   `project/report*.txt`。

---

### ★ A↔B 端到端集成（显示级）当前状态 —— 2026-10-05 更新

| 层次 | 覆盖它的东西 | 状态 |
|---|---|---|
| **B 侧半段**：真 BMP → 帧缓存内容（阶段 8+10+11+13） | **`tb_b_frame_memory.sv`（本页新增，14 项）** | ✅ **本机 ModelSim 已跑通，逐字 0 错**；**已进 `run_sim.ps1`** |
| **A 侧半段**：帧缓存 → 屏幕像素（A 阶段 11–15 + B 的仲裁/换帧） | A 的 `tb_a_video_display_core.sv`（用**合成数据**） | ✅ 在 **A 的 XSim** 上跑 |
| **A+B 显示级全链路**：真 BMP → 屏幕像素 | `tb_ab_frame_display.sv`（**本机 ModelSim**） | ✅✅ **已全绿：`errors=0  pix_ok=307200  pix_bad=0`** —— **整整一帧 307200 个像素逐点全对**，换帧握手正常（`swap_err=0`）。入口 `run_ab_display_sim.ps1`（独立脚本，已登记进 `run_all.ps1`） |

**★ 让 A 的显示核心能在 ModelSim 上跑：只改了一个文件的端口连接（2026-10-05）**
`a_pixel_fifo_ip.v` 里 `ram_inst`（ERAM）只写了 14/16 个端口，**`doa`（A 口读数据）与
`dib`（B 口写数据）在 SDP 模式下本来就不用**，所以 XSim 容忍；但 **ModelSim 的 vopt 会报
"Too few port connections ... Expected 16, found 14" 并在代码生成阶段内部崩溃**。
⇒ **把这两人端口显式写出来**（`doa` 留空、`dib` 接 0）即可，**零功能改动** ✓。
改完实测：`[PROBE-A] elaborated and ran OK` ✓，`tb_ab_frame_display` 也能 elaborate 并跑出
**`ok=9950458 bad=0`**（A 的显示核心与 B 的帧缓存内容逐点一致）✓✓。
★ 该改动在 A 的文件里，**请 A 确认无异议**（综合与仿真行为不变）。

**★★ 本轮踩到并记档的 Questa 10.7 / TB 写法陷阱**（都会让调试白花几十分钟）：
1. **`func(...)[7:0]`（对函数返回值直接位选）会让 vopt 内部崩溃**
   —— `Questa ... unexpected internal error: vgenexpr.c(3346)`，报在**文件最后一行**（`endmodule`），
   极难定位。⇒ **必须先把函数返回值存进临时变量，再选位**。（`tb_b_frame_memory` 实测）
2. **在 `always` 块里用了"声明在它后面"的 `wire` ⇒ Verilog 按隐式 1 bit 网线建，永不驱动**
   —— 表现是**整条链在第 N 个字节卡死、无报错**。（本 TB 实测：`.ready(bp_ready)` 接错名字）
3. **`wait (<单拍信号>)` 会永久挂住**：单拍信号若在 `wait` 之前就闪过，`wait` 等不到。
   ⇒ **等电平信号**（`pix_active_valid` / `fw_slot_valid` / `fw_px_cnt`），不要等 `active_commit` /
   `wr_done` 这类单拍脉冲。（本 TB 实测）
4. **不要给期望值额外加延迟**：A 的 core 输出端的 `x`/`y` **本身已经是延迟后的扫描坐标**
   （`rgb` 与 `x`/`y`/`de` 在输出端同拍）。再给期望值加 5 拍 = 拿 `x-5` 的期望去比 `x` 的像素，
   表现是"每个像素都错、且错得像横向平移 5 个像素"。（本 TB 实测）

---

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
| `tb_ab_storage_contract.sv`（**16 项**，2026-10-05 新增） | **A↔B 存储侧接口的契约守门**（依据 `docs/B链-整机集成-存储侧接线表.md`）：`rd_len` 恒为契约值 64 / `rd_ack` 单拍 / 每突发 `rd_data_valid` 计数 == `rd_len` / `data_valid` 只在 `busy` 期间 / 突发内 `mem_addr` 每次 **+4**（**字节**地址）/ 突发数不多不少；**★ CDC 往返"恰好一次"**（5 次换帧 ⇒ A 侧恰好 5 次 req、恰好 5 次 ack、B 侧恰好 5 次提交、`swap_req` 恰好 5 次翻转；两个 evt 单拍）；**★ 无效 CRC 不提交不 ACK**（`wr_crc_ok=0` 时 `swap_req` 不翻转、无 `active_commit`、不报超时）。★ 补的是现有 TB 的真空：`tb_frame_swap_ctrl` 里 `wr_crc` **恒为 1**，CRC 分支从没跑过 | ModelSim（本机可跑）；A 的端到端 TB 跑在 **XSim**，本机没装 Vivado ⇒ 两者互补 |
| `tb_framebuffer_loopback_core.sv` | **阶段 10 帧缓存回环核心**（`framebuffer_loopback_core` + `mem_read_burst`，内部例化既有 `frame_writer`/`video_read_dma`/`mem_ctrl`/`sync_fifo`）：整帧 640×480 写入 → 整帧读回 → **逐像素比对零错**（LFSR 图案覆盖全 16 位）/ 抽样 CRC / `slot_valid` / 定长 208 Byte 报告逐字节（含 **地址斜坡探针 A 匹配位图 `AM/AF/AV` + 探针 C/B 抽样回读**，2026-10-03 起）/ **探针写值 = 字地址** / **探针段内写地址严格连续** | SDRAM 行为模型（`frame_memory_model`）仿真 |
| `tb_sdram_app_adapter.sv` | **板级突发桥适配器**（`sdram_app_adapter`，逐字事务口 ↔ 厂商 `sdram` 的 App_* 口）。★ TB 内含**厂商 app 口模型**（按 M-11 已验形态：en 连发时**每拍采样地址**、每拍一条读命令、延迟 `RD_LAT` 拍按 **1:1** 返回）：写 32 个连续字（值=地址）→ 读 32 个连续字（**跨两次预取**）逐字相等 / **写突发与读突发期间地址必须每拍 +1**（D2/D4，**旧版适配器过不了这两条**）/ 非 16 对齐基址（0x1035）写 4 读 4 / **缓冲未排空时跳到缓冲外地址（D7，正是板上暴露的那个场景）** / 等 ready 与 rdata_valid 零超时 | 厂商 App 口行为模型（TB 内建） |
| `tb_sdr_pat_gen.sv` | **SDRAM 测试图案生成器**（`sdr_pat_gen`，纯组合）：稀疏扫描（步长 2049）1024 个图案**两两不同**（单射）/ 连续扫描 1024 个两两不同 / 稀疏扫描时 **4 个字节各自都取到 ≥2 个值** / **21 位地址每一位单独翻转都改图案（无死位）** / mode 0 五个已知值 / 地址 0 图案非 0（mode 0/1/2）/ ★ **反向对照：把旧公式也算一遍，确认它在稀疏扫描下只有 2 种图案**（证明判据抓得到那个 bug）/ **mode 1（LFSR）也是单射** / **mode 2/3/4/5 八个已知值**（walking-1 / walking-0 / 全0全1 / 相邻位交替）。★ 为什么必须有：写侧读侧用同一个生成器，**"图案没区分度"在板上会表现为 `BAD=0000` 通过**，只有本 TB 能抓（2026-10-04 它还抓出"xorshift 的 0 是不动点 ⇒ 某地址会输出全 0"这个真缺陷） | 纯组合，无需行为模型 |
| `tb_top_sdram_loopback.sv` | **板级 SDRAM 回环顶层（带桩仿真）** —— 用 `vendor_ip_stub` 顶掉两个编译不了的单元后，该顶层**第一次进回归**：自建 125 MHz 采样 UART 8N1 接收模型。**阶段 1**（`ROUNDS=3` 三轮全过）：报告**恰好 190 Byte** / **逐字节一致**（含 `RND=00000003/00000003 PAT=2` ⇒ **soak 轮次与图案模式轮换真的生效**）/ `led=8`；**阶段 2**（在 `0x2805` 注入 1 bit 错）：**只跑 1 轮就出报告**（fail-fast）/ `BAD=0001` / **`BAD0=00000001:002805 E=88002805 A=88002804`**（轮次:地址 精确定位）/ `led=3`。★ 只验我们自己的逻辑（状态机/soak/报告/地址/图案），不验 SDRAM 协议 | 厂商 IP 仿真桩（`vendor_ip_stub`，理想存储器 + 故障注入钩子） |
| `tb_b_frame_memory.sv`（**14 项**，2026-10-05 新增） | ★ **B 链帧缓存内容集成测试**（阶段 8 + 10 + 11 + 13 串起来）：TB 生成真 BMP 字节流（54 B 头 + 640×480×24bit，**自底向上**）→ `bmp_parser` → `bmp_unpack`（BGR→RGB565 + 翻转）→ `frame_writer`（2 像素/word 打包 + CRC）→ `memory_arbiter` 写通道 → 真存真取存储模型 → **`memory_arbiter` 读通道**（A 的显示核心就是从这个口读的）→ TB 按 A 的读契约读回，**逐字与期望像素对比对**。断言：BMP 头 640×480 校验 / 整帧 307200 像素写完 / CRC 通过 / `slot_valid` 置位 / **★ 153600 个 word 逐字 0 错（`wok=153600 wbad=0`）** / 读突发 2400 次 ack / `rd_ack` 单拍 / `rd_data_valid` 只在 `rd_busy` 期间。★ 补的是真空：`bmp_unpack` 的 TB 只看像素流、`frame_writer` 的 TB 用**合成图案**，**没人验过"真 BMP → 帧缓存内容"** | ModelSim（本机可跑）。**注意**：本 TB 把 `bmp_parser`/`bmp_unpack` 与 `frame_writer` 都放在 mem_clk；**若产品里这两级跨域需补 CDC FIFO（待与 A 确认）** |
| `tb_top_stage5_sector_rd.sv` | 板级 bring-up 顶层：完整命令序列、CMD17 参数、512 Byte 经 UART 逐字节、顶层进成功态 | SD 行为模型 + UART 接收模型仿真 |
| `tb_top_stage6_fat32_mount.sv` | **阶段 6–7 板级顶层**：卷基址只加一次（FAT32 层 LBA 0 → 卡 LBA = 分区基址，直接断言卡模型收到的 `o_arg`）/ MBR 分区表 / BPB 几何 / 目录项 / UART **ASCII 报告**内容（**字节数 372/374、无前导 `0x00`、每行 CRLF**）/ **连读汇总 `RPT=`**（健康卡 `OK=total BAD=0`；连读中拔卡 → 有限时间内进 `ST_ERR`、末行 `ERR=02`、LED=错误主码低 4 位）/ 顶层进成功态 | SD 行为模型（`VOL_BASE` 参数模拟分区卡）+ 文本 UART 接收模型 |

现有 B 回归为 **618 项断言 / 24 个 Testbench / 2 个行为模型 + 1 个厂商 IP 仿真桩**，`run_sim.ps1` 输出 `TOTAL PASS=618 FAIL=0`。`run_sim.ps1` 的 ModelSim 目录来自 `-ModelSimBin` 参数或 `MSIM_BIN` 环境变量（与 `run_clock_sim.ps1` 同口径，脚本里不再写死本机路径）；换机器时设好这两者之一即可重跑，并把日志放 `evidence/sim/`。

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

B `run_sim.ps1` 全回归基线为 **604 PASS / 0 FAIL**（2026-10-05 加入 `tb_ab_storage_contract` 16 项后）。2026-10-04 最新 selector RTL 的独立索引映射检查为 190/190 PASS，但专用仿真再次尝试时未能启动：本机没有目标 XSim 2018.3，`MSIM_BIN` 未配置，故本轮无 HDL compile/TB 结果。同期已完成 TD reroute 与独立 postroute STA：C1→C1 setup `+0.113 ns`、0/2517 setup 违例，整板 setup 仍 `−6.826 ns`；未生成位流、未上板。历史 B soak 与 A `d6f40a6` STA 不属于同一 build，不能代替当前集成版本验收。详见 [SDRAM/PLL 核查](../docs/B链-SDRAM接口与PLL时序核查.md)。

> ✔ **口径已核对（2026-10-05）**：本行的"自研 `C1→C1` setup **+0.113 ns**、0/2517 违例"**是对的**。
> 我先前怀疑它与 `README.md` 的 `−0.094 ns` 矛盾 —— **那是我读错了**：`−0.094 → +0.113` 是
> "两级报告选择器"那次修复的 **before→after**，`−0.094` 是**修复前**的值（`README.md` 与待办清单
> §四 的同一条记录都这么写，本来是一致的）。**真正写错的只有 `README.md` 里另一处**
> （把修复前的旧值当成了当前值），**已订正**。
>
> **★ 权威来源**：`project/report22.txt`（2026-10-04 20:53，顶层 `top_sdram_loopback`）：
> `clkc[1]→clkc[1]` **+0.113 / 0 违例 / 2517 端点**；`clk→clkc[1]` +1.360 / 0 / 26；
> `clk→clk` +18.694 / 0 / 1；`clkc[1]→clkc[2]` **−2.859 / 32 / 48**；
> `clkc[2]→clkc[1]` **−6.826 / 32 / 32**（**全局 −6.826 就是这一组**）。
> ⚠ 注意 `safevision_Runs/phy_1/final_timing.rpt` **当前不在磁盘上**（TD 运行目录被清理过），
> 引用时请用 `project/report*.txt` 系列，或重跑 TD 后再引用运行目录。
