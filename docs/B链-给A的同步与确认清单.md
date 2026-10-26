> 历史阶段记录，版本、参数与结论按原记录日期理解。当前 BASE 的模块和验收状态见仓库首页。

# B 链 · 给 A 的同步与确认清单

> 用途：B 侧要 A 回答/确认的事项，按优先级排。
> 各项记录问题、原因和预期答复，A 侧按编号确认。
> 状态：2026-10-05。当前已推送（`origin/main` = `150e38d`）。


## 一、整机对接记录

> B 侧已完成整机对接，以下四项待 A 侧确认。
>
> 结论：接口逐根核对完了，结论是"直连即可"：详见 `docs/B链-整机集成-存储侧接线表.md`。
> A 侧的 `rd_req/rd_addr/rd_len/rd_ack/rd_busy/rd_data/rd_data_valid` 7 根与 B 的 `memory_arbiter` Video Read 口
> 同名同宽、方向互补、单位一致（地址=字节、`rd_len`=word 数=64），同在 mem_clk 域、不需要同步器。
> `frame_swap_cdc` 已经在A 侧的 `a_video_display_core` 里例化了，B 侧不会重复例化。
>
> 待确认的 4 项：
>
> ① 时钟域（优先确认）：`bmp_unpack` 输出的 RGB565 像素流，与 `frame_writer` 的输入，
> 在产品里是不是同一个时钟域？B 侧集成 TB 先按同域（mem_clk）接的；
> 如果实际是跨域，需要在它们之间补一级 CDC FIFO：这是集成时容易漏的一环。
>
> ② B 侧修改了 A 文件中的端口连接，待确认：`ip/a_pixel_fifo/a_pixel_fifo_ip.v` 里 `ram_inst`（ERAM）
> 只写了 14/16 个端口，漏了 `doa`（A 口读数据）和 `dib`（B 口写数据）。这两个口在 SDP 模式下本来就不用，
> 所以 XSim 能过，但 ModelSim 的 vopt 会报 "Too few port connections ... Expected 16, found 14" 然后内部崩溃，
> 导致B 侧无法仿真 A 的显示核心。B 侧将这两个端口显式写出来（`doa` 留空、`dib` 接 0），零功能改动，
> 注释里写了来由。待 A 侧确认。
>
> ③ 实测的提交时间差，待核对设计意图：
> 整机集成 TB 测得：A 的显示核心从 mailbox 到达就激活画面（`pix_active_valid`），
> 而 B 的 `frame_swap_ctrl` 要等到下一个垂直消隐才提交（`active_commit`），两者差约 1.74 ms（一帧）。
> 需确认是否符合设计预期，以及是否存在"画面已换、但槽管理还没提交"的窗口。
>
> ④ 整机顶层 `safevision_core` / `safevision_top` 由谁做、大概什么时候？
> 待办清单里写的是"未开始（A 负责）"。板卡和 TD 均在 B 侧，顶层一出来B 侧可执行综合/布线/STA/上板。
>
> B 侧已验证的基线：B 链回归 618 项断言全 PASS；
> 卡上文件 → 屏幕像素的集成测试 46 项全 PASS；A+B 显示级全链路 15 项全 PASS
> （真 BMP → A 侧的 `a_video_display_core` → 307200 个像素逐点与源 BMP 一致）。
>
> 重复例化的既有问题：接线表里写的"B 侧不要再例化 `frame_swap_cdc`"：B 侧曾在 TB 中
> 违反过一次，结果是 `fs_evt_b`/`ack_evt_b` 双驱动、换帧 FSM 永远收不到 `frame_start`、超时进 SAFE。
> 那条禁忌确实有用，集成时请照接线表接。


## 二、确认清单（A 只需回编号 + 结论）

| # | 要确认什么 | 为什么 | 期望的回答 |
|---|---|---|---|
| ① | `bmp_unpack` ↔ `frame_writer` 是否同域 | B 侧按同域连接；若跨域需补 CDC FIFO，否则整机接线是错的 | "同域" / "跨域，需要加 FIFO" |
| ② | `a_pixel_fifo_ip.v` 补 `doa`/`dib` 两个未接端口无异议 | 该修改位于A 侧的文件里（零功能改动） | "无异议" / "有异议，原因是…" |
| ③ | "画面激活比 B 的槽提交早一帧"是否符合设计意图 | 实测 A 从 mailbox 生效、B 要等垂直消隐提交，差约 1.74 ms | "符合" / "不符合，应该…" |
| ④ | 整机顶层 `safevision_core` 谁做、何时 | 板测的前置；板卡 + TD 在 B 侧，顶层一出来B 侧可运行综合/STA/上板 | 负责人 + 大致时间 |


