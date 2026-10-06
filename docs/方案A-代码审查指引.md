# 方案 A 代码审查指引（给下一个会话/审查者）

> **用途**：这是一份**审查地图**，不是结果汇报。开新对话时把本文件 + 下面列的源文件一起给模型，
> 它就能按图索骥地检查我的改动。
>
> **本次工作**：把 "SD 卡 BMP → HDMI" 播放链从 125 MHz 的 mem 域搬到**板载 50 MHz 域**（方案 A），
> 并补齐此前缺失的仿真覆盖。
> **时间**：2026-10-06
> **状态**：两个仿真闸门全过；板级 STA 的 50M 侧全清、**mem 域已收敛**；顶层仍有一项未查清（见 §5）。

---

## 0. 一分钟看懂改了什么

```
                    ┌──────────── 板载 50 MHz (R7) ────────────┐
SD 卡 ──SPI──► sd_bmp_player ──32 位打包像素──┐                 │
                （媒体链：FAT32/BMP 解析）      │                 │
                                              ▼                 │
                                  官方 a_pixel_fifo             │  ← 真正的跨域点
                                  （写 50M / 读 125M）           │
                                              │                 │
              ┌──────────── 125 MHz mem 域 ───▼──────────┐      │
              │  bmp_frame_sink                         │      │
              │    = 官方 FIFO + A 的桥 + 自研帧控制器    │◄─────┘
              │    → wr_* 给 core 的 memory_arbiter      │  mem_ready / frame_done
              │    → swap_* 打包到 sys 域               │  （两级同步）
              └─────────────────────────────────────────┘
```

**为什么这么改**：这条媒体链原本就是按 50 MHz 设计并 STA 过的；塞进 125 MHz 后
链内长路径（88 位目录名解码＋十进制乘法、`bmp_unpack` 乘法器、LBA 计算）在 8 ns 预算下过不去。

---

## 1. 怎么复现我声称的每一件事

```powershell
$env:MSIM_BIN='D:\modeltech64_10.7\win64'

# 闸门1：播放链（player + sink 串联，同频）—— 期望 17/17 PASS + "153600 words pixel-exact"
safevision\tools\run_sd_bmp_player_sim.ps1

# 闸门2：sink 单元 TB（★ 真实异步 50M/125M 双时钟）—— 期望 26 项断言全过
safevision\tools\run_bmp_frame_sink_sim.ps1

# 闸门3：顶层 TB（★ 此前顶层零覆盖）—— 期望 SAFEVISION-TOP PASS
safevision\tools\run_top_verify_sim.ps1

# 闸门4：B 主回归 —— 期望 TOTAL PASS=657 FAIL=0
safevision\tools\run_sim.ps1

# 闸门5：板级 STA（综合+布局布线+STA）。★ 注意：脚本把"任何违例"当 FAIL 抛出，这是**有意的严格门禁**；
#        真正要看的是 base/route.timing 的分组数据。默认 -RunDir 会覆盖，建议每次另存目录。
safevision\tools\run_board_sta.ps1 -Mode base -RunDir "$PWD\safevision\build\out\sta_check"
```

**STA 期望结果（`sta_check/base/route.timing` 的分组）**

| Path Group | SWNS | 违例端点 | 说明 |
|---|---|---|---|
| `board_clk → board_clk` | ≈ +3.0 ns | **0** | 50 MHz 媒体链（方案 A 的目的） |
| `board_clk → clkc[1]` | ≈ +3.0 ns | **0** | 方案 A 新引入的 50M→125M 交叉 |
| `clkc[1] → clkc[1]`（mem→mem） | ≈ +0.12 ns | **0** | ★ 由 §3-16 的 skid 修复清掉 |
| `clkc[2] → clkc[1]` | **−6.826 ns** | 32 | 厂商封装内 SDRAM 硬核读回，**既有项** |
| `clkc[1] → clkc[2]` | ≈ −3.6 ns | 32 | 同上（写路径） |

