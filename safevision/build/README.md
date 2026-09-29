# 构建输入与输出

`manifests/` 放每个目标的确定性源文件表与 include 路径；`configs/` 放分辨率、像素格式、时钟/内存地图等可审查配置；`out/` 为工具生成结果，Git 忽略。当前 B 的仿真源列表仍在 `tools/run_sim.ps1`；建立新 filelist 前须与该脚本同步，避免两套清单漂移。未来每个 build 记录 Git commit、工具/IP 版本、目标板和约束哈希。
