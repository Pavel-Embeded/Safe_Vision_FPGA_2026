# A 阶段十：数拍与像素标签对齐

> [更新 2026-10-04] 下文的 USR-6135 开放状态属于历史构建。`a1dba93` 已修正四个 PLL 的 C0 反馈连线及系统 C2 缓冲；本次 SDRAM 回环图案/报告缓存修正版复验未再出现 USR-6135、PHY-5079。SDRAM setup −6.826 ns 仍开放，不能登记为整板时序通过。当前说明见 [SDRAM/PLL 核查修正版](B链-SDRAM接口与PLL时序核查.md)。

依据：手册 V2.0 §6.10，印刷第 52 页（PDF 第 61 页）。交付的是固定速率延迟模块，不是完整 HDMI/Frame Reader/OSD/应急顶层。

## RTL 与接口

`safevision/rtl/video/video_pipeline/video_pipeline.v` 使用 Verilog-2001，仅有一个 `clk`（pixel_clk）和本域低有效 `rst_n`。默认 `PIXEL_WIDTH=24`、`XY_WIDTH=12`、`LATENCY=1`；接 B 的 RGB565 时显式设置 `PIXEL_WIDTH=16`。模块只移动比特，不改变颜色格式，也不跨时钟域。

| 输入 → 输出 | 含义 | 延迟 |
|---|---|---|
| `pixel_in` → `pixel_out` | PIXEL_WIDTH 位像素 | LATENCY 拍 |
| `x_in/y_in` → `x_out/y_out` | XY_WIDTH 位坐标，含消隐坐标 | LATENCY 拍 |
| `hsync_in/vsync_in` → `hsync_out/vsync_out` | 扫描同步电平，极性与 Video Timing 一致 | LATENCY 拍 |
| `de_in` → `de_out` | 扫描有效区 | LATENCY 拍 |
| `pixel_valid_in` → `pixel_valid_out` | 媒体像素是否可用，与 de 独立 | LATENCY 拍 |
| `line_start_in` → `line_start_out` | 每行首坐标标签 | LATENCY 拍 |
| `frame_start_in` → `frame_start_out` | 垂直消隐入口标签 | LATENCY 拍 |
| `active_frame_start_in` → `active_frame_start_out` | 可见帧首像素标签 | LATENCY 拍 |
| `hblank_in/vblank_in` → `hblank_out/vblank_out` | 水平/垂直消隐 | LATENCY 拍 |

所有输入必须已经属于同一个像素、同一个像素时钟域。`LATENCY=0` 是组合旁路；`LATENCY>=1` 每拍无条件推进整个 bundle，包括无效像素和消隐。没有 ready、stall、使能或时钟门控。不能把 `de` 接成 `de & pixel_valid`，也不能用 pixel_valid 冻结扫描。

异步复位会清空所有级：pixel/x/y=0，de/valid/三个事件=0，hsync/vsync 为不活动电平，hblank/vblank=1。调用方须用已有 `pixel_rst_n` 同步释放。同步极性参数为一位：BASE 为 0/0，HD 为 1/1；运行期间不能改参数。

## 精确数拍约定

输入在上升沿 E 之前稳定，则 L≥1 时输出在 E+L−1 的 NBA 更新后出现。如果上游寄存器在 E 之后推出该像素，本模块第一次采样在 E+1，输出在 E+L 后出现。测试先驱动再采样，采样后等待 NBA；不把同一个边沿前后的值混算一拍。

| 链路 | 像素与全部标签的累计延迟 |
|---|---:|
| Input → A（LATENCY=1） | 1 |
| A → B（LATENCY=2） | 3 |
| B → C（LATENCY=1） → Output | 4 |

这里的 Stage A/B/C 是手册示例中的三个流水级，不表示团队成员 A/B/C 的模块已经全部实现。两个 TB 都实际例化该级联。`video_timing` 的标签是当前坐标的组合译码，与当前 x/y 对齐，相对当前坐标的标签延迟为 0。

若以后颜色计算本身已经延迟 N 拍，必须让对应原始标签也经过 N 拍；不能再给已延迟的颜色和原始标签一起套本模块，期待它自动消除已有错位。上游每增加寄存器级数，接口账本和 TB 必须一起改。

## 与队友对接

像素从 B 的 mem_clk 路径进入 A 前仍须经过约定的安路异步像素 FIFO；本模块不是 FIFO/CDC。SDRAM 返回以 `Sdr_rd_en` 标识数据有效，等待含仲裁和刷新，不能把它写成固定四拍延迟。B 的 `frame_swap_cdc` 及原始扫描 `frame_start` 控制连接保持原协议；`frame_start_out` 是与输出像素对齐的标签，不可直接替换 B 的帧交换控制入口。

`safevision.al` 仅新增本模块源文件条目 CompileOrder=45；当前上板顶层仍为 `top_sdram_loopback`。TB 不登记到综合源表。Frame Reader、合成、HDMI 和产品顶层仍须在各自阶段实现，阶段十不能提供完整播放器位流。

## 复现仿真

从仓库根目录运行：

```powershell
./safevision/tools/run_video_pipeline_sim.ps1 -XSimBin D:/Xilinx/Vivado/2018.3/bin
```