**全局残余 64 个违例端点应全部落在 `memory_ip` 内部**（Logic Level 0~1、cell 占比极高）。

---

## 2. 改动清单（文件 → 改了什么）

| 文件 | 改动 |
|---|---|
| `safevision/rtl/storage/sd_bmp_player.v` | 时钟域改 50 MHz；参数 `CLK_HZ_MEM`→`CLK_HZ`(50M)；`CLK_DIV_INIT=62`/`CLK_DIV_FAST=0`；超时按 50 MHz 重算；像素出口改 **32 位** `px_word/px_word_valid/px_word_ready`；`mem_ready`/`frame_done`/`last_frame_ok` 三路两级同步；行序改在 `bmp_check_done` 锁存；`fd_pending` 只在 `S_STREAM` 有效 |
| `safevision/platform/.../rtl/bmp_frame_sink.v` | **新增**。官方 `a_pixel_fifo`（写 50M/读 125M）+ A 的 `bmp_frame_write_bridge` + 自研帧控制器 + **1 级 skid** |
| `safevision/platform/.../rtl/safevision_top/safevision_top.v` | player 挂 `clk`+`ref_rst_n`；sink 挂 `mem_clk`；按键消抖搬到 50 MHz 域并**重写**；UART 的 PX/F/SLOT/CRC 改指 sink；**新增遥测两级同步层 `t_*`**；`card_mode` 守卫；**声明顺序修正**；`RPT_PERIOD_N` 参数化 |
| `safevision/verification/unit/tb_sd_bmp_player.sv` | 重写为 player + sink 串联 |
| `safevision/verification/unit/tb_bmp_frame_sink.sv` | **新增**。sink 单元 TB，双自由时钟（50M/125M） |
| `safevision/verification/unit/tb_safevision_top.sv` | **新增**。顶层 TB（此前零覆盖） |
| `safevision/verification/models/top_ip_stub.sv` | **新增**。视频 PLL / HDMI 发送核 / TMDS 串化器 三个厂商 IP 桩 |
| `safevision/tools/run_bmp_frame_sink_sim.ps1` | **新增** |
| `safevision/tools/run_top_verify_sim.ps1` | **新增** |
| `safevision/tools/run_sim.ps1` | RTL 清单加 `bmp_frame_sink.v` + `a_pixel_fifo` 三件；TB 清单加 `tb_bmp_frame_sink` |
| `project/board_verify/td_flow.tcl` | 源表加 `rtl/bmp_frame_sink.v` |
| `project/board_verify/board_cdc.sdc` | 加 50M↔125M 例外（同步器首级 false_path + FIFO 内部 Gray 指针 max_delay + 复位分发兜底） |

---

## 3. 本次发现并修掉的 21 个缺陷（**建议逐条复核**）

> ★ **后续新增缺陷（22–24）不在这张表里**，见 [方案A-第二轮复核交接.md](方案A-第二轮复核交接.md)：
> 缺陷 22（换帧载荷 off-by-one）、缺陷 23（SDC `max_delay` 静默落空）、
> **缺陷 24（目录项首簇号按大端装配 → 真卡首簇全错、卡→屏链首次上板失败）**。
> 缺陷 24 是"TB 与 DUT 同错互相抵消"的典型漏网，**复核外部格式字段时务必拿规范/真卡 dump 对**。

> 说明：🔴 = 会让综合/仿真直接失败或功能完全不可用；🟠 = 功能/时序/CDC 错误；🟡 = 可观测性/文档/约束。

### 3.1 方案 A 实现过程中暴露的（1–15）

