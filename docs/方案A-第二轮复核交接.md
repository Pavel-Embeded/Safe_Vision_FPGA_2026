# 方案 A · 第二轮复核交接（给下一个会话）

> **用途**：第一位实现者交付了方案 A（见 `方案A-代码审查指引.md`），第二位审查者（2026-10-06）
> 独立复跑了全部闸门、通读三个关键文件，**修掉 2 个新缺陷**，并查明"未查清项"的根因。
> 本文件是当前最新状态锚点：**先看这里**，再看 `B链-方案A-续做入口.md`（已同步）。
>
> **一句话状态**：仿真世界全绿（G1–G4 + 顶层 40 项）；**板级 STA 的 `mem→mem` 已收口**
> （P1/P2 两刀结构切分后，cecut1/cecut2 最坏 **+0.267 ns**、cecut3 +0.249、fix24 +0.247、
> retry/misopu +0.173 —— 跨运行判据 ≥ +0.1~0.2 ns 达成，详见 §3）。
> ★ 2026-10-06 深夜后续：缺陷 24（目录项字节序）、25（`ent_key` 位宽截断）、
> 26（初始化重试沉降窗）、以及上板补强 A–E 见 `B链-方案A-续做入口.md` §2a/§2b。

---

## 1. 状态总表

| 项 | 状态 | 证据 |
|---|---|---|
| 方案 A 本体（SD 卡 BMP → HDMI，链跑 50 MHz） | ✅ 完成 | 闸门 1–4 独立重跑全过（17/17、sink 全过、顶层全过、回归 **657/0**） |
| 缺陷 22 🔴：换帧载荷 off-by-one | ✅ **已修 + 仿真验证** | §2.1；`tb_safevision_top` 新增 T7×3（31→**34 项**） |
| 缺陷 23 🟡：SDC `max_delay` 静默落空 | ✅ **已修 + STA 验证** | §2.2 |
| **缺陷 24 🔴：目录项首簇号按大端装配** | ✅ **已修（待上板复测）** | §2.3；卡→屏链首次上板抓到的根因 |
| ★ **`mem→mem` 时序** | ✅ **已收口**（P1/P2 切分；跨运行最坏 +0.173 ns / 0 违例） | §3；`board_verify_cecut1/2/3`、`fix24`、`retry`、`misopu`、`r1` |
| 缺陷 24/25/26 | ✅ 已修（字节序 / `ent_key` 截断 / 重试沉降窗） | `B链-方案A-续做入口.md` §2b |
| 上板验证 | 🟡 进行中：SD 链已跑通，**显示侧未出图**（`RD≫PX` 待查） | `evidence/board/INDEX.md` SVPLAY-CAP-01..03 |

---

## 2. 本轮已修的两个缺陷（**勿再动**，有断言/约束守着）

### 2.1 缺陷 22 🔴：mem→sys 换帧打包跨域，载荷与事件**同拍**捕获

**位置**：`safevision_top.v` 的 `tog_sync` 块。**现象**：`frame_swap_ctrl` 在
`frame_ready` 有效拍判 `frame_ready && wr_crc_ok` 时，`crc_sys` 还是**上一帧**的值
（复位后 = 0）⇒ 复位后第一帧请求被丢（回落单帧 = 永不显示）；此后每帧挂上一帧的
slot/generation ⇒ 显示滞后一帧、双缓冲错位（sink 写进正在显示的槽 = 撕屏）。

**根因写法**（错误）：

```verilog
if (tog_sync[2] ^ tog_sync[1])  crc_sys <= prod_crc_ok;  // 载荷捕获
wire frame_ready = tog_sync[2] ^ tog_sync[1];            // ← 与事件同拍！
```

**修复**：载荷提前一拍捕获（`tog_sync[1] ^ tog_sync[0]`），`frame_ready` 定义不变。

**怎么实锤的**（方法比结论更值得学）：
1. 原实现者记录 `fr_pulses=1 / swap_state=0 / swap_error=0 / active=0`，怀疑 SDRAM 桩。
2. 探针 TB 加两个监视器：`vs_pulses`（数 `core.display.scan_frame_start`）、
   `pending_seen`（看 `core.display.slot.pending`）。结果 **`vs_pulses=3 而 pending_seen=0`** ——
   垂直消隐来了 3 次 pending 都没置起 ⇒ 排除"仿真窗口不够"。
