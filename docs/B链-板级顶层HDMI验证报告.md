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