| # | 文件 | 症状 | 根因 | 修法 |
|---|---|---|---|---|
| 1 🔴 | `bmp_frame_sink.v` | sink 永远出不了 `S_DRAIN`，字节全读完但**一帧都写不进去** | `fa_rise = fa_sync[2] && !fa_sync[1]` —— 第 2/3 级**同一拍一起变 1**，条件永不成立 | 改 `fa_sync[1] && !fa_sync[2]` |
| 2 🔴 | `bmp_frame_sink.v` | **槽号恒为 0**，整帧写错槽 | `reg [1:0] sl_sync;` 却写 `{sl_sync[0], slot}`（3 位拼进 2 位）⇒ 静默截断，`sl_sync[1]` 实际 = `slot[1]` | `reg [3:0]`，取 `sl_sync[3:2]` |
| 3 🔴 | `sd_bmp_player.v` | ModelSim 只告警；**TD 报 `HDL-8007` 并置黑盒 ⇒ 综合直接失败** | `fd_d`/`fd_pending` 被**两个 always** 驱动（既有老问题） | 复位只留在边沿检测块 |
| 4 🔴 | `sd_bmp_player.v` | 32 位打包字根本没出模块 | 只导出 16 位 `px`，内部 `wire px_word_ready;` **悬空未赋值** | 改 32 位端口 |
| 5 🟠 | `bmp_frame_sink.v` | 像素流**其实没跨域**（双时钟 FIFO 白用） | `a_pixel_fifo` 的 `wr_clk`/`rd_clk` 都接 `mem_clk` | 加 `wr_clk` 端口接 50 MHz |
| 6 🟠 | `safevision_top.v` | 真 CDC（sys→mem 跨域组合） | `swap_busy` 直接接 sys 域的 `swap_state_o`（**设计文档原写"可直连"是错的**） | 接已同步的 `swap_busy_mem` |
| 7 🟠 | `safevision_top.v` | TD 报 `board_clk→mem` **55 条违例**（最差 −1.77 ns、LL 6） | UART 状态行 / `card_mode` / LED 在 mem 域**组合地**读 50 MHz 的 player 寄存器 | 新增逐字段两级同步层 `t_*` |
| 8 🔴 | `bmp_frame_sink.v` | **板级每帧都被中途掐断**（只写 ~2/3，屏幕上"上 2/3 对、下 1/3 残留"） | `S_WRITE` 超时按**总时长**计（400 ms），而真实一帧要 ~600 ms | 改成**无进展**超时（`br_px_cnt != px_d` 就重新计时） |
| 9 🟠 | `bmp_frame_sink.v` | sink 永久卡在 `S_SWAP` | 超时判断藏在 `if(busy)… else if(seen)… else if(timeout)` 之后，`swap_busy` 恒高时**永不超时** | 超时判断**独立于** `swap_busy` |
| 10 🟠 | player + sink | **混合朝向的 BMP 静默竖翻**（CRC 只覆盖写入数据、抓不到行序错） | 开帧那拍取 `bmp_top_down`，但 `check_done` 是**单拍脉冲**、`top_down` 是**结果寄存器** ⇒ 拿到的是**上一幅**的值；且 player 把 `top_down_o` 与 `frame_active` **同拍**置起 | player 改在 `bmp_check_done` 锁存；sink 把**实时** `td_sync[1]` 交桥，桥在首像素捕获 |
| 11 🟠 | `sd_bmp_player.v` | 下一帧**一开帧就跳走**，`frame_cnt` 虚增 | `fd_pending` 只在进 `S_SWAP` 时清 ⇒ 空闲期多收一次 `frame_done` 会残留 | 只在 `S_STREAM` 内有意义 |
| 12 🟡 | `safevision_top.v` | 跨域沿检测漏/多一拍 | `card_mode` 可从回落态**再切回卡路径**，中途换掉生产者 toggle 源 | 加 `&& !fb_go` 守卫 |
| 13 🟡 | `bmp_frame_sink.v` | **板上看不到错误码**（只亮 ~64 ns，而状态行 500 ms 刷一次） | 退出 `S_ERROR` 即清零 | 改为粘滞到下一帧成功 |
| 14 🟡 | `board_cdc.sdc` | 一条复位路径被当**真 recovery 检查**报 **−3.94 ns 假违例**（预算仅 0.302 ns） | `-to [get_pins {*/*.sr}]` 只匹配**两级**名，顶层综合单元是一级（`add5_syn_104.sr`） | 补 `-to [get_pins {*.sr}]` |
| 15 🟡 | `safevision_top.v` | 消抖结果还要再跨一次域 | 按键消抖留在 mem 域，而 player 已在 50 MHz 域 | 搬到 player 时钟域 |