3. 推理链：`pending=0` + `swap_error=0` ⇒ `swap_req` 从未翻转 ⇒ `swap_ctrl` **从没离开过 IDLE**
   （`swap_state=0` 是"没走过"，不是"走完了"——若走过又卡住，50 ms 超时必置 `swap_error`）。
4. `git diff 6716de8`：10-05 上板能亮是因为 `wr_crc_ok` **硬接 1'b1**；方案 A 改成真载荷
   `crc_sys` 才暴露 ⇒ **"以前上板是好的"证明不了"重构后还是好的"**。

**验证**：修复后 T7 断言 `active=1`（提交后首个 `frame_start` 置起，244397 clk），
`swap_error=0 / frame_fault=0 / led[2]=1` ⇒ SDRAM 桩的嫌疑**彻底排除**。

### 2.2 缺陷 23 🟡：SDC `set_max_delay` 的 `-from` 匹配为空（约束静默落空）

**位置**：`board_cdc.sdc`。原写法 `-from [get_regs {prod_slot* prod_gen* prod_crc_ok}]` ——
`prod_*` 在顶层是 **wire（mux 输出）**，`get_regs` 匹配不到任何寄存器 ⇒ 约束静默落空
（与缺陷 14 的 `*/*.sr` 只匹配两级名**同一类**：TD 对空集合**不报错**）。

**修复**：改时钟源形式 `-from [get_clocks {system_pll/pll_inst.clkc[1]}]`
（mem 域所有寄存器 → `slot_sys*/gen_sys*/crc_sys`，精确覆盖载荷路径）。

**验证方法**（下次复核 SDC 照这个做）：
- 改前：存在 `clkc[1]→clkc[0]` 普通分组（2 端点）；改后：该分组**消失**（路径移入 SMD 例外）；
- TD 的规则：**SMD/SMCP 的 slack 只进全局 Timing Status、不进 Clock Summary 分组**；
- 对账：全局 STNS = −300.677 = −218.432（clkc[2]→clkc[1]）− 81.973（clkc[1]→clkc[2]）
  − 0.272（mem→mem 3 端点）⇒ **分毫不差，证明 SMD 路径 0 违例**。

### 2.3 缺陷 24 🔴：目录项 FstClusHI/LO 按**大端**装配（真卡上首簇全错）

**位置**：`rtl/storage/fat32_directory_scanner.v` 的目录项装配 case（原第 267-270 行）。

**现象**（2026-10-06 卡→屏链**首次上板**，UART 状态行）：
`SV-PLAY ST=A FS=7 EC=03 SD=0 CARD=0 CNT=4 CUR=0 RD=0x37 PX=0 F=0 SLOT=0 CRC=0`
—— 首幅（槽 0 = SV0001，好图）在 `bmp_parser` 头校验处被拒（`RD=55` ≈ 54 字节头读完即判），
**不是**用户故意做坏的 SV0005（它被"取前四"规则落榜、从未被读）。

**根因**：FAT32 目录项里 `DIR_FstClusHI`(0x14-0x15) / `DIR_FstClusLO`(0x1A-0x1B) 是**小端**，
RTL 却写成大端（低偏移进高半）：

```verilog
// 错（原）：      5'd26: fc_l[15:8] <= sd_data;  5'd27: fc_l[7:0] <= sd_data;
// 对（现）：      5'd26: fc_l[7:0]  <= sd_data;  5'd27: fc_l[15:8] <= sd_data;
```

真卡（Windows 小端）上首簇全部字节交换 ⇒ 文件数据地址全错。**实卡指纹**（可复核）：
阶段 6 报告的 5 个首簇 `0x0600/0xE800/0xCA01/0xAC02/0x8E03` 按 16 位交换即
`6/232/458/684/910` —— 差值恰为 **226 簇 = ceil(1801/8)**，是真实 FAT32 顺序分配的形态；
而 SV0001 真簇 232 被算成 59392 ⇒ 数据读地址从卷 LBA 34608 偏到 507888 ⇒ 读回垃圾。

