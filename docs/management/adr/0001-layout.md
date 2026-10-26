# ADR-0001：可移植核心与板级适配分层

提出日期：2026-09-29。状态：待 A/B/C 评审。

## 背景

现有 B 链已按 `rtl/{common,storage,media,memory,include}` 组织，仿真脚本依赖这些路径。手册 V2.0 要求 A/B/C 并行、接口先行、证据追踪。板级 IP/引脚与业务 RTL 混放会使换板和仿真困难。

## 决定

保留 B 文件原位；新业务 RTL 分 A 视频、C 控制/安全/音频、可移植 core。安路 IP/引脚/约束集中在 `platform/anlogic_eg4s20_hx4s20c/`；文件表在 `build/`；测试按层放 `verification/`；原始结果和索引放 `evidence/`。只创建目录及说明，不生成假 RTL。

## 后果

换板时主要替换 `platform/` 并重做 IP/时序/上板验收；跨人接口仍需在 `docs/interface_spec.md` 审查。新增文件落点清楚，但它们在实现并提交证据前均保持“计划”状态。