`tb_video_pipeline.sv` 覆盖 L=0/1/2/4/7/31、1+2+1 级联、像素宽度 1/16/24、坐标宽度 1/10/12、同步极性、单比特行走、随机 bundle、valid 空洞、消隐和中途异步复位。`tb_video_pipeline_timing.sv` 连接已有 Video Timing，用独立坐标/窗口计算和历史样本索引验证完整 BASE 与 HD 帧，检查行首、可见帧首、垂直消隐入口和同步宽度。日志与临时文件自动留在 `safevision/build/out/video_pipeline_sim`。

2026-10-03 实跑：两个新 TB 分别 25,124 / 1,657,732 次 bundle 检查通过；原有五项 clock/video 功能测试和 41 项参数测试通过。新增 RTL 与 B 的原回归源表合并编译通过；TD 对 `safevision.al` 全部 45 条 Verilog 源及加密 SDRAM IP 完成 RTL 综合，0 latch，原顶层保留。

跨仿真器检查发现 B 的 `tb_mbr_parser.sv` 在 `@(posedge clk)` 返回的同一 active region 用阻塞赋值撤销 init_start/mbr_start，XSim 会先撤销请求，使 DUT 漏采样并最终看门狗超时。仅在两个撤销动作前增加 `#1`，让请求保持到采样/NBA 完成；`tb_fat32_directory_scanner.sv`、`tb_file_streamer.sv` 和 `tb_bmp_parser.sv` 各增加一个 `@(negedge clk)`，在非采样沿释放反压，避免 DUT 和计数监视器看到不同的 ready。原 RTL、断言、超时、输入数据和文件路径均保留；修正后 B 的全部 18 个 TB / 540 项检查在 XSim 通过。没有用延长看门狗或改判据隐藏失败。

B 的原 ModelSim 入口 `run_sim.ps1` 保留；新增 `run_b_xsim_compat.ps1` 从其原源文件列表读取 RTL/TB，并合入 A 阶段十 RTL，供本机 XSim 重现上述检查。本轮未安装或运行 ModelSim。运行命令：

```powershell
./safevision/tools/run_b_xsim_compat.ps1 -XSimBin D:/Xilinx/Vivado/2018.3/bin
```

TD 6.2.168116 / EG4S20BG256 的独立 stage-10 验证顶层使用现有 BASE/HD 官方视频 PLL、复位同步器、Video Timing、0+1+2+1 流水链与输出观测寄存器。完成布局布线并在新进程重建最终时钟：BASE 的 SWNS/HWNS 为 +35.320/+0.050 ns，HD 为 +8.740/+0.070 ns，STNS/HTNS 均为 0，未定时钟网络为 0；setup/hold/recovery/removal 均有实际分析。

重新导入 BASE/HD 最终数据库，实际像素 C1 和 C0 反馈线网均报告 global，反馈详细路由可追踪到全局 clock mesh 和 PLL fbclk；布线 DRC 和 check_design 通过。但 final check_timing 仍报 USR-6135（反馈被判为 local、补偿延迟不可预测），以及 clock-definition/dummy-node 项。隔离实验增加 C0 实际寄存器负载、使用官方支持的 set_clock_route_enforce 均未清除告警；没有把这些实验改进产品 RTL。物理路由与时钟图检查存在不一致，尚无厂商确认的修正或豁免。

当前原板级顶层 top_sdram_loopback 使用原 pin.adc/timing.sdc，45 条源文件实际完成综合、布局、布线、check_design 和 bitgen；生成的本地验证位流为 629,639 字节，编译没有报错，未下载到板。其全局 SWNS/STNS 为 −6.826/−298.836 ns、HWNS/HTNS 为 +0.054/0 ns；自研 C1→C1 组为 +0.102/+0.054 ns、0 违例，负 setup 余量落在现有 SDRAM 硬核 C1↔C2 的 64 个端点。此前队友的同类报告已有此问题，阶段十模块尚未在此顶层例化，不能把这次合编成功当作 SDRAM 全局时序通过。未改硬核 IP、系统 PLL 或添加 false path/multicycle 来消除报告中的违例。

本轮直接读取本机赛方 lab_ex4_tf 原例程随附的 2026-06-05 Routed 报告：SWNS/STNS 为 −6.565/−297.430 ns，也存在同类硬核路径负余量，并另有自研逻辑小幅违例。因此原例程不能作为“全部时序通过”的依据。判断：SDRAM 硬核 STA/采样边沿建模及 TD 的 PLL 反馈检查存在疑点，尚不足以认定功能 IP 有错；控制器主体为厂商加密实现，未取得可验证的修正依据。进一步隔离使用 set_clock_net 声明实际 C0 时钟也未清除 USR-6135，不向产品提交无效修改。

以上证明已分析的阶段十内部路径通过，不是整机时序签核：验证顶层的外部复位输入及 49 个观测输出没有板级 I/O 预算，完整产品顶层尚未实现，本轮未做阶段十板级烧录测试。本次不上传波形、时序报告、数据库或运行日志。

复核修正：仿真入口在切换工作目录前解析 RepoRoot/XSimBin/RunDir；显式使用相对路径实跑两个 TB 仍分别通过 25,124 / 1,657,732 次检查。扫描 TB 移除未使用的 L 参数，固定 1+2+1 链及断言未变。
