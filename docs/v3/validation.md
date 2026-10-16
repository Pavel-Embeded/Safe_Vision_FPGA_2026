# 可复现验证与发布规则

所有 XSim 运行目录必须使用 ASCII 路径，且与工程源码隔离。Vivado 2018.3 原生编译在受限沙箱中会有 `XSIM 43-3409/43-3915` 工具失败，需在正常审批后运行；这些错误不属于功能通过或 DUT 断言失败。不要改工具安装目录。

在仓库根目录使用可用的 Python 运行：

```powershell
python safevision/tools/run_v3_sim.py --suite v3 --run-dir D:/Codex/runs/v3
python safevision/tools/run_v3_sim.py --suite controls_period --run-dir D:/Codex/runs/controls_period
python safevision/tools/run_v3_sim.py --suite parser_digit_seen --run-dir D:/Codex/runs/parser_digit_seen
python safevision/tools/run_v3_sim.py --suite parser_compact --run-dir D:/Codex/runs/parser_reference
python safevision/tools/run_v3_sim.py --suite v3_board --run-dir D:/Codex/runs/board_units
python safevision/tools/run_v3_top_snapshot.py --run-dir D:/Codex/runs/board_top
python safevision/tools/run_v3_sim.py --suite c --run-dir D:/Codex/runs/c
python safevision/tools/run_v3_sim.py --suite layers --run-dir D:/Codex/runs/layers
python safevision/tools/run_v3_sim.py --suite audio_v3 --run-dir D:/Codex/runs/audio
python safevision/tools/run_v3_sim.py --suite video_v3 --run-dir D:/Codex/runs/video
python safevision/tools/run_v3_sim.py --suite media --run-dir D:/Codex/runs/media
python safevision/tools/run_v3_sim.py --suite media_crc --run-dir D:/Codex/runs/media_crc
python safevision/tools/run_v3_negative_controls.py --run-dir D:/Codex/runs/negative
python safevision/tools/run_v3_audio_negative.py --run-dir D:/Codex/runs/audio_negative
```

每个结果应有 `results.json`、原始 compile/elab/sim 日志和 `sources.sha256.json`。runner 要求进程成功、`$finish called`、用例结束标记、至少一个成功检查、所有 `errors=0` 且没有 FAIL/FATAL/ERROR；前后源码哈希必须一致。单独检查 waveform 或看到一条 PASS 不足以验收。

生成的SD卡镜像和独立期望文件同样参加前后指纹检查，以`generated:`条目区别于生产源码。证据清点器只接受当前suite显式声明、位于该运行目录内、前后清单一致且当前文件SHA仍相同的生成资产；拒绝漏清单、越界路径、未声明文件和中途改变。外部实验源码单列`EXTERNAL_SNAPSHOT_PASS`，不能算当前生产通过。18项清点器正负自测覆盖这些边界，清点器本身不代表发布验收。

`tb_v3_controls_period` 是正式必需回归，同时进入 `v3` 总清单。它检查运行中把30秒改2秒、再改5秒时，倒计时均从新窗口开始。`period_select` 的变化在至多一个SYS采样周期后重启计时，按键长按和轮播仍保留逐SYS时钟计数。`v3_controls_original_negative` 的原始故障正常结束但有2个错误，用于证明回归能够发现原缺陷，不能统计为功能通过。

`tb_v3_parser_digit_seen` 同时进入`v3`必需清单，覆盖16个前导零导致数字计数回卷的原始语法错误。独立期望检查合法正负数、32字符精确边界与无效嵌入负号；原实现正常结束但有7项错误。`parser_compact`另与原解析器做53212次逐拍对照，专项修正后的语法边界以独立期望为准。负控集合还将digit_seen的置位故意删除，要求正常结束并明确报错。

`tb_v3_priority_difference`进入`c`必需清单，600040项比较检查默认240样本斜坡、1样本/1025样本参数、全24bit有符号PCM、复位与valid气泡。最终只合入10bit饱和比较的最小修复，未采用面积增加的差分乘法候选；原1样本参数回卷错误必须由负控再次检出。

参考模型独立于 DUT：Pillow 解码完整 BMP 转 RGB565；Python zlib 给行 CRC32；缩放和混合使用独立整数公式；WAV 用独立 PCM 期望；完整输出帧包含坐标/同步、透明字模/几何和 alpha。检查器负控在临时副本破坏 CRC、前景、标签、恢复 ACK、音频代号与声道，要求明确的数据断言捕获，并校验原源码未变。

原始故障注入和反压必须保留，不降低测试阈值掩盖合法输入。厂商加密 HDMI 内部不支持当前 XSim 解密，测试使用其接口契约；实际官方源进入 TD 生产构建。不能因此把 HDMI 数据岛的内部功能或实体接收端兼容标为已仿真通过。

最终发布在源码冻结后分别重新综合、布局布线 BASE 和 HD。Slow/Fast setup、hold、recovery、removal 无负裕量；检查所有时钟/生成时钟、I/O 预算、无约束路径和 CDC/多周期实际命中。LUT/DFF/RAM 目标 70/65/75%，硬门槛 80/80/85%；超限须优化，不能删扩展功能或添加无依据 false path 来换取通过。

两份位流必须分别登记源码提交、TD 版本、HD 参数、IP 文件与哈希、SDC/ADC、完整源清单和 bit SHA-256。源码修改后影响的仿真和最终物理构建重新运行。带时序失败或缺报告的产物只可诊断，不能冠以发布位流。

V3生产入口是 `run_v3_board.py` / `run_v3_board.ps1`。`--synth-only` 仍执行资源硬门槛，超限返回 `RESOURCE_REJECTED` 和非零退出；正常综合不等于发布。`--bitgen` 要求同次BASE和HD均通过，并把构建依赖逐一匹配指定Git提交的blob。清洁隔离副本可使用 `--source-repo` 指向来源Git仓库、`--source-ref` 指向已冻结提交。

SDC文件只保留展开后的标准TD约束语句。TD的 `read_sdc` 延迟解析，不能用普通Tcl过程包装集合表达式；48组映射对象的存在检查在普通Tcl文件 `v3_cdc_audit.tcl` 执行。最终仍需逐项核对 `route.exceptions` 中实际Total/Dominated/Shadowed/Ignored路径，映射对象非空本身不代表约束生效或时序通过。每份综合还从mapped RAM INIT位解码，比对compact字模与状态文字的全部2048字节，防止资产文件存在但没有正确进入硬件。

最终还须运行独立 `audit_v3_raw_logs.py`：原始日志任意位置出现`[FAIL]`或`[SKIP]`、非零errors、工具Fatal/ERROR或缺正常finish，均拒绝。legacy A/B由Python wrapper逐正向用例读取原始日志；不能因PowerShell整体退出0或某条PASS就接受。16项raw审计自测及18项证据自测包含前缀FAIL与伪造汇总PASS，原始被撤回的B结果保留作负向见证。
