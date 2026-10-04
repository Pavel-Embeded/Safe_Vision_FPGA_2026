# A 阶段 11–15：接口与实施契约

依据手册 V2.0 第6章 §6.11–6.15（PDF第61–68页）。基于 `b50ac4f`，2026-10-05完成本轮开发验证。已有A阶段1–10及 B/C RTL、端口、测试和 B 的 `safevision.al` 保留；本文件只补充A新增接口和验证结论。

| 阶段 | 新增交付 | 域与契约 |
|---|---|---|
| 11 | video_stream_slice | 同域弹性数据流；valid && ready 才推进，停顿期间data/last保持；不暂停扫描 |
| 12 | a_pixel_fifo_ip、a_pixel_fifo、pixel_word_packer | TD异步软FIFO；32位写、16位读、低半字先出、FWFT/NOREG；写计数按word，读计数按pixel |
| 13 | video_cdc_mailbox、video_level_sync、frame_slot_commit | 事件与多位载荷用请求/应答邮箱；电平同步；保留B帧交換CDC |
| 14 | frame_reader、a_frame_fetch_bridge | 有效窗口消费FIFO，扫描标签同拍延迟；欠载安全色；垂直消隐重启预取与FIFO epoch |
| 15 | video_compositor、osd_text_layer、a_video_display_core | Emergency > OSD > Normal；输入延迟先对齐，RGB与标签统一输出 |

FIFO默认地址宽10，官方软FIFO保留一个写位置，容量为1023个32位word/2046个RGB565像素。原B DMA输出16位像素，经独立packer恢复32位写口；不改变B DMA端口。写域水位额外保留4像素覆盖IP计数流水延迟。FIFO公共高有效复位，在两域内部同步释放；禁止一端单独清指针。

存储格式仍是冻结的640×480 RGB565与四槽字节地址。BASE扫描640×480；HD扫描1280×720时居中显示640×480存储画面，不将B缓存改成HD整帧。Frame Reader可独立参数化验证1280×720输入，集成B路径按640×480计算带宽。

读取在原始垂直消隐frame_start发起。取消旧帧时先停止新读请求并等待读通道命令/响应排空，再共同清FIFO与本地DMA，禁止复位共享仲裁器或SDRAM。欠载后本媒体帧剩余部分用安全色，下一垂直消隐重新从像素0取数，避免迟到数据造成整行错位。

阶段15提供应急图形输入及优先级接口。阶段16应急策略/生成器、阶段17 HDMI PHY和阶段20产品顶层仍按对应阶段交付。功能仿真、内部STA、整板I/O、真实HDMI与上板验收分别登记。

## 集成顺序与时钟归属

`a_video_display_core.v` 是本阶段集成入口：

```text
B frame_swap_ctrl(sys) -> 原B frame_swap_cdc -> A frame_slot_commit(pixel)
                                                        | 原始vblank提交slot/base
                                                        v
A frame_request邮箱(pixel→mem) -> 原B video_read_dma(mem)
                                  | rd_* 接原B memory_arbiter -> B mem_ctrl/SDRAM
                                  v
                           pixel_word_packer(16→32)
                                  v
                  TD官方a_pixel_fifo(mem32→pixel16 FWFT)
                                  v
                             frame_reader(1拍)
                                  | Normal
原始scan -> osd_text_layer(4拍) ----+---- video_compositor -> RGB888/全部标签(5拍)
原始scan -> Emergency输入(0拍) ----+
C整组OSD配置(sys→pixel邮箱) -> 原有状态文字/透明字模
```

`sys_clk`=100MHz、`mem_clk`=125MHz；像素时钟在编译时选择BASE/HD。跨域配置只使用整组mailbox，`video_level_sync`仅用于稳定单bit；脉冲沿用B的toggle/事件转换。每域同步释放复位。合并复位许可只作为异步断言源，再分别同步释放；FIFO清零由mem域顺序状态机驱动，读域采用官方IP内部同步释放。

核心完整ANSI端口见 `safevision/rtl/video/video_pipeline/a_video_display_core.v`；上层接线应按以下契约：

| 端口组 | 域 | 接线/行为 |
|---|---|---|
| `swap_req_b, mb_*_b` | sys输入 | 原B控制器toggle+稳定payload；保持至ACK |
| `frame_start_evt_b,swap_ack_evt_b` | sys输出 | 单拍事件，直接接原B控制器，不重复CDC |
| `rd_req/addr/len`，`rd_ack/busy/data/data_valid` | mem | 原B仲裁Video Read口；地址byte，长度32bit word；按序完整响应 |
| `cfg_valid/cfg_ready,cfg_*` | sys | valid&&ready捕获全部60bit配置；等待时保持数据/valid |
| `emergency_rgb/valid` | pixel输入 | 对应原始scan，延迟0；上游C控制须另做mailbox/图形生成 |
| `scan_x/y/de/frame_start` | pixel输出 | 原始扫描，用于图形生成/预取；frame_start为vblank入口 |
| `rgb,x,y,hsync,vsync,de,...` | pixel输出 | 全部从原始扫描延迟5拍；`pixel_valid`独立于de；blank RGB为0 |
| `pix_*`诊断 | pixel | active slot/gen/index、欠流及丢帧计数；跨给C须另做CDC |
| `mem_*`诊断 | mem | DMA进度、保守FIFO水位、溢出及状态；跨给C须另做CDC |