### 3.2 补覆盖/修时序时新抓到的（16–21）

| # | 文件 | 症状 | 根因 | 修法 |
|---|---|---|---|---|
| 16 🟠 | `bmp_frame_sink.v` | `mem→mem` **硬违例 −0.445 ns / 3 端点** | 官方 FIFO 是 FWFT + `NOREG` ⇒ `rd_data` 是 ERAM 的**组合输出**，直进桥的 4 级 CRC 组合链（`ramread0 → crc_src_*`，8.165 ns / 8.0 ns） | 在 sink 里加 **1 级 skid**（把读数据寄存一拍再给桥），保持 FWFT 语义 |
| 17 🔴 | `safevision_top.v` | **ModelSim 直接编译不过**：`Undefined variable: 'card_mode'` + `already declared`；且按隐式网规则会另建一根未驱动的 1 bit 网 ⇒ 卡/回落选择 mux 可能读到未驱动网 | `card_mode`/`mode_cnt`/`rbyte_c` **先用后声明** | 把声明移到首次使用之前 |
| 18 🔴 | `safevision_top.v` | 回落帧**写进去了却从不提交换帧**（屏幕上看不到、`led` 相应位不亮） | `fb_writer` 是 `.slot_sel(2'd0)`，`frame_writer` 只置 `slot_valid[0]`，但判断写的是 `fb_slot_valid[1]` ⇒ **永不成立** | 改 `fb_slot_valid[0]` |
| 19 🔴 | `safevision_top.v` | 按钮等于**被永久按住**：`btn_auto` 恒 1（连播停不下来）、`btn_next` 恒 1、`restart` 恒 1 | `btn_next_db = (dn_cnt == 16'hFFFF)` 只表示"电平稳定 65536 拍"，**按下和松开都为 1** | 改"稳定 **且** 按下"；`btn_next` 做**按下沿单拍脉冲**（player 端口注释就是"脉冲：下一幅"） |
| 20 🟠 | `safevision_top.v` | **消抖窗被整个绕过**（按下立刻出脉冲） | 空闲时电平稳定 ⇒ `dn_cnt` **早已饱和在 0xFFFF**，按下的那一拍 `(dn_cnt==0xFFFF) && btn_next` 立刻为 1 | 改成 **else 链**：`if(变了)清计数; else if(未满)累加; else dn_db<=电平`（只有"稳定满窗"才更新输出） |
| 21 🟡 | `safevision_top.v` | 文档与代码不一致（硬件上板时"LED 全亮"两种写法都成立，所以一直没暴露） | `led` 注释里的 `led[1]`/`led[2]` 说明与 `assign` **写反了** | 更正注释（**按代码实际**写，不改行为） |

---

## 4. ★ 请你重点审的地方（按风险排序）

### 4.1 我最不确定的：`safevision_top.v` 的遥测两级同步层

新增了 ~10 个字段的两级同步（`t_state1/t_state`、`t_fail1/t_fail`、`t_ec1/t_ec`、
`t_sd1/t_sd`、`t_card1/t_card`、`t_fok1/t_fok`、`t_fcnt1/t_fcnt`、`t_cur1/t_cur`、
`t_bytes1/t_bytes`、`t_fcnt16_1/t_fcnt16`）。

**请检查**：
- 有没有字段**漏同步**（mem 域还在直接读 50 MHz 域的 player 寄存器）？
  搜索方法：在 `safevision_top.v` 里找所有 `pl_*` 的引用，应当**只出现在 player 端口连接**和**同步块内部**。
