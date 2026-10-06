# B 链 · 板级顶层（HDMI B）验证报告

> 目的：把已验证的 `safevision_core` **接到 HX4S20C 板的真实引脚**，并给出"**能不能上板**"的明确判据。
> 日期：2026-10-05。基线 `5b54072`。
> **结论：★ 上板成功 —— HDMI B 已点亮（彩条 + LED 全亮）** ✓✓✓（见 §8）；
> 用户逻辑域 STA 全绿；**唯一遗留是封装内 SDRAM 硬核自身的物理路径**（STA −6.565 ns，用户 RTL 无法优化，本次以实测判定可用）。
> ⇒ **功能可用，但不得据此宣称"时序已收敛"** ✗

**本文件一次性回答四个问题**：① 板上有 HDMI 吗、B 口引脚对吗（§2/§3）；② 整机能接起来吗（§1/§4）；
③ 时序什么状态（§4/§5/§6）；④ 怎么上板、结果如何（§8/§9）。

---

## 一、新增文件（本报告对应的工作）

| 文件 | 作用 |
|---|---|
| `platform/.../rtl/safevision_top/safevision_top.v` | **板级顶层**：PLL（50M→sys/mem/pixel/serial）+ 封装内 SDRAM + `mem_ctrl`/`sdram_app_adapter` + `safevision_core` + **HDMI B 发送链**（厂商 1.4b 核 + `hdmi_phy_wrapper` 串化）+ 片上**固定测试帧**源 + LED |
| `project/board_verify/board_b.adc` | **HDMI B** 引脚约束（独立文件，**不动共享的 `pin.adc`** ✓） |
| `project/board_verify/board_b.sdc` | 板级时钟：`create_clock` R7 + `derive_clocks` |
| `project/board_verify/board_cdc.sdc` | **CDC 例外**：复用 A 的 `ab_core_verify/cdc.sdc` 那套 + 板级复位断言通路 |
| `project/board_verify/td_flow.tcl` + `base.tcl`/`hd.tcl` | TD 综合→布局→布线→STA（**不生成位流**） |
| `tools/run_board_sta.ps1` | 入口脚本：跑 `base` + `hd`，**违例即失败**（严格门禁） |

★ **没有改任何共享资源**：`safevision.al` 的 `TOP_MODULE` 仍是 `top_sdram_loopback` ✓、`pin.adc` 未动 ✓、`rtl/**` 里既有文件未动 ✓

---

## 二、硬件接口事实（已核对来源）

| 事实 | 来源 |
|---|---|
| 板上有 **HDMI A、HDMI B** 两个口（不是 VGA/TF/扩展口误认） | 开发板手册-HDL版2410.pdf 第 4–5 页；原理图 `3_原理图/开发板原理图/7_HDMI.pdf` |
| **HDMI B** 的 FPGA 正端：D2=`E1`、D1=`F1`、D0=`G5`、CLK=`C3`；负端 `D1/F2/G6/C2` 由 LVDS33 自动配对；DDC=`P2/R2` | 手册第 11–12 页 + 厂商例程 `7_lab_ex_2026_nosoft/.../constraints_source/pin.adc:14-20`（**有效约束**，非注释） |
| HDMI 是 **TMDS 差分**，编码/串化在 FPGA 内做 | 原理图 `7_HDMI.pdf`；厂商 1.4b 发送核 + `lane_lvds_10_1`（`EG_LOGIC_ODDR`） |
| **SDRAM 是封装内硬核** `EG_PHY_SDRAM_2M_32`（2M×32），**不出引脚、无 pin 约束** | `6_EG4S20数据手册/EG4S20数据手册.pdf` 第 5–6 页；`top_sdram_loopback.v` 头注 |

★ **A 的扫描几何与 HDMI 例程完全吻合** ✓：BASE `640+16+96+48=800` / `480+10+2+33=525`；HD `1280+110+40+220=1650` / `720+5+5+20=750` ⇒ 板级顶层直接用同一组 HTOTAL/VTOTAL ✓

---

## 三、★ HDMI B 引脚逐脚复核（四方交叉 + 工具实测，上板前的关键一步）

### 3.1 声明值 vs 三个官方来源（**四方一致** ✓）

| 信号 | **我的 `board_b.adc`** | 官方 DEMO 31 **B 口**例程 | 厂商 `lab_ex4_tf` | 手册 B 口表 |
|---|---|---|---|---|
| `HDMI_CLK_P` | **C3** | C3 | C3 | K1/J1 对（A）→ B 口 C3/C2 ✓ |
| `HDMI_D0_P` | **G5** | G5 | G5 | B 口 D0=F5/F4（A）→ B 口 G5/G6 ✓ |
| `HDMI_D1_P` | **F1** | F1 | F1 | E3/E4（A）→ B 口 F1/F2 ✓ |
| `HDMI_D2_P` | **E1** | E1 | E1 | B3/D3（A）→ B 口 E1/D1 ✓ |
| `HDMI_DDC_SCL` | **P2** | （该例程不读 EDID，未声明） | **P2** | — |
| `HDMI_DDC_SDA` | **R2** | （同上） | **R2** | — |

★ **官方单个 A 口例程文件里就自证了 A/B 之分**：它同时声明
无后缀（=**B 口**：C3/G5/F1/E1）与 `_P1`（=**A 口**：**K1/F5/E3/B3**），
而 `_P1` 那组与手册的 HDMI A 表吻合 ⇒ **无后缀就是 B 口** ⇒ **本次用的就是 B 口** ✓

★ 官方 B 例程**只写正端 `_P`、不写负端**、`IOSTANDARD = LVDS33` ——
**与我的写法完全相同** ⇒ 印证"**负端由 TD 自动配对**"这条做法 ✓

### 3.2 ★ 工具实测分配（`route.area` 的 Detailed IO Report —— 最强证据）

```
HDMI_CLK_P     → C3   LVDS33  (DDRX1)      HDMI_CLK_P(n) → C2   LVDS33
HDMI_D0_P      → G5   LVDS33  (DDRX1)      HDMI_D0_P(n)  → G6   LVDS33
HDMI_D1_P      → F1   LVDS33  (DDRX1)      HDMI_D1_P(n)  → F2   LVDS33
HDMI_D2_P      → E1   LVDS33  (DDRX1)      HDMI_D2_P(n)  → D1   LVDS33
HDMI_DDC_SCL   → P2   LVCMOS33  PULLUP  OREG
HDMI_DDC_SDA   → R2   LVCMOS33  PULLUP  TREG
clk R7 / rst_n A2(PULLUP) / led A4,A3,C10,B12   LVCMOS33
```

⇒ **负端 = C2 / G6 / F2 / D1，与手册 B 口表逐字节一致** ✓✓✓
⇒ **不再依赖"我以为会配对"，而是工具实际就是这么配的** ✓
⇒ 正端带 `DDRX1`（走 DDR 输出路径，与 `lane_lvds_10_1` 里 `EG_LOGIC_ODDR` 一致）✓

### 3.3 资源统计：**没有意外占用的引脚** ✓

