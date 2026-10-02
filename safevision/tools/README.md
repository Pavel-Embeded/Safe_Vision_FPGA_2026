# 工具脚本

`run_sim.ps1`：B 链（含板级 bring-up 顶层）ModelSim 回归；ModelSim 的 `win64` 目录与 `run_clock_sim.ps1` 同口径——传 `-ModelSimBin <win64目录>`，或设置环境变量 `MSIM_BIN`，两者都没给则报错退出（2），脚本里不再写死本机路径。`run_clock_sim.ps1`：A 的时钟复位单元测试，显式编译两份 clock RTL 与 `tb_clock_reset_ctrl.sv`；同样用 `-ModelSimBin` / `MSIM_BIN`，断言失败或工具缺失返回非零。此脚本与 B 回归分开，A 的断言数不与 B 的 514 项混计。`check_repo.ps1`：纯 PowerShell 目录与 B 回归文件引用检查（会解析 `run_sim.ps1` 里 `../rtl/`、`../platform/`、`models/`、`unit/` 的引用），不需要 ModelSim。新脚本须写清依赖、输入、输出及失败退出码。