- 位宽拼接有没有再次踩"静默截断"的坑？（本项目反复踩：`reg [1:0] x; x <= {x[0], bus2};`）
- 逐 bit 同步**不是原子快照**，`cur_bytes_rd`/`frame_cnt` 在值变化的 1~2 拍内可能被读到中间值 ——
  我判定这**只影响该次 500 ms 状态行的显示数值、无功能后果**，你同意吗？

### 4.2 sink 的 1 级 skid（缺陷 16 的修法）

```verilog
wire sk_ready = br_din_ready;
wire sk_load  = fifo_rd_valid && (!sk_valid || sk_ready);
wire br_din_valid = sk_valid && (state_o == S_WRITE);
// state_o != S_WRITE 时强制 sk_valid <= 0（丢弃）
assign fifo_rd_en = (state_o == S_WRITE) ? sk_load : fifo_rd_valid;
```

**请检查**：
- 会不会**丢像素**或**重复像素**？（我的 `tb_bmp_frame_sink` 有逐像素比对，但它只跑了两帧）
- `state_o != S_WRITE` 时清 `sk_valid` 是否足以保证**上一帧的残留像素不会进下一帧**？
- 有没有引入**组合环**（`sk_load` 依赖 `br_din_ready`，后者来自桥的组合输出）？

### 4.3 `S_WRITE` 改成"无进展"超时（缺陷 8 的修法）

```verilog
if (br_px_cnt != px_d) to_cnt <= 32'd0;   // 有进展就重新计时
else                   to_cnt <= to_cnt + 32'd1;
```
**请检查**：`px_d` 的更新时机（在主 always 的默认段 `px_d <= br_px_cnt;`）会不会导致
**误判无进展**或**漏判**？400 ms 的无进展门限是否合理？

### 4.4 行序（缺陷 10 的修法）—— 我改了 player 和 sink 两处

- player：`if (stream_kicked && bmp_check_done) top_down_o <= bmp_top_down;`
- sink：`.top_down(td_sync[1])` 直接给桥（不再在 `fa_rise` 锁存）

**请检查**：`bmp_check_done` 是否**一定**在第一个像素之前到达？（我的 TB 用两帧不同朝向验证了，
但那是合成场景。）如果某个 BMP 的头解析异常（例如 `check_error`），行序会怎样？

### 4.5 按键消抖（缺陷 19/20 的修法）

```verilog
if (btn_next != dn_s)        dn_cnt <= 16'd0;
else if (dn_cnt != 16'hFFFF) dn_cnt <= dn_cnt + 16'd1;
else                         dn_db  <= btn_next;    // 稳定满窗才更新输出
dn_db_d <= dn_db;
wire btn_next_db = dn_db & ~dn_db_d;   // 按下沿单拍脉冲
```
**请检查**：这个消抖对不对？65536 拍（1.31 ms @50 MHz）是否合适？
把 `btn_next` 从"电平"改成"脉冲"是否会破坏 player 的既有行为（`restart` 也接的它）？

### 4.6 `card_mode` 守卫

```verilog
if (t_card && !fb_go) begin card_mode <= 1'b1; mode_cnt <= 32'd0; end
else if (card_mode && !fb_go && t_fcnt16 == 16'd0) begin ... 超时回落 ... end
```
**请检查**：`fb_go` 作为"已经写出过东西"的判据是否充分？
（`fb_go` 在 `sdr_init_done && !fb_go` 时置 1，一旦置位永不清零。）

### 4.7 STA 的两个例外段（`board_cdc.sdc`）

- `set_false_path -to [get_regs {t_state1* t_fail1* ...}]`（遥测同步器首级）
- `set_false_path -from [get_clocks {board_clk}] -to [get_pins {*.sr */*.sr}]`（复位分发兜底）