```
#IO   = 12 out of 188     ← 正好是声明的 12 个外部信号
#pad  = 16 out of 188     ← 16 = 12 + 4 个 LVDS 负端  ✓ 精确自洽
#pll  =  2 out of   4
#lut 3766/19600 (19.2%)   #reg 3442/19600 (17.6%)   #bram 16/64 (25%)   #dsp 0/29
```

★ **IO 报告里那些 `S1…S76` 球位（含 `clk → S73`）是 SDRAM 硬核的内部裸片 PAD，
不是外部引脚** ✓（真实可约束引脚是"字母+数字"如 R7/C3/G5；`S+数字` 是封装内合封存储器的内部连接）
⇒ 它们**没有计入 `#IO`/`#pad`** ⇒ **证实不占外部引脚** ✓
⇒ `route.check` **零未约束告警** ✓

### 3.4 实际时钟频率（`route.timing` Clock Summary）

| 域 | 实测频率 | 扇出 |
|---|---|---|
| video pixel（BASE） | **25.185 MHz** | 1114 |
| **mem** | **125.000 MHz** | 914 |
| sys | **100.000 MHz** | 63 |
| video serial | **125.929 MHz** | 31 |
| board | 50.000 MHz | 8 |
| mem 180°（硬核采样相位） | 125.000 MHz | 1 |

⇒ **与设计的 PLL 方案一致** ✓

---

## 四、BASE 模式验证结果（Routed STA，`base/route.timing`）

**流程**：`read_hdl` → `read_adc` → `optimize_rtl` → `optimize_gate` → `place` → `route` → `update_timing -mode final` **全部通过** ✓

### ★ 所有用户逻辑域全绿 ✓✓

| Path Group | SWNS | 违例 | 端点 |
|---|---|---|---|
| `video_base/…clkc[1] → clkc[1]`（**pixel 域**） | **+27.945** | **0** | 2875 |
| `system_pll/…clkc[1] → clkc[1]`（**mem 域**） | **+0.121** | **0** | 2606 |
| `system_pll/…clkc[0] → clkc[0]`（**sys 域**） | **+3.113** | **0** | 164 |
| `video_clkc[1] → video_clkc[2]`（pixel→serial） | +5.013 | **0** | 53 |
| `video_clkc[2] → clkc[2]`（serial 自身） | +4.510 | **0** | 49 |
| `board_clk → system_clkc[0]` | +5.636 | **0** | 2 |
| `board_clk → board_clk` | +18.949 | **0** | 1 |
| **所有跨域组**（sys↔pixel、mem↔pixel、board→mem 等） | — | **全部消失** ✓ | — |

### ✗ 唯一未收敛：SDRAM 硬核物理路径（**64 端点**）

| Path Group | SWNS | 违例端点 |
|---|---|---|
| **`system_clkc[2] → clkc[1]`** | **−6.565 ns** | **32 / 32** |
| **`system_clkc[1] → clkc[2]`** | **−3.017 ns** | **32 / 48** |

**全局 SWNS = −6.565 ns** ✗

---

## 五、★ 为什么这**不是**用户 RTL 的问题（关键证据）

最差路径（`−6.565 ns`）的原始记录：

```
Begin Point   : memory_ip/sdram.dq[0]        (clkc[2] 域)
End Point     : memory_ip/sdram_syn_1.bpad   (clkc[1] 域, bpad = 硬核边界 PAD)
Data Path Delay : 6.453ns  (cell 6.453ns = 100%, net 0.000ns = 0%)
Logic Level   : 0        Max Fanout : 0
```

⇒ **起点是 SDRAM 硬核的 DQ 数据引脚、终点是硬核边界 PAD；延迟 100% 来自硬核内部单元、0% 布线；逻辑层级 0（没有用户组合逻辑）** ✓✓

**⇒ 这是封装内 SDRAM 硬核自身的物理路径，用户 RTL 无法优化、也无法用约束消除** ✗✗
**⇒ 它正是长期记录的那条「SDRAM 物理路径 −6.826 ns」** ✓（本次 −6.565 ns，顶层不同故数值略异）

---

## 六、HD 模式验证结果（`hd/route.timing`）

| Path Group | SWNS | 违例 | 端点 |
|---|---|---|---|
| `video_hd/…clkc[1] → clkc[1]`（pixel 域，**74.167 MHz**） | **+2.648** | 0 | 2895 |
| `system_pll/…clkc[1] → clkc[1]`（mem 域） | **−0.030** | **2** ✗ | 2605 |
| `system_pll/…clkc[0] → clkc[0]`（sys 域） | +3.991 | 0 | 166 |
| `video_clkc[1] → clkc[2]` / `clkc[2] → clkc[2]` | +0.857 / +1.015 | 0 | 54 / 49 |
| `board_clk → board_clk` / `→ sys` | +18.905 / +3.707 | 0 | 1 / 1 |
| **`system_clkc[1] → clkc[2]`** | **−3.001** | **32** ✗ | 48 |
| **`system_clkc[2] → clkc[1]`** | **−6.565** | **32** ✗ | 32 |
| **合计违例端点** | | **66** | |

⇒ **HD 与 BASE 同源结论**：主违例仍是 **SDRAM 硬核的 64 个端点**（同一数值 −6.565 ns）✓；
HD 另多出 **2 个 mem 域边角违例（−0.030 ns，极边际）** ✗ —— 属**可尝试用流水/布局收掉的量级**。
★ 注意 HD 的 **pixel 域余量从 BASE 的 +27.945 降到 +2.648**（74.167 MHz 比 25.185 MHz 紧得多）⇒ HD 对布局更敏感，**值得留意但当前 0 违例** ✓

---

## 七、CDC 例外的作用（两步都必要，否则会误判成"设计有 bug"）

| 阶段 | 违例端点 | 说明 |
|---|---|---|
| ① 不加减任何 CDC 例外 | 很多组（含 sys↔pixel 62、pixel→mem 47、mem→pixel 14、复位跨域 38、mem 自身 15） | 会**误判**成"整机到处都错" ✗ |
| ② 加 A 的 core CDC 例外 | 102 | 跨域 123 端点全消 ✓、**mem 域自身从 −0.712 变 +0.149** ✓ |
| ③ 再加 `-through [get_nets {common_rst_n}] -to [get_pins {*/*.sr}]` | **64** ✓ | 复位断言跨域 38 端点也消 ✓ |

★ **教训**：`set_false_path -from [get_regs {reset_ref/release_pipe*}]` **不生效**（`release_pipe` 是 `(* keep *)` 数组，`get_regs` 匹配不到 ⇒ 静默什么都不做 ✗）；**必须用 A 那种 `get_nets` + `-through` 写法** ✓

---

## 八、★★ 上板结果 —— **已点亮（彩条 + LED 全亮）** ✓✓✓

### 8.1 实测结果（2026-10-05 晚）

| 观察项 | 结果 |
|---|---|
| **HDMI B 输出** | ★ **显示器上出现彩条** ✓✓✓ |
| **`led[3:0]`** | ★ **四个全亮** ✓ → `led[0]`=PLL+SDRAM init、`led[1]`=画面激活、`led[2]`=整帧+CRC、`led[3]`=HDMI 锁定且无反压/无 mem 错 |
| 使用位流 | `board_verify/base/safevision_top.bit`，**631963 字节**，SHA256 `c9f9ff98327759699ddbdded64698f8e6255784a3cda14c6b8cb90fb2f1b9bce` |

