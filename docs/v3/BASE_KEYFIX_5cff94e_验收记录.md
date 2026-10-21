# BASE 实体按键管脚修复与验收记录

此记录对应 four_features_BASE_KEYFIX_5cff94e，功能ID26102004。ID保留是因为本次没有修改任何功能RTL；精确版本由提交和位流SHA区分。

## 故障原因

用户已确认旧版左下秒计时递增、右下实际PCM青色波形出现，但KEY2+KEY3无法开菜单。
复核原始HX4S20开发板手册-HDL版2410第19页：KEY1=A2、KEY2=B2、KEY3=B1、KEY4=C1，按下均为低。
旧v3_board.adc把自动键btn_auto接C1、应急键btn_emergency接B1；独立参考JSON也重复了此错误。
因此实体KEY2+KEY3被解释为下一图+应急，组合菜单条件不能成立。
用户随后确认旧版KEY2+KEY4可以进入菜单并改变数值，形成实体对照证据。

## 修正与验证

- btn_auto改为KEY3/B1，btn_emergency改为KEY4/C1；功能RTL和SDC逐字节保留。
- 参考JSON一并改正；检查器额外固定四个实体编号与球位，并从原始PDF重取表格，防止两个表一起错仍通过。
- 288项不同功能测试、202项正常结束且发现错误的语义负控重新绑定当前源码。
- 额外11项管脚错误全部被拒绝，旧真实布线PAD报告因btn_auto位置不符被拒绝。
- 新增8组按键先后按下/松开、释放抖动、菜单/亮度/对比度/退出场景，实际XSim89项比较零错误。
- 新BASE重新综合、布局布线及独立进程最终STA通过。Slow/Fast setup、hold、recovery、removal均无负裕量；约束实际命中、IO范围、ROM、采样存储与资源检查全部通过。
- 原生全局setup WNS +0.145ns、全局hold WNS +0.029ns；细分路径最小setup +0.145、hold +0.030、recovery +4.212、removal +0.029ns。
- LUT18170/19600，DFF13116/19600，物理RAM等效60/64个9K单元；保留全部功能。

## 本地文件与实际下载

- 位流：`D:\Safe_Vision_FPGA_2026\artifacts\v3\four_features_BASE_KEYFIX_5cff94e\SafeVision_BASE_5cff94e.bit`
- SHA-256：`394a0f8151142886c3c950e3ea7220727258eb97dc8f8c7f73c954e8ef04f42d`
- 实际设计构建提交：`9c789eaddd514997c534602026ca14d20b03edbe`
- 冻结源码/证据批准提交：`5cff94eb70e800337e4617dbfa44349066f3d504`
- V3 GUI工程：`D:\Safe_Vision_FPGA_2026\safevision\platform\anlogic_eg4s20_hx4s20c\project\v3_board_verify\base\safevision_v3_base.al`
- 工具：TD V6.2.168116，目标EG4S20BG256。
- 已保存并核对6932个源码/证据文件；覆盖前备份在`D:/Codex/svkeylocal486b/backup`。
- 用户主分支HEAD保持`9e524950158586d106514506e621bec67a34b856`；本地验收引用`refs/safevision/local/four_features_BASE_KEYFIX_26102004`指向批准提交。
- 原始编程日志和串口：`D:\Safe_Vision_FPGA_2026\artifacts\board_validation\four_features_BASE_KEYFIX_5cff94e`。

已自动SRAM下载成功，实际串口身份正确，CACHE=15、STATUS=7；40项配置测试、540个有效ACK和42次健康观察全部通过，已恢复默认5秒轮播。
本轮健康记录FAULT、WAVFALLBACK、INTEGRITY、PRESENTATION、RECOVERY、VUNDERFLOW、UNDERFLOW、OVERFLOW、LEVEL均为0。

## 操作与实体边界

KEY2下一图、KEY3轮播开关、KEY4应急、KEY1媒体复位。
KEY2+KEY3同时长按约2秒，看到菜单后松开；短按KEY2/KEY3增/减；长按KEY2约1秒切换字段；长按KEY3约1秒退出。
首次菜单字段为亮度BRI，下一字段为对比度CON；顶部数值和画面应同步改变。

此文件生成时，修复位流的实体KEY2+KEY3验收正在进行；后续结果应查同目录physical_keys.acceptance.json，不把串口通过冒充实体显示通过。
较早同功能RTL的秒计时和青色PCM波形已获用户确认；新位流的多尺寸实卡显示仍须另做实体测试。
HD仍在独立解决布线拥塞，没有HD全时序通过声明。本次没有上传GitHub，也没有写Flash。
SRAM程序断电或按CONFIG1后会丢失并重载Flash旧程序；此前重连后实际读到过旧ID26101003，请用本位流重新SRAM下载恢复。

## 后续实体验收：已通过按键菜单

用户对本修复位流的四步操作直接回复“四步全部正常”：KEY2+KEY3进入菜单、亮度和对比度数值与画面增减、KEY3长按退出均已确认。
按键操作的长时间串口采集曾在120秒时断开，此段没有正常完成标记，不作为串口轨迹通过证据。
随后重新打开COM6，固件身份、CACHE=15、STATUS=7、默认AUTO=1/5秒以及全部健康计数再次通过。
独立短时串口正常结束，MENU=0、BRI=80、CON=128；最后选中FIELD=4，属于用户保留的菜单选择，不擅自改成对比度字段。
详见artifacts/board_validation/four_features_BASE_KEYFIX_5cff94e/physical_keys.acceptance.json及原始数据。
已修复实体KEY3/KEY4角色交换；HD和多尺寸实卡显示仍按前述边界分别验收。不写Flash，不上传GitHub。
