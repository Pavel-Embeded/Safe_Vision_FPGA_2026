# 26101003 下载候选

先下载 BASE/safevision_top.bit，HDMI 接 B 口，串口必须显示 ID=26101003。位流已通过内部严格 STA 和接口模型回归；开发板未连接，实板验收待完成。详细说明与验证边界见 ../../evidence/ab_sd_dqm_fix_26101003/README.md。

`test_card/` 含四幅已生成并逐字节读回验证的 640×480、24 位未压缩 BMP 和哈希清单。可复制 SV0001.BMP 到 SV0004.BMP 至 FAT32 卡根目录作首次复测；此操作不会替你格式化 SD 卡。
