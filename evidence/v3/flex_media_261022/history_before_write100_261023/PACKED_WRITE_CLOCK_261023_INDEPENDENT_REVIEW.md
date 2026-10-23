# BASE packed-cache 写时钟独立只读复核

检查对象：`D:\Codex\svflex537\candidate803` 与对应 `native803\base` 原生报告。检查期间没有修改候选源码、约束、报告或位流，没有烧录或上传。此文是缺陷分析，不是修复后的验收结果。

## 1. 确定存在的生产接线违约

- `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v:24–28`：BASE 的 `SYS_HZ=50000000`，`sys_clk=mem_clk`；PLL 的 `clk0_out` 仍连接 `pll_sys100_clk`，但没有专门向 packed writer 传递。
- `safevision/rtl/video/v3_video_display_core.v:166`：cache 的 `write_clk` 直接使用 `sys_clk`。`rtl/hd/v3_video_display_core.v` 也保留这一接口接法；BASE 当前物理源码选择的是 `rtl/video` 实现。
- `safevision/rtl/video/v3_packed_row_store.v:6–9` 明确要求同一 PLL 的相位零 `MEM50 → WRITE100`。每个 32 位输入字必须分为两个 16 位写拍。
- 该模块 `:23–29` 在每次 MEM `word_valid` 时覆盖单个 packet 并翻转 request toggle；`:37–45` 每次 WRITE 只能完成 LOW 或 HIGH 中的一拍。它没有足以吸收长期 1:1 输入/输出速率差的队列，也没有反压端口。
- `:41` 在 HIGH 挂起时看见下一 packet 就锁存 `write_fault`；`:46–56` 把故障返回 MEM；`v3_line_cache.v:97` 锁存 cache fault；`v3_video_display_core.v:178–183` 返回 SYS 完整性故障；顶层 supervisor 的 `integrity_fault` 包含 `video_fault`。

因此连续每 MEM 一字的合法读返回，在 BASE 的 1:1 错误接法下必然存在来不及写完 HIGH 的情形。packet payload/toggle 可被后续输入覆盖或抵消，进而触发显示缓存故障。CRC 在 MEM 原始读流上算对，并不能证明两拍后的像素 RAM 写入正确。SD 卡装载/SDRAM 行校验可以成功，而显示阶段仍然进入 SAFE。

## 2. 实际布局布线图同样确认错误时钟

`D:\Codex\svflex537\native803\base\route.clocks`：

| 实际原生时钟 | 频率 | 报告 endpoints | 关键负载 |
|---|---:|---:|---|
| `system_pll/pll_inst.clkc[0]` | 100 MHz | 0 | 无负载 |
| `system_pll/pll_inst.clkc[1]` | 50 MHz | 3291 | packed store 的 `high_data`、`high_position`、`seen_toggle`、`done_toggle`，以及 `ramread0..3_syn_6.clka` |

可机读摘录：`outputs/packed_writer_clock_native803_readonly.json`。这不是仅由 RTL 注释推测：最终实际 RAM 写端及写状态机确实落在 50 MHz 树上。

原来的 setup/hold/recovery/removal PASS 是对这份实际错误连线的物理边沿检查。它没有证明算法需要的 2:1 吞吐比成立，不能据此发布此固件。

## 3. 独立 100 MHz serializer 与复位的约束边界

现有 `sv_v3_memory_pll.v` 已提供同一 PLL 的 `clk0_out=100 MHz`、`clk1_out=50 MHz`，不需要再增加 PLL。建议保持 BASE 控制/UI/UART/看门狗在真实 50 MHz，只给 packed writer 独立的 PLL100 时钟入口；HD 的控制100与写100仍可使用同一物理输出。

新写域必须有该 100 MHz 域自己的复位同步释放。`platform/.../rtl/clock/reset_sync.v:8–10` 明确要求每个目标域独立例化。不要直接把 SYS50 的同步释放结果作为 WRITE100 的同步复位。异步断言源应属于同一个 canonical global/media epoch；释放在 WRITE100 本域完成。可评估现有 `RELEASE_FALLING=1` 选项为写端提供半拍 recovery/removal 余量，最终仍须实际 STA。

保持 MEM packet producer 与 WRITE consumer reset epoch 一致，验证复位期间 request/seen/done toggle 均清零，写域早于第一份有效 MEM packet 释放；不得用取消故障、绕过 CRC 或不清 packet 的方式恢复画面。现有 core 的 MEM/PIX media reset 是域内两级传播，测试必须覆盖它与新写域释放的先后关系。

现有 `v3_board.sdc:3–4` 的 board clock 与 `derive_clocks` 已能派生这两个同 PLL 输出。`v3_cdc.sdc` 对 packet payload/request/high 状态没有 false-path；这个约束原则应保留。MEM→WRITE 是相关时钟路径，必须实际检查 setup/hold，不能新增异步 clock group 或宽泛 false path。done/fault 返回的两级同步器目前仅第一采样级允许现有例外。

