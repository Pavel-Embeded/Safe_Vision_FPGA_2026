# 文档入口

当前稳定版是 BASE 26102301。使用和复测时先查现行文档，旧问题再按日期查调试记录。

| 要做的事 | 入口 |
| --- | --- |
| 核对固件、源码和位流 | [当前交付](../SAFEVISION_CURRENT.md) |
| 准备 TF 卡、下载或恢复旧版 | [操作与恢复](releases/BASE_26102301/OPERATIONS.md) |
| 使用实体按键和八项参数 | [菜单说明](releases/BASE_26102301/MENU_CN.md) |
| 看数据流与模块接口 | [项目结构](PROJECT_STRUCTURE.md)、[生产模块](modules/README.md)、[媒体与频谱](architecture/flexible-media-and-spectrum.md) |
| 对照赛题要求 | [官方要求对应表](requirements/official_problem1.md) |
| 查看测试与实物反馈 | [BASE 验收](releases/BASE_26102301/ACCEPTANCE.md) |
| 排查旧故障 | [调试目录](debug/README.md)、[时间线](debug/TIMELINE.md)、[逐次记录](debug/RUNS.md) |
| 查找旧说明的整理版和原件 | [历史说明索引](history/DOCUMENTS.md) |
| 提交修改或补充记录 | [开发规范](../CONTRIBUTING.md)、[文字约定](WRITING.md) |

## 版本与记录

模块目录内的 README 说明该模块或历史阶段的设计。早期 A/B 交接、V2 接口规范和 docs/v3 检查点保留当时参数及未完成项，不能直接作为当前固件的验收结果。

当前 BASE 支持手动亮度、对比度调节。图像的“自适应”指长宽比适配，当前位流没有自动感光或图片内容自动亮度反馈。HD 试验沿用各次原始结果，未列入当前 BASE 发布。

2026-10-25 的完全断电重启已由用户实物确认，2026-10-26 再次确认。现场测试次数、耗时和串口原始采集未提供，详见 [验收更新](../evidence/board/acceptance_updates.json)。

## 原件与整理版

冻结发布包、串口日志、波形、时序报告和既有归档保留原字节。原始说明绑定发布哈希时，另存整理版，并在历史索引中给出原件路径。厂商版权和许可说明沿用原文。

本次文字修改的逐文件来源、校验值和检查结果见 [文档复核记录](../evidence/documentation_review_261026/review.json)。