**请检查**：第二条**是否过宽**？我判定"`board_clk` 域只有复位分发会驱动异步复位脚"，
所以实际效果精确；但如果将来新增 `board_clk`→异步复位脚的路径，会被**静默豁免**。

---

## 5. 我**没有**覆盖 / 没有证明的东西（别当成已验证）

1. **`safevision_top` 的"真卡"路径**：顶层 TB 用的是**卡不可用**场景（走回落）。
   顶层 + 真卡的 SD 初始化/挂载/整帧播放**没有被顶层 TB 覆盖**（由 `tb_sd_bmp_player` 在
   player+sink 层面覆盖）。
2. **`active`（显示激活）在本仿真环境里不置起 —— 未查清。**
   观测：`fr_pulses=1`（换帧事件确实跨域送达 core）、`swap_state=0`、`swap_error=0`、
   `frame_fault=0`、`active=0`。**怀疑**是 SDRAM 桩的读模型不满足显示取数路径，
   但**没有证实**。A 的 `tb_card_to_display` 覆盖了提交路径（断言 `commits=1 acks=1`），
   所以不是"没人管"，但**顶层环境下的这一环是空的**。
3. **HDMI/TMDS/DDC/EDID/PLL 全是桩**（`models/top_ip_stub.sv`）⇒ 不证明任何电气/协议层面的事。
4. **SDRAM 是理想存储器桩** ⇒ 不证明协议/时序/数据完整性。
5. **两个仿真 TB 都是功能验证**，不覆盖亚稳态、不覆盖真实时钟抖动。
6. `mem→mem` 的余量只有 **+0.118 ns**（两次独立运行数值一致）—— 过了，但**余量很小**。
7. 上板实测、HDMI 电气合规、显示器兼容、音频：**均未做**。

---

## 6. 证据在哪

| 内容 | 位置 |
|---|---|
| STA 报告（**已修 mem→mem**，两次独立运行） | `safevision/build/out/board_verify_skid/base/`、`board_verify_skid2/base/` |
| STA 报告（修 skid 之前的对照） | `safevision/build/out/board_verify_tb2/base/` |
| STA 报告（QA 独立复现，证明"给定输入 PnR 是确定的"） | `safevision/build/out/board_verify_qa/base/`、`board_verify_qa2/base/` |
| 播放链日志 | `safevision/build/out/sd_bmp_player/sd_bmp_player.log` |
| sink 单元日志 | `safevision/build/out/bmp_frame_sink/bmp_frame_sink.log` |
| 顶层日志（含 UART 状态行） | `safevision/build/out/top_verify/safevision_top.log` |
| 接口契约 + 缺陷表 + 已知局限 | `docs/B链-板级顶层HDMI验证报告.md` **§12** |
| 续做入口（含 10 类踩坑） | `docs/B链-方案A-续做入口.md` |

---

## 7. 建议的审查顺序

1. **先跑闸门 1–4**（`run_sd_bmp_player_sim` / `run_bmp_frame_sink_sim` / `run_top_verify_sim` / `run_sim`），
   确认它们真的 PASS（不要相信本文件的转述）。
2. **读 `bmp_frame_sink.v` 全文**（~330 行）—— 方案 A 的核心新模块，21 个缺陷里有 6 个在它里面。
3. **读 `sd_bmp_player.v` 的 S_STREAM / 边沿检测 / 打包器**三段。
4. **读 `safevision_top.v` 的**：遥测同步层、sink 例化、按键消抖、`card_mode`、`led`。
5. **跑一次 STA 到独立目录**，核对 §1 的分组表。
6. **最后看 §5**，确认我没有把"没验证的"说成"已验证的"。

---

## 8. 一句话总结

方案 A 的**架构判断是对的**（把媒体链放回它原本的 50 MHz 口径），
但**实现里埋了很多"看起来对、其实不工作"的东西**（21 个，其中 6 个会让功能完全不可用）。
我怀疑**还有**同类型的坑没被找到 —— 特别是"声明顺序/隐式网"和"跨域组合读"这两类，
它们在本项目里已经反复出现。**请重点往这两个方向扫。**

