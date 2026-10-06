# B 链 · 方案 A 续做入口（新会话从这里开始）

> **给下一个会话（或队友）**：读这一页 + §0 交接摘要就够，不用翻历史。
> 历史交接：[方案A-第二轮复核交接.md](方案A-第二轮复核交接.md)；
> 详细接口契约与三闸门结果：[B链-板级顶层HDMI验证报告.md](B链-板级顶层HDMI验证报告.md) **§12**；
> 项目长期约定与开发方针：`.workbuddy-ai/memory/MEMORY.md`。
> 更新时间：**2026-10-06 23:35**（板级整链跑通 ✓）。

---

## §0 交接摘要（2026-10-06 晚，本轮）

### 0.1 一句话结论

★★★ **"SD 卡 BMP → HDMI"整链已在实物上跑通**：
`evidence/board/INDEX.md` **SVPLAY-CAP-06**（位流 `board_verify_d28`，7 行连续采集）显示
`SD=1 CARD=1 CNT=4` 全程保持、`ST=8` 持续流传输、`EC=00 ED=00` 无错，
且 **`F` 0→1→2 递增、`CRC=1`、`SLOT` 0/1/0 交替、`CUR` 0→1→2 自动换幅**
⇒ 首帧完成、CRC 通过、双缓冲与换帧都工作。

### 0.2 本轮改了什么（缺陷 24~28 + 板级补强 A~E）

| # | 缺陷/改动 | 一句话 |
|---|---|---|
| 24 🔴 | `fat32_directory_scanner.v` + 卡模型 | 目录项 `FstClusHI/LO` **大端→小端**（真卡首簇曾被字节交换，读回垃圾） |
| 25 🟠 | `file_index.v` | `ent_key` **位宽截断**（4×8bit 拼 32bit 赋 16bit）⇒ 编号以 `00` 结尾被静默忽略、`SV0101` 与 `SV0001` 撞键 |
| 26 🟡 | `sd_bmp_player.v` | 初始化重试的 `init_arm` **沉降窗在重试入口失效** ⇒ 16 次重试 ~30 拍烧完（真尝试 ≈8 次） |
| 27 🔴 | `sd_initializer.v` | **CMD0 的 R1 判据过严**（`== 0x01`）⇒ 真卡返 `0x03`(idle+erase reset) 被拒 ⇒ **SD 初始化"看运气"的主因** |
| 28 🔴 | `sd_initializer.v` | CMD0 返**非 idle**（实测 `0x02`）时**先重同步**（重走 CS 高前导 + CMD0，最多 3 次）再判错 |
| A | `sd_bmp_player.v` | SD 初始化失败**自动重试**（最多 15 次，总时长受 `INIT_TO_N` 约束） |
| B | `safevision_top.v` | 状态行加 `ED=xx`（细分码），**90→96 字节** |
| C | `board_b.adc` | `sd_miso` 改 **内部上拉**（悬空 MISO 的噪声会被当成"假 R1"） |
| D | `sd_bmp_player.v` | 初始化时钟 **396.8 kHz → 100 kHz**（留边沿裕量） |
| E | `sd_initializer.v` + 顶层 | 状态行加 **`R1=xx SQ=x`**（协议原始字节），**96→107 字节** |

★ **方法论（本轮最大收获）**：`R1/SQ` 这两个诊断字段是**当晚现加**的，
**第一次上板就抓到了缺陷 27 的根因**——"偶发/概率性"的接口问题，
**优先加"能看见协议原始字节"的诊断**，比反复猜便宜得多。

### 0.3 验证证据（可复现）

| 闸门 | 命令 | 结果 |
|---|---|---|
| B 主回归 | `safevision\tools\run_sim.ps1` | ✅ **TOTAL PASS=668 FAIL=0**（基线 657 → 668） |
| 整链仿真 | `run_sd_bmp_player_sim.ps1` | ✅ 17/17，`153600 words pixel-exact` |
| 顶层仿真 | `run_top_verify_sim.ps1` | ✅ **40 项**（含 T8：缺陷 26 回归） |
| sink 单元 | `run_bmp_frame_sink_sim.ps1` | ✅ 29 项（真实异步 50/125 MHz） |
| 板级 | `INDEX.md` CAP-01..06 | 见 §0.1；每份采集都记了位流 SHA-256 |

★ **负向验证已做**（本项目有"TB 与 DUT 同错"的教训）：缺陷 27、28 的守门用例都**验证过
"在旧代码上会失败"**（27：T7.1~T7.5 全 FAIL；28：5 项 FAIL）。

### 0.4 ★ 下一步（按优先级）

1. **`mem→mem` 余量恢复（时序纪律）**：最新位流 `board_verify_d28` 是 **+0.111 ns**
   （`d27` 曾到 **−0.052**，`d2526` +0.147）——**同一族 `core/arbiter → core/display/fetch/dma`
   在 P&R 抖动下会翻负**。另 `fb_writer` 的 CRC 族（`crc_src_reg[9]→[13]`）也贴过 +0.030。
   ⇒ 按 P1/P2 的切法给这两族各切一刀，把跨运行最坏推回 **≥ +0.2 ns**。
2. **"生产者交接"改造（消花屏）**：`card_mode` 复位=1 把回落写入器整个门住
   ⇒ **槽 0 从未被写** ⇒ 显示器读未初始化/上次遗留的 SDRAM（"彩条+图片混在一起"的来源）。
   改法：让回落**先无条件画一帧到槽 0 并换帧**，再把写端口交给卡路径
   （`prod_wr_* = fb_submitted ? sk_* : fb_*`）。★ 需同步改 `tb_safevision_top` 的 T4/T7。
3. **`0x03` 处置不符规范**：`interface_spec §6.1` 要求"**跳过该图并计数**"，
   当前是 `S_ERROR` 停机（检出 ✓ 处置 ✗）。
4. **双时钟整链 TB**：现有 `tb_sd_bmp_player` 里 player 与 sink **同频**，
   真板是 **50 MHz ↔ 125 MHz** —— 这是**最大的验证缺口**（曾有 `RD≫PX` 疑云，后来自洽）。
5. **文档口径**：断言条数、`INDEX.md` 的"采集↔位流"表已在 §0.3 与 INDEX 内更新；
   `方案A-第二轮复核交接.md` §1/§3 已从"未修"改为"已收口"。