`gen_v3_cdc.py:38–39` 与 `v3_cdc_audit.tcl:52–60` 目前只审计 packet/high/seen 寄存器“存在”，并不审计其时钟归属。`check_v3_clock_contract.py` 校验 PLL 参数和控制时间单位，却没有校验 cache writer 的端口来源。`check_v3_board.py` 要求 `route.clocks` 文件存在/绑定哈希，但没有解析这份报告来拒绝 100 MHz 零负载或 RAM 写端错误归属。

因此应新增两个分开的门禁：

1. 静态接线：生产 packed writer 明确接同 PLL100，复位在 WRITE100 释放；控制仍 BASE50/HD100。生产 core 若引入可选独立写接口，应保证显式启用，不能让新增未连接端口悬空；HD 镜像源与所有显式源清单也要能编译。
2. 原生网表：packet 数据/request producer 属于 MEM50；writer hold/high/seen 与四个 BRAM 写端属于 PLL100；新写复位同步器属于 PLL100。结合 `route.netlist.v` 的实际引脚连线与 clock report 验证，避免只看频率名字或只要求 endpoints>0。clock summary 会按共享物理单元显示部分代表名字，不宜要求每个逻辑 bit 都逐名出现。

## 4. 此前回归为什么漏检

- `tb_v3_video_final.sv:4`、`tb_v3_video_midfade.sv:4`、`tb_v3_video_one_to_one.sv:4` 等完整视频测试自行产生 SYS100/MEM50，并直接例化 core，绕过生产 TOP 的 BASE50 选择。
- `tb_v3_video_packed_store.sv` 已测试正确的 2:1 aligned/offset 两种相位、连续320字、tile 511/512边界和复位重写；它没有检查生产 TOP 是否真的把 WRITE100 接到该单元。
- `tb_v3_control_clock776.sv` 通过真实 TOP 检查 SYS50/HD100、波特率和 UI/看门狗计数，但不产生有效 packed-cache 显示读流。
- `tb_v3_board_clocks.sv` 检查像素/HUD 参数、时间边界及 media epoch，也不加载完整显示行。
- `tb_v3_feature_board198.sv:41–44` 为频谱/HUD 隔离强制了图像前层背景、SAFE 选择和 missing tags；其 `sd_miso=1` 不提供有效 TF 图像，不能覆盖生产显示缓存吞吐。
- `v3_memory_pll_clock_model.sv:6` 的独立 `#5/#10` 振荡从零开始，使100MHz上升沿为5/15ns、50MHz为10/30ns，属于固定5ns错相的契约模型；生产声明是同 PLL 相位零。新整机测试应明确相位，不能只测周期。

## 5. 必须补齐的验证

1. **实际 TOP 时钟/端口测试**：同时例化 BASE/HD 真实顶层，不强制 writer clock/reset。由显式 nominal PLL model 产生同源相位零 WRITE100/MEM50；测量 SYS、MEM、WRITE 周期与相位、每个 MEM 周期恰有两次 WRITE 边沿，并确认复位只在对应本域边沿释放。
2. **实际 TOP 内显示缓存有效流测试**：保留实际 TOP→core→line cache→packed store 全部接线，产生真实连续每 MEM 一字的64字 burst与320字整行，再到两路四行/八个 bank。可以把文件装载作为另一个已单独验收边界，用公开生产接口/外部 SDRAM 模型提供已知内容；必须注明这种聚焦集成边界。不能 force cache fault/serializer fault、不能把 RAM 写时钟替换为测试时钟，不能只检查没有故障而不核对内容。
3. **独立数据预期**：逐个 LOW/HIGH 像素核对丢失/重复/交换，覆盖首字、尾字、row_done 恰好一次、bank与511/512 tile边界；读出八路邻像素并在完整 RGB 帧中比对。NN、双线性、所有scale、双源Fade时也要正确。
4. **负向控制**：把生产 serializer 接回 SYS50，测试必须正常结束并发现错频/丢像素/故障；把新 writer reset 错接 SYS50 释放或漏 media epoch，也必须检测。正测和负测都要求结束标记与独立比较数，不能将工具崩溃当作检测成功。
5. **复位/恢复**：启动、KEY1、媒体故障恢复、HIGH pending 中途断言；在多个相位断言/释放后重写，检查旧 epoch 的 ACK/packet 不能污染新行，writer fault 只在完整 media epoch 后清除，SAFE 光栅与音频独立保留。
6. **重新物理构建**：新物理输入重新冻结、综合/布局布线、资源门禁、完整 Slow/Fast setup/hold/recovery/removal 与约束健康检查；额外保存 MEM50→WRITE100 的实际路径及新复位的 recovery/removal 证据。
7. **重新上板**：新位流绑定新提交/输入/报告及 SHA 后 SRAM 下载；核对真实 ID，缓存四槽、持续 generation 提交、VIDEO/INTEGRITY/underflow 等计数和长时间轮播；之后补充实体图像、声音和菜单观察。旧包/旧 native PASS 不能复用于修复后的硬件成功声明。

本复核确认一处足以造成当前显示缓存完整性故障的确定性接线缺陷；修复是否消除实板故障仍须新构建与串口实测闭环。
