# 安路 TD 官方 PLL 配置

四组 PLL 参数与 `.ipc` 由本机 TD 6.2.168116（6.2.1 Engineer）官方 IP Generator 生成，目标 EG4S20BG256，参考输入 50 MHz。保留厂商版权、参数与模拟配置。系统和 VGA/HD 生成于 2026-10-01，音频生成于 2026-10-02。2026-10-04 对 `.v` 外壳的反馈/SDRAM 时钟连线作下述修正。GUI 原始导出在验证工程 `al_ip/`，该重复生成目录由 Git 忽略；本目录是项目使用的唯一源。

## 参数与实际频率

Normal / CLKC0_EXT：`Fvco = 50 MHz × FBCLK_DIV × CLKC0_DIV / REFCLK_DIV`，`Fi = Fvco / CLKCi_DIV`。GUI 允许分频后参考频率 10 至 400 MHz，VCO 300 至 1200 MHz，各整数分频 1 至 128。下表由理想 50 MHz 输入计算，板晶振误差和 PLL 抖动另计。

| IP | REFCLK_DIV | FBCLK_DIV | C0/C1/C2 除数 | VCO MHz | 输出用途及实际 MHz |
|---|---:|---:|---|---:|---|
| sv_system_pll | 1 | 2 | 10 / 8 / 8 | 1000 | C0=sys 100；C1=mem 125；C2=SDRAM Clk_sft 125@180° |
| sv_video_vga_pll | 3 | 17 | 4 / 45 / 9 | 1133.333333 | C0=反馈；C1=pixel 25.185185185；C2=serial 125.925925926 |
| sv_video_hd_pll | 4 | 1 | 89 / 15 / 3 | 1112.5 | C0=反馈；C1=pixel 74.166666667；C2=serial 370.833333333 |
| sv_audio_pll | 2 | 1 | 29 / 59 / 禁用 | 725 | C0=反馈；C1=audio 12.288135593 |

视频 C1 除数是 C2 的五倍，pixel:serial=1:5。每次构建只例化一种视频 PLL，共用三颗物理 PLL。仅系统 PLL 的 C2 为 180° 相移（给 SDRAM `Clk_sft`）；其余输出零相移；高有效 reset 接 `~board_rst_n`；lock 启用；模拟参数使用向导生成的 Medium 配置。

| 用途 | 手册标称 MHz | 本配置实际 MHz | 误差 ppm |
|---|---:|---:|---:|
| VGA pixel | 25.175 | 25.185185185 | +404.575 |
| HD pixel | 74.25 | 74.166666667 | -1122.334 |
| audio | 12.288 | 12.288135593 | +11.035 |

上述整数和参考/VCO 限制下，三个标称值无法精确实现；保持视频 5:1 时选用最接近目标的合法频率。标称宏不能代替实际 PLL 时钟约束。VGA 实际约 59.964727 Hz，HD 约 59.932660 Hz；audio/256 约 48000.530 Hz。接收端兼容性、抖动和 HDMI ACR 仍须验证。

## 重新生成

1. TD 打开 EG4S20BG256 工程，Tools → IP Catalog → Clock → PLL。
2. 用表中模块名导出，输入 50 MHz，Normal，CLKC0 反馈，启用 lock，保持高有效 reset。
3. Parameters setting 填表中 REFCLK_DIV、FBCLK_DIV、C0/C1/C2；只启用所用输出。
4. 系统 C2 保持 180°，其余输出保持零相移；保持 Medium 带宽，核对摘要后生成。
5. 将 `.v` 与 `.ipc` 成对复制到本目录，按下一节恢复外壳连线修正，核对参数，重跑 XSim 和两档 TD。不要把 al_ip 的同名副本加入源表。

原理和验收范围见 `docs/clock_video_implementation.md`；验证工程见 `../../project/clock_video_verify/README.md`。生成成功和 lock=1 不证明整机 STA 或显示器兼容性。

## 官方频率限制与补偿模式

[新增/纠正] DS301 v2.7.6 第 3 节引用 EAGLE 系列 DC/AC。DS300 v3.9.4 表 2-14/3-18 指定 PLL 输入/PFD 10 至 400 MHz、VCO 300 至 1200 MHz、输出 4 至 400 MHz；表 3-17 的 EAGLEA_10/20 推荐最大时钟频率为 440 MHz。全部启用输出含反馈 C0 已审计在范围内；HD serial=370.833333 MHz，距离 PLL 输出上限约 29.166667 MHz。

`check_pll_profiles.py` 已实际运行并过滤超出输出范围的整数候选，所选频点与官方配置参数不变。Normal 与 No Compensation 的 GCLK 延迟补偿不同，不能直接互换以消除 USR-6135；当前配置继续使用 Normal。范围检查不证明实际晶振抖动、锁定、输出电气或 HDMI 接收端兼容性。来源、页码、原文件 SHA-256 见 `evidence/clock_video_20261002/official_spec_review.json`。

## 2026-10-04 连线修正与验证边界

四组外壳以单一 C0 网络连接 `clk0_out` 与 `fbclk`，替代会被 TD 合并后误分类的显式反馈 BUFG 拆分接法；NORMAL / CLKC0_EXT 及全部 PLL 参数保持不变。系统 C2 显式增加 `bufg_memory`，声明 SDRAM 相移时钟的专用网络。最终布线中反馈可追踪到全局 mesh 和 `fbclk`，USR-6135 消失；SDRAM 顶层的 PHY-5079 也消失。这是本机工具结果，未经厂商勘误确认，不能推广到其他 TD 版本而省略复验。

新增 `tb_pll_feedback_equivalence.sv` 与 `run_pll_feedback_equivalence.ps1`：从基准提交 `021e4150d618cca5468309a208438ab701221de5` 读取原外壳，使用同一官方模型比较 11 路时钟、半周期、180° 内存相位及复位重锁；参数逐字比较，并以相位突变检验 TB 会报错。另已重跑时钟、A 阶段 1 至 10、B 的 18 项回归及 BASE/HD 布局布线。时钟验证器同时检查 8 个时钟、54/58 个物理时钟端点和 68/71 位寄存器，防止少报时钟获得假通过。

SDRAM setup 仍为 −6.826 ns，不能称为整板时序闭合。 时钟验证器仍有主时钟/衍生关系健康项与未约束观测 I/O，按原规则返回 2。未采用 No Compensation、降频、false path 或 multicycle 绕过；未进行新版本烧录、HDMI 或 SDRAM 上板验证。此前文档中的旧告警数值属于当时版本的历史结果。