### 0.5 ⚠️ 与队友工作（`09c7f9f`）的重叠提醒

队友 2026-10-06 21:59 推了 `origin/main` 的 **`09c7f9f`**（"Complete A emergency and HDMI assembly
with verified B compatibility"），其中 **5 个文件与本轮改动重叠**：

| 文件 | 队友改的 | 本轮改的 |
|---|---|---|
| `rtl/memory/memory_arbiter.v` | `COMPACT_CONSEC_COUNTER` 参数化计数位宽 | P1：授权事件迟一拍结算 |
| `rtl/video/frame_reader/a_frame_fetch_bridge.v` | 响应 beat 寄存一拍 | `guarded_level` 寄存一拍 |
| `platform/.../safevision_top/safevision_top.v` | 2 行 | 遥测同步层 / 回落 / 状态行（大量） |
| `project/board_verify/board_cdc.sdc` | 2 行 | slot_sys 约束改 `get_regs` |
| `project/board_verify/td_flow.tcl` | 1 行 | 源表补文件 |

⇒ **两边都在解同一个 `mem→mem` 时序问题、思路不同**。合并时**必须人工取舍**，
不要机械取一边（否则会丢对方的工作）。

★ **本轮已完成合并**（分支 `backup/b-chain-board-bringup` = 双方成果之和）：
- 自动合并成功：`a_frame_fetch_bridge.v`（他的响应寄存 + 我的 `guarded_level` 寄存 **共存**）、
  `board_cdc.sdc`、`td_flow.tcl`
- **2 处冲突，已人工解为"双方都保留"**：
  1. `memory_arbiter.v`：保留本轮 P1 的**结算位置**（`grant_event`），
     同时采用对方的**参数化位宽**（`CONSEC_WIDTH` / `{CONSEC_WIDTH{1'b1}}`）——两处改动正交；
  2. `safevision_top.v`：保留对方的 `FONT_FILE` 相对路径，同时保留本轮新增的
     `MODE_TO_N` / `RPT_PERIOD_N` 两个可测性参数。
- **合并后三闸门全过**：主回归 **668/0**、顶层 TB **PASS(40)**、整链 TB **PASS 17/17**。

---

## 一句话背景

把 **SD 卡里的 BMP 播到 HDMI** 这条链，从"只在测试台里搭的线"变成**可综合模块**，
仿真 **307200 像素逐点全对** ✓；板级 STA 发现这条链原本是 **50 MHz 的设计口径**，
塞进 125 MHz 的 mem 域过不去 ⇒ **方案 A**：链跑 50 MHz，只在边界跨一次。

---

## ★ 当前状态：方案 A **已完成**，三个闸门全部通过 ✓

| 闸门 | 命令 | 结果 |
|---|---|---|
| 播放链仿真 | `safevision\tools\run_sd_bmp_player_sim.ps1` | ✅ **17/17**，`SD-BMP-PLAYER PASS (0 error)`，153600 words **pixel-exact**（= 307200 像素） |
| sink 单元仿真 | `safevision\tools\run_bmp_frame_sink_sim.ps1` | ✅ **26 项断言全过**；★ 跑**真实异步 50 MHz / 125 MHz 双时钟** |
| **板级顶层仿真** | `safevision\tools\run_top_verify_sim.ps1` | ✅ **34 项断言全过**（31 + 复核新增 T7×3：换帧 commit→pending→active→`led[2]` 全链路） |
| B 主回归 | `safevision\tools\run_sim.ps1` | ✅ **TOTAL PASS=657 FAIL=0**（基线 628 → 657） |
| 板级 STA | `safevision\tools\run_board_sta.ps1 -Mode base` | ✅ **`mem→mem` 已收口**：cecut1/cecut2 两次独立运行最坏 **+0.267 ns**（跨运行判据 ≥ +0.1~0.2 ns 过严格端）；50M 媒体链与各交叉每次全 0 违例 |

**全局残余违例 = 厂商 `memory_ip`（封装内 SDRAM 硬核）两组，共 64 个端点**：
`system_pll/clkc[1]→clkc[2]`（读）**−2.880 ns** 与 `clkc[2]→clkc[1]`（写）**−6.826 ns**
（均为 dq↔内部 pad，Logic Level 0、cell 100%）。**既有项**，归厂商、按约定以实测判定 ✓
（`run_board_sta.ps1` 仍会把它们当 FAIL 抛出 —— 那是**有意的严格门禁**，看报告分组即可）。

★ **`mem→mem`：2026-10-06 深夜已收口 ✓**（判据：跨运行最坏 SWNS ≥ +0.1~0.2 ns、
至少 2 次独立运行、每次另存报告目录 —— 全部达成）：

- **终态数据**：`board_verify_cecut1` 与 `board_verify_cecut2` 两次独立运行（同 RTL/SDC
  纯运行间对比）**逐条一致**：最坏 **+0.267 ns / 0 违例 / 3147 端点**，紧带
  +0.267 → +0.286 → +0.334 → +0.36 …（近零段 < +0.1 **无任何族**）。
  最紧一条是 P2 新切端点 `crc_pair_q_reg → crc_src_reg`（新切口必然最紧，属预期）。
  第三次运行 `cecut3`（slot_sys 约束修复后，P&R 有轻微抖动）最坏 **+0.249 ns** ——
  端点换人但仍在 +0.2 之上 ⇒ **跨运行最坏 = +0.249 ns，判据成立且有余量**。
- **两刀结构切分**（mem 域内、语义等价均有论证）：
  - **P1 `memory_arbiter.v`**：授权事件**迟一拍结算**（`grant_event/grant_ch` 先寄存、
    下一拍更新 `consec_cnt/last_ch`）——把 winner 优先树（连带 `rd_req→rd_e` 长锥）
    移出计数器 CE 路径。授权后 busy 至少占 2 拍 ⇒ 下一次仲裁决策最早 3 拍后，迟一拍等价。
  - **P2 `frame_writer.v`**：CRC 源侧**载荷寄存一拍**（`crc_pair_q`）——把 `px_pair` 载荷
    从 4 级 CRC 组合链上摘下来。配对完成间隔 ≥ 2 拍、帧满结算最早在提交后第 2 边沿 ⇒ 余 1 拍。