⇒ **★ 从"仿真绿"跨到"实物绿"** ✓：
**帧生成 → `frame_writer` → 封装内 SDRAM → `memory_arbiter` → `safevision_core` 读取/合成 → 固定速率扫描 → HDMI 1.4b 发送核 → TMDS 串化 → HDMI B 口 → 显示器**
这条**整机物理路径在真实硬件上打通** ✓✓

### 8.2 这一步一次性关闭了哪些未决项

| 原未决项 | 现在的状态 |
|---|---|
| **HDMI B 引脚映射**（正端 C3/G5/F1/E1 + 负端 C2/G6/F2/D1） | ★ **实测验证通过** ✓（不再是"纸面核对"） |
| HDMI TMDS 极性 / 串化路径 | ★ 实测有画面 ⇒ 极性正确 ✓ |
| `hdmi_1_4b_transmitter_core` + `hdmi_phy_wrapper` 接入方式 | ★ 实测有效 ✓ |
| 封装内 SDRAM 读写（本工程用法） | ★ 实测可用 ✓（LED0/LED2 亮 = init 完成 + 整帧写完且 CRC 通过） |
| 扫描几何（BASE 800×525）与显示器匹配 | ★ 实测被显示器接受 ✓ |

### 8.3 ★ 唯一仍然遗留的：SDRAM 硬核 **STA 物理路径**

| 判据 | 状态 |
|---|---|
| 板级流程能综合/布局/布线 | ✅ |
| **所有用户逻辑域**时序收敛 | ✅（BASE pixel +27.945 / mem +0.121 / sys +3.113 ns） |
| **全局 setup 收敛** | ❌ **−6.565 ns** —— `dq → 内部 pad`，`cell 100% / net 0%`、逻辑层级 0 |
| **功能上板** | ✅ **已点亮**（本次） |

⇒ ★ **该违例是封装内 SDRAM 硬核自身的物理路径，用户 RTL 无法优化；本次上板实测表明本用法下功能可用** ✓
⇒ ★ 但**仍不能宣称"时序收敛"** ✗ —— 它是**实测定性**，不是 STA 结论；**长稳/全温/全容量的裕度未证**
⇒ ★ HD 模式另有 2 个 mem 域边角违例（−0.030 ns，极边际）—— 本次上板用的是 **BASE**

---


## 九、上板操作清单（逐条核对，别跳）

### 9.1 上板前的两个"必须知道"

1. ★ **显示器必须插在 `HDMI B` 口**（板上有 A/B 两个口）。本顶层固定用 **B**（TMDS = C3/G5/F1/E1，DDC = P2/R2）。
   插到 A 口 ⇒ **不会出画面**（A 口是 K1/F5/E3/B3）✗
2. ★ **本顶层是「片上固定测试帧」**，不是 SD 卡播放 ✗ —— 目的是先打通"帧缓存 → HDMI"这条物理路径。
   画面应是**渐变/网格状彩色图案**（源为 `src_x/src_y` 的位拼接），**不是卡里的 BMP** ✓

### 9.2 LED 判读（`led[3:0]`，高电平点亮）

| LED | 含义 |
|---|---|
| `led[0]` | **PLL 锁定 + SDRAM 初始化完成**（三个 lock + `Sdr_init_done`） |
| `led[1]` | 帧已入槽、`pix_active_valid` 有效且换帧无错（画面应已激活） |
| `led[2]` | `slot_valid[0]` —— 整帧写完且 CRC 通过 |
| `led[3]` | **HDMI 视频锁定 且 无欠载 且 无 mem 错误 且 无帧故障**（= 全好） |

⇒ **期望：四个全亮** ✓；若 `led[3]` 不亮 ⇒ 查 HDMI `video_locked` / 反压 / `mem_error`

### 9.3 时钟与判据来源

- 时钟：50 MHz(R7) → **sys 100 / mem 125 / pixel 25.185 / serial 125.929 MHz**（已 STA 核对）
- 本顶层**没有 UART 输出**（不像 `top_sdram_loopback` 会发 190 字节报告）⇒ **判据 = LED + 屏幕** ✓

### 9.4 已知风险（若有问题，按此排查）

| 现象 | 排查方向 |
|---|---|
| LED 全亮但没画面 | ① 是否插在 **A 口**？② EDID/DDC —— 本顶层做 EDID 读，而**官方 B 例程不读 EDID 也能出彩条** ⇒ 可先试"不依赖 EDID"的路径 ③ TMDS 极性 |
| `led[0]` 不亮 | PLL 未锁定 或 SDRAM 未初始化 ⇒ 查复位 / 时钟 / 加密件 |
| `led[2]` 不亮 | 帧未写完或 CRC 不过 ⇒ 查 `GAP_TIMEOUT` 与 SDRAM 读回 |
| `led[3]` 不亮 | HDMI `axis_ready` 曾拉低（**反压**）或 `mem_error` ⇒ 查 `hdmi_backpressure` 锁存 |

### 9.5 位流（本次已产出，2026-10-05）

`run_board_sta.ps1` **默认不生成位流**（先看 STA）；加 **`-Bitgen`** 才会流片：

```
powershell -ExecutionPolicy Bypass -File safevision\tools\run_board_sta.ps1 -Mode base -Bitgen
```

**本次实测产出**：

| 项 | 值 |
|---|---|
| 文件 | `safevision/build/out/board_verify/base/safevision_top.bit` |
| 大小 | **631963 字节** |
| **SHA256** | `c9f9ff98327759699ddbdded64698f8e6255784a3cda14c6b8cb90fb2f1b9bce` |
| 流程输出 | `WARN … setup=-6.565 ns hold=0.011 ns; VIOLATED, bitgen forced by user` |

★ **位流 ≠ 时序通过**：脚本在流片前后都打印警告，明确指出该违例是
**封装内 SDRAM 硬核物理路径**（`dq →` 内部 pad，`cell 100% / net 0%`、逻辑层级 0），
**用户 RTL 无法优化**，按既有口径**以实测判定** ✗。
★ 脚本**从不自己烧板**（烧录是 TD 下载器的一步独立动作）✓
★ 该位流在 `.gitignore` 覆盖的 `build/out/` 下（不随仓库分发）；引用时以**上面的 SHA256** 为准 ✓

---

## 十、诚实边界（别越界）

- ★ 本板级顶层是**片上固定测试帧**，**不代表 SD 卡/FAT32 播放已上屏** ✗
- ✗ 不证明 HDMI 电气合规、显示器兼容、HDMI 音频
- ✗ 不证明 **SDRAM 物理 AC**（那 64 个违例端点就是硬核物理路径，须实测判定）
- ✗ **HD 模式仍有 2 个 mem 域边角违例（−0.030 ns）**，且 pixel 域余量仅 +2.648 ns
- `axis_s_valid` 直接跟**几何 `de`**（照厂商例程）⇒ **HDMI 路径无法反压固定速率扫描**；
  代码把 `!axis_ready` **锁存成 fault**，一旦发生 LED 会指出，且**不声称有画面** ✓
