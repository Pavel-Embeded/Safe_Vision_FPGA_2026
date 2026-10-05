# B 链 · 整机集成：存储侧接线表（A ↔ B）

> **用途**：A 集成 `safevision_core` / `safevision_top` 时**照这份表接线即可**，不需要再问 B。
> **对应契约**：`docs/interface_spec.md` **v1.34**「A 阶段11–15补充契约」（A 写的两段要求）。
> **本文档是 B 侧的应答**：把 A 的要求落成**逐根信号**的可执行接线 + 时序语义 + "不该做什么"。
> **写于** 2026-10-05；核对基线 `0d878aa`。

---

## 0. 一句话结论

**A 的 `a_video_display_core` 与 B 的 `memory_arbiter` / `frame_swap_ctrl` 之间一共 14 根线，
全部同名同宽、方向互补、单位一致 ⇒ 直连即可，不需要任何转换器、也不需要额外同步器。**

| 接口 | 线数 | 时钟域 | 谁提供 CDC |
|---|---|---|---|
| 存储器读口（`rd_*`） | 7 | **`mem_clk`（125 MHz）** | **不需要** —— 两侧同域 |
| 帧交换口（`swap_*` / `mb_*`） | 7 | **`sys_clk`** | **A 的 core 内部已有 `frame_swap_cdc`** |

★ **两条最容易踩的**：
1. **`frame_swap_cdc` 已经由 A 的 `a_video_display_core` 例化**（`a_video_display_core.v:43` 的 `swaps` 实例）。
   ⇒ **B 侧不要再例化一份**，否则两个 CDC 抢同一组线。
2. **A 的 `frame_start_evt_b` / `swap_ack_evt_b` 是"已边沿检测过的单拍脉冲"**，
   直接接 B 的 `frame_swap_ctrl`，**不要再做边沿检测 / 再转一次 toggle**（见 §5 第 1 条）。

---

## 1. 三个时钟域与各自的接口

A 的 `a_video_display_core` 端口里有 `sys_clk / mem_clk / pixel_clk / rst_n` 四个时钟相关引脚，
**A 内部已各自做了 `reset_sync` 同步释放**（`a_video_display_core.v:32–34`）：

| 域 | 频率（本工程） | A 侧在里面放什么 | B 侧在里面放什么 | 本表涉及的接口 |
|---|---|---|---|---|
| `sys_clk` | 100 MHz | `frame_swap_cdc.clk_b`、配置邮箱源侧 | **`frame_swap_ctrl`** | 帧交换口（§3） |
| `mem_clk` | 125 MHz | `a_frame_fetch_bridge`（驱动 `rd_*`）、官方异步 FIFO 写端 | **`memory_arbiter`** | 存储器读口（§2） |
| `pixel_clk` | 25.2 / 74.25 MHz | 扫描、FIFO 读端、图层合成、`frame_swap_cdc.clk_a` | —— | 本表不涉及 |

★ **`rd_*` 完全在 `mem_clk` 域内**：A 的 `a_frame_fetch_bridge` 与 B 的 `memory_arbiter` 都挂在
`mem_clk` 上（`a_video_display_core.v:59`）⇒ **这 7 根线不要加任何同步器**。

---

## 2. 表 1：存储器读口（7 根，`mem_clk` 域，**直连**）

A 的 `a_video_display_core` 把整条读通道**引出到核外**，由 B 的 `memory_arbiter` 的
**Video Read 通道**服务。

| # | A 的端口 | 方向 | 位宽 | 接到 B 的 | 单位 / 语义（**以 B 端口注释为准**） |
|---|---|---|---|---|---|
| 1 | `rd_req` | A → B | 1 | `memory_arbiter.rd_req` | 一次 req = **一个突发**；只在突发边界仲裁 |
| 2 | `rd_addr[31:0]` | A → B | 32 | `.rd_addr` | **逻辑字节地址**（突发起始），不是 word 下标 |
| 3 | `rd_len[15:0]` | A → B | 16 | `.rd_len` | **32 bit word 个数**；集成取值 **64**（A 的 `BURST_WORDS` 默认 64） |
| 4 | `rd_ack` | B → A | 1 | `.rd_ack` | **单拍**：整个突发被受理、开始搬运 |
| 5 | `rd_busy` | B → A | 1 | `.rd_busy` | 高 = 该通道突发进行中；**维持到所有响应返回** |
| 6 | `rd_data[31:0]` | B → A | 32 | `.rd_data` | 读回数据（**按序**，组合转发） |
| 7 | `rd_data_valid` | B → A | 1 | `.rd_data_valid` | 与 `rd_data` **同拍**有效；**每拍确认一个 word** |