- **历史轨迹**：−0.606/10 → skid 修复 → +0.118/+0.118/+0.009（薄）→ 复核 −0.163/3
  （`wr_addr_diff→cur_addr` 族）→ guardfix 后 −0.069/2 与 −0.017/1 两族 → **P1/P2 切完
  +0.267 × 2**。每次"换人"的族都照同一节奏切掉了，最后紧带不再挤在近零段 ⇒ **收手**。
- **证据留档**：`build/out/board_verify_skid*/base/`、`board_verify_final/base/`、
  `board_verify_review/base/`、`board_verify_guardfix2/base/`、`board_verify_cecut1/base/`、
  `board_verify_cecut2/base/`（+ `cecut3`：slot_sys 约束修复的验证运行）。
  提取工具：`safevision/tools/extract_sta_paths.py`（`--mem` 按双方 clkc[1] 过滤）。

★★ **踩过的坑（务必记住）**：我第一次跑出 `+0.108 / 0 违例` 时差点报"mem→mem 已清零"——
但那次用的是**改动前的 RTL**（与最终态不同源，不是收敛证据）。
教训两条（已入 MEMORY.md STA 纪律）：
1. **判收敛看跨运行最坏值 + 明确门槛**（"最坏 SWNS ≥ +0.1~0.2 ns"），别用单次结果结案。
2. **每次 STA 先另存报告目录**（`-RunDir`）：早期几次互相覆盖，旧报告无法复核。

---

## 已完成的工作（均编译/仿真/STA 干净）

| 文件 | 状态 |
|---|---|
| `safevision/rtl/storage/sd_bmp_player.v` | ✅ 跑**板载 50 MHz**；像素出口改 **32 位** `px_word/px_word_valid/px_word_ready`；参数 `CLK_HZ_MEM`→`CLK_HZ`(50M)、`CLK_DIV_INIT=62`/`CLK_DIV_FAST=0`、超时按 50 MHz 重算；`mem_ready`/`frame_done`/`last_frame_ok` 三路两级同步 |
| `safevision/platform/.../rtl/bmp_frame_sink.v` | ✅ 新增。官方 `a_pixel_fifo`（**写 50M / 读 125M**）+ A 的 `bmp_frame_write_bridge` + 自研帧控制器 |
| `safevision/platform/.../rtl/safevision_top/safevision_top.v` | ✅ player 挂 `clk`+`ref_rst_n`；sink 挂 `mem_clk`（`wr_clk=clk`）；按键消抖搬到 50 MHz 域；UART 的 PX/F/SLOT/CRC 改指 sink；**新增遥测两级同步层**（`t_*`） |
| `safevision/verification/unit/tb_sd_bmp_player.sv` | ✅ 重写为 **player + sink 串联**，逐像素比对保留 |
| `safevision/verification/unit/tb_bmp_frame_sink.sv` | ✅ **新增**。sink 单元 TB：**真实异步 50 MHz / 125 MHz 双时钟**；26 项断言覆盖正常帧逐像素、两帧**不同行序**、`S_ERROR`、两个换帧超时、`S_WRITE` 无进展兜底、FIFO 排空判据 |
| `safevision/tools/run_bmp_frame_sink_sim.ps1` | ✅ **新增**。sink 单元 TB 的独立入口 |
| `safevision/tools/run_sd_bmp_player_sim.ps1` | ✅ 编译清单加 sink + `a_pixel_fifo` 三个文件 |
| `safevision/platform/.../project/board_verify/td_flow.tcl` | ✅ 源表加 `rtl/bmp_frame_sink.v` |
| `safevision/platform/.../project/board_verify/board_cdc.sdc` | ✅ 加 50M↔125M 例外（同步器首级 false_path + FIFO 内部 Gray 指针 max_delay） |
| `docs/B链-板级顶层HDMI验证报告.md` **§12** | ✅ 接口契约 + **§12.5 三闸门结果** + **§12.5.2 修掉的 8 个真缺陷** + **§12.5.3 已知局限** |

---

## ★★ 下一步（按优先级）

### 1. 验证覆盖：已补齐，剩两个明确的缺口

- ✅ `bmp_frame_sink.v` 有单元 TB（`tb_bmp_frame_sink.sv`，已进回归）。
- ✅ 真实的 **50 MHz ↔ 125 MHz 异步边界**被仿真覆盖了（双自由时钟）。
- ✅ **`safevision_top.v` 有顶层 TB 了**（`tb_safevision_top.sv`，31 项断言）：
  UART 状态行格式+字段、`card_mode` 回落、HDMI AXI 活动、按键消抖。
- ❌ **缺口 1：顶层的"真卡"路径没覆盖** —— 顶层 TB 用的是**卡不可用**场景（走回落）。
  建议给 `tb_safevision_top.sv` 加一个"卡可用"的 phase（需要造 FAT32 卷，可复用
  `tb_sd_bmp_player.sv` 里的 `build_volume` 手法）。
- ✅ **缺口 2 已关闭（2026-10-06 复核）**：`active` 不置起的根因**不是** SDRAM 桩 ——
  是顶层 mem→sys 打包跨域的**载荷与 `frame_ready` 同拍捕获**（缺陷 22，见下）。
  修复后 `tb_safevision_top.sv` 新增 **T7 三项断言**（pending→active→`led[2]`，
  31 → **34 项**），`active` 在换帧提交后第一个 `frame_start` 正常置起。

### 2. 上板验证（★ 2026-10-06 位流已出，只差烧写+观测）

**位流就绪**（`board_verify_bitgen/base/`，独立报告目录、未覆盖 cecut 证据）：
- `safevision_top.bit`，**631963 字节**，SHA-256 `019cbf357738838dc23facccfdbb851ada9abaaf55de81fb0eef641ecb61f5cd`
- 本次独立 P&R 的 `mem→mem` 最坏 **+0.249 ns**（与 cecut3 一致）；`SWNS −6.826`
  仍只是厂商 SDRAM 硬核违例（**位流 ≠ 时序收敛**，按实测判定）。

**上板检查单**（烧写是刻意手动步骤，TD GUI 下载器；无 CLI 通路）：
1. TD 下载器烧写 `board_verify_bitgen/base/safevision_top.bit`。
2. SD 卡：**不用动**——卡 `HX4S20C` 已有 `SV0001..SV0005.BMP`
   （8.3 大写名、640×480、24bpp 未压缩，921654 B = 54+640×480×3 ✓，符合
   `bmp_parser` 校验清单）。命名规则 `SV`+4 位数字（0000 非法），最多取前 4 幅。