- 引脚结论来自 **TD 实测分配**（`route.area`）+ **三方官方来源交叉** ✓；
  但**真实 HDMI 信号质量、TMDS 极性、显示器接受性**仍须**上板实测** ✗

---

## 十一、★★ 2026-10-05 新增：SD 卡 BMP 播放链的板级集成与时序发现

### 11.1 这一段做了什么

| 新增 | 说明 |
|---|---|
| `rtl/storage/sd_bmp_player.v` | **可综合**的整链装配（此前这条链**只存在于测试台**）：`sd_initializer → mbr_parser → fat32_boot_parser → fat32_directory_scanner(+walker) → file_index → file_streamer(+walker) → bmp_parser → bmp_unpack → bmp_frame_write_bridge`，外加控制状态机（init→mount→scan→index→pick→stream→swap→下一幅）、按键换图、自动连播、各阶段独立超时 |
| `verification/unit/tb_sd_bmp_player.sv` | 用**真卡模型 + 整幅 921654 字节真 BMP**（FAT32 卷、2048 扇区）跑通整链，**逐像素比对 307200 个像素** |
| `tools/run_sd_bmp_player_sim.ps1` | 该 TB 的独立入口（约 45 s） |
| `safevision_top.v` 扩展 | 接入播放引擎 + SD 引脚 + KEY + **UART 周期状态报告**；卡不可用时**回落到片上测试图案**（保证 HDMI 仍有画面） |

**仿真结果（已验证）**：`SD-BMP-PLAYER PASS (0 error)`，16 项检查全过，含
`13) slot 1 content (frame 1) : 153600 words pixel-exact` ✓ —— 即**整幅 307200 像素逐点全对**（含行序重映射）。

### 11.2 ★★ 板级时序发现（重要，影响整机架构）

板级 STA 显示：把这条链放进 **125 MHz 的 mem 域**后，`mem→mem` 组出现大量违例（曾达 1452 个端点）。

**根因证据**：最差路径全部集中在这几处（`Logic Level 10~11`，8 ns 预算）：

| 位置 | 现象 |
|---|---|
| `fat32_directory_scanner` → `file_index` | 88 位目录名解码 + 十进制 `*1000/*100` + 4 槽插入排序压在一拍：**15.03 ns**，TD 报出 **MULT18 + ADDER×3** |
| `bmp_unpack` 内部 | 含**乘法器**（`mult1`）→ `phase_reg` |
| `file_index` 槽簇 → `file_streamer` | `sel_first_clus` 的 4:1 mux → `cur_lba` 计算 |

**关键事实**：这条存储/媒体链原本是按 **50 MHz** 设计并 STA 过的 ✗ ——
`top_stage6_fat32_mount.v` 头注按 50 MHz 算分频（`SD_DIV_INIT=124 → 200 kHz`），
`constraints/timing.sdc` 也写明那两个顶层是 "single 50 MHz domain, no PLL"。
**而 `safevision_core` 的 `frame_writer`/`memory_arbiter` 在 125 MHz 的 mem 域** ⇒ 直接搬进来过不去 ✗。

### 11.3 已做的一处修补（保留，且不回归）

`file_index.v`：**去掉十进制乘法的同序键 + 译码打一拍**
- 比较键由 `nd0*1000+…`（14 位十进制）改为 **4 个 nibble 打包**（每个 0..9），**与十进制同序**但不再有乘法/加法器 ✓
- 88 位名比较与「插入排序 + 表移位」分成两拍，并让 `idx_commit` 在模块内**延后 3 拍**（保证最后一个目录项流过第 2 段再冻结表）
- **回归：`run_sim.ps1` → `TOTAL PASS=628 FAIL=0`** ✓（含 `tb_file_index`、`tb_sd_bmp_player`）
- **STA：mem 域最差从 −8.399 改善到 −6.038 ns** ✓（但**未收敛**）

### 11.4 ★ 需要的决定（未解决）

链内**还有**同类长路径（`bmp_unpack` 的乘法器、`file_streamer` 的 LBA 计算），
逐个改造既有已验证模块代价大、风险高。**结构上正确的做法是给这条链一个慢时钟域**：

| 方案 | 说明 |
|---|---|
| **A（推荐）** | 让存储/媒体链跑在 **50 MHz**（与其原始设计与验证口径一致），只在**边界**跨到 125 MHz mem 域：① 像素流（`bmp_unpack` → 桥）经**异步 FIFO**；或 ② 写口（`wr_*`）做 req/ack 打包握手。50 MHz 下 SPI 仍是瓶颈，**不损失吞吐** ✓ |
| **B** | 继续在 125 MHz 下逐条流水化既有模块（`bmp_unpack` 乘法器、`file_streamer` LBA…），改动面大 |
| **C** | 先按现状出位流上板试（SDRAM 硬核那条本来就违例但实测能用）；**必须清楚这是赌**：SD 路径有 −6 ns 违例，可能不稳 |

★ 在选定方案之前：**不上板、不宣称 SD 播放可用** ✗。当前板级 STA 严格门禁**未通过**（唯一不可约项仍是 SDRAM 硬核 `−6.826 ns`，另加链内上述几处）。

---

## 十二、★ 方案 A 接口契约（2026-10-06，**已实现并三闸门通过** ✓）

### 12.1 架构与时钟

```
板载 50 MHz (R7)                          125 MHz (sv_system_pll C1)
┌──────────────────────────┐  官方 a_pixel_fifo  ┌────────────────────────────┐
│ sd_bmp_player (50M 域)   │  (双时钟, 32→16)    │ bmp_frame_sink (125M 域)   │
│  SD→FAT32→BMP→像素打包   │ ──────────────────► │  FIFO + 桥 + 帧控制器      │
│  (业务逻辑, 自研)        │ ◄── mem_ready / ─── │  (只写控制器, 复用现成件)  │
└──────────────────────────┘     frame_done      └────────────────────────────┘
                                                          │ wr_* / 换帧
                                                          ▼
                                                  safevision_core (mem+sys)
```

★ **为什么用板载 50 MHz 而不是新开 PLL 输出**：`top_stage5/6` 原本就是
"single 50 MHz domain, no PLL" —— 同一个晶振，**零风险、不动共享 IP** ✓

### 12.2 `sd_bmp_player`（50 MHz 域）—— 已重构完成、编译干净 ✓

