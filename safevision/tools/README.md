# 工具脚本

`run_sim.ps1`：现有 B 链 ModelSim 回归，代码路径保持不变；当前脚本含 `D:\modeltech64_10.7\win64` 本机路径，移植前需配置并在工具可用机器复测。`check_repo.ps1`：纯 PowerShell 目录与 B 回归文件引用检查，不需要 ModelSim。新脚本须写清依赖、输入、输出及失败退出码。