3. 显示器插 **HDMI B** 口（TMDS=C3/G5/F1/E1）。
4. 串口 CH340G 115200 8N1，**HEX 导出**采集（勿用文本模式——U+FFFD 替换不可逆，
   见 evidence/board/INDEX.md 的 CAP-M9-01 教训）。
5. 判据：画面显示卡里的 BMP + LED 四灯语义 + UART 状态行（格式见下）。
6. 回归点：**回落场景**（卡不可用/坏文件）是缺陷 22 修复的板上回归点，换张坏卡试一次。
状态行格式（★ 2026-10-06 起为**固定 107 字节**，末尾依次新增 `ED=xx` / `R1=xx` / `SQ=x`）：
`SV-PLAY ST=x FS=x EC=xx SD=x CARD=x CNT=x CUR=x RD=xxxxxxxx PX=xxxxx F=xxxx SLOT=x CRC=x ED=xx R1=xx SQ=x`
- `ED=xx` = `err_detail` 细分码：`0x11`=CMD0/CMD8/ACMD41 协商失败、`0x21`=命令响应超时、
  `0x22`=数据 CRC16、`0x23`=数据起始 token 异常（完整表见 `interface_spec` §6.2 与 `fault_code_defs.vh`）。
- `R1=xx` = SD 初始化里**最近一次收到的 R1 原始字节**；`SQ=x` = 挂在第几条命令
  （`0`=CMD0 / `1`=CMD8 / `2`=CMD55 / `3`=ACMD41）。
  ★ 判读：`R1=FF` ⇒ 卡没应答（接触/供电）；`R1=05` ⇒ **非法命令**（卡没听懂 ⇒ 时钟/位序问题）；
  `R1=00` ⇒ 卡应答但状态不对；`R1=01` 且 `SQ=1` ⇒ CMD8 回显/电压不符。
- ★ 2026-10-06 之前的采集是 **90 字节**（无 ED/R1/SQ），历史记录不改。
- `ST/FS/SD/CARD/CNT/CUR/RD` 取自 **player**（SD 链）
- `PX/F/SLOT/CRC` 取自 **sink**（mem 侧的像素与换帧才是真相）
- `EC` 报**有效错误码**：sink 报错时优先报 sink 的（`0xF1`=换帧超时、`0xF2`=帧写超时），
  否则报 player 的（`0xE1~0xE5`=各阶段超时/无文件）

#### ★ 2a. 首次上板实测结果（2026-10-06 晚）—— **失败，根因已定位并修复（缺陷 24）**

采集（已归档 `evidence/board/INDEX.md` 的 **SVPLAY-CAP-01**）：
`SV-PLAY ST=A FS=7 EC=03 SD=0 CARD=0 CNT=4 CUR=0 RD=0x37 PX=0 F=0 SLOT=0 CRC=0`

- **判读**：首幅（槽 0）在 `bmp_parser` 头校验被拒（`RD=55` ≈ 54 字节头读完即判）。
  `SD/CARD=0` 是 S_ERROR 进入时清标志所致，**不是**"卡未就绪"。
- ★ **不是**卡上那张故意做坏的 `SV0005`（头两字节 `FF FF`）——它按"取前四"规则**落榜、从未被读**。
  把 `CUR=0` 误判成"坏图被检出"是**反向结论**，别再重复。
- **根因 = 缺陷 24**：`fat32_directory_scanner.v` 把目录项的 `FstClusHI/LO` 按**大端**装配，
  而 FAT32 是小端 ⇒ 真卡上首簇全部字节交换 ⇒ 文件数据地址全错（读回垃圾 ⇒ 头校验拒收）。
  详细指纹与"为什么全部闸门都绿"见 [方案A-第二轮复核交接.md](方案A-第二轮复核交接.md) **§2.3**。
- **修复状态**：RTL（`fat32_directory_scanner.v`）+ 仿真模型（`sd_spi_card_model.sv` 同款错序）**已一起改**，
  `tb_fat32_directory_scanner` / `tb_sd_bmp_player` 回归通过。

#### ★ 2c. 第二轮复核发现的 2 个缺陷（已修 + 补了断言）

复核（只读）发现两处**我漏修且 TB 没覆盖**的问题，均已修复并补回归：

- **缺陷 25 🟠 `file_index.v` 的 `ent_key` 位宽截断**（是我 10-05 那次时序优化引入的功能回归）：
  `wire [15:0] ent_key = {(nd0-8'h30),…}` —— 四项各 8 bit ⇒ 拼接是 **32 bit**，
  赋给 16 bit 只留**低 16 位** ⇒ 实际只有【后两位数字】参与比较。后果：
  编号以 `00` 结尾（`SV0100`…）⇒ `ent_key==0` ⇒ `num_ok` 假 ⇒ **整幅被静默忽略**；
  只差前两位（`SV0001` vs `SV0101`）⇒ **键相同** ⇒ 被当重复丢弃 + 排序错。
  修法：先把每个数字截成 4 bit（`nk0..nk3`）再拼 16 bit（仍无乘法，时序收益不变）。
  ★ 已补 `tb_file_index` **T69**（三条一起放：`SV0100`+`SV0001`+`SV0101`，旧实现必挂）。
- **缺陷 26 🟡 `sd_bmp_player.v` 的 `init_arm` 沉降窗在重试入口失效**：
  `S_INITR` 不清 `init_arm` ⇒ 重试回到 `S_INIT` 那一拍它仍是饱和值 7
  ⇒ `if (init_arm >= 4)` **立刻成立**，而 `init_error` 是电平、还没被新 `start` 的
  `do_soft_reset` 清掉 ⇒ **立刻再判一次错** ⇒ 16 次重试在 ~30 拍内烧完
  （真正跑起来的初始化尝试 ≈8 次）——**这就是"自动重试没救活卡"的原因**。
  修法：`S_INITR` 里加 `init_arm <= 3'd0;`。
  ★ 已补 `tb_safevision_top` **T8**（卡不可用 ⇒ 必走重试路径；检查每次
  `S_INITR→S_INIT` 时 `init_arm` 是否为 0；实测 `retries seen=9, bad=0`）。
- **回归**：主回归 **668 PASS / 0 FAIL**（657 → 668，`tb_file_index` 60→71）；
  顶层 TB **PASS（39 项）**。
