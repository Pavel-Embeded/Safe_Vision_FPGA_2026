# 仓库清点与基线

通过 GitHub 插件读回确认：`Pavel-Embeded/Safe_Vision_FPGA_2026` 为私有仓库，默认 main，当前账号具有读写权限。实施基线为 `98fb43beaa12bf903186ec73f6dc64e00d9259c7`，其上一提交 `0234402` 是原本地目录的 HEAD。

该基线共有 461 个跟踪文件：docs 42、evidence 44、safevision 369，另有 README、Git 配置与 GitHub 模板。平台无关业务 RTL 有 78 个 `.v` 文件，单元测试有 100 个 `.sv`，tools 有 45 个文件。这是基线的清点数字，新增 V3 文件另计。

已有真实内容包括 SD/SPI/FAT32/BMP/WAV 解析、SDRAM 仲裁与厂商适配、像素 FIFO、帧读取和 HDMI 包装、PLL、基本图层及 A 链显示管线；最新队友提交已加入 C 链控制/安全/音频 RTL 与七个单元 TB。文档还保留早期“只有 B 链”的叙述，不能用该叙述代替当前源文件清点。

尚未由基线完整装配的 V3 功能包括：四合法图常驻、坏候选跨批跳过、全行 CRC32、HD 源行复用、四层 Alpha/32 帧转场、真实字幕/HUD、独立 WAV/PCM 环、音画代号提交、完整 UART/菜单、有限故障恢复。此次采用新 V3 顶层装配，业务 RTL 与板级 IP 分开，保留旧顶层便于核对队友基线。

原目录唯一已知的未提交跟踪改动是 `safevision/platform/anlogic_eg4s20_hx4s20c/project/safevision.al`。在同步前保存了原字节副本，SHA-256：`183accc362ae8db3ffac3279579c14f3046907197fa65ec0c431ccb355088901`。同步操作必须保留该副本，不用重置覆盖队友其他新增修改。
