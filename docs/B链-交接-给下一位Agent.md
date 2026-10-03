# B 链 · 交接说明（给下一位 Agent）

> 目的：让接手的人**不必重问一遍"这是干嘛的、做到哪了、下一步干什么、坑在哪"**。
> 本文件是**交接索引**：一页说清全局，细节都在引用的仓库文档里。
> 工作区规则见 [`.trae/rules/项目规则.md`](../../.trae/rules/项目规则.md)
> （Trae 里会自动注入；**若你的运行环境没有注入，请务必先手动读一遍**，它含结构基准与硬约定）。
> 最近更新：2026-10-03 晚（阶段 10 板级验收通过那一版）。

---

## 0. 一句话现状

- **手册阶段 1–10 的板级验收全部通过**：M-9（单扇区读 512/512 逐字节）、M-10（卷基址 / BPB / 根目录）、
  M-6（连读 100 次）、M-8a（无卡有界退出）、M-11（SDRAM 官方 Demo 回环 `BAD=0000`）、
  **阶段 10 帧缓存回环（2026-10-03：整帧 307200 像素 `BAD=000000` 逐像素零错 + 三个探针全对）**。
- **仿真回归全绿**：`run_sim.ps1` → `TOTAL PASS=558 FAIL=0`（20 个 testbench / 2 个行为模型）；
  `check_repo.ps1` → `LAYOUT PASS`。
- **唯一遗留是阶段 10 板级顶层的时序**：自研组 `clkc[1]→clkc[1]` **−0.992 ns / 31 个违例端点**
  （已从 475 收到 31，还差约 1 ns）。**功能不需要再烧板**，只剩 TD 复算与最后一段压时序。
  → 为什么没压完、还有哪三根杠杆，见 §5。
- **工作树未提交**（9 改 + 7 新，清单见 §4）。**接手第一件事建议就是提交它**（见 §4 的提交建议）。

---

## 1. 半小时上手（按这个顺序读）

1. [`.trae/rules/项目规则.md`](../../.trae/rules/项目规则.md) —— **规则**（不是文档）：开发基准＝手册、
   结构基准＝`docs/PROJECT_STRUCTURE.md`、硬约定（收数据 `valid&&ready` 双判 / FAT 侧小端 / SD 命令参大端 /
   每态独立超时 / 冻结地址表只在 `rtl/include/pixel_format_defs.vh` / 公共算法只在 `rtl/common/` /
   **一个 `reg` 一个驱动源** / **可综合 RTL 禁 `/` `%`** / **别写 `\r` 转义**）、已知工具坑。**§8 = 进度锚点**。
2. [`docs/B链-待办与硬件验证清单.md`](B链-待办与硬件验证清单.md) —— **运维手册 + 变更日志**：
   §零 状态总览、§2.x 各阶段上板步骤与判据、§2.6 排查顺序、§三 已知未完成项、**§四 逐次变更记录
   （每次改完代码都要在这里加一行）**。
3. [`docs/interface_spec.md`](interface_spec.md) —— **接口契约**（信号 / 有效电平 / 时钟域 / 延迟 /
   地址表 / 错误码 / 命名迁移表 / §九 变更历史）。改接口必改它。
4. [`docs/architecture/module_registry.md`](architecture/module_registry.md) —— 模块登记表（状态 / 负责人 /
   接口 / 测试），新增模块**先登记再写代码**。