```verilog
// 像素流出口 → 官方 a_pixel_fifo 写侧（**这三个信号都在 50 MHz 域**）
output wire [31:0] px_word;        // 2 像素打包（低半字 = 先到的像素）
output wire        px_word_valid;
input  wire        px_word_ready;  // ← FIFO 的 wr_ready
output reg         frame_active;   // 本帧正在产像素（电平，随帧起落）
output reg         top_down_o;     // 本帧行序（帧内稳定，随 frame_active 打包）
output wire [1:0]  slot_o;         // 本帧目标槽（帧内稳定）
// 与 mem 侧握手（本域内已做两级同步）
input  wire        mem_ready;      // 电平：mem 侧空闲且 FIFO 已排空
input  wire        frame_done;     // toggle：mem 侧已完成
input  wire        last_frame_ok;  // 电平：刚完成那帧是否成功
// 遥测
output reg  [31:0] cur_px_written; // 语义改为"当前行内列号"（仅遥测）
output reg         last_frame_ok_o;
```
★ **已删除**（下游不可再连）：`wr_req/wr_addr/wr_data/wr_len/wr_ready`、
`ready_toggle/out_slot/out_generation/out_crc_ok/swap_busy`、参数 `GAP_TIMEOUT`。
★ **参数改名**：`CLK_HZ_MEM` → `CLK_HZ`（值改 50 MHz），默认 SPI 分频
`CLK_DIV_INIT=62`（396.8 kHz）/`CLK_DIV_FAST=0`（钳位后 12.5 MHz），各阶段超时按 50 MHz 重算。
★ **实测坑**：改版前这里只导出 16 位 `px`，而内部 `wire px_word_ready;` **从未赋值**（悬空）
—— 32 位打包字根本没出模块。已改为 32 位端口。

### 12.3 `bmp_frame_sink`（125 MHz 域）—— 已写好、编译干净 ✓

`platform/anlogic_eg4s20_hx4s20c/rtl/bmp_frame_sink.v`

```verilog
input  wire        clk,            // mem_clk 125 MHz（读侧 / 帧控制器）
input  wire        rst_n,
input  wire        wr_clk,         // ★ 50 MHz：官方 FIFO 的**写侧**时钟
// 与 SD 侧
input  wire [31:0] px_word;        // 32 位打包像素（低半字 = 先到的像素）
input  wire        px_word_valid;
output wire        px_word_ready;  // = FIFO wr_ready（反压回 50M 域）
input  wire        frame_active;   // 电平（内部两级同步）
input  wire        top_down;       // 电平（帧内稳定，打包数据）
input  wire [1:0]  slot;           // 电平（帧内稳定，打包数据）
output reg         mem_ready;      // 电平
output reg         frame_done;     // toggle
output reg         last_frame_ok;  // 电平
// 帧写口 → core 的 memory_arbiter
output wire wr_req, output wire [31:0] wr_addr, wr_data,
output wire [15:0] wr_len, input wire wr_ready,
// 换帧请求 → 板级顶层打包到 sys 域
output reg swap_toggle, output reg [1:0] swap_slot,
output reg [7:0] swap_generation, output reg swap_crc_ok,
input  wire swap_busy,             // ★ 必须接**已同步进 mem 域**的 swap_busy_mem
// 遥测
output reg [3:0] state_o, output reg [7:0] err_code, err_detail,
output reg [15:0] frame_cnt, output reg [18:0] px_written
```
★ **`wr_clk` 是必须的**：改版前 `a_pixel_fifo` 的 `wr_clk` 与 `rd_clk` 都接了 `mem_clk`
⇒ 像素流**其实没有跨域**（双时钟 FIFO 白用了）。
★ **`swap_busy` 不能直接接 `swap_state_o`**：`frame_swap_ctrl` 跑在 **sys_clk**
（见 `frame_swap_ctrl.v` 头注），那是 sys→mem 的 CDC；必须接板级顶层已两级同步的
`swap_busy_mem`。本报告早期版本写的"可直连"是**错的**，已纠正。
**帧生命周期**：① 空闲持续排空 FIFO（连续 8 拍报空才算真排空）→ `mem_ready=1`
② SD 侧见 `mem_ready` 才开帧 ⇒ `frame_active` 上升（两级同步）⇒ 采样
`top_down`/`slot`（打包数据）并 pulse `bridge.start` ③ 桥逐 word 写
④ `br_done` ⇒ 锁存 `crc_ok`，pulse 换帧请求 ⑤ 等 `swap_busy` 起→落
（独立超时 100 ms）⇒ 翻 `frame_done` 回 ①

### 12.4 ★ 复用清单（用户方针：**优先官方 IP/例程，不自研通用件**）

| 用途 | 复用什么 | 不自研什么 |
|---|---|---|
| 跨时钟像素搬运 | **官方 `a_pixel_fifo`**（双时钟 + 32→16 位宽转换，FWFT，`wr_ready` 反压） | ✗ 异步 FIFO（自研踩过 2 个真坑） |
| 行序重映射 + 逐 word 写 | **A 的 `bmp_frame_write_bridge`** | ✗ 行重映射逻辑 |
| 时钟 | `sv_system_pll` + **板载 50 MHz 原始晶振** | ✗ 逻辑分频造时钟 |
| SDRAM / HDMI / PLL | 厂商 IP 与例程 | ✗ 控制器 |
| SD/FAT32/BMP 解析、状态机、帧装配 | **自研**（官方没有） | — |

### 12.5 实现与三闸门结果（2026-10-06，✅ 全部通过）

| 项 | 内容 | 结果 |
|---|---|---|
| 1 | `tb_sd_bmp_player.sv` 改为 **player + sink 串联**（同频），存储模型与 `cmp_frame` 逐像素比对保留；编译清单加 `bmp_frame_sink.v` + `a_pixel_fifo` 三个文件 | ✅ **17/17 通过**，`SD-BMP-PLAYER PASS (0 error)`，含 `14) slot 1 content (frame 1) : 153600 words pixel-exact`（= **307200 像素逐点全对**） |
| 2 | `safevision_top.v`：player 挂板载 `clk`(50 MHz)+`ref_rst_n`、sink 挂 `mem_clk`/`mem_rst_n`（`wr_clk=clk`）；回落图案保持 mem 域；按键消抖搬到 50 MHz 域；UART 的 PX/F/SLOT/CRC 改指 sink；**新增遥测两级同步层** | ✅ 见下（STA 归零） |
| 3 | `td_flow.tcl` 源表加 `rtl/bmp_frame_sink.v`；`board_cdc.sdc` 加 50M↔125M 例外（同步器首级 false_path + FIFO 内部 Gray 指针 max_delay） | ✅ |
| 4 | `run_sim.ps1`（B 主回归基线） | ✅ **TOTAL PASS=657 FAIL=0**（基线 628 → 657；新增 sink TB 贡献 29 项） |
| 4b | `run_bmp_frame_sink_sim.ps1`（**新增**，sink 单元 TB） | ✅ **26 项断言全过**。★ 用**两个独立自由运行的时钟**（`wr_clk` 50 MHz / `clk` 125 MHz）⇒ **真实异步边界第一次被仿真** |
| 4c | `run_top_verify_sim.ps1`（**新增**，板级顶层 TB） | ✅ **31 项断言全过**。顶层此前**零仿真覆盖**；本 TB 覆盖复位/PLL/SDRAM 通路、**UART 状态行格式与字段**、`card_mode` 回落、HDMI AXI 活动、按键消抖 |
| 5 | `run_board_sta.ps1 -Mode base`（板级综合+布局布线+STA） | ⚠️ **50M 媒体链与新交叉全清**；`mem→mem` **违例已清零（三次运行全 0）但余量极薄（最差 +0.009 ns）⇒ 仍 at-risk**；全局只剩 SDRAM 硬核 64 端点 |

