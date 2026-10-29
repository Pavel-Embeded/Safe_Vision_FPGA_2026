# 构建与回归

## 工具

| 工具 | 使用版本或要求 |
| --- | --- |
| Python | 3.12 |
| Tang Dynasty | 已验收工具为 `V6.2.168116` |
| XSim | 已运行环境为 Vivado 2018.3 |
| Icarus Verilog | 使用 `-g2005`；GitHub 检查安装发行版工具 |
| Git | 构建记录绑定提交和实际源文件 |

基本检查和仿真驱动使用 Python 标准库。媒体生成、字库和数值工具所需的 NumPy、Pillow 版本保存在 `requirements-dev.txt`：

```powershell
python -m pip install -r requirements-dev.txt
```

所有命令从仓库根目录执行。TD、XSim 的运行目录使用英文路径，并放在仓库外。目录已有构建结果时，换一个新目录运行。

## 源码和语言检查

```powershell
python -B safevision/tools/check_source_tree.py
python -B safevision/tools/check_verilog.py --compile --elaborate --run-dir D:/sv_runs/verilog_check
```

`check_source_tree.py` 核对工程清单、ROM、管脚、配置及源文件。`check_verilog.py` 检查 HDL 扩展名、语言语法和受保护 IP 校验值，再以 Verilog-2005 模式编译可读取源码、展开仿真清单中的顶层。工具不在 PATH 时，通过 `--iverilog` 指定可执行文件。

## BASE 功能回归

```powershell
python -B safevision/tools/check_source_tree.py --simulate --xsim-bin D:/Xilinx/Vivado/2018.3/bin --output D:/sv_runs/base_regression
```

该入口运行字幕、共享字库、整机装配、目录扫描、读取重试、多尺寸 BMP 和频谱回归。单独运行一份清单：

```powershell
python -B safevision/tools/run_v3_sim_flexible.py --suite ticker_board261028 --run-dir D:/sv_runs/ticker_board
python -B safevision/tools/run_v3_sim.py --suite uart_link --run-dir D:/sv_runs/uart_link
```

仿真同时检查结束标记、自然结束、有效检查项、错误计数及输入文件一致性。失败诊断会写出 `[FAIL]`，运行脚本据此返回失败。

部分对照实验按固定历史提交核对源文件，应与对应归档一起使用。日常开发使用本页列出的检查和回归入口。

## TD 构建

先做综合检查：

```powershell
python -B safevision/tools/run_v3_board.py --mode base --synth-only --run-dir D:/sv_runs/base_synthesis
```

从已提交的源码构建、布局布线并生成 BASE 位流：

```powershell
python -B safevision/tools/run_v3_board.py --mode base --bitgen --run-dir D:/sv_runs/base_release
```

脚本先执行功能回归，再核对提交与实际输入。综合和实现分别由新的 TD 进程完成，最终时序也在新的进程中复核。所选模式全部通过资源、约束和时序检查后才生成位流。

默认 TD 目录为 `D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`，可用 `--td-root` 修改。HD 使用 `--mode hd`；每份输出按自己的构建记录验收。

## 提交约定

HDL 使用 Verilog-2005，HDL 测试模型也遵守同一语言范围。修改接口时更新源文件清单和对应测试；修改流水线时核对坐标、标签和数据延迟。时钟及约束变更应附带实际命中对象和 Slow/Fast 报告，检查 setup、hold、recovery、removal。

生成目录、数据库、波形、位流和原始运行日志放在仓库外。归档保存源码提交、工具版本、参数、约束、依赖校验值和位流 SHA-256。