---

## 9. 复核结论（2026-10-06，第二位审查者实跑 + 读码）

### 9.1 闸门复核：全部属实 ✓

独立重跑（不信转述）：闸门 1 **17/17**（153600 words pixel-exact）、闸门 2 全过、
闸门 3 全过、闸门 4 **TOTAL PASS=657 FAIL=0**。与本文档声称一致。

### 9.2 ★ 新抓到 1 个 🔴 缺陷（第 22 个）—— 就是 §5.2 的"未查清项"

**`active` 不置起的根因不是 SDRAM 桩，是顶层 mem→sys 打包跨域的载荷 off-by-one：**

```verilog
if (tog_sync[2] ^ tog_sync[1]) begin  slot_sys/gen_sys/crc_sys <= prod_*;  end
wire frame_ready = tog_sync[2] ^ tog_sync[1];   // ← 与载荷捕获同拍
```

`frame_swap_ctrl` 在 `S_IDLE` 的门条件是 `frame_ready && wr_crc_ok` —— 事件脉冲有效的
那一拍，`crc_sys` 还是**上一帧的值**（复位后 = 0）⇒
- 复位后**第一帧的请求被直接丢掉**（回落单帧场景 = **永不显示**，正是 §5.2 观测到的
  `fr_pulses=1 / swap_state=0 / swap_error=0 / active=0` —— `swap_state=0` 不是"走完了"，
  是**从没离开过 IDLE**）；
- 此后每帧都挂着**上一帧**的 slot/generation ⇒ 显示滞后一帧、双缓冲错位
  （sink 会写进正在显示的槽 = **撕屏**）。

★ 用探针 TB 实锤：`vs_pulses=3 而 pending_seen=0` —— 垂直消隐来了 3 次 pending 都没置起，
排除"仿真窗口不够"；`swap_error=0` + `pending=0` ⇒ 请求在 sys 域门口被拒。

★ **为什么 10-05 上板是亮的**：提交 `6716de8` 里 `wr_crc_ok` **硬接 1'b1**、slot/gen 也硬接，
载荷差一拍无所谓；方案 A 把它改成真载荷 `crc_sys` 才暴露。**"以前是好的"证明不了"重构后还是好的"。**

**修复**（已实施 + 验证）：载荷捕获提前一拍（`tog_sync[1] ^ tog_sync[0]`），
`frame_ready` 不变 ⇒ `swap_ctrl` 在事件拍看到新载荷。修复后顶层 TB 新增 **T7×3 断言**
（pending→active→`led[2]`，31→**34 项**）：`active=1` 在提交后第一个 `frame_start` 置起，
`swap_error=0 / frame_fault=0`。

### 9.3 ★ 新抓到 1 个 🟡 SDC 缺陷（同类"静默落空"）

`set_max_delay -from [get_regs {prod_slot* prod_gen* prod_crc_ok}]` 的 `prod_*` 在顶层是
**wire（mux 输出）**，`get_regs` 匹配为空 ⇒ 约束**静默落空**（与缺陷 14 的 `*/*.sr` 同一类）。
**已修**：改时钟源形式 `-from [get_clocks {system_pll/pll_inst.clkc[1]}]`；
STA 复核运行确认载荷路径移入 SMD 例外、0 违例（全局 STNS 数值恰好对上 67 个端点）。

### 9.4 §4 各重点问题的答复

- **§4.1 遥测同步层**：✓ 无漏同步（`pl_*` 只在端口连接与同步块内出现，`pl_ed/pl_file_size/
  pl_px_written` 未用但也没被跨域读）；✓ 无拼接截断（逐字段独立两级 reg）。
  **同意**"非原子快照只影响当次显示"的判断；补充：`t_fcnt16` 还被 `card_mode` 功能性地读，
  但最坏情形（多 bit 跳变被读成瞬态 0）只会**多等 1~2 拍**、不会切错模式 —— 良性。
