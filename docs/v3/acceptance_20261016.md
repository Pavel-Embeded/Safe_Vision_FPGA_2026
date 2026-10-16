# 2026-10-16 当前实施检查点

发布验收尚未完成。当前源码的资源占用仍高于批准硬门槛，没有通过完整 BASE/HD 路由验收的最终位流，也没有实体上板结果。实施分支、原工程已有配置和验证记录分别保全；实际上传与本地副本一致性以 outputs 中的同步回执为准。

## 当前源码新增修正

1. FPS 在秒边界收到第256个帧脉冲时保持255，避免8bit加法回卷0。秒计数宽度由频率参数推导。新增 PIXEL_HZ 放在显示核原有参数之后，保留旧位置参数的含义。
2. 板级按厂商 PLL 整数参数向显示核/HUD传递名义频率：BASE 为680000000/27 Hz，HD 为222500000/3 Hz；计数器使用四舍五入的25185185/74166667。通用显示核的标准视频默认频率保留。HD接口模型半周期按名义配置量化到1ps，不能当作厂商PLL、电气或相位仿真。
3. FAT32目录和共享文件内核的cluster_sectors替换为三层移位网络。全部32bit地址、模32bit溢出语义及非法SPC返回0均保留；不缩小簇号或文件长度，不改变时钟或握手。

## 当前已完成与仍在执行的验证

FPS独立整数oracle的16396次比较正常通过；旧原件在同一oracle下正常结束并检出3075错误。当前清洁源快照的FPS两项、BASE/HD板级频率参数链及预置计数终点、顶层装配、双模式音频压力、FAT几何和两个目录专项均正常结束。名义时钟检查器的五种漂移负控全部拒绝，分别覆盖PLL分频、HUD标尺、参数漏接、输入SDC和反馈模式。

FAT网络独立比较234304项，涵盖全部256种SPC、每个32bit位、边界值和100000组随机值；故意将第二级移位2改成3的负控正常结束且明确检出。当前A链5项、B链28项、系统V3单元、BMP边界、四槽行CRC均已正常结束，7项功能负控和6项音频负控全部正常结束并检出。

当前完整音频11项已正常结束。其余相位/音量/图层矩阵、BASE/HD完整输出帧及默认32帧Fade、真实SPI四幅图/四轨WAV长测另有独立任务；未获得正常退出、结束标记、零errors及来源一致性之前不算通过。原始日志和当前来源登记见 evidence/v3/fps_cluster_20261016；完整清点继续更新，不用重复运行次数冒充覆盖范围。

## 资源与物理构建

同路径完整综合，在area_prior、min_control_set=1、min_ripple_len=64下，FAT网络使BASE 17374→17286 LUT，HD 18117→17957 LUT；DFF分别13179/13357，RAM各50，DSP各13/26。这一映射配置仍在隔离比较，尚未写入正式GUI/CLI共同参数。硬门槛保持LUT/DFF各15680、RAM至多54个物理9K块。任何候选都不得据此标为发布通过。

隔离Alpha偏置候选以完全整数公式保持原三拍接口，通过1052584次旧实现/独立舍入比较，故意把舍入偏置加1的负控准确检出。单模块实际综合212→174 LUT，但DFF 41→60，整机映射结果仍在比较；它尚未进入生产。

旧视频候选的BASE/HD布局分别需要4957/5041个MSlice，超过器件4900。后续更高打包力度候选的BASE已进入布线，但仍以物理布线冲突失败，不能当成时序通过；HD和其他参数仍单独执行。最终必须在选定提交上重新完成两种模式的Slow/Fast setup、hold、recovery、removal、约束健康与资源检查，随后才允许生成发布位流。

## 历史检查点与可追溯性

提交0c8955c的91项原生正向测试、13个严格负控，以及614400完整图字/1920行CRC/24000对PCM真实SPI通过记录，完整保存在evidence/v3/bmp_row_20261016。更早f25f070的68项记录位于evidence/v3/acceptance_20261016。这些是各自源码快照的结果；当前FPS、板级时钟或FAT依赖变化后，不能自动继续称为当前通过。

三份生产runner拒绝原始日志任意位置的FAIL/SKIP及前缀错误。六个原生哨兵证明三个正控接受、三个前缀FAIL负控拒绝。历史B28/670伪通过已撤销；修正测试台并逐原始日志复审后的B28/672正常通过，失败原件保留。

GitHub main最近读回仍为98fb43b。实施分支为codex/safevision-v3-20261016；main快进及原工程根目录最终同步等待验收完成。原工程已有safevision.al保持SHA-256 183accc362ae8db3ffac3279579c14f3046907197fa65ec0c431ccb355088901。检查点另存D:/Safe_Vision_FPGA_2026/codex_v3_checkpoints，逐Git对象读回校验，不覆盖已有工程。

## 可重现入口与边界

在源码根目录运行，所有--run-dir必须是全新ASCII目录：

```powershell
$py="C:/Users/曲梓铭/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
& $py safevision/tools/check_v3_clock_contract.py --output D:/SafeVisionRuns/clocks.json
& $py safevision/tools/check_v3_clock_selftest.py --output D:/SafeVisionRuns/clock_controls.json
& $py safevision/tools/run_v3_sim.py --suite video_v3_fps --run-dir D:/SafeVisionRuns/fps
& $py safevision/tools/run_v3_sim.py --suite v3_board_clocks --run-dir D:/SafeVisionRuns/board_clocks
& $py safevision/tools/run_v3_sim.py --suite cluster_shift --run-dir D:/SafeVisionRuns/cluster_shift
& $py safevision/tools/run_v3_audio_sim.py --suite audio_complete --run-dir D:/SafeVisionRuns/audio_complete
& $py safevision/tools/run_v3_shared_storage.py --run-dir D:/SafeVisionRuns/shared_storage
& $py safevision/tools/run_v3_sim.py --suite video_v3_final --run-dir D:/SafeVisionRuns/video_final
```

这些仿真替代了加密/物理IP边界，不能覆盖厂商HDMI发送核内部、PCB电气、实体显示音频兼容或真实板卡长稳。无板条件不能保证首次上板零错误。