层延迟账：Normal1拍→补3；OSD4拍→补0；Emergency0拍→补4；优先级合成寄存1拍，总计5。不同层的mask与RGB必须同拍。扫描和de持续推进，禁止用FIFO空或pixel_valid控制扫描时钟/坐标。

带宽边界：B的640×480 RGB565一帧614400 byte，60Hz平均36.864MB/s。HD仅在中央640×480窗口读媒体，但窗口内瞬时仍需74.25M pixel/s，即148.5MB/s。当前B DMA按64word收集再拆128pixel，供数受返回延迟、仲裁和停顿影响；2046pixel FIFO及消隐预取用于缓冲，不等于物理SDRAM带宽保证。已用125/74.25MHz异步时钟、变延迟响应、每23周期停顿和竞争写入通过完整HD窗口测试。参数/外部响应性能变化需重新预算并重跑。

## 本轮实际执行的验证

新增测试入口 `safevision/tools/run_a_stage11_15_sim.ps1`，XSim2018.3。显式同库编译64份真实A+B RTL；官方FIFO及其同模板RAM直接参与，不用简化FIFO替换。

| TB | 已通过覆盖 |
|---|---|
| `tb_a_pixel_fifo` | 6818有序像素检查；异步125/74MHz、AW6实际126pixel容量、full/empty/阈值/计数、32/16低先、回绕、停顿、公共复位 |
| `tb_video_stream_cdc` | 3008次传输；独立源序列/last、反压保持、快慢时钟互换、中途公共复位 |
| `tb_frame_slot_commit` | 原B frame_swap_cdc；109次有效vblank提交/ACK，11次CRC拒绝；同拍预取新base、请求在途复位 |
| `tb_frame_reader` | BASE1260000拍+原生HD3712500拍；各3整帧；逐像素顺序、RGB扩展/全标签、欠流锁帧与下一帧恢复 |
| `tb_osd_text_layer` | 1637字模/颜色样本；独立字体位参考、4拍mask、透明边缘、禁用及复位 |
| `tb_video_compositor` | 9000拍；延迟组合1/4/0、0/0/0、4/1/2；全部8种valid优先级、blank、RGB/标签/层号、复位 |
| `tb_a_video_display_core` | 原B DMA+arbiter+swap_ctrl/CDC、官方FIFO；BASE2484007拍+HD7375507拍；逐像素黄金参考、竞争写、读延迟、约20行长断供/恢复、两次原子换槽及Emergency优先级；两模式overflow/missed_frame均0 |

整合测试BASE/HD分别核对1232512/1232384个正常媒体像素及180个Emergency像素；各303488/303616个故障后安全像素，且分别接受47876/48292个竞争写word。欠流各只计1次，下一帧恢复顺序。该测试检验中央640×480媒体窗口；`tb_frame_reader`另检验1280×720 Reader几何。

既有回归：A阶段1–9的5TB+计数器负对照、阶段10的2TB、Clock/Timing5功能+41参数、存储7TB+5旧代码负对照、B18TB/540检查，全部通过。B SDRAM应用层回归也通过（官方PLL模型、6故障/回环场景、115200baud/190byte报告、全部2^21地址签名可逆）；其SDRAM应用模型不包含物理DQ/刷新/CAS时序。

TD入口 `safevision/tools/run_a_display_sta.ps1`，真实EG4S20BG256布线，慢/快corner均检查：

| 模式 | Setup WNS | Hold WNS | TNS | 时钟/约束健康 |
|---|---:|---:|---:|---|
| BASE | +0.838ns | +0.011ns | setup/hold均0 | 100/125/25.185MHz；无无时钟、无效约束、组合环路、未放宽的FIFO跨域项 |
| HD | +1.004ns | +0.021ns | setup/hold均0 | 100/125/74.25MHz；同上 |

CDC载荷及Gray指针有8ns最大传播约束；只对同步首级和明确的异步复位入口放宽相位检查。同步第二级/业务路径仍受STA。BASE含TD复制的复位寄存器，约束覆盖其异步SR引脚，避免只命中原寄存器而漏掉副本。TD打包LSLICE/MSLICE的未使用子引脚仍会列为dummy node；探针4个非时钟输入、93个输出未设板级I/O delay，报告明确保留这些未验证项。

## 验收边界与复现

功能代码/内部STA已完成本轮开发验证，无法据此承诺所有未来队友代码、所有故障或所有板卡完全无错。既有SDRAM物理路径−6.826ns与PLL反馈补偿健康告警未在本轮改变；原B回环top及项目原样保护。真实HDMI、阶段16/17/20、产品顶层约束、上板/ChipWatcher和长期运行仍需后续验收。缺失读响应会使B仲裁保持busy，不能靠A擅自复位共享SDRAM恢复；故障策略由系统控制层处理。

```powershell
powershell -NoProfile -File safevision/tools/run_a_stage11_15_sim.ps1
powershell -NoProfile -File safevision/tools/run_a_display_sta.ps1
```

可指定 `-RepoRoot/-RunDir` 和仿真/TD安装路径。XSim2018.3的RunDir须为ASCII路径；字体 `.mem` 是必要资源，不是运行日志。脚本只接受PASS标志且拒绝Fatal/ERROR；STA另验证数值和约束健康。日志、波形、网表、DB、STA长报告及位流留本机，不上传。
