# 构建输入与输出

`manifests/` 记录各目标的源文件表与 include 路径，`configs/` 保存分辨率、像素格式、时钟和内存地图等配置，`out/` 保存工具产物并由 Git 忽略。早期 B 仿真源表位于 `tools/run_sim.ps1`；建立新 filelist 时需同步核对，防止两套清单不一致。该阶段计划在每次 build 中记录 Git commit、工具/IP 版本、目标板与约束哈希。