**接线片段（照抄即可）**：

```verilog
    memory_arbiter #(
        .MAX_BURSTS  (4),        // 单次 grant 连续突发上限（防独占）
        .STARVE_LIMIT(64)        // 最长等待周期，超限临时提权
    ) u_mem_arb (
        .clk              (mem_clk),
        .rst_n            (mem_rst_n),        // ★ 见 §6：必须是 mem_clk 域同步释放后的复位
        .video_fifo_level (mem_fifo_pixels),  // A 的 a_video_display_core.mem_fifo_pixels
        // ---- Video Read 口：直连 A 的 core ----
        .rd_req           (rd_req),
        .rd_addr          (rd_addr),
        .rd_len           (rd_len),
        .rd_ack           (rd_ack),
        .rd_busy          (rd_busy),
        .rd_data          (rd_data),
        .rd_data_valid    (rd_data_valid),
        // ---- Frame Write 口：接 B 的 slot_writer / frame_writer ----
        .wr_req           (wr_req),
        .wr_addr          (wr_addr),
        .wr_data          (wr_data),
        .wr_len           (wr_len),
        .wr_ack           (wr_ack),
        .wr_busy          (wr_busy),
        // ---- SD / 调试通道（最低优先级）----
        .sd_req           (sd_req),
        .sd_wr            (sd_wr),
        .sd_addr          (sd_addr),
        .sd_wdata         (sd_wdata),
        .sd_len           (sd_len),
        .sd_ack           (sd_ack),
        .sd_busy          (sd_busy),
        .sd_rdata         (sd_rdata),
        .sd_rdata_valid   (sd_rdata_valid),
        // ---- 到 mem_ctrl ----
        .mem_req          (mem_req),
        .mem_wr           (mem_wr),
        .mem_addr         (mem_addr),
        .mem_wdata        (mem_wdata),
        .mem_wstrb        (mem_wstrb),
        .mem_ready        (mem_ready),
        .mem_rdata        (mem_rdata),
        .mem_rdata_valid  (mem_rdata_valid),
        .wr_starve_cnt    (wr_starve_cnt),
        .rd_starve_cnt    (rd_starve_cnt)
    );
```

---

## 3. 表 2：帧交换口（7 根，`sys_clk` 域，**CDC 在 A 内部**）

**方向要看清**：B 的 `frame_swap_ctrl` 与 A 的 core **互为对端**，
中间的 `frame_swap_cdc` **已经例化在 A 的 core 里**（`a_video_display_core.v:43`）。

| # | B 的 `frame_swap_ctrl` 端口 | 方向 | 位宽 | 接到 A 的 core | 语义 |
|---|---|---|---|---|---|
| 1 | `swap_req` | B → A | 1 | `swap_req_b` | **toggle 电平翻转**（★ 不是单拍脉冲） |
| 2 | `frame_index` | B → A | 1 | `mb_frame_index_b` | mailbox 载荷 |
| 3 | `slot_id[1:0]` | B → A | 2 | `mb_slot_id_b` | mailbox 载荷 |
| 4 | `generation[7:0]` | B → A | 8 | `mb_generation_b` | mailbox 载荷 |
| 5 | `crc_ok` | B → A | 1 | `mb_crc_ok_b` | mailbox 载荷 |
| 6 | `frame_start` | A → B | 1 | `frame_start_evt_b` | **sys 域单拍**：垂直消隐入口 |
| 7 | `swap_ack` | A → B | 1 | `swap_ack_evt_b` | **sys 域单拍**：A 已完成切换 |

**接线片段**：