- **新位流**：`board_verify_d2526/base/safevision_top.bit`，631963 B，
  SHA-256 `d1b1845458edf66eb3d958ec4817a8b53d442a312d5bfe8435b4b4229d2a2541`；
  `mem→mem` 最坏 **+0.147 ns / 0 违例**（最紧路径已换到 UART 报告 mux —— 即加 `R1/SQ` 的那一段）。
- ⚠ **仍待查（复核列的头号）**：`RD ≫ PX`（卡帧写不完）。已排除：`a_pixel_fifo.wr_ready` 是写域信号、
  `bmp_parser`/`bmp_unpack` 都是一字节一握手、packer 握手正确、FIFO 容量仅 2046 像素
  （装不下 7.4 万像素的差额）⇒ **指向"显示侧把帧头丢掉了"**（sink 在 `S_DRAIN` 会无条件弹掉 FIFO）。
  ★ **根因需要一个"双时钟整链 TB"才能复现**——现有 `tb_sd_bmp_player` 里 player 与 sink **同频**，
  而真板是 50 MHz ↔ 125 MHz。这是当前**最大的验证缺口**，建议下一步就做。

#### ★★ 2d. 缺陷 27（SD 初始化不稳的**真正根因**）——`R1/SQ` 诊断上线后立刻抓到

**证据**（`evidence/board/INDEX.md` **SVPLAY-CAP-04**，位流 `board_verify_r1`）：
`SV-PLAY ST=A FS=1 EC=01 SD=0 CARD=0 CNT=0 … ED=11 R1=03 SQ=0`

- `SQ=0` ⇒ 挂在 **CMD0**；`R1=0x03` = **bit0(idle) + bit1(erase reset)**
  ⇒ **卡确实进了 idle 状态、复位是成功的**！
- 而 RTL 当时写的是**严格等值** `if (r1 == 8'h01)` ⇒ 把 `0x03` 判成失败（`ED=11`）。
- ⇒ **"SD 初始化约 1/10 才成功"的来源**：卡干净时返 `0x01` 就过；带 erase-reset 状态位时返 `0x03`
  就被拒（连续按复位时后者居多）。

**修复**：判据改为 **`bit0(idle)=1 且 bit6..bit2（非法命令/CRC/擦除序/地址/参数）全 0`**，
**容忍 bit1（erase reset，状态位）**。（CMD8/CMD55 本来就是按位判，只有 CMD0 用了等值。）

**守门用例**：`sd_spi_card_model` 新增参数 `CMD0_R1`（默认 `0x01`）；
`tb_sd_initializer` 的"慢卡"实例改用 **`CMD0_R1=0x03`** ⇒ 旧实现直接挂（T7.1/T7.2），
新实现通过 ⇒ 这条判据以后有断言守着。

★★ **已做"负向验证"**（本项目有"TB 与 DUT 同错"的教训，新断言必须证明"在旧代码上会失败"）：
临时把判据改回 `r1 == 8'h01` 重跑 `tb_sd_initializer` ⇒ **T7.1~T7.5 全 FAIL**
（`慢卡最终初始化成功` 等）；恢复修复版后 `[FAIL]` 计数 = **0** ⇒ **这条断言是真守卫，不是装饰**。

**回归/位流**：主回归 **668 PASS / 0 FAIL**；
新位流 `board_verify_d27/base/safevision_top.bit`，631963 B，
SHA-256 `16539e1878728746ffb21885783f38d622ec3fab5e8437dbfbbe56692064508a`（含 A~E + 缺陷 25/26/27）。

⚠️ **但这一版的 `mem→mem` 出现用户域 setup 违例：−0.052 ns**
（`core/arbiter/responses_left_reg[4] → core/display/fetch/dma/drain_word_reg[1]`，7.772 ns / 8.0）。
与上一版 `d2526`（+0.147）相比，**netlist 只差 CMD0 那一行判据**，却是 P&R 抖动把 `core/display/fetch`
这一族推到了负值 ⇒ **再次印证"不能靠跑运"**。
- 对**今晚的功能复测**：−0.052 ns = 预算的 0.65%，且落在**显示 DMA** 这条一直在跑（彩条）的路径上
  ⇒ **可以用**（这不是时序收敛的声称，只是功能验证）。
- **但它不满足项目时序纪律** ⇒ 下一步必须做"恢复余量"的结构切分
  （该族与 `video_read_dma`/`a_frame_fetch_bridge` 相关，参照 P1/P2 的切法）。

★ **方法论收获**：`R1=xx / SQ=x` 这两个诊断字段是**当晚现加**的，**第一次上板就抓到了根因**——
比"再猜三轮"便宜得多。**遇到"偶发/概率性"的接口问题，优先加"能看见协议原始字节"的诊断**。

#### ★★ 2e. 缺陷 28：`R1=02`（CMD0 非 idle）⇒ 加"重同步重试"

后续又抓到 `ED=11 R1=02 SQ=0`（`INDEX.md` **SVPLAY-CAP-05**，**12 行逐字节相同**）：
`0x02` = bit1(erase reset)=1 但 **bit0(idle)=0 ⇒ 卡没进 idle**（与 CAP-04 的 `0x03` 不同）。
⇒ **卡对 CMD0 的响应在变（`01`/`02`/`03` 都出现过）**，且**同一会话内稳定复现同一个值**
⇒ 不是随机噪声，更像"卡被上次 FPGA 复位打断后残留状态 / 内部忙"。

**修复**：CMD0 的 R1 非 idle 时**不立刻判死**，重走 `M_POWER`（CS 高 + 80 拍前导）→ `M_CSON`
（CS 拉低）→ `M_CMD`（CMD0），最多 **`CMD0_RETRY_MAX=3` 次**（CS 翻转 + 前导可中止并重新同步卡）；
`cmd0_try` 在 `do_soft_reset` 清零。

**守门 + 负向验证**：卡模型加 `CMD0_BAD_TRIES`（前 N 次回 `0x02`）；`tb_sd_initializer` 的慢卡实例设
`CMD0_R1=0x03, CMD0_BAD_TRIES=2`（**同时守缺陷 27 + 28**）⇒ **关掉重同步 ⇒ 5 项 FAIL；恢复 ⇒ 0** ✓。

