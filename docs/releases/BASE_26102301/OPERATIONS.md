# 使用、下载与恢复

下载使用 [SafeVision_BASE_6a957b0.bit](../../../artifacts/releases/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit)。其 SHA-256 为 `95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e`。

## 图片与音频

FAT32 卡根目录至少四张合法 BMP，24 位 BGR 或 32 位 BGRX、BI_RGB，每轴 1 至 16384；允许中文和长文件名。按文件名的确定字典顺序选择前四张有效图，不是按复制时间，也不是 Windows 数字自然排序。不同长宽比等比例居中，剩余区域补黑。JPG/PNG、RLE、调色板和损坏图片不属于本版支持范围，改后缀不能转换格式。

优先同主干 WAV；无同名时按轮播槽使用卡内 WAV，坏音频有界尝试其他候选，全部不可用才退内置提示音。标准工作媒体为 48 kHz、16 位、双声道 PCM WAV。完整排序、别名、编码、目录和格式边界见 [媒体规范](../../architecture/flexible-media-and-spectrum.md)。

[菜单与按键详解](MENU_CN.md) 包含八个配置项、默认值和顶部状态。

## 固化与旧版恢复

本机已经完成最新版固化；不要为阅读说明而重新烧录。包内 flash_install 保留旧整片 Flash 两份备份、成功历史位流、实际编程日志、新 Flash 双份回读、可预演的恢复工具及完整说明。

- [完整 Flash 固化/恢复说明](../../../artifacts/releases/BASE_26102301_6a957b0/flash_install/FLASH_固化与恢复说明.md) 是当时本机操作的原始记录；其中 D 盘绝对路径是原始证据位置。
- 恢复工具以自己的 tools 目录定位包内容，默认仅核验/预演；显式 -Apply 才写 Flash。原始说明中的本机路径可替换为当前克隆对应的 flash_install 路径。
- Latest 恢复本次 BASE；Previous 恢复所保留的成功历史 BASE。整片二进制恢复使用厂商 Program SPIBIN，在偏移 0 写入并完整读回核对。
- 完全断电试验需断开全部供电包括 Type-C、JTAG USB-B 和外部电源，确认全灯灭至少 10 秒；接回时不重新下载，才能验证 Flash 自行启动。用户于 2026-10-25 反馈该项已测试正常，记录见 [当前验收](ACCEPTANCE.md)。

## 离线校验与构建

在仓库根目录运行 `node safevision/tools/verify_base_release.mjs`。只读验证 206 份生产输入、位流和全部本次交付文件，不接触串口、不联网、不烧录。验证器通过不是重新进行 HDL 仿真或 STA。

生产工程及显式清单保留在 safevision/platform、safevision/build/manifests；构建入口为 safevision/tools/run_v3_board.py / finalize_v3_four_features.py，BASE 必须显式 --engineering-base-only。使用 TD V6.2.168116，按原构建清单保持 top、参数、IP、管脚和约束一致；修改 RTL 后必须重新通过相关功能测试、原生 STA 和位流身份核对，不能继续沿用本位流的批准结论。

## 本地历史与空间

主项目为 D:\Safe_Vision_FPGA_2026；Codex 仅保留 D:\Codex\SafeVision_BASE_CURRENT 的现版工作入口。旧 SafeVision 试验目录的源码、Git 数据、成功位流及报告在主项目 artifacts/archive/codex_history_261023 按 SHA-256 去重压缩保存，旧任务原始工作区另行移入本地 archive；可再生编译缓存按白名单清理。其他无关项目和回收站保留。实际清理范围、校验和恢复方式以本地归档回执为准，不把逻辑大小直接当作磁盘实际释放量。历史归档不加入 GitHub 工作树；现版代码、文档、位流与验收资料进入仓库。
