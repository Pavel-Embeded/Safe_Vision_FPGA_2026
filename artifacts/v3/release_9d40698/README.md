# SafeVision V3 离线验收交付

源码提交：9d40698de1d57fc46efb0b035ecf91cf58c3605b。BASE与HD均在清洁目录重新完成综合、布局布线、独立Slow/Fast STA和完整约束门禁，然后才生成位流。113项原生正向测试正常结束且零失败，28项语义负控正常结束并检出错误。

使用根目录的SafeVision_BASE_9d40698.bit或SafeVision_HD_9d40698.bit，先完成BOARD_STEPS.md中的BASE步骤。每份位流的SHA-256、全部资源和时序见release.index.json。Python运行verify_release.py可重新核验载荷、当前源码/证明字节、原始时序、资源、3072 ROM字节及位流哈希。

完整ZIP含编译时精确source快照和native/*/route.db；Git仓库保留位流及原始报告，原生数据库在完整包内。source快照中的进度文件保持源码提交时原样，最终结果以包根目录release.index.json为准。

重建须用已安装的TD6.2.168116，在全新ASCII目录运行source/safevision/tools/run_v3_board.py --repo source --run-dir D:/SV113_REBUILD --bitgen --source-repo D:/Safe_Vision_FPGA_2026 --source-ref 9d40698de1d57fc46efb0b035ecf91cf58c3605b。项目Git需保留此提交；不要复用已有非空运行目录。GUI入口为source/safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/base/safevision_v3_base.al和hd/safevision_v3_hd.al。

没有实体板卡验收。加密HDMI核心内部、SDRAM AC、PLL/DDR电气、显示器/音频/SD卡/线缆兼容及硬件长稳仍待实物测试；离线通过不能保证首次上板零错误。