#### 12.5.1 ★ 板级 STA 分组结果（Routed，`base/route.timing`）

下表取**当前 RTL**（含 `S_WRITE` 无进展超时修复 + 新增 sink TB）的一次运行，
报告留档 `safevision/build/out/board_verify_tb2/base/`。
（早期若干次运行写进了同一个 `build/out/board_verify/base/`、**互相覆盖**，
只有 QA 在隔离目录留下的 `board_verify_qa/`、`board_verify_qa2/` 可复核 —— 见 12.5.2 的流程教训。）

| Path Group | SWNS（当前 RTL） | 违例端点 | 备注 |
|---|---|---|---|
| **`board_clk → board_clk`**（50 MHz 媒体链） | **+3.372 ns** | **0 / 4710** ✓ | 历次运行（+1.66 … +3.37）**全部 0 违例** ✓ |
| **`board_clk → clkc[1]`**（方案 A 新引入的 50M→125M） | **+2.682 ns** | **0 / 1** ✓ | 历次运行**全部 0 违例** ✓ |
| `clkc[0] → clkc[0]`（sys 100 MHz） | +3.045 ns | 0 / 174 ✓ | 稳定 |
| `clkc[1] → clkc[0]`（mem→sys） | +0.190 ns | 0 / 2 ✓ | 稳定 |
| video pixel / clk2 各组 | +4.1 … +27.9 ns | 0 ✓ | 稳定 |
| **`clkc[1] → clkc[1]`（mem→mem，125 MHz）** | **+0.009 ns** | **0 / 3055** ✓ | ⚠️ **0 违例，但余量极薄**：三次运行 +0.118 / +0.118 / **+0.009** |
| `clkc[1] → clkc[2]`（mem → SDRAM_CLK，**SDRAM 写路径**） | −4.081 ns | 32 / 48 ✗ | 既有项 |
| **`clkc[2] → clkc[1]`（SDRAM 读回，`sdram.dq[*] → sdram_syn_*.bpad`）** | **−6.826 ns** | 32 / 32 ✗ | 恒 −6.826（既有项） |

**结论（★ 必须按这个口径讲，别夸）**：

1. ✅ **方案 A 的目的完全达成**：50 MHz 媒体链 `board_clk→board_clk` **历次运行全部 0 违例**
   （+1.66 … +3.37 ns），新增的 `board_clk→mem` 交叉也**历次全清**（+2.61 … +3.03 ns）。
   这正是方案 A 要解决的问题（把链内长路径从 8 ns 预算里挪出去）。
2. ⚠️ **`mem→mem`：违例已清零，但余量极薄 ⇒ 仍属 `at-risk`。**
   - **原始判据"违例清零"：达成 ✓** —— 三次独立运行**全部 0 个违例端点**（+0.118 / +0.118 / +0.009）。
   - 但**按本报告 12.5.2 自定的更严门槛（最坏运行 SWNS ≥ +0.1 ns）：未达成 ✗** ——
     最差那次只有 **+0.009 ns**，几乎贴在 0 上。
   - ⇒ **口径应写"0 违例但余量极薄（最差 +0.009 ns），未达 +0.1 ns 门槛，仍 at-risk"**，
     不要写成"已稳健收敛"。
   - 违例清掉的功劳在 §12.5.3 缺陷 16：给官方 FIFO 的**组合读数据**加 1 级 skid，
     把 `ramread0 → crc_src_*` 那条最差路径（8.165 ns / 8.0 ns）从触发器重新起算。
   - ★ **必须纠正的一处历史误记**：早期版本写"四次同源 PnR：+0.108 / −0.014 / −0.294 / −0.606"，
     其中 **+0.108 / 0 违例那次用的是"改动前的 RTL"**，与最终态不同源、**不能作为收敛证据**。
   - ★ **确定性已单独验证**：QA 用**逐字节相同的 SDC** 在隔离目录跑两次，分组摘要 **MD5 全同**
     ⇒ 给定相同输入本次 TD PnR 是确定的（证据留在 `build/out/board_verify_qa/`、`board_verify_qa2/`）。

   该路径落在 bridge 的 CRC/错误侧（**不在像素数据通路**），功能风险低。
3. ❌ **全局残余 = 64 个端点，全部落在 `memory_ip` 内部**（厂商封装内 SDRAM 硬核）：
   - 读回 `sdram.dq[*] → sdram_syn_*.bpad`：**Logic Level 0、cell 100%、net 0%** —— 纯硬核内部；
   - 写 `u2_wrrd/app_wr_addr_4d_reg[*] → sdram.dq[*]`：LL 1（PAD=1）、cell 78% —— 硬核输出 PAD 单元内。
   两条都是**既有项**（改版前分别报 −6.826 / −2.799 ns），归厂商、按用户约定**以实测判定**。
4. ✅ 顺带修掉一个 **SDC 约束覆盖缺口**：`-to [get_pins {*/*.sr}]` 只匹配**两级**路径名，
   顶层综合单元是一级（`add5_syn_104.sr`）⇒ 静默漏掉一条复位纪元路径，
   被当成真 recovery 检查报 **−3.94 ns 假违例**（预算仅 0.302 ns）。
   已加 `-from [get_clocks {board_clk}] -to [get_pins {*.sr} */*.sr}]` 兜底，该组已消失。

#### 12.5.2 mem→mem 收敛过程与后续处理

**前提**：该组**未收敛**，是**稳定可复现的硬违例**
（当前 RTL：−0.445 ns / 3 端点；修 `S_WRITE` bug 之前：−0.606 ns / 10 端点，
且那份由 QA 在隔离目录独立复现、逐字节一致）⇒ **不是"坐在 PnR 噪声带里"，
不能靠换种子/多跑几次糊过去，要真改逻辑。**

最差路径（DPD 8.326 ns / 8.0 ns，**LL 7**）：
`sink/u_bridge/writer/y_cnt_reg[5] → sink/u_bridge/writer/wr_error_reg`
—— 落在 A 的 `frame_writer` 的**行计数 → 错误/CRC 侧**，**不在像素数据通路**，所以功能风险低。

可选修法（按性价比）：

| 方案 | 说明 | 风险 |
|---|---|---|
| **A（首选，针对最差路径）** | 把 `frame_writer` 里 `y_cnt` → `wr_error`/`err_code` 这段**切一拍**（行计数与错误登记解耦）。这段是"错误报告"逻辑，加一级流水不影响像素写入顺序 | 要动 A 的 `frame_writer`；但该模块有既有 TB（`tb_frame_writer`/`tb_bmp_frame_write_bridge`/`tb_b_frame_memory`），改完必须全跑 |
| **B（针对方案 A 引入的那部分）** | 给官方 FIFO 读侧加一级 **1-entry skid**。根因：官方 FIFO 是 FWFT + `NOREG` ⇒ `rd_data` 是 ERAM 的**组合输出**，直进桥的 CRC mux（`sink/u_fifo/.../ramread0 → crc_src_reg`，LL 4） | ★ **不能简单把 `OUTREG_EN` 改成 `"OUTREG"`**：读 `a_pixel_fifo_ip.v` 的 valid 逻辑，`SHOW_AHEAD_EN=1 && OUTREG_EN="OUTREG"` 会落到 `valid = re_r1 & !empty_flag_r1`，即从 **FWFT 变成非 FWFT**，而 sink 依赖 FWFT 的"组合取数+同拍弹出"（`br_din_valid = fifo_rd_valid`、`fifo_rd_en = br_din_valid && br_din_ready`）⇒ 直接改参数会**打断握手**。正确做法是在 **sink 里自加 1-entry skid** 保持 FWFT，并重跑像素逐点比对 |
| C | 在**生产者写口**（`prod_wr_req/addr/data/len` → core 的 `wr_req/...`）插一级流水，让仲裁器从触发器出发而不是从 mux 出发 | 标准 valid/ready 流水；但**顶层目前零仿真覆盖**，需先补 TB 再改 |
| D | 调 TD 布局布线策略（timing-driven effort / seed） | **仅可作辅助观察**，不得当收敛证据（最终态已证明可复现，换种子不是解法） |