## 三、已推送的参考资料

| 文件 | 核对内容 |
|---|---|
| `docs/B链-整机集成-存储侧接线表.md` | 逐根接线表 + 时序语义 + "不该做什么" 6 条：他集成 `safevision_core` 时照它接 |
| `docs/interface_spec.md` | v1.35（B 对 v1.34 契约的应答已登记） |
| `docs/verification/test_matrix.md` | 验证入口总清单 + A/B 显示级现状 + 待查项 |
| `docs/B链-交接-给下一位Agent.md` | §2.9「集成测试现状」（含两台机器路径不要混的说明） |


## 四、沟通建议

- 一次把 4 条都问出去，别分多次：②③④ 可先确认分工与设计意图，① 优先核对。
- 附上接线表链接，他集成时不用再来回问 B 的端口方向/单位。
- 两条"不需要他确认"的别混进去（避免信息过载）：B 侧的回归数字、TB 细节，这些写"供参考基线"即可。
- 若他回"① 跨域" ⇒ B 侧需在 `bmp_unpack` 与 `frame_writer` 之间补 CDC FIFO，
  并把接线表 §2 补一节：这是唯一可能改 RTL 的一条，值得优先问。


## 五、一条备注：让集成测试"从卡上的真文件取数"（使用文件内容驱动卡模型）

### 5b54072 的集成测试

A 侧的 `tb_safevision_core` / `tb_ab_frame_display` 用 TB 合成的 BMP 字节流喂 `bmp_parser`
（`px24(x,y)` 现算），再用同一个函数算期望：这对验证显示链是完全够的
（而且A 侧增加了 `MUTATE_COLOR` 变异、`HD`、`SUBMIT_LEAD` 参数，比我当初做的更强 ）

### 差别在哪

B 侧另建了一条测试：把真文件内容完整写进 SD 卡模型，让它从卡里读 ⇒
`sd_initializer → sd_sector_reader → mbr_parser → fat32_boot_parser → fat32_directory_scanner
→ file_index → file_streamer → bmp_parser → bmp_unpack → frame_writer → …`

它多证明了一件事："卡上那 921654 字节"到"屏幕 307200 像素"中间，
`file_streamer` 的簇链遍历、`bmp_parser` 的头部/行序、以及字节序全对：
也就是TB 造数据那条路覆盖不到的前半段

### 关键技术点（要复现只需两点）

1. 卡模型的卷要够大：`sd_spi_card_model` 原卷窗口是 64 扇区（≈32 KB），装不下
   640×480×24bit BMP（921654 字节）⇒ B 侧增加了 `VOL_SECTORS` 参数（默认放到 2048 扇区 = 1 MiB）；
   默认 `VOL_BASE=0` 的行为不变，所以既有 TB 不受影响
2. `frame_writer` 的 `GAP_TIMEOUT` 必须放大到能跨过一次 FAT 读：
   真卡取数时每个簇边界要读一次 FAT 扇区，CMD17 停顿约 16384 个 `clk_mem` 拍（131 µs），
   远超默认 512 拍 ⇒ 会误报"上游断流" （未通过）。
   A 侧已在 RTL 里把 `GAP_TIMEOUT` 位宽改成 32 位（`frame_writer.v`）：
   正是为解决这一类问题，方向完全一致 （B 侧版本是只在 TB 里实例化大值，不如A 侧的改法）

### 建议

- 这条"从卡取数"的路子值得并进A 侧的集成 TB：它能把"SD/FAT32 前段"也纳入整机回归
- 做法上：卷扩大到 2048 扇区 + 把 `GAP_TIMEOUT` 实例化为 ~500_000（B 侧已验证可行）
- B 侧实现在本地分支 `backup/card-to-screen-merge`（提交 `2e97790`）；
  因为和你 5b54072 的改动（你重写了 `tb_ab_frame_display`、也动了 `sd_spi_card_model`）正面冲突，
  我按约定没有合并、也没推送：分支保留用于后续协调

此测试使用合成微型 FAT32 镜像，包含 1 个 FAT 扇区、32 扇区/簇，声明容量 2048 扇区。它未使用真实卡镜像，也未覆盖多扇区 CMD18 或真实 SD 时序 AC。