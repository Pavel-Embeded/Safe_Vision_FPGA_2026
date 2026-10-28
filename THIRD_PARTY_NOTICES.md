# 第三方来源与依赖

板卡和FPGA为康芯HX4S20C/安路EG4S20BG256。平台目录保留原厂PLL、SDRAM、FIFO、HDMI等IP及来源指纹；来源与许可说明以原文件和各自manifest为准。本次不为厂商加密IP、板卡PDF、原理图或工具安装包另授许可证。

`qualification.zip`保存验收实际使用的板卡手册和原始证据，供私有项目追溯。厂商工具与许可证由开发者自行合法安装，本仓库不包含授权文件。Python标准库与Git用于交付复核，PDF解析使用pypdf，版本记录在发布验证环境清单中。

厂商加密IP内部没有直接仿真；外部接口模型、网表检查、STA与实际板卡结果分开记录，不能把模型的通过当成内部实现证明。

滚动字幕使用 Noto Sans SC Medium 的位图子集。正式配置包含 16 个字格，子集名为 SafeVisionSharedTicker16；原有 32 字测试子集 SafeVisionTicker16 保留在接口回归中。字体来源为 `notofonts/noto-cjk`，采用 SIL Open Font License 1.1，版权为 © 2014-2021 Adobe。许可证保存在 `safevision/assets/fonts/OFL-NotoSansSC.txt`。原字体提交、文件校验值及生成参数分别保存在同目录的 `v3_spectrum_ticker.provenance.json` 和 `v3_ticker16.provenance.json`。