- **§4.2 skid**：✓ 逐拍推过四种 `(sk_valid, sk_ready, fifo_rd_valid)` 组合，**不丢不重**；
  无组合环（`sk_load` 只经寄存器回环）；非 `S_WRITE` 清 `sk_valid` + `fifo_rd_en` 排空，
  残留像素进不了下一帧。**修法正确。**
- **§4.3 无进展超时**：✓ `px_d` 每拍跟踪、`S_WRITE` 里比较当拍与上拍 —— 判据是
  "过去 1 拍有没有推进"，不会误判/漏判；400 ms 无进展门限合理。
- **§4.4 行序**：✓ 桥在**首个被接受的像素**捕获 `top_down`（`bmp_frame_write_bridge.v:35`），
  player 在 `bmp_check_done`（54 字节头）就锁存 ⇒ 远早于首像素；头解析失败 ⇒ player 进
  `S_ERROR`、sink 无进展超时兜底，**不会写进错误行序的帧**。
- **§4.5 消抖**：✓ else 链实现正确（按下沿单拍、按住不重复、抖动不过窗）。
  两处改进建议（非缺陷）：① 1.31 ms 窗口偏短（机械抖动常 5~20 ms，建议 18 bit 计数到 ~5 ms）；
  ② 异步按键直接进组合比较，建议先进两级同步器再比（亚稳态自纠，仅规范性问题）。
  `btn_next` 电平→脉冲**不破坏** player（`S_READY` 沿触发、`S_ERROR` restart 脉冲触发）。
- **§4.6 `card_mode` 守卫**：✓ `fb_go` 作为"不许切回"的判据**充分且安全**（保守方向）。
  已知取舍：卡路径出过帧再挂掉 ⇒ 不切回落（停在最后一帧）；`MODE_TO_N=300 ms` 对**慢卡**
  可能偏紧（ACMD41 轮询最坏 ~1 s 的卡会误判"卡不可用"且**永久锁死到复位**）——
  建议上板带 2~3 张不同品牌卡验证，必要时放宽到 1 s。
- **§4.7 SDC 例外**：复位兜底 `-from board_clk -to {*.sr */*.sr}` 当前**精确**
  （board_clk 域确只有复位分发驱动异步复位脚）；但**确实过宽于未来** —— 建议加一条
  评审规则："新增 board_clk→异步复位脚的路径必须重审此约束"。

### 9.5 次要观察（不阻塞，建议记入 backlog）

1. `sd_bmp_player` 打包器**没有帧尾冲刷**：奇数像素 BMP（640×480 是偶数，不触发）会把
   最后半个字留在 `have_lo` 里，且 `have_lo/hold_*` 跨帧不清 ⇒ 奇数帧的残字会拼进下一帧开头。
   建议帧尾按 `bpu_done` 冲刷 + 进帧时清零。
2. `sd_bmp_player` 的 `SWAP_TO_N` 参数已成死代码（`S_SWAP` 现在只停一拍），建议删除或注释。
3. `S_STREAM` 的 `STREAM_TO_N=3 s` 是**总时长**超时，与项目"等外部数据流一律按无进展计"
   的约定不一致；当前余量 5×（实际 ~600 ms）风险低，建议统一口径。
4. `mem→mem` **复核运行翻负**：`board_verify_review` = **−0.163 ns / 3 端点**，路径是
   `core/display/fetch/fifo/.../wr_addr_diff → core/arbiter/cur_addr`（A 的显示取数水位→仲裁），
   **不是** skid 修的 CRC 路径 ⇒ mem 域多条路径挤在预算 99~102%，布局抖动即可打负。
   **需要真正加余量**（取数判决流水化），不能再靠单次跑过结案。这正是 §1 自己定的
   "跨运行最坏值"纪律的价值 —— 它是对的。

