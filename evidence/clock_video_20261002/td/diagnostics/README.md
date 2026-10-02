# 报告顺序隔离实验

这是早于最终交付复跑的同一 BASE routed 数据库实验，不是新的功能验收。原始路径为 work/final_td/base；数据库、输入 SDC、实验 Tcl 和原始报告在此归档。

只导入该 DB 并重读同一 SDC、update_timing，然后依次执行 timing-before → check-before → clock-summary → check-after → timing-after。
网表/约束不改，8 时钟和余量不变；clock definition local / not-connected 从 0 变成 4。该结果支持 TD 报告状态问题的推断，未获厂商确认，也不能消除独立 USR-6135 告警。

order_experiment.tcl 保留历史原文及硬编码的绝对路径，不读取模式或输出环境变量。复现时须在单独副本中将 import_db 改为本归档 order_base_route.db、read_sdc 改为 order_input.sdc，并将五个报告输出路径改到隔离目录；使用新 TD 进程。不得当成正式项目构建入口，也不要覆盖本次归档原件。