**为什么全部闸门都绿**（关键教训）：
- `verification/models/sd_spi_card_model.sv` 的 `mk_dir_entry` 用了**同一个错误字节序**
  （`off+26 = first_clus[15:8]`）⇒ 模型与 RTL 的错**互相抵消**，TB 全过；
  与"`\r\n` 转义在 TD/ModelSim 里同样错、老 TB 用同一错误构造期望值"是**同一类**漏网。
- 阶段 6 板级验收（M-10）**只报目录项、不用首簇取数** ⇒ 打印出的（交换后）值照样"对"；
  且该基准的 `first_clus` 段本来就是"待上板报告回填"，回填的是**板子自己的输出** ⇒ 自证循环。
- `tb_fat32_directory_scanner` 虽用了字节不对称的簇值（100/200/900/700），但因模型同错而失效。

**修复**（两处必须一起改，否则 TB 又变成"守着同一个错"）：
1. `fat32_directory_scanner.v`：`fc_h/fc_l` 两字段改回**小端**（低偏移进低半）；
2. `sd_spi_card_model.sv`：`mk_dir_entry` 改成按规范小端写 —— **改完后 TB 才真正能守住这个字段**
   （若 RTL 再退回大端，`tb_fat32_directory_scanner` 会立刻失败）。

**复测**：重新综合/布线出位流 → 同卡上板 → 期望 `ST` 离开 `A`、`PX/F` 递增、屏幕出图。

---

## 3. ✅ 已收口：`mem→mem`（历史上曾是 −0.163 ns / 3 端点）

> **收口结论（2026-10-06 深夜）**：P1（`memory_arbiter` 授权事件迟一拍结算）+
> P2（`frame_writer` CRC 源侧载荷寄存 `crc_pair_q`）两刀结构切分后，
> cecut1/cecut2 最坏 **+0.267 ns**（两次逐条一致）、cecut3 +0.249、fix24 +0.247、
> retry/retry2/misopu +0.173 —— **跨运行最坏 ≥ +0.1~0.2 ns 判据达成**。
> 后续 `board_verify_r1` 出现 +0.030 ns（换到 `fb_writer` 的 CRC 族）⇒
> **待办：给 `fb_writer` 做同款 P2 切分**（详见 `B链-方案A-续做入口.md` §2b）。
> 下面 3.1/3.2 保留**当时**的现场与处方，作为"怎么切的"的记录。

### 3.1 事实（当时）

- 当前 RTL（含缺陷 22 修复）下**两次 STA 运行数值完全一致**（PnR 确定）⇒ 是真违例，不是噪声。
- 路径：`core/display/fetch/fifo/fifo/wr_addr_diff_reg[2]` → `core/arbiter/cur_addr_reg[17].a[0/a1]`
  （数据路径 7.883 ns / 预算 8.0，**Logic Level 7、ADDER=4、net 占 50%、扇出 38**）。
- **这条不是 skid 修的 CRC 路径**。同族路径在原实现者自己的 qa2 运行里已有 7.406 ns
  （`wr_addr_diff_reg[2] → arbiter/consec_cnt_reg[0].ce`，LL6/ADDER=4）⇒ **这族路径一直贴着预算**，
  skid 只修了 CRC 那一条，这族是"下一张多米诺"。
- 历史轨迹：skid 修复后 +0.118 / +0.118 / +0.009（0 违例）→ 本轮 −0.163（3 端点）。
  任何无关 RTL 改动引起的布局抖动都能把它打负 ⇒ **必须真正加余量，不能靠跑运**。

### 3.2 修复处方（已备好，未实施）

**链的构成**（全部组合串联）：

```
a_pixel_fifo 内部 wr_addr_diff（占用量寄存器）
  → wr_words 输出逻辑（FIFO 内部）
  → guarded_level = {fifo_words,1'b0} + (half_pending?1:0) + 4   （a_frame_fetch_bridge.v:71-72，2 个加法器）
  → video_read_dma：fifo_has_space / < LOW_WATER 比较 + rd_addr 发起判决（V_CHECK 态）
  → rd_req → memory_arbiter/cur_addr.ce
```