**位流**：`board_verify_d28/base/safevision_top.bit`，631963 B，
SHA-256 `d515af2ccd86a3ec99ef61670966a505e92857fd92d2646db5fecdeab4805dd8`（含 A~E + 25/26/27/28）；
`mem→mem` **+0.111 ns / 0 违例**（同族 `core/arbiter → core/display/fetch/dma`，7.616/8.0 ⇒ **仍需那刀切分**）。

#### ★ 2b. 上板复测（★ 含 A~E + 缺陷 25/26/27 修复的新位流）

**A+B 改动（2026-10-06 晚，针对"SD 初始化约 1/10 成功"）**：
- **A. 初始化自动重试**（`sd_bmp_player.v`）：新增状态 `S_INITR`，初始化失败后**自动重试最多 15 次**
  （含首次共 16 次尝试）。`to_cnt` 跨重试累加 ⇒ 总时长仍受 `INIT_TO_N`(200 ms) 约束，
  **不会挤掉顶层 `MODE_TO_N`(300 ms) 回落窗口**。`init_done`/`restart` 都会把重试计数清零。
  ★ 关键陷阱：`init_error` 是**电平**，重发 `start` 后要等 initializer 的 `do_soft_reset` 清掉它
  才能再判错 ⇒ 用 `init_arm` 设 5 拍沉降窗（否则 16 次重试会在 ~50 拍内被瞬间耗尽）。
- **B. 状态行加 `ED=xx`**（`safevision_top.v`）：把 `err_detail` 细分码报出来（新增 `t_ed` 两级同步层），
  行**从 90 字节变 96 字节**。这样 `EC=01` 能进一步区分 `0x11` 协商失败 / `0x21` 响应超时 /
  `0x22` CRC16 / `0x23` token ⇒ 板上能分清"卡接触不良"还是"卡应答错"。
  历史 90 字节采集**不改**（那是旧位流的记录）。
  ★ **B 的效果已在上板验证**（`evidence/board/INDEX.md` 的 **SVPLAY-CAP-02**）：
  96 字节整，且 `ED=11` 直接把故障钉在"CMD0 的 R1 ≠ 0x01（协商失败）"而不是"响应超时"。
- **C. `sd_miso` 改用内部上拉**（`project/board_verify/board_b.adc`，2026-10-06 板级实测后）：
  `ED=11` 说明卡**没有**在驱动 MISO（悬空 ⇒ 噪声里带 bit7=0 的字节被当成"假 R1"）。
  加上拉后"卡不应答"会干净地变成 `0xFF` ⇒ 报 `ED=21`，诊断不再被噪声带偏、FSM 也不拿噪声当响应。
  ★ 这本就是 `constraints/pin.adc` 里预留的处置（"switch to PULLUP if MISO floats"）。
  ⚠ 注意：这**只改善诊断与鲁棒性，不修卡座接触本身**——物理排查（换卡/按住卡/供电）仍要做。
  ★ 上板复核（22:33 连采 10 行）：**仍报 `ED=11` 而非 `21`** ⇒ MISO 确实被驱动（不是悬空噪声）
  ⇒ 更像**边沿质量/信号完整性**问题，而非"没接触"。据此新增下面 D/E 两项。
- **D. 初始化时钟降到 100 kHz**（`sd_bmp_player.v` 的 `CLK_DIV_INIT`：`16'd62`→`16'd249`）：
  396.8 kHz → **100 kHz**（SD 规范允许初始化段 100–400 kHz，取低端留最大裕量；
  数据段 `CLK_DIV_FAST` 12.5 MHz 不变）。若失败源于边沿质量/信号完整性，降速会显著改善。
- **E. 状态行报 `R1=xx SQ=x`**（`sd_initializer.v` 新增 `dbg_r1/dbg_seq` 输出 →
  `sd_bmp_player` 的 `init_r1/init_seq` → 顶层两级同步 → 状态行；**行 96 → 107 字节**）：
  一眼区分"卡没应答(`FF`)"、"非法命令(`05`，卡没听懂 ⇒ 时钟/位序)"、"应答但状态不对(`00`)"。
  ★ 只报 R1 会被 CMD8 的"回显错但 R1=01"误导，所以**必须带 `SQ`** 指明挂在哪条命令。

**位流已就绪**（`safevision/build/out/board_verify_r1/base/`，独立报告目录；**含 A+B+C+D+E**）：
- `safevision_top.bit`，**631963 字节**，SHA-256 `08b6bd9b1c096467b2a0c613540cfb0498a9358ba490ccd3412532edfc0ca155`
- ⚠ **时序偏薄（要盯）**：用户域 `mem→mem` 最坏 **+0.030 ns / 0 违例**，且**换了族** ——
  `fb_writer/crc_src_reg[9] → fb_writer/crc_src_reg[13]`（7.733 ns / 8.0）。
  ★ 这是**回落图案写入器（`fb_writer`）的 CRC 源侧**路径，与 `frame_writer` 当年"P2 切分"
  （`crc_pair_q` 载荷寄存一拍）**同族**，但 `fb_writer` 没做那一刀 ⇒ **下一轮建议对 `fb_writer`
  做同款 P2 切分**把余量推回 +0.2 以上。（+0.030 为正、功能可用；但它只在**回落路径**上，
  卡路径（`frame_writer`）余量更宽。）
- 上拉已核实仍在：`route.area` = `sd_miso INPUT B14 LVCMOS33 PAD N/A PULLUP` ✓
- 前几版：`board_verify_misopu/base/`（A+B+C，`ae25fd9c…`）、`board_verify_retry/base/`（A+B，`3e2ad765…`）。

**复测步骤**：
1. TD 下载器烧写 `board_verify_retry/base/safevision_top.bit`（**烧写是刻意手动步骤**，脚本不碰硬件）。
2. 卡**不用动**（`HX4S20C`，SV0001..SV0005，SV0005 是故意坏图）。
3. 期望：`ST` 离开 `A`、`PX`/`F` 递增、屏幕出现 SV0001；按 `btn_next` 换幅、按 `btn_auto` 连播。
   ★ 若仍失败：看 **`ED=`** —— `11`/`21` 指向"卡不应答"（接触/供电/卡本身），
   `22`/`23` 指向"应答了但数据错"（信号完整性/速率）。
4. 再补一条 **`0x03` 处置**的规范缺口（`interface_spec §6.1` 要求"**跳过该图并计数**"，
   当前实现是 `S_ERROR` 停机）——见 §4 待办。

