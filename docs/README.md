# 文档入口

BASE 26102801 是当前交付，也已固化到板载 Flash。使用时先核对下载目标和固件标识，再查对应版本的操作说明。

| 要做的事 | 入口 |
| --- | --- |
| 核对固件、源码、位流和 Flash | [当前交付](../SAFEVISION_CURRENT.md) |
| 准备 TF 卡、下载或恢复 | [本版操作说明](releases/BASE_26102801/OPERATIONS.md)、[旧版 Flash 恢复](releases/BASE_26102301/OPERATIONS.md) |
| 操作实体按键和八项参数 | [菜单说明](releases/BASE_26102301/MENU_CN.md) |
| 看模块与数据流 | [项目结构](PROJECT_STRUCTURE.md)、[模块手册](modules/README.md)、[媒体与频谱](architecture/flexible-media-and-spectrum.md) |
| 看字幕的字库与像素时序 | [字幕模块](modules/scrolling_ticker.md) |
| 对照赛题要求 | [官方对应表](requirements/official_problem1.md) |
| 读取本版机器采集 | [发布索引](../artifacts/releases/BASE_26102801/release.index.json)、[板测原件](../artifacts/releases/BASE_26102801/board) |
| 排查故障和构建尝试 | [调试目录](debug/README.md)、[本版记录索引](debug/TICKER_261028.md)、[历史时间线](debug/TIMELINE.md) |
| 查历史说明 | [整理版与原件索引](history/DOCUMENTS.md) |
| 提交修改或记录 | [开发规范](../CONTRIBUTING.md)、[文字约定](WRITING.md) |

模块说明以当前顶层、生产清单和实际端口为准。历史交接、V2 及 docs/v3 按原来的版本读取。冻结发布包、原始日志、波形、时序报告及版权许可保留原字节。

当前支持实体菜单或串口调节亮度和对比度；图片导入按长宽比适配。BASE 26102301 的用户掉电反馈，以及 BASE 26102801 的 SRAM 实物反馈、Flash 安装和重载板测分别保存，版本关系见当前交付页。
