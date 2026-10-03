# `ip/sdram/` — 厂商 SDRAM 控制器（**厂商提供，非本项目自研代码**）

## 来源与版权（重要）

| 项 | 说明 |
|---|---|
| 来源 | 厂商例程包 `7_lab_ex_2026_nosoft/example/lab_ex4_tf/src/user_source/hdl_source/`（工作区参考材料，**本身不进本仓库**） |
| 版权 | 文件头写明 `Copyright (c) Anlogic Inc. All Right Reserved.` / `Company: anlgoic` |
| 归属 | **不是我们的代码**。比赛要求"参考例程做修改"，用厂商 SDRAM 控制器属于正常做法（SDRAM 控制器不该自研） |

本目录内容与例程的对应关系：

| 本目录文件 | 例程原路径 | 性质 |
|---|---|---|
| `sdram.v` | `SD/sdram.v` | **应用级控制器外壳**（模块名 `sdram`，端口 `Clk/Clk_sft/Rst/Sdr_*/App_*`）。★ 例程顶层真正例化的就是它 |
| `global_def.v` | `include/global_def.v` | 位宽宏（`DATA_WIDTH`/`ADDR_WIDTH`/`DM_WIDTH`/`ROW_WIDTH`/`BA_WIDTH`） |
| `sdram.ipc` | `IP/sdram.ipc` | TD IP 生成器配置（PHY `EG_PHY_SDRAM_2M_32`，器件 `EG4S20BG256`），作配置记录保留 |
| `sdr_as_ram.enc.v` | `include/sdr_as_ram.enc.v` | ★ **加密源码**，真正的控制器状态机 |
| `sdr_init_ref.enc.v` | `include/sdr_init_ref.enc.v` | ★ **加密源码**，上电初始化 / 自刷新 |
| `sdr_wrrd.enc.v` | `include/sdr_wrrd.enc.v` | ★ **加密源码**，读写通路 |

### ★ 一处必须记住的区别（2026-10-02 踩过）

例程里**有两个同名 `sdram` 模块**：

1. `IP/sdram.v` —— 引脚级 PHY 外壳，端口是 `clk/ras_n/cas_n/we_n/addr/ba/dq/cs_n/dm0..3/cke`，
   里面只有一句 `EG_PHY_SDRAM_2M_32` 例化。**例程没有用它**（TD 工程 `*.al` 里没有登记这个文件）。
2. `SD/sdram.v` —— 应用级控制器外壳，端口 `Clk/Clk_sft/Rst/Sdr_init_done/Sdr_init_ref_vld/Sdr_busy/App_*`。
   **这才是例程顶层 `sdram U3(...)` 用的那一个**，本目录现在放的是它。

两个模块同名 ⇒ **不能同时进同一个 TD 工程**（重复模块名）。本目录只保留 2 号（应用级）。

### 加密文件

`sdr_*.enc.v` 是 Anlogic 加密 IP（IEEE-1735 `pragma protect`，RSA，`encrypt_agent = "Anlogic"`），
密钥块里含 Cadence / Mentor Graphics 的 key。**内容不可读、不可改**，只能由 TD 综合时解密。
✅ 2026-10-02 用户决定：**随仓库一起提交**（比赛用例程 IP 属常规做法）。
文件头已注明版权与来源，不要再改动被保护区内任何字节。

★ **对 `sdr_init_ref.enc.v` 做过一处前导行修改**（唯一一处）：原始文件里写的是
`\`include "../user_source/hdl_source/include/global_def.v"`，这条路径是**相对于例程自己的
工程目录**的（TD 按工程目录解析 `\`include`，不是按文件所在目录），拷进本仓库后必然找不到文件。
已改为 `\`include "global_def.v"`。该行位于 `\`pragma protect begin_protected` **之前**，
属于明文前导部分，**不在 RSA 保护区内**。若哪次 TD 综合报解密失败，先怀疑这一处，
把它改回原字符串并恢复例程目录结构即可（届时应改用 include 搜索路径方案，不要再改加密文件）。

## 用法（来自例程 `top_tf_hdmi_audio.v` 的真实例化）

```verilog
sdram U3(
    .Clk               (ext_mem_clk),        // 125 MHz（sv_system_pll C1 输出）
    .Clk_sft           (ext_mem_clk_sft),    // 125 MHz 的 180° 相移（同源 PLL）
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),      // 输出：初始化完成（上电后等它）
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),   // 输出：初始化/刷新周期有效
    .Sdr_busy          (Sdr_busy),           // 输出：控制器忙
    .App_wr_en         (App_wr_en),          // 输入：写使能（应用侧握手）
    .App_wr_addr       (App_wr_addr),        // 输入：写地址
    .App_wr_dm         (App_wr_dm),          // 输入：写数据掩码（byte enable，例程恒 4'b0000）
    .App_wr_din        (App_wr_din),         // 输入：写数据
    .App_rd_en         (App_rd_en),          // 输入：读使能
    .App_rd_addr       (App_rd_addr),        // 输入：读地址
    .Sdr_rd_en         (Sdr_rd_en),          // 输出：读有效（与读使能相隔固定延迟）
    .Sdr_rd_dout       (Sdr_rd_dout)         // 输出：读数据
);
```