```verilog
    frame_swap_ctrl #(
        .TIMEOUT_N (32'd5_000_000)   // 覆盖一整帧 + CDC/ack 余量（100/125 MHz）
    ) u_swap_ctrl (
        .clk              (sys_clk),
        .rst_n            (sys_rst_n),        // ★ 见 §6：sys_clk 域同步释放后的复位
        // ---- 写侧提交（B 的 frame_buffer_manager / slot_writer）----
        .frame_ready      (frame_ready),
        .wr_frame_index   (wr_frame_index),
        .wr_slot_id       (wr_slot_id),
        .wr_generation    (wr_generation),
        .wr_crc_ok        (wr_crc_ok),
        // ---- A 侧：★ 直连 A 的 core，不要再做边沿检测 / 不要再转 toggle ----
        .frame_start      (frame_start_evt_b),   // A → B，单拍
        .swap_ack         (swap_ack_evt_b),      // A → B，单拍
        // ---- B → A：经 A 内部的 frame_swap_cdc ----
        .swap_req         (swap_req_b),
        .frame_index      (mb_frame_index_b),
        .slot_id          (mb_slot_id_b),
        .generation       (mb_generation_b),
        .crc_ok           (mb_crc_ok_b),
        .swap_error       (swap_error),          // 握手超时 → C 的可靠性链
        // ---- 提交给 frame_buffer_manager（原子更新）----
        .active_commit    (active_commit),
        .active_next      (active_next),
        .generation_next  (generation_next),
        .frame_index_next (frame_index_next),
        .state_o          (swap_state_o)
    );
```

---

## 4. 时序语义（逐条，来自 B 侧 RTL 的实际实现）

**读口（`rd_*`）**

1. A 拉高 `rd_req` 并同时给出 `rd_addr` / `rd_len`；**在 `rd_ack` 到来前必须保持这组值不变**。
2. B 在**突发边界**仲裁；被受理时给出**单拍** `rd_ack`，同时 `rd_busy` 拉高。
3. 此后 B 把该突发的 `rd_len` 个 word **连续搬完**（`mem_ctrl` 侧逐 word 事务），
   **中途不会切给别的通道**（手册 7.13 易错点）。
4. 每个 word 返回时 `rd_data_valid` 拉高一拍，`rd_data` 与它同拍有效；**顺序与请求顺序一致**。
5. 最后一个 word 返回后 `rd_busy` 落下。
6. `rd_ack` 只确认**整个突发**，**不逐 word 确认**。

**交换口（`swap_*`）**

7. B 在 `S_REQ` 过渡拍里先锁存 payload 到 mailbox，**下一拍才翻转 `swap_req`**
   ⇒ **req 翻转前 payload 已稳定**（手册 7.15 纠错要求）。
8. **payload 必须保持到 A 确认**（A 的契约原文："必须保持 payload 直到 A 确认"）；
   `frame_swap_ctrl` 在收到 `swap_ack` 之前不会改这组寄存器。
9. A 在**原始垂直消隐**才更新 active slot / generation / index，并给出 `swap_ack_evt_b`。
10. A 侧 `frame_swap_cdc` 对 A 的 `swap_ack` toggle **取边沿**后给出 `swap_ack_evt_b`
    （`frame_swap_cdc.v:115`：`assign swap_ack_evt_b = ack_sync[2] ^ ack_sync[1];`）
    ⇒ **到 B 手上已经是单拍**。
11. **无效 CRC 不提交、不 ACK**：`wr_crc_ok = 0` 时 `frame_swap_ctrl` 不进入请求序列
    （见 `frame_swap_ctrl.v` 的 `S_IDLE` 分支：`frame_ready && wr_crc_ok && !fr_d`）。

---

## 5. ★ 不该做什么（6 条，每条都有过真实教训）

| # | 不要做 | 为什么 |
|---|---|---|
| 1 | **不要对 `frame_start_evt_b` / `swap_ack_evt_b` 再做边沿检测或再转 toggle** | 它们是 `frame_swap_cdc` 已取过边沿的**单拍脉冲**。再转一次 ⇒ **每两次切换只认出一次，帧交换静默丢帧**。★ A 的 v1.34 契约专门警告了这一条 |
| 2 | **不要在 B 侧再例化一份 `frame_swap_cdc`** | 它已经例化在 A 的 `a_video_display_core` 里；两份 CDC 会抢同一组线 |
| 3 | **不要给 `rd_*` 加同步器** | 两侧同在 `mem_clk` 域 |
| 4 | **不要在突发中途切走 `memory_arbiter` 的授权** | 手册 7.13：切换粒度过细会反复打断长突发 |
| 5 | **换帧时不要复位共享的仲裁器 / SDRAM** | A 的契约原文："新帧先停发新请求并排空旧响应，再清本地 DMA/FIFO，**不复位共享仲裁器/SDRAM**" |
| 6 | **不要把 `rd_addr` 当 word 下标** | 它是**字节**地址（A 侧算的是 `SV_SLOT_BASE(slot) + 2*offset`，见 `tb_a_video_display_core.sv:67`） |

