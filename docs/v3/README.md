# SafeVision V3 实施与验收入口

当前功能与物理进度见 [112 项检查点](timing_closure_checkpoint_112.md)。历史验收目录不能替代修改后源码的测试与时序报告。

本次从 GitHub main `98fb43beaa12bf903186ec73f6dc64e00d9259c7` 开始，增加 V3 顶层 `safevision_v3_top`，保留队友 `safevision_top`。队友工程继续使用原来的40 MHz配置；V3完整双图HD并发压力在40 MHz下未通过，独立使用MEM/SDRAM 50 MHz、SYS100 MHz及+8 ns SDRAM移相配置。4096行刷新和FAST_READ/PREFETCH_READ保留，专用PLL的模板、参数及来源单独登记。新增功能的验证不能继承旧位流的板测结论。

阅读顺序：[系统与模块契约](architecture.md) → [已有错误与修正](defect_report.md) → [需求矩阵](requirements.md) → [验证方法](validation.md) → [UART 与按键](uart_protocol.md) → [上板步骤](board_steps.md)。音频的详细契约见 [音频接口](../v3_audio_contract.md)。

生产源码、仿真、综合和实物验收是四个独立状态。只有与当前源码哈希匹配、正常结束且零失败的测试才记为通过；只有最终 BASE/HD 的布局布线报告才可回答时序是否收敛；两台显示器的音频枚举、实际出声、线缆兼容和长稳必须实物完成。没有板子时不把这些项目写成通过。

最终证据索引以生成的 `evidence/v3/release_status.json` 为准；若该文件不存在或标有 pending，表示发布验收仍未完成。源码存在、生成了综合结果或生成了候选位流，均不能替代发布验收。