**★ 板上按键与"彩条先出现"的机制**（`pin.adc` 按键表 + `safevision_top.v` 回落逻辑）：

| 按键 | 引脚 | 作用 |
|---|---|---|
| **KEY1** | A2 | `rst_n` —— **整机复位**（重新给卡 300 ms 窗口） |
| **KEY2** | B2 | `btn_next`：换下一幅；**同时接 player 的 `restart`** ⇒ 卡路径出错后按它可以重试 SD 初始化 + 重扫目录 |
| KEY3 | B1 | 未使用 |
| **KEY4** | C1 | `btn_auto`：自动连播开关（电平） |

- **彩条是"回落图案"，不是错误**：上电后 `card_mode=1` 给卡 **`MODE_TO_N = 300 ms @125 MHz`** 窗口；
  超时卡仍未就绪 ⇒ `card_mode→0`，显示回落图案。
- ★ **一旦回落图案写出过帧（`fb_go=1`）就永不再切回卡路径**（防止中途换生产者 toggle 源）⇒
  **卡插晚了/接触不良导致回落后，必须按 KEY1 复位或断电重上电**，只插卡无效。
- ⇒ 诊断技巧：**屏幕上是不是彩条不重要，看串口状态行**——按 KEY2（重启 player）后若出现
  `SD=1 CARD=1 CNT=4`，说明卡其实认得出来，只是显示侧已回落。
- 上板实测（2026-10-06 晚第二采）：`ST=A FS=1 EC=01 SD=0 CARD=0 CNT=0` = **SD 初始化失败**
  ⇒ 先查卡是否插到位 / 卡座接触，再复位重试（**不是**缺陷 24 的现象，缺陷 24 是 `FS=7 EC=03`）。
- ★★ **缺陷 24 的修复已获上板验证**：用户反复复位约 10~15 次中有 1 次初始化成功，
  **那次屏幕正常出了图** ⇒ 卡路径一旦起来就工作，字节序修复有效。
- ★ **剩余问题 = SD 初始化不稳定（约 1/10~1/15）**。初始化路径已逐项审计，**全部规范**：
  `CLK_DIV_INIT=62` → 396.8 kHz（≤400 kHz ✓）、80 拍 CS 高前导（`SD_POWERUP_BYTES=10` ✓）、
  响应超时 3.2 ms @50 MHz（`SD_TO_RESP=160_000` ✓，比 100 MHz 时代更宽松）、
  `sd_ncs = init_cs_n & rd_cs_n` 且 reader 空闲时 `cs_n=1`（前导期不会被误拉低 ✓）、
  `S_ERROR + restart → S_INIT` 会重跑初始化（KEY1/KEY2 都是真重试 ✓）、
  总线归属用 `sd_ready` 而非 `init_done`（避免重跑时 SPI 被错划给 reader ✓）。
  ⇒ 指向**硬件侧**：卡座接触 / 卡本身 / 供电（初始化在**最慢**的 400 kHz 上失败，
  更像"卡根本没应答"而不是速率问题）。
- **快速重试法**：卡在 `S_ERROR` 时按 **KEY2**（`restart` 会回 `S_INIT`）即可重跑初始化，
  不必断电；连按并盯串口，统计 `SD=1 CARD=1 CNT=4` 出现频率。
- ★ **诊断缺口（待办）**：状态行只报 `EC`，不报 `err_detail` ⇒ 分不清是
  `0x11`（CMD0/CMD8/ACMD41 协商失败）、`0x21`（响应超时）、`0x22`（CRC16）、`0x23`（token）。
  若硬件排查不能解决，下一步是把 `err_detail` 加进状态行（需同步改 spec/TB）。

### 3. ~~修 `mem→mem` 硬违例~~ → ✅ **已收口**（2026-10-06 深夜，见上文终态数据）

### 3b. 遗留的约束开放项（低优先级，但别忘）

✅ **slot_sys 打包载荷 max_delay 已修复并验证命中**（2026-10-06 深夜，见上文）：
`-from` 改 `get_regs` 点名真实源寄存器，cecut3 `route.exceptions` **Total=1 命中**、
0 违例（SWNS +6.269/+6.529 ns）⇒ 换帧前提"载荷 1 个 sys 周期内到达"首次真正受约束。
遗留小疑问：该约束 `Total=1 / Dominated=100%` 的语义（detail 里 2 个端点、统计 1 Paths）
未逐字考证 —— 不影响结论，留待后查。

`board_cdc.sdc` 复位段三条 `-from [get_clocks ...]` 形式的 `set_false_path`
（fetch_mem_reset / fetch_pixel_reset / asy_r_rst*）与 slot_sys 曾落空的 max_delay 是
**同一类解析时刻问题**（TD 时钟对象 read_sdc 时不存在）。它们现在的实际行为
（豁免过宽/豁免为空）未逐一核实 —— 本次**刻意不动**（改了会动分析面，需单独一轮
核查+STA）。处理时照 slot_sys 的定责方法：`route.exceptions` 查 Total>0 +
`write_verilog` 网表连通性 + 探针，一次订正一类。

### 4. 其他并行待办（别忘了）

| 事项 | 说明 |
|---|---|
| **推 `backup/card-to-screen-merge`** | ✅ **已推送**（2026-10-06 15:1x，网络恢复后 push + `ls-remote` 核实，远端 `2e97790`）；A 可直接拉参考 |
| 工作树未提交 | 按项目约定"没有明确要求不自动提交" ✓ |
| SDRAM 硬核 −6.826 ns | 归厂商、以实测判定；若要彻底收敛需换封装外 SDRAM 或降 mem_clk |

---

## ★ 开发方针（用户明确要求，务必遵守）

> **优先复用厂商例程与安路官方 IP 核；不要自研已被官方 IP 覆盖的通用件；自研只留业务逻辑。**

已经照此纠正过：**自研异步 FIFO 撤掉，改用官方 `a_pixel_fifo`** ✓
（自研踩过两个真坑：Cummings 判满结构的组合环；TB 核对与寄存输出错位一拍）

---

## ★ 本次踩过的坑（同类别再犯代价很高，务必记住）

1. **边沿检测写反**：`sync[2] && !sync[1]` —— 第 2/3 级同一拍一起变 1 ⇒ **永不触发**。
   正确写法：`sync[1] && !sync[2]`（2 级同步 + 第 3 级做延迟沿检测）。