---

## 6. 复位

- A 的 core **只收一个 `rst_n`**，内部对 `sys_clk` / `mem_clk` / `pixel_clk` **各自**
  用 `reset_sync` 同步释放（`a_video_display_core.v:32–34`）。
- ⇒ **B 的 `frame_swap_ctrl` / `memory_arbiter` 也要各自用对应时钟域的 `reset_sync`**，
  不能直接吃 A 的内部信号（A 没有引出 `srn` / `mrn` / `prn`）。
- 契约原文："`rst_n` 必须共同断言，内部每域同步释放；整个邮箱/FIFO 组**不支持一端独立复位后
  保留另一端旧数据**" ⇒ **三域复位一起断言**。

```verilog
    // B 侧：每个域各自同步释放（顶层只给一个 rst_n）
    reset_sync u_rst_sys  (.clk(sys_clk),  .async_rst_n(rst_n), .rst_n(sys_rst_n));
    reset_sync u_rst_mem  (.clk(mem_clk),  .async_rst_n(rst_n), .rst_n(mem_rst_n));
```

---

## 7. 与 A 契约条款的逐条对照（核对结论：**全部一致**）

| A 的 v1.34 契约条款 | B 侧实际实现 | 结论 |
|---|---|---|
| "`rd_*` 原样接 B `memory_arbiter` 的 Video Read 口" | 7 根同名同宽，方向互补 | ✅ 直连 |
| "地址按字节" | `memory_arbiter.rd_addr` 注释：**逻辑字节地址（突发起始）** | ✅ |
| "`rd_len` 按 32bit word，默认 64" | `rd_len` 注释：**本次突发 word 数**；`word_left` 16 位不设上限 | ✅ |
| "ACK 确认整个突发" | `rd_ack` 单拍、在突发边界给出 | ✅ |
| "`rd_data_valid` 每拍确认一个按序 word" | 每拍一 word、顺序与请求一致 | ✅ |
| "B 的 busy 维持到所有响应返回" | `rd_busy` 由 `responses_left` 维持 | ✅ |
| "B 将 `frame_swap_ctrl` 的 5 根接到 `swap_req_b/mb_*_b`" | 5 根同名同宽 | ✅ |
| "必须保持 payload 直到 A 确认" | `S_REQ` 锁存后才翻转 req；收到 ack 前不改 | ✅ |
| "A 返回的两个信号是 sys 域单拍，**不要再次转 toggle**" | `frame_swap_ctrl` 直接把它当事件用（`frame_swap_ctrl.v:100/152`），**内部没有边沿检测** | ✅ ★ 本轮已把误导性注释订正（§5 第 1 条） |
| "无效 CRC 不提交、不 ACK" | `S_IDLE` 要求 `frame_ready && wr_crc_ok && !fr_d` | ✅ |
| "新帧先停发并排空旧响应，不复位共享仲裁器/SDRAM" | 由 A 的 `a_frame_fetch_bridge` 负责停发/排空；B 的 arbiter 不参与复位 | ✅ |

---

## 8. 验证状态（哪条已被哪个 TB 覆盖）