5. [`docs/PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md) —— 目录落点规则（**板级相关一切归
   `safevision/platform/anlogic_eg4s20_hx4s20c/`**；只有不带引脚的可移植 core 才放 `safevision/rtl/`）。

跑一遍验证（换机器要设 `MSIM_BIN`）：

```powershell
$env:MSIM_BIN = "<ModelSim 的 win64 目录>"     # 本项目实测：D:\modeltech64_10.7\win64
powershell -ExecutionPolicy Bypass -File safevision\tools\run_sim.ps1     # 期望 TOTAL PASS=558 FAIL=0
powershell -ExecutionPolicy Bypass -File safevision\tools\check_repo.ps1  # 期望 LAYOUT PASS
```

---

## 2. 工程全景

**这是什么**：全国大学生嵌入式芯片与系统设计竞赛 2026 · FPGA 赛道 · 赛题一（SafeVision）。
本工作区是**三人分工里的 B 链**：**TF 卡 → SPI/SD → FAT32 → 媒体解析 → SDRAM 帧缓存 → 仲裁/DMA**。
A 负责视频/HDMI/产品顶层，C 负责 UART 命令与日志等；**B 链的边界**看 `interface_spec.md` §四。

**目录落点（记住这四条就够）**：

| 位置 | 放什么 |
|---|---|
| `safevision/rtl/{include,common,storage,media,memory,top,...}` | **不带引脚**的可移植 RTL；`.v` = Verilog-2001 子集 |
| `safevision/platform/anlogic_eg4s20_hx4s20c/` | **板级一切**：`rtl/`（含引脚的顶层与适配器）、`constraints/`（`pin.adc` / `timing.sdc`）、`ip/`（含加密 IP）、`project/`（TD 工程 `safevision.al`） |
| `safevision/verification/{unit,models,board,...}` | TB（`.sv`）、行为模型、上板采集脚本 |
| `docs/` `evidence/` | 文档三件套与管理文档；**要留证的原始数据**（仿真日志 / 报告 / 采集件） |

**`.v` vs `.sv` 的分工是项目自定约定**（不是随手选的）：`rtl/**` 一律 `.v` + **TD 已验证支持的
Verilog-2001 子集**（要过安路 TD 综合）；`verification/**` 用 `.sv`（不综合，只跑 ModelSim）。别把
`.sv` 放进 `rtl/`。

---

## 3. 交付物与验收状态一览

| 阶段 | 内容 | 仿真 | 板级 |
|---|---|---|---|
| 1–5 | SPI 地基 / SPI 主机 / SD 初始化 / 每态超时 / CMD17 单扇区读 + CRC16 | ✅ | ✅ **M-9**（512/512 逐字节） |
| 6–7 | FAT32 挂载（BPB）/ 根目录扫描 / 簇链跟随 / 字节流 / BMP 头 / 索引表 | ✅ | ✅ **M-10**（含卷基址 `BASE=00002000`）+ **M-6** + **M-8a** |
| 8–9 | FIFO 水位 / 切分缓冲 / 健康度统计 / SDRAM wrapper + 行为模型 | ✅ | ✅ **M-11**（官方 Demo 回环 `BAD=0000`） |
| 10 | **帧缓存回环**：`frame_writer` + `mem_read_burst` + 地址斜坡探针 | ✅（11 项） | ✅ **2026-10-03 验收通过**（`BAD=000000`） |
| 11–16 | 突发策略 / 带宽与水位计数 / 仲裁 / 双缓冲与槽所有权 / 帧交换 / 错误上报 | ✅ | ⏳ 板级多须等 A 的整机（或自建 bring-up 顶层）；阶段 16 的五类故障注入也待整机 |
| 媒体层 | `bmp_parser` / `bmp_unpack` / `wav_parser` / `file_index` | ✅ | — |

其余已落地但**未做**的：`pcm_ring` / `audio_cdc_fifo`（音频链最后两块）、CMD18 多扇区读、
与 A 的帧交换联仿、整机集成（`safevision_core.v` / `safevision_top.v` 由 A 负责）。
**完整清单见待办清单 §三（"已知的未完成项，别当成 bug"）** —— 那里逐条写了"为什么现在不做、什么时候做"。

---

## 4. 当前工作树（未提交）与建议的第一次提交

`git log` 最新提交是 `5e210aa Stage 9: dedup the system PLL onto the A-side sv_system_pll`。
**阶段 10 的全部成果还没提交**，工作树 = **9 改 + 7 新**：

- **新增 7 个**（其中 6 个是阶段 10 的成果，1 个是本文件）：
  - `safevision/rtl/memory/framebuffer_loopback_core.v`（**可仿真核心**，含地址斜坡探针 + 208 Byte 报告）
  - `safevision/rtl/memory/mem_read_burst.v`（读突发引擎：把突发读变成 `mem_ctrl` 的逐字读）
  - `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/sdram_app_adapter.v`（**突发桥**，见 §6.1）
  - `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage10_framebuffer.v`（板级顶层）
  - `safevision/verification/unit/tb_framebuffer_loopback_core.sv`（11 项断言）
  - `safevision/verification/unit/tb_sdram_app_adapter.sv`（7 项断言，含"厂商 app 口模型"）
  - `docs/B链-交接-给下一位Agent.md`（本文件）
- **改动 9 个**：`README.md`、`docs/B链-待办与硬件验证清单.md`、`docs/interface_spec.md`、
  `docs/architecture/module_registry.md`、`docs/requirements/traceability.md`、
  `docs/verification/test_matrix.md`、`safevision/platform/anlogic_eg4s20_hx4s20c/project/safevision.al`
  （登记阶段 10 的 4 条文件 + `TOP_MODULE` 切到 `top_stage10_framebuffer`）、
  `safevision/rtl/memory/frame_address_gen.v`（补 `` `include `` + `y*640` 改移位相加）、
  `safevision/tools/run_sim.ps1`（把 `sdram_app_adapter.v` 与 `tb_sdram_app_adapter.sv` 加进编译/回归列表）。

**建议的提交**（信息用 ASCII —— 中文提交信息在这个 shell 里会乱码；分两段更清楚）：

```bash
git add -A
git commit -m "Stage 10: verify the framebuffer loopback on the board" \
           -m "Add framebuffer_loopback_core, mem_read_burst, sdram_app_adapter, top_stage10_framebuffer and two TBs. Board result: WR=RD=04B000 BAD=000000 with all three address-ramp probes passing. Regression 540 -> 558 assertions / 20 TBs. Self clock group is still -0.992 ns / 31 endpoints."
```

> ★ **提交前先看一眼 `git status` 里有没有你不认识的改动**（尤其 `project/safevision.al`：
> 如果 TD 正开着并保存过工程，磁盘上的 `.al` 可能是 TD 内存状态覆盖的版本）。

---

## 5. 阶段 10 完整复盘（一页）

### 5.1 现象 → 定案 → 修复 → 验收

1. **现象**：整帧写→整帧读回比对，**恰好 3/4 的 word 错**（`BAD=038400` = 153600 的精确 3/4），
   首个不符像素 `BF=00000A`；而帧前 2 个 word 是对的（`W0=59C3ACE1 W1=670FB387`，与核心 LFSR
   逐步推算完全一致）⇒ **写侧数据与前 2 个 word 的读通路正常，错位从后面开始**。
2. **定位手段**：加**「地址斜坡探针」** —— **写进去的值 = 它自己的字地址**，于是回读值直接告诉你
   "这份数据当初被写在哪个地址"，一次上板就能读出**错位量 / 步长 / 丢没丢**。
   探针 A：字 `0x1000`（16 对齐）起连写 32 个、顺序读回 32 个（跨两次 16 字预取），只报
   `AM`（32 位匹配位图）/`AF`（首个不符序号）/`AV`（该处实际读回值）—— 因为**存 32 个回读值要
   512 个寄存器，会把 125 MHz 的报告通路时序打穿**（实测过）。
   探针 C：**另起一次预取**读字 `0x1004` 起 4 个 —— 这是**区分"写错"还是"读错"的关键**；
   探针 B：字 `0x1035`（**非 16 对齐**）写 4 读 4，作"非对齐基址"对照。
3. **定案**：板上报文显示 `A0..A3` 对、**`A4..AF` 又重复回这 4 个值**，而 `B0..B3` 全对
   ⇒ **一次连续读突发里，读地址只推进 4 个字就回绕**，与帧级"每 4 个读回只对 1 个"完全吻合。
   根因：`sdram_app_adapter` 把**读预取的地址推进挂在 `Sdr_rd_en` 上**（厂商应答延迟窗内地址被"钉住"
   不前进）⇒ 违反 M-11 已验形态（见 §6.1）。
4. **修复**：读引擎按 M-11 形态重写（发命令 / 收响应两条独立计数 + 1:1 配对 + 突发间静默）；
   另外修掉自己的两个后续问题（**"跳到缓冲外地址但缓冲没排空"不会重预取 ⇒ 永久死等**；
   以及**报告寄存器数量导致的 STA 回归**）。
5. **验收（2026-10-03 晚，208 Byte 报文，采集 ID 211030）**：

```
SV-FB-LOOP
INIT=01
WR=04B000 CRC=01 SV=01              ← 整帧 307200 像素写完（CRC / slot_valid 都过）
RD=04B000 BAD=000000                ← ★ 整帧读回逐像素零错
W0=59C3ACE1 W1=670FB387             ← 帧前 2 word 与核心 LFSR 逐步推算一致
AM=FFFFFFFF AF=FF AV=00000000       ← 探针 A：32 个回读全对（跨两次预取）
C0=1004 C1=1005 C2=1006 C3=1007     ← 探针 C：非零偏移处全对（写侧正常）
B0=1035 B1=1036 B2=1037 B3=1038     ← 探针 B：非 16 对齐基址全对
BF=000000
DONE
```

### 5.2 唯一遗留：自研组时序 ~1 ns

**四版 STA 记分（只看自研组 `clkc[1]→clkc[1]`；全局 −6.826 ns 是硬核 PAD 路径，与 stage 9 同数，正常）**：

| 构建 | SWNS | 违例端点 | 端点总数 | 最差路径在哪 |
|---|---|---|---|---|
| report13（加探针**之前**） | **+0.030 ns** | 0 | 3023 | — |
| report14（354 B 报告 + 512 回读寄存器） | −1.083 | 475 | 4445 | `ra_reg → rpt_vec 选择 → u_uart_tx/shifter` |
| report15（208 B 报告） | −1.562 | 312 | 3691 | 适配器 `rbase+rhead` 32 位加法器 → `ready` → 核内状态机 |
| **report16（当前代码）** | **−0.992** | **31** | 3709 | `u_core/st → amask/bw 变址译码 → 报告寄存器 CE`（net 占 76%） |

**已经做过的两项减负**：① 报告瘦身（354 → 208 Byte、报告寄存器 640 → 199 个、去掉探针回读的
512 个寄存器）；② 回读结果收集由"**变址写数组**"改成"**纯移位**"（`amask` 右移塞入、
`cwq/bwq` 左移 16 位）⇒ 32 路/4 路译码器与它们的高扇出网消失。

**下一步（按杠杆大小排序，都不需要动功能）**：

1. **先复算一次 TD**，看 31 个违例端点还剩多少、最差路径在哪（可能这次改动已经够）。
2. **把报告 mux 按段拆成小 case**（文档里登记已久的备选）：现在是"1664 bit 向量 + 变址选取"，
   改成"12 路选段 + 段内小 mux"，能显著缩短走线与 LUT 层级。
3. 还不行就给 `rep_data` 加**输出寄存器**（注意：索引要提前一拍，且 **`req` 必须在握手上升沿**
   才撤 —— 见 §7 的 TB 握手三坑）。

> ★ 判定口径（项目规则 §7 末条）：**先看 Clock Summary 的扇出与分组，再看违例是否落进"我们自己的组"，
> 最后拿厂商参考设计对表**；**不要急着加 `set_false_path` 刷绿**，那会把以后真出问题一起盖住。
> ★ 参考无害告警：`HDL-5007 concat with unsized literal`（厂商 `.enc` 内部）、
> `HDL-5917 Input port ... not connected`、以及若干 `*.vh will not be compiled` —— 都不是问题。

---

## 6. 最贵的三条经验（这一层不可仿真，每次猜错 = 一次烧板）

### 6.1 ★★ 厂商 SDRAM app 口：只照抄 M-11 的形态，不要自己发明

`ip/sdram/` 是**安路加密 IP**（`sdr_*.enc.v`：TD 能解密、ModelSim 不能）⇒ **适配器只能板上验**。
厂商 App 口的**唯一被实物验证可行**的形态，就是 M-11（`top_sdram_loopback.v`，4096 个连续 word、
`BAD=0000`）那一版：

> **`App_*_en` 连发 N 拍 + `App_*_addr` 在连发期间每拍自增 + 突发之间 en 静默若干拍 +
> 读侧按 1:1 收响应（第 k 个 `Sdr_rd_en` 对应第 k 条读命令）+ 读写不重叠**

踩过的三个反例（三轮实验定论）：
① **只拉 1 拍使能** ⇒ 读到全 FF（厂商要 ≥2 拍）；
② **同址连发** ⇒ 能写进去但相邻地址互相覆盖（读回全是最后写入值）；
③ **地址跟着应答走（挂在 `Sdr_rd_en` 上）** ⇒ 一次突发只推进 4 个字就回绕（阶段 10 的根因）。

**烧板纪律**：这一层不可仿真，**每猜一次协议就是一次烧板**。正确姿势 = **先照抄 M-11 已验证的形态**；
每次上板前把假设写成**显式判据**，争取"一次 burn 拿全部信息"（斜坡探针就是为这个设计的）。

### 6.2 ★★ 诊断方法论：「值 = 它的地址」的斜坡探针

需要回答"错位几 / 步长几 / 丢没丢"时，**别只写固定图案（1111/2222…）** —— 那只回答"对不对"；
**写"值 = 该字的地址"**，回读值本身就是地址，一次就能读出整张映射。
配套两条：**分段基址**（对齐 / 非对齐各一段）**用来区分"写错"还是"读错"**；
**匹配位图（mask）比"存回读值"省 10 倍寄存器**，而信息量几乎不损失。

### 6.3 ★ 报告 / 序列化通路是 TD 时序的地雷

本工程历史上最薄的路径反复出现在**报告装配**上（`rpt_vec[... +: 8]` 的变址选取、
`u_uart_tx` 的输入 mux）。**加报告字段 / 加回读寄存器之前，先想清楚 STA**：
优先用"**寄存器 + 小 mux**"，别用"大向量 + 变址"；报告长度一变，`rpt_idx` 的位宽与取值方式都要跟着看。

---

## 7. 已知工具/工程坑（都踩过，别再踩）

**TD 工程与约束**
- **`.al` 只是"上次保存的快照"，跑综合用的是 TD 内存里的状态**：手改 `.al` 后必须**关掉 TD
  （提示保存选【否】）再重开**，或 GUI 里手动添加；**判断综合了哪个顶层只信 `syn_1/run.log` 的
  `elaborate -top <名>`**，不要信 UI。
- **`pin.adc` 给顶层不存在的端口指引脚 = 报错**（`USR-8168` / `HDL-1492`）。多顶层共用一份 `.adc`
  时把只有部分顶层才有的引脚用 `#` 注释（现在分成"公共 6 条 + `[SD-ONLY]` 4 条"）。
  **两个修改的生效方式不同**：`read_adc` 每次 Run 都执行（改完 `.adc` 直接重综合即可），
  而 `.al` 的改动必须**重开 TD**。
- **"全局 SWNS 为负"不一定是我们的问题**：全局 −6.826 ns 100% 出自 SDRAM 硬核 PAD 路径
  （`clkc[1]↔clkc[2]`，`clkc[2]` 扇出=1，厂商参考设计同数）。**判定只看自研组**（见 §5.2）。

**仿真/回归**
- **`run_sim.ps1` 只跑 `.sv`/`.v` 的可仿真部分**；**阶段 10 板级顶层 `top_stage10_framebuffer.v`
  进不了回归**（含加密 IP）。但**适配器 `sdram_app_adapter.v` 不含加密件**，已进 `$RTL` 且有
  单元 TB（TB 里内建"厂商 app 口模型"）—— 这是把不可仿真的一层尽量捞回仿真里的做法。
- **`check_repo.ps1` 只查"引用的文件在不在"**，查不到"新建文件没进 `$RTL/$SIM/$TBS`" ⇒ **两个脚本都要跑**。
- ★ **仿真全绿 ≠ 能综合**：改完 RTL 还要在 TD 里跑一次综合 —— **多驱动**（一个 `reg` 被两个 `always`
  写）和**组合除法**这类问题 **ModelSim 完全不报**，只有 TD 报（`HDL-8007` / `Logic Level 100`）。
  **每个 `.v` 必须自带它用到的头文件**（TD 按文件独立编译、不共享宏；`frame_address_gen.v` 就栽过）。
- **`sync_fifo` 的 `data_count` 位宽 = `$clog2(DEPTH)+1`**：改深度会改位宽，接线位宽不匹配会把高位
  悬空（仿真里是 `Z`）⇒ 水位比较变 X、DMA 永不发起。
- **报告 `rpt_idx` 要按报文长度定宽**（当前 208 Byte ⇒ **9 位**、且是**倒计数**
  `rpt_vec[8*rpt_idx +: 8]`）。位宽不够会让报告状态机卡死（`rpt_idx >= RPT_LEN` 永不成立）。
- 断言名是中文 ⇒ **PowerShell 控制台会把 `[FAIL]` 那行显示成乱码**；**判定只看 `PASS=/FAIL=` 计数与 `TOTAL` 行**。

**写 TB（这一轮连踩三次，值得单独记）**
- ① 用**阻塞赋值**驱动 `req`/`wr` 后紧接着 `while (!ready)`：同一个 delta 里读到的是**旧 ready** ⇒ 误判握手。
  **⇒ 驱动一律用非阻塞赋值。**
- ② `while (!ready)` 在 `ready` 为 **X** 时也会退出（`!X` 不为真）⇒ 同样误判。**⇒ 判据写 `ready !== 1'b1`。**
- ③ ★★ **握手是在上升沿被吃掉**：`req` 必须**恰好跨一个上升沿**。在 negedge 撤 ⇒ 握手丢失；
  为了躲 ① 多等一个 negedge 再撤 ⇒ `req` 跨**两个**上升沿、同一字被**写两遍**。
  **⇒ `@(negedge clk)` 拉高 → `@(posedge clk)` 对齐 → 每个上升沿判 ready → 在 ready=1 的那个上升沿同拍撤 req。**
- ★ 排障有效手法：**把"DUT 内部存储内容"与"回读值"并排打出来**（本轮靠 `read == mem` 逐项一致，
  把嫌疑从被测模块锁回 TB）。
- ★ **TB 的判据自己也会错**：给"分段探针"写连续性判据时，只能**段内**判（A 段末尾与 B 段基址本来就不连续）。
- ★ TB 里的行为模型**要如实标注"它不能证明什么"**（`tb_sdram_app_adapter` 的厂商模型按 M-11 形态建模，
  守得住"地址每拍自增"，但**不能复现**厂商的内部细节 ⇒ 别让后人以为"仿真过了 = 板子过了"）。

**采集/留证**
- 串口采集**必须用 HEX/二进制导出**：文本模式会把 ≥0x80 换成 `EF BF BD`，**不可逆**；
  判据是"把参考按 UTF-8 解码(errors=replace)再编码，若与采集件逐字节相同，就说明 FPGA 发的是对的"。
- 报告一律用**显式字节** `8'h0D, 8'h0A`（**Verilog-2001 没有 `\r` 转义**，写 `"\r\n"` 得到的是 `72 0A`）。

---

## 8. 下一步该做什么（按优先级）

**A. 收尾阶段 10 的时序**（唯一阻塞项）：TD 复算 → 按 §5.2 的三根杠杆压到 SWNS ≥ 0。
        复算时顺便确认 `syn_1/run.log` 是 `elaborate -top top_stage10_framebuffer`、无 `HDL-8007` / 无黑盒。

**B. 补证据归档**（阶段 10 的板级采集**目前只在工作区根目录**，不在仓库白名单内、不会进仓库）：
        `Serial Debug 2026-10-03 211030.txt`（**验收报文，208 Byte**）应复制进 `evidence/board/`、
        在 `evidence/board/INDEX.md` 记一条（参考已有条目的写法：条件 / 结论 / 原始文件 + SHA-256）。
        建议一并归档：`195845`（354 Byte，定案那次）、`205358`（208 Byte，暴露死锁那次）。
        完整采集清单与解读见待办清单 §2.5。

**C. 板级还能做的实测**（都能独立于 A 的整机）：
        M-7（3 张不同品牌 TF 卡）、M-8 的"**连读中途拔卡**"分支、M-5（SCLK 频率，可用 ChipWatcher）、
        M-10 精确拍数（`Sdr_init_done` 到齐的拍数）、**SDRAM 全片稀疏扫描**
        （`top_sdram_loopback.v` 的 `ADDR_SHIFT=11 + TEST_WORDS=1024`，参数已留，覆盖行/体地址译码）。

**D. 与 A/C 的待确认项**（越早定越便宜，见待办清单 §1.5）：O-1 `bmp_unpack` 舍入/截断、
        O-3 `mem_arbiter` 突发长度、O-7 音频 `track_id` 编号规则；以及把 `interface_spec.md` 发给 A/C 过一遍。

**E. 代码级待办**（等整机或有余力）：CMD18 多扇区读（现只支持 CMD17）、`pcm_ring` 与
        `audio_cdc_fifo`（音频链最后两块，跨时钟域**必须**用安路软 FIFO，禁止手写异步 FIFO）、
        WAV 出错后的排空/回退提示音、`bmp_parser` 坏文件提前 abort、`frame_swap_*` 与 A 的联仿。

---

## 9. 文档同步义务（改代码后必做，不是可选）

| 文档 | 触发条件 |
|---|---|
| `docs/interface_spec.md` | **任何**信号名 / 有效电平 / 时钟域 / 延迟 / 异常策略变更；模块接口增删；地址表或错误码变化；命名调整（另在 §九 补一行变更历史） |
| `docs/B链-待办与硬件验证清单.md` | 阶段状态 / 回归断言数 / 已知未完成项 / 新增实测或排查条目变化（**文末 §四 变更记录每次都要加一行**） |
| `README.md` | 结构或回归数变化时的"当前状态"表 |
| `module_registry.md` / `test_matrix.md` / `traceability.md` | 模块增删或状态变化 |

**判据**：**改动让某文档的一句话变成错的，就必须改那份文档。**
"代码已经对了、文档回头补"在这个项目里不成立 —— **三份文档就是交付物的一部分**。
（另：文档里**只用仓库相对路径**，不要出现盘符、本机用户名、本机安装路径；机器相关的值按变量名描述，
例如 `MSIM_BIN`。）
