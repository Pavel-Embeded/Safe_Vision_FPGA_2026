> 历史记录整理版。内容对应原记录的版本与日期，当前验收请查仓库首页；原件按索引保留。

# SafeVision 26101736 完整应用本地工程候选

批准源码、功能证据和工具提交：674c62e86b1a8497277f93f5ad287cc76d9dcf23。
工程候选：True；双模式发布：False。

本包保留TF四图、HDMI、音频、按键、菜单和故障恢复功能。集成33实板通过的物理读写四字边界对齐、写首尾掩码、读首尾过滤及存储末端裁剪。33对旋转读起点、混合突发、六种图案和保护字完成46272次实板比较零错；这不替代本包完整应用上板验证。

包含精确UART超时、事件原时间戳流水、DIAG分组快照、非活动回执银行保持。36另外优化基础fat32_cluster_walker，并以独立参考完成全部128个入口逐周期等价检查；整机共享文件系统实际使用v3_cluster_walker_ctx，该实例未应用本项优化。不能把基础模块优化声称为整机关键路径修复。

位流必须通过114项正向、48项唯一且正常结束的语义负控和14项补充契约门禁；变化依赖重跑，字节完全相同的依赖才复用。36原编排负控重复错误已拒绝，独立重跑11项唯一变化负控；接受证据见current_gate_verified_02及orchestration_repair.json。实际生成输入经过独立重放与逐文件SHA核对。

BASE来自最终布局布线、独立STA、约束健康和源码绑定均通过的冻结数据库。最小setup +0.122ns、hold +0.024ns、recovery +4.849ns、removal +0.022ns，负路径为零。LUT17509/19600，片上RAM53/64。仅当two_mode_release=true时方可声称BASE与HD均通过；BASE工程候选没有放宽任何BASE门禁。

source/保留批准时精确输入和完整功能证明；reports/保留原始时序、约束和数据库。运行verify_payload.py核对载荷SHA、冻结源码、功能证明及原始STA。该校验不能替代实体屏幕、声音、按键和长稳验证。

从D:/Safe_Vision_FPGA_2026/artifacts/board_repair/repair_26101736_674c62e/选择BASE位流。先校验全部载荷，再打开COM6，最后由官方BitWriter CLI通过JTAG下载SRAM；不写Flash，不按CONFIG1。DIAG=0须读到26101736，随后核查CACHE=F、CRC、故障状态、转场和音频计数。没有WAV时按设计可用ROM后备音，须按故障等级和具体状态判断。

release.index.json和approval.index.json记录精确身份、参数、时序及SHA。hardware_verified=false表示本包生成时尚未完成整机实测，后续板测应新增独立记录，不能改写本包冻结证明。

按用户要求，仅保存本地，不上传GitHub。