★ **通用验收口径（建议写死，防止再用单次结果结案）**：判收敛看**跨种子/跨运行最坏值**，
并声明明确门槛（例如"最坏 SWNS ≥ +0.1~0.2 ns"）；达不到就标 **at-risk** 并附最坏值 + 运行次数。
本次差点踩坑：08:46 那次快照跑出 +0.108 / 0 违例（**改动前的 RTL**），若不追查就会误报"已清零"。

★ **流程教训**：四次 STA 都写进同一个 `build/out/board_verify/base/`，**每跑一次就覆盖上一次**，
导致 08:53 / 08:56 两份报告无法再复核。**以后每次 STA 先另存报告目录**（脚本已支持
`-RunDir` / `SAFEVISION_BOARD_OUT`），否则无法做"同源/不同源"的追溯。

#### 12.5.3 本次实现中修掉的 21 个真缺陷（都留了注释，避免复发）

| # | 文件 | 缺陷 | 现象 |
|---|---|---|---|
| 1 | `bmp_frame_sink.v` | `fa_rise = fa_sync[2] && !fa_sync[1]` —— 第 2/3 级同一拍一起变 1，**条件永不成立** | sink 永远出不了 `S_DRAIN`：字节全读完、像素全被当垃圾排掉，**一帧都写不进去** |
| 2 | `bmp_frame_sink.v` | `reg [1:0] sl_sync;` 却写 `{sl_sync[0], slot}`（3 位拼进 2 位）⇒ 静默截断成 `slot` | `slot_lat` 只剩 `slot[1]`，**槽号恒为 0**，整帧写错槽 |
| 3 | `sd_bmp_player.v` | `fd_d`/`fd_pending` 被两个 always 驱动（**既有老问题**） | ModelSim 只告警；**TD 报 `HDL-8007` 并置黑盒 ⇒ 综合直接失败** |
| 4 | `sd_bmp_player.v` | 只导出 16 位 `px`，内部 `wire px_word_ready;` **悬空未赋值** | 32 位打包字根本没出模块 |
| 5 | `bmp_frame_sink.v` | `a_pixel_fifo` 的 `wr_clk`/`rd_clk` 都接 `mem_clk` | 像素流**其实没跨域**（双时钟 FIFO 白用） |
| 6 | `safevision_top.v` | `swap_busy` 直接接 sys 域的 `swap_state_o`（文档原写"可直连"是错的） | 真 CDC（sys→mem 跨域组合） |
| 7 | `safevision_top.v` | UART 状态行 / `card_mode` 回落判据 / LED 在 mem 域**组合地**读 50 MHz 的 player 寄存器 | TD 报 `board_clk→mem` **55 条违例**（最差 −1.77 ns、LL 6） |
| 8 | ★★ `bmp_frame_sink.v` `S_WRITE` 超时 | 写超时按 **S_WRITE 总时长**计（默认 400 ms）。但**真实板级一帧要 ~600 ms**（50 MHz 板载时钟 → SPI 12.5 MHz SCLK、921654 字节 + 1801 个扇区的命令/令牌/CRC 开销）⇒ **每帧都在 400 ms 被中途掐断**，只写进去约 2/3，屏幕上表现为"上 2/3 正确、下 1/3 是上一帧残留"，且 `frame_cnt` 照样递增 | 改成**无进展**超时（桥还在推进像素就重新计时）。**这个 bug 是"给 sink 补仿真覆盖"时才抓到的**：既有 TB 把 SPI 分频调到最快档（236 ms < 400 ms）⇒ **仿真跑得快反而掩盖了真问题** |
| 9 | `bmp_frame_sink.v` `S_SWAP` 超时 | 超时判断藏在 `if(busy)… else if(seen)… else if(timeout)` 之后，`swap_busy` 恒高时**永不超时** ⇒ sink 永久卡死（core 进 `S_SAFE` 时 `swap_state != 0` 会一直挂着） | 超时判断**独立于** `swap_busy` |
| 10 | `sd_bmp_player.v` + `bmp_frame_sink.v` 行序 | 开帧那一拍取 `bmp_top_down` —— 但 `bmp_parser.check_done` 是**单拍脉冲**、`top_down` 是**结果寄存器**，此时它还是**上一幅**的值；且 player 把 `top_down_o` 与 `frame_active` **同拍**置起，sink 又在 `fa_rise` 锁存 | **混合朝向的 BMP 会静默竖翻**（CRC 只覆盖写入数据、抓不到行序错）。改成：player 在 `bmp_check_done` 锁存；sink 把**实时** `td_sync[1]` 交桥，桥在首像素捕获 |
| 11 | `sd_bmp_player.v` `fd_pending` | 只在进 `S_SWAP` 时清 ⇒ 空闲期多收一次 `frame_done` 会让下一帧**一开帧就跳走** | `frame_cnt` 虚增、该帧未写。改为只在 `S_STREAM` 内有意义 |
| 12 | `safevision_top.v` `card_mode` | 可从回落态**再切回卡路径**，中途换掉生产者 toggle 源 | 跨域沿检测漏/多一拍。加 `&& !fb_go` 守卫 |
| 13 | `bmp_frame_sink.v` `err_code` | 退出 `S_ERROR` 即清零 ⇒ 错误只亮 ~64 ns，而状态行 500 ms 刷一次 | **板上看不到错误码**。改为粘滞到下一帧成功 |
| 14 | `board_cdc.sdc` | `-to [get_pins {*/*.sr}]` 只匹配**两级**名，顶层综合单元是一级（`add5_syn_104.sr`） | 漏一条复位纪元路径，被当真 recovery 检查报 **−3.94 ns 假违例**（预算仅 0.302 ns）。补 `-to {*.sr}` |
| 15 | `safevision_top.v` | 按键消抖留在 mem 域，而 player 已在 50 MHz 域 | 消抖结果还要再跨一次域。搬到 player 时钟域 |
| 16 | `bmp_frame_sink.v` **1 级 skid** | 官方 FIFO 是 FWFT + `NOREG` ⇒ `rd_data` 是 ERAM 的**组合输出**，直进桥的 4 级 CRC 组合链（`ramread0 → crc_src_*`，8.165 ns / 8.0 ns）⇒ `mem→mem` **硬违例 −0.445 ns / 3 端点** | 在 sink 里加 **1 级 skid**（读数据寄存一拍再给桥），保持 FWFT 语义 ⇒ `mem→mem` **+0.118 ns / 0 违例** |
| 17 | `safevision_top.v` 声明顺序 | `card_mode`/`mode_cnt`/`rbyte_c` **先用后声明**：ModelSim 报 `Undefined variable` + `already declared`（**顶层根本编译不过**）；按隐式网规则还会另建一根未驱动的 1 bit 网 ⇒ 卡/回落选择 mux 可能读到未驱动网 | 把声明移到首次使用之前 |
| 18 | `safevision_top.v` `fb_slot_valid[1]` | `fb_writer` 是 `.slot_sel(2'd0)`、`frame_writer` 只置 `slot_valid[0]`，判断却写 `[1]` ⇒ **永不成立** ⇒ 回落帧**写进去了却从不提交换帧**（屏幕看不到、`led` 相应位不亮） | 改 `fb_slot_valid[0]` |
| 19 | `safevision_top.v` 按键语义 | `btn_next_db = (dn_cnt == 16'hFFFF)` 只表示"电平稳定 65536 拍"，**按下与松开都为 1** ⇒ 按钮等于**被永久按住**（`btn_auto` 恒 1 连播停不下来、`btn_next` 恒 1、`restart` 恒 1） | 改"稳定 **且** 按下"；`btn_next` 做**按下沿单拍脉冲**，`btn_auto` 保持电平 |
| 20 | `safevision_top.v` 消抖毛刺 | 空闲时电平稳定 ⇒ `dn_cnt` **早已饱和在 0xFFFF**，按下那一拍 `(dn_cnt==0xFFFF) && btn_next` 立刻为 1 ⇒ **消抖窗被整个绕过** | 改 **else 链**：`if(变了)清计数; else if(未满)累加; else dn_db<=电平`（只有稳定满窗才更新输出） |
| 21 | `safevision_top.v` LED 注释 | `led` 的注释里 `led[1]`/`led[2]` 说明与 `assign` **写反了**（上板时"LED 全亮"两种写法都成立，所以一直没暴露） | 更正注释（**按代码实际**写，不改行为） |