2. **位宽拼接静默截断**：`reg [1:0] x;` 写 `x <= {x[0], bus2};` —— 3 位拼进 2 位，
   结果只剩 `bus2`。**多 bit 总线同步必须用够位宽**（2 位 × 2 级 = 4 位），或分开两级 reg。
3. **同一 net 被两个 always 驱动**：ModelSim 只告警，**TD 直接报 `HDL-8007` 并置黑盒 ⇒ 综合失败**。
4. **端口没接出去**：内部 wire 声明了但从未赋值（悬空），仿真里表现为 x。
5. **跨域"能直连"是幻觉**：先查清对方寄存器到底在哪个时钟域（本例 `frame_swap_ctrl` 在 **sys**，不在 mem）。
6. **别在 mem 域组合地读 50 MHz 域的寄存器**（哪怕只是 UART 状态行）—— 55 条违例 + 真 CDC。
7. ★★ **"超时"要分清是"总时长"还是"无进展"**：`S_WRITE` 写成按总时长计（400 ms），
   而真实一帧要 ~600 ms ⇒ **每帧都被中途掐断**。**仿真跑得快反而掩盖了它**
   （既有 TB 把 SPI 分频调到最快档，一帧只要 236 ms < 400 ms）。
   ⇒ 凡是"等外部数据流"的超时，一律按**无进展**计。
8. ★ **TB 里用 `task` + `@(posedge)` 做 valid/ready 推送容易静默丢字**：
   "沿前采样 ready、沿后盲目撤 valid"在 ready 恰好掉下去的那一拍会丢。
   本 TB 因此让桥少收 14604 个字（推 153600、只收到 138996）。
   ⇒ 用**时钟化驱动器**：只在 `(valid && ready)` 的那一拍才前进到下一个字。
9. ★★ **"先用后声明"是隐式网的雷**（本项目已记录过，这次又踩）：
   `safevision_top.v` 里 `card_mode`/`mode_cnt`/`rbyte_c` 先用后声明 ⇒
   **ModelSim 直接编译不过**（`Undefined variable` + `already declared`）；
   按隐式网规则还会**另建一根未驱动的 1 bit 网**，与后面的 reg 不是同一个对象。
   TD 恰好容忍了这种写法，所以一直没暴露。
   ⇒ **所有 `reg`/`wire` 必须先声明再使用**；这条在 `sd_bmp_player.v` 文件头早就写了。
10. ★★ **消抖写成 `(cnt==MAX) && level` 会被"空闲期饱和计数"绕过**：
   空闲时电平稳定 ⇒ 计数器早已饱和，按下那一拍条件立刻为真 ⇒ **消抖窗被整个跳过**。
   ⇒ 用 **else 链**把"锁存输出"挂在"计数器满"那一支上，输出只在**新电平稳定满窗**后更新。
11. ★ **TB 里的"监视器"比被测信号晚一拍**：`always @(posedge clk) if (sig) flag<=1;`
   在下一个沿才置位，而 TB 常在同一时刻就检查 flag ⇒ 误判"没发生"。检查前先放几拍。
12. ★★ **打包跨域：载荷不能和事件脉冲"同拍"捕获**（缺陷 22，2026-10-06 复核抓到）：
   `if (tog_sync[2]^tog_sync[1]) payload <= ...;` + `wire evt = tog_sync[2]^tog_sync[1];`
   ⇒ 接收方在 `evt` 有效那一拍看到的是**上一帧的载荷**（复位后第一帧 = 初始值）。
   后果两级：① 首帧请求被对端 `evt && crc_ok` 的门条件直接丢掉（单帧场景 = 永不显示）；
   ② 此后每帧都挂着上一帧的 slot/generation（显示滞后一帧、双缓冲错位 ⇒ 写进正在
   显示的槽 = 撕屏）。**正确写法：载荷比事件早一拍捕获**（用 `[1]^[0]` 那级异或），
   或把事件打一拍再用。★ 隐蔽点：10-05 上板能点亮是因为当时 `wr_crc_ok` **硬接 1'b1**，
   改成真载荷后才暴露 —— "以前是好的"证明不了"重构后还是好的"。
   ★ 同类还有一个 SDC 版：`set_max_delay -from [get_regs {prod_slot* ...}]` 的
   `prod_*` 是 **wire（mux 输出）**，`get_regs` 匹配为空、约束静默落空；要约束到
   真实源寄存器（**注意：2026-10-06 深夜证实"改用时钟源形式 `-from [get_clocks ...]`"
   这条老建议是错的**，见 #13 —— 可靠写法是 `get_regs` 点名真实源寄存器）。
13. ★★ **SDC 里 `-from [get_clocks ...]` 在 read_sdc 解析时刻静默落空**（defect 23
   家族新病例，2026-10-06 深夜定责）：TD 的时钟对象要到 `update_timing` 才实体化，
   read_sdc 刚执行完时 `get_clocks` 连 board_clk 都返回空（probe10 实证）；
   `get_regs` 则在解析时刻就能解析（probe11）。slot_sys 打包载荷 max_delay 因此
   **历次 route.exceptions Total=0**，"载荷 1 个 sys 周期内到达"的换帧前提从未被验证。
   ⇒ 铁律：**任何约束都要到 `route.exceptions` 查 Total>0 才算生效**——
   `route.check` 的 invalid-constraint 检查抓不到这种落空（它只抓 get_regs 空集）。
   ⇒ 修法：`-from` 用 `get_regs` 点名真实源寄存器（综合吸收的用别名/网表尸检找真名）。
14. ★ **TD 探针卫生**（本次踩了三个）：① 脚本错误会掉进 `td >` 交互 REPL 干等
   （表象=挂死，如 probe3 卡 18 分钟）⇒ **一律 `td_commands_prompt.exe x.tcl < /dev/null`**；
   ② Tcl 双引号里的 `[..]` 会被命令替换（`puts "clkc[1]"` 直接炸）⇒ 标签用花括号、
   方括号用 `[format %c 91]` 构造；③ `font8x16_rom.v` 的 `$readmemh` 需要
   **`font8x16.mem` 在 CWD**（td_flow.tcl 是 copy+`cd $out` 处理的）——探针复刻流程
   时必须照做，否则 HDL-8007 黑盒中断。
