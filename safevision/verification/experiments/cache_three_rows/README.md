# EXPECTED_FAIL：否决的三行视频缓存

这是独立架构实验，不进入生产源清单，也不属于生产必过项。实验将每流四行缓存减为三行，并将提前量从两行减为一行；在当时的物理 App 时序和 MEM50 下未满足视频期限，方案未采用。

`v3_line_cache_three_rows.v` 是完整候选源码，按 `row % 3` 选择 bank，保留通用随机坐标及原单拍读取。独立测试使用完整 HD 双流、八邻点、共享 48 kHz PCM、真实 adapter/arbiter/memory-controller 和包含命令/quiet/刷新间隙的物理 App 模型。首次记录有 336,465 个缺像素；音频799对且零欠载。生产选择四行加提前两行，并以另行打包的十块 RAM 保存数据。

在仓库根目录执行以下命令，使用 ASCII 运行目录。原生 XSim 需要在允许运行本机程序的环境执行。

```powershell
python safevision/verification/experiments/cache_three_rows/run_experiment.py --run-dir D:/Codex/runs/v3_three_rows_rejected
```

`manifest.json` 显式选择本目录候选源码，不覆盖生产 RTL。脚本保存全部源及 include 哈希、原始编译/仿真日志和 `experiment_results.json`。只有进程正常结束、出现视频期限断言、缺像素非零、错误数恰为缺像素数、音频无欠载且运行期间源哈希不变，才返回 `EXPECTED_FAIL`。工具崩溃、缺少结束标记或出现别的错误不会被当作成功复现。脚本退出0表示“否决结论被正常复现”，绝不表示该缓存可用于生产。