#### 12.5.4 ★ 已知局限（别越界）

**2026-10-06 下午更新：sink 与异步边界已补上仿真覆盖**（新增 `tb_bmp_frame_sink.sv`，
`run_bmp_frame_sink_sim.ps1`，并已加入 `run_sim.ps1` 回归）：

- ✅ **真实的 50 MHz ↔ 125 MHz 异步边界现在被仿真了**：新 TB 用**两个独立自由运行的时钟**
  （`wr_clk` = 50 MHz、`clk` = 125 MHz），不再像 `tb_sd_bmp_player` 那样同频。
- ✅ **`bmp_frame_sink.v` 现在有单元覆盖**：正常帧逐像素比对、`S_ERROR`、两个换帧超时分支、
  `S_WRITE` 无进展兜底、FIFO 排空判据，共 26 项断言全过。
- ✅ **行序缺陷有专项回归**：连续两帧用**不同 `top_down`**（0 然后 1），两帧都要求逐像素全对
  —— 若"开帧取到上一幅行序"复发，T2e 会立刻失败。
- ✅ **`S_WRITE` 超时语义有回归防线**：新 TB 里一帧要 ~3 ms（远大于 WRITE_TO = 160 µs），
  若有人把超时改回"按总时长计"，T1 会立刻失败。

**仍然存在的局限（务必别越界）**

1. ❌ **顶层的"真卡"路径没有被顶层 TB 覆盖**：`tb_safevision_top` 用的是**卡不可用**场景（走回落）。
   顶层 + 真卡的 SD 初始化/挂载/整帧播放由 `tb_sd_bmp_player`（player+sink 层面）覆盖，
   **不是**在顶层环境里验证的。
2. ❌ **`active`（显示激活）在顶层仿真环境里不置起 —— 未查清。**
   观测：`fr_pulses=1`（换帧事件确实跨域送达 core 的 sys 域）、`swap_state=0`、`swap_error=0`、
   `frame_fault=0`、但 `active=0`。**怀疑**是 `sdram` 桩的读模型不满足显示取数路径，**没有证实**。
   A 的 `tb_card_to_display` 覆盖了 core 的提交路径（断言 `commits=1 acks=1`），
   所以这一环在 A 侧有人管，但**顶层环境下是空的**。⇒ 见 `docs/方案A-代码审查指引.md` §5。
3. ❌ **HDMI / TMDS / DDC / EDID / PLL 全是桩**（`models/top_ip_stub.sv`、`models/vendor_ip_stub.sv`）
   ⇒ 不证明任何电气或协议层面的事；**SDRAM 也是理想存储器桩** ⇒ 不证明协议/时序/数据完整性。
4. ❌ `tb_sd_bmp_player` 只对**第一幅**做整帧逐像素比对；第二幅只验证"能干净重入 + 槽交替"。
5. ❌ `sd_bmp_player` 自身的错误分支由 `run_sim.ps1` 里各单元 TB 覆盖，
   但**"player + sink 串联"下的错误恢复路径**没有覆盖。
6. ⚠️ 遥测同步层是**逐 bit 两级同步**，不是原子快照：`cur_bytes_rd`/`frame_cnt` 在值变化的
   1~2 拍内可能被读到中间值 —— 只影响该次 500 ms 状态行的显示数值，无功能后果，下次报告自愈。
7. ⚠️ **`mem→mem` 余量极薄**：三次运行 0 违例，但最差只有 **+0.009 ns**（见 12.5.1）。
8. ⚠️ **`board_cdc.sdc` 的复位兜底用了时钟源形式**（`-from [get_clocks {board_clk}] -to [get_pins {*.sr}]`），
   比原 `-through` 形式宽；本项目 `board_clk` 域只有复位分发会驱动异步复位脚，故实际效果精确，
   但**将来若新增 board_clk→异步复位脚的路径会被静默豁免**。
9. ⚠️ **`run_board_sta.ps1` 把任何违例当 FAIL 抛出**（有意的严格门禁），因此该脚本当前**恒为失败退出**；
   判断要看报告分组，不能看退出码。
10. ❌ 上板实测、HDMI 电气合规、显示器兼容、音频：**均未做**。

**★ TB 自身踩过的两个坑（写新 TB 时注意）**

- 用 `task` + `@(posedge)` 做 valid/ready 推送时，"沿前采样 ready、沿后盲目撤 valid"会在 ready
  恰好掉下去的那一拍**静默丢字**。本次因此让桥少收 14604 个字（推 153600、只收到 138996）而排查了很久。
  ⇒ 改成**时钟化驱动器**：只在 `(valid && ready)` 的那一拍才前进到下一个字。
- **监视器比被测信号晚一拍**：`always @(posedge clk) if (sig) flag<=1;` 在下一个沿才置位，
  而 TB 常常在**同一时刻**就检查 flag ⇒ 误判"没发生"。检查前先放几拍（本次 T6e/T6f 就是这样误判的）。