| 接口 / 语义 | 覆盖它的 TB | 在哪跑 |
|---|---|---|
| **A↔B 端到端**（A 的真实 core + B 的真实 `memory_arbiter`/`frame_swap_ctrl`，BASE + HD，含饥饿恢复 / 欠流安全色 / 应急优先 / 原子换槽） | `tb_a_video_display_core.sv`（**A 写的**） | `run_a_stage11_15_sim.ps1`（**XSim**，需 Vivado） |
| `frame_swap_ctrl` 自身（四态、两类超时进 SAFE、原子切换、CDC payload 预稳定、req 保持电平） | `tb_frame_swap_ctrl.sv`（23 项） | `run_sim.ps1`（ModelSim） |
| `frame_swap_cdc` 的 vblank/ack 场景 | `tb_frame_swap_vblank_ack.sv`、`tb_frame_slot_commit.sv` | `run_sim.ps1` / A 的脚本 |
| `memory_arbiter` 最坏场景与防饥饿 | `tb_memory_arbiter.sv`（7 项） | `run_sim.ps1` |
| **★ 契约守门（B 侧新增，16 项）**：<br>T1 `rd_len` 恒为契约值 64 · T2 `rd_ack` 单拍 · T3 每突发 `rd_data_valid` 计数 == `rd_len` · T4 `data_valid` 只在 `busy` 期间 · T5 突发内 `mem_addr` 每次 +4（**字节**地址）· T5b 突发数不多不少<br>**T6 ★ CDC 往返"恰好一次"**（5 次换帧 ⇒ A 侧恰好看到 5 次 req、恰好回 5 次 ack、B 侧恰好提交 5 次、`swap_req` 恰好翻转 5 次）· T6f/T6g 两个 evt 单拍<br>**T7 ★ 无效 CRC 不提交不 ACK**（`swap_req` 不翻转、无 `active_commit`、不报超时） | `tb_ab_storage_contract.sv`（**B 新增**，本表的守门 TB） | `run_sim.ps1`（**ModelSim，本机可跑**） |

**★ 为什么 B 还要自己写一条**（不是重复劳动）：
- A 的 `tb_a_video_display_core.sv` 跑在 **XSim** 上、验的是**端到端功能**（像素正确性、欠流、应急、换槽）。
  它**没有**断言本表的"契约条款"，而且 `wr_crc_ok` **恒接 1'b1** ⇒ **CRC 无效分支从没被跑过**。
- 本机**没装 Vivado/XSim**，A 那条 TB 在 B 侧跑不了。
- ⇒ `tb_ab_storage_contract.sv` 用**符合契约的驱动模型**驱动 B 的模块，只断言"接线表里写下的承诺"，
  这是 **B 侧的责任边界**，且 **ModelSim 可跑**。它验的是"B 兑现了承诺"，**不是**"B 与 A 联调成功"。

★ **仍然没有"全绿"总门禁**：`run_sim.ps1`（ModelSim，**不含 A 的 9 个 `tb_a_*`**）
与 `run_a_stage11_15_sim.ps1`（XSim，含 A+B 同库编译）是**两套**，需要分别跑（见 §9 未决第 6 条）。

---

## 9. 未决 / 待确认

| # | 事项 | 需要谁 |
|---|---|---|
| 1 | **突发长度口径**：集成取值 64（A 的 `BURST_WORDS` 默认）—— 已写进 `memory_arbiter.v` 头注与本文档；若 A 后续改这个参数，**请同步通知 B** | A ↔ B |
| 2 | **`video_read_dma` / `mem_read_burst` 的归属**：A 新写了 `a_frame_fetch_bridge` 承担同一职责（读帧 → FIFO）。集成时**用 A 的 bridge**（它自带 pixel/mem 域穿越）；B 的这两个模块目前只被 `framebuffer_loopback_core`（阶段 10 自测）使用 ⇒ **是否废弃/保留作自测**待定 | A ↔ B |
| 3 | **`LOW_WM` / `HIGH_WM` / `MAX_BURSTS` / `STARVE_LIMIT` 的实测标定**：现在是设计目标值 | 需整机实测 |
| 4 | **`TIMEOUT_N`**：默认 5 M 周期覆盖 60 Hz + 余量；若整机跑 HD 或改帧率要复核 | A ↔ B |
| 5 | **SDRAM `C1↔C2` 的 −6.826 ns**：A 的 v1.34 里也写明"仍是未关闭问题"；与本文档的接线无关，但**是整机时序的未决项** | A ↔ 厂商 |
| 6 | **★ 验证入口碎片化，没有"全绿"总门禁**：现在有 8 个 `run_*.ps1`（`run_sim` 22 TB / `run_b_xsim_compat` 18 / `run_a_stage11_15_sim` 9 / `run_memory_protocol_sim` 7 / `run_a_stage1_9_sim` 5 / …），而且 **`run_sim.ps1` 完全不含 A 的 9 个 `tb_a_*`**。⇒ 建议做一份**"跑哪些脚本才算过"的总清单**（或一个总入口），否则多 agent 并行时容易"我这绿了、整机红" | A ↔ B |