**处方**：在 `a_frame_fetch_bridge.v` 把 `guarded_level` **寄存一拍**（mem_clk 域），
寄存版同时喂 `.pix_fifo_level(...)` 和 `fifo_mem_pixels`（后者还送给 arbiter 的
`video_fifo_level` 防饥饿输入）。链条一刀两断，两半都远低于 8 ns。

**为什么安全**（已核实，不是拍脑袋）：
- `video_read_dma` 只用 `pix_fifo_level` 做**水位启发式**（`video_read_dma.v:89,164`：
  `< LOW_WATER` 且 `<= PIX_DEPTH−BURST_WORDS*2`）—— FIFO 1024 word、突发 64 word，
  滞后巨大；`guarded_level` 本来就带 `+4` 保守余量，再多 1 拍滞后完全在余量内。
- arbiter 的 `video_fifo_level` 是防饥饿**优先级**启发式，同样不怕 1 拍滞后。

**改动面**：`a_frame_fetch_bridge.v` 一个 always 块 + 两处引用改名（~6 行）。
★ **注意该文件是 A 的模块**（A/B 边界），改完必须跑 A+B 联调仿真，别只跑 B 的回归。

**验证流程**（按项目纪律）：
```powershell
$env:MSIM_BIN='D:\modeltech64_10.7\win64'
safevision\tools\run_sim.ps1                  # 期望 TOTAL PASS=657 FAIL=0
safevision\tools\run_ab_display_sim.ps1       # A+B 显示链路（A 的文件改了必须跑这个）
safevision\tools\run_board_sta.ps1 -Mode base -RunDir "$PWD\safevision\build\out\<新目录>"
# ★ 判据：跨运行最坏 mem→mem SWNS ≥ +0.1~0.2 ns；至少跑 2 次、每次另存目录。
#   若修完最差路径"换人"了（挤在 0.1 ns 内的还有好几条），照同一节奏继续切，或写明理由收手。
```

**不要做的事**：① 不要把 `a_pixel_fifo` 的 `OUTREG_EN` 改成 `"OUTREG"`（FWFT→非 FWFT，
打断 sink 握手）；② 不要加 `set_false_path` 刷绿（项目规则明令禁止；要放宽只能用
有理由的 `set_multicycle_path`）；③ 不要顺手改 `frame_writer` / `video_read_dma` 的
状态机语义 —— 本处方只动 `guarded_level` 一处。

### 3.3 修完后的口径

`mem→mem` 达标（跨运行最坏 ≥ +0.1 ns）后，把 `B链-方案A-续做入口.md` 的
"mem→mem at-risk/翻负"段落和 `.workbuddy-ai/memory/MEMORY.md` 的对应行一起改掉
（两处都写着当前是 −0.163 真违例）。

---

## 4. backlog（按建议优先级）

| # | 事项 | 位置 / 说明 |
|---|---|---|
| 1 | **顶层"真卡"路径 TB 覆盖**（缺口 1，唯一的仿真真空） | `tb_safevision_top.sv` 加"卡可用" phase：复用 `tb_sd_bmp_player.sv` 的 `build_volume` 手法造 FAT32 卷；断言整链（卡 → 屏）在顶层环境走通 |
| 2 | player 打包器**帧尾冲刷** | `sd_bmp_player.v`：`have_lo` 残字无冲刷、跨帧不清 ⇒ **奇数像素 BMP** 会把残字拼进下一帧开头（640×480 是偶数不触发）。修法：`bpu_done` 时按 `have_lo` 补发最后一字（高半字补 0），进帧时清 `have_lo/hold_*` |
| 3 | `MODE_TO_N=300 ms` 对**慢卡**偏紧 | ACMD41 轮询最坏 ~1 s 的卡会被误判"卡不可用"且 `fb_go` 锁死到复位 ⇒ 上板带 2~3 张不同品牌卡；必要时放宽到 1 s |
| 4 | 消抖两处规范性改进 | `safevision_top.v`：① 窗口 1.31 ms 偏短（机械抖动常 5~20 ms）⇒ 计数器加宽到 18 bit（~5 ms）；② 异步按键先过两级同步器再进比较（当前直接用裸 `btn_next` 比较，亚稳态虽自纠但不规范） |
| 5 | 死代码 / 口径清理 | `sd_bmp_player.v`：`SWAP_TO_N` 已是死参数（`S_SWAP` 只停一拍）；`S_STREAM` 的 `STREAM_TO_N` 是**总时长**超时，与项目"等外部数据流一律按无进展计"的约定不一致（余量 5×，低风险） |

