> 历史记录整理版。内容对应原记录的版本与日期，当前验收请查仓库首页；原件按索引保留。

# SafeVision 26101714 本地板级修复包

批准源码/功能证据/发布工具提交：03f7ea0559c5bd3a3e15b7931495945226860144。
工程候选：True；双模式发布：False。
完整应用实体显示与音频尚未验收。独立SDRAM的60000轮、61440000次比较零错记录单独保留，不能替代整机板测。

本包内每份bit均由最终全角时序、资源、约束健康、源码字节一致性及当前113正向/37严格负向测试门禁通过的冻结route.db生成。另有13项补充契约测试。BASE工程候选即使先于HD完成，也没有放宽BASE任何门禁；仅当two_mode_release=true才可声称两种模式离线构建均通过。

source/保留该bit批准时的精确构建输入和功能证据。运行verify_payload.py可核对全部载荷哈希、冻结源码/证明字节、113/37主门禁、13项补充契约及原始STA。该校验不替代新一次布局布线或实体板测，也不要求之后的HD参数试验与旧bit的全仓库快照完全相同。

在D:/Safe_Vision_FPGA_2026/artifacts/board_repair/repair_26101714_03f7ea0/选择BASE位流，用BitWriter的PROGRAM_SRAM下载。串口COM6为115200/8N1，保持供电，不按CONFIG1（会重新加载Flash旧程序）。当前临时SDRAM探针没有HDMI图像；下载完整BASE应用后再检查TF卡四图和音频。

先读取DIAG=0核对26101714，再核对CACHE=F、FAULT=0、INTEGRITY=0、PRESENTATION=0、RECOVERY=0；这些只代表内部状态，实际画面、声音、物理按键及长稳需要实物记录。坏WAV可能按规定使用ROM后备音。

release.index.json给出全部载荷SHA-256，approval.index.json给出批准时的逐文件源码和完整功能证据指纹。各模式reports保留原始STA、健康、例外命中、网表、参数和冻结数据库。包含绝对运行路径的原始文件保持原样，不能把搬运后的路径差异当作新一次构建。

按用户要求，本包只保存至本地，不上传GitHub。