**接口形态**：写侧是直通式（`App_wr_en`/`addr`/`dm`/`din`）；读侧是**延迟应答式**
（发 `App_rd_en`+`App_rd_addr` → 过固定延迟后 `Sdr_rd_en` 有效并给出 `Sdr_rd_dout`）。
⇒ **不许假设"发读命令下一拍就有数据"**；`Sdr_rd_en` 才是取数时刻。

★ 例程 `frame_fifo_read.v` 给的经验值是**约 10 个 `mem_clk` 拍**（它用
`rd_delay == 4'd10` 判 `rd_burst_finish`，并注释"读指令还没过去十个时钟"）。
这个 10 是厂商控制器的固定读延迟经验值，**可以参考，但不要靠它硬等**
（M-8 要求的是"不裸等、有超时退出"）。

**地址映射**（见加密文件头注释）：`App_*_addr` = `row[10:0], bank[1:0], col[7:0]`，
即 21 bit；容量 2M×32 bit = 8 MB。

## 时钟方案（照例程，2026-10-02 决定采用 A 方案）

板载 50 MHz `clk` → **`sv_system_pll`**（见 `../pll/`）：

| 输出 | 用途 |
|---|---|
| `sd_card_clk` = **100 MHz** | SD/TF 卡侧（例程口径；我们的 bring-up 目前跑 50 MHz，整机再切） |
| `ext_mem_clk` = **125 MHz** | **SDRAM 侧**（就是上面例化的 `Clk`） |
| `ext_mem_clk_sft` = 125 MHz **180° 相移** | SDRAM 采样相位（同源 PLL，**不能用普通反相器代替**） |

`video_pll` 另出 640×480 像素时钟 **25 MHz** 与 5 倍串行时钟（HDMI 用）。

**为什么跟着例程走 125 MHz**：SDRAM 的初始化/刷新/CAS 是硬时序，例程这套时钟是厂商验过的；
自己换频率等于改 IP 时序参数，反而多一层不确定性。（bring-up 阶段曾经"不接 PLL 全跑 50 MHz"
是为了阶段 1–5 少变量；接 SDRAM 就必须回到 PLL。）

## 还缺什么 / 下一步

- ✅ 加密实现 `sdr_*.enc.v` 已随仓库落地（2026-10-02）。
- ✅ **TD 工程已登记**（2026-10-02）：`safevision.al` 的 `design_1` 里已加入
  `sdram.v` / `global_def.v` / `sdr_as_ram.enc.v` / `sdr_init_ref.enc.v` / `sdr_wrrd.enc.v`
  与 `../ip/pll/sv_system_pll.v`、`../rtl/top_sdram_loopback.v`；`TOP_MODULE` 已指向
  `top_sdram_loopback`。
  ★ **不需要改 IncludeDir**：TD 解析 `\`include` 时会**同时按"包含文件所在目录"和"工程目录"**
  两处搜索 —— 这一点是从例程反推出来的：同在 `include/` 目录下的
  `sdr_as_ram.enc.v` 写 `"global_def.v"`（同目录形式）、`sdr_init_ref.enc.v` 却写
  `"../user_source/hdl_source/include/global_def.v"`（工程目录相对形式），**两条都能编过**。
  所以只要 `global_def.v` 与 IP 文件同目录，`\`include "global_def.v"` 就能解析。
- ⚠ **ModelSim 跑不了这个 IP**：加密体只能由 TD 解密（ModelSim 是否认这组 key 未验证），
  所以 SDRAM 通路**只能在板上验证，进不了 `run_sim.ps1` 回归**。这一点要在验收清单里写明。
- `ip/` 下另有可用的厂商 IP：`afifo_16_256`（异步 FIFO，含 `_sim.v` 仿真模型）、
  `afifo_16_32_256` / `afifo_32_16_256`（**跨位宽**异步 FIFO）—— 对应项目规则第 7 条
  "禁止手写异步 FIFO，跨时钟域用安路软 FIFO IP"，将来接 CDC 直接用它们（这些**能**进回归）。
- 阶段 9 的第一步（手册 7.9「SDRAM 先跑官方 Demo」）：写 `top_sdram_loopback.v`，
  写图案 → 读回 → 比对 → UART 报结果。**端口表已在上方，可以直接开工。**