---

## 5. 上板验证（mem→mem 收口之后）

```powershell
safevision\tools\run_board_sta.ps1 -Mode base -Bitgen   # 出位流
# 注意：脚本把"任何违例"当 FAIL 抛出（有意的严格门禁）；64 个厂商硬核端点是既有项，看分组即可
```

插 **HDMI B** 口 → 看卡里的 BMP + UART 状态行（★ 2026-10-06 起为 **96 字节**定长，
`SV-PLAY ST=x FS=x EC=xx SD=x CARD=x CNT=x CUR=x RD=xxxxxxxx PX=xxxxx F=xxxx SLOT=x CRC=x ED=xx`；
旧采集为 90 字节、无 `ED=`）：
- `ST/FS/SD/CARD/CNT/CUR/RD` 看 player；`PX/F/SLOT/CRC` 看 sink；
- `EC`：sink 优先（`0xF1`=换帧超时、`0xF2`=帧写超时），否则 player（`0xE1~E5`）；
- **回落验证**：不插卡上电 ⇒ 300 ms 后应显示片上测试图案（`led[1]/led[2]` 亮）——
  ★ 这正是缺陷 22 修复前**必然黑屏**的场景，是板上回归的第一检查点；
- **按键**：B2 下一幅（单拍脉冲）、C1 自动连播（电平）；S_ERROR 下按 B2 = 重新开始。

---

## 6. 验证入口速查（本机可跑）

```powershell
$env:MSIM_BIN='D:\modeltech64_10.7\win64'
safevision\tools\run_sd_bmp_player_sim.ps1   # G1 播放链：17/17 + 153600 words pixel-exact
safevision\tools\run_bmp_frame_sink_sim.ps1  # G2 sink 单元（真异步 50/125M）：断言全过
safevision\tools\run_top_verify_sim.ps1      # G3 顶层：34 项（含本轮新增 T7×3）
safevision\tools\run_sim.ps1                 # G4 B 主回归：TOTAL PASS=657 FAIL=0
safevision\tools\run_ab_display_sim.ps1      # A+B 显示链路（改 A 的文件后必跑）
safevision\tools\run_board_sta.ps1 -Mode base -RunDir <每次另存新目录>
```

STA 期望（修完 §3 之前）：`board_clk→board_clk` ≈ +3.3 / 0；`board_clk→clkc[1]` ≈ +2.8 / 0；
`clkc[1]→clkc[1]` **−0.163 / 3**（待修）；`clkc[1]↔clkc[2]` = −2.88/32 与 −6.826/32
（厂商封装内 SDRAM 硬核，既有项，64 端点）；载荷路径在 SMD 例外里 0 违例（对账法见 §2.2）。

---

## 7. 给下一个会话的三条提醒（本轮新交的学费）

1. **打包跨域（toggle + 载荷）：载荷必须比事件脉冲早一拍捕获**。
   `if(tog[2]^tog[1]) payload<=...; wire evt=tog[2]^tog[1];` ⇒ 对端在 evt 拍看到的是**上一帧**。
   用 `[1]^[0]` 级捕获，或把 evt 打一拍再用。（已并入续做入口踩坑 #12 与 MEMORY.md 约定 0）
2. **SDC 里 `get_regs` 的对象若是 wire（mux 输出）会静默匹配为空、约束落空且不报错**。
   写约束时点名真实源寄存器或用时钟源形式；复核方法 = 分组消失 + 全局 STNS 对账（§2.2）。
3. **判活要看过程信号（pending/ack/计数器），不能只看终态**：
   `swap_state=0` 既可能是"走完了"也可能是"从没走过"；本轮正是靠 `pending_seen=0`
   把"没走过"实锤出来的。
