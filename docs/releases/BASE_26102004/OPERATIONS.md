# 板卡运行、按键、串口与故障定位

## 启动与 TF 卡

目标 HX4S20C / EG4S20BG256。TF 卡使用 FAT32；根目录至少放置四组合法媒体，推荐连续编号 `SV0001.BMP`：`SV0004.BMP` 和对应 `SV0001.WAV`：`SV0004.WAV`。BMP 为24位BI_RGB，无压缩，宽1 至 1920、高绝对值1 至 1080，支持正/负高度及4字节行填充。WAV使用48kHz、16位双声道PCM。不要把JPEG/PNG更名成BMP。

四幅图归一化为640×480后常驻SDRAM，按行CRC32和读回检查通过才发布。坏文件会跳过。首次大图扫描最多预算60秒，等待期间可能显示SAFE；这不能直接等同读卡故障。不同尺寸测试媒体放在 `artifacts/test_media/four_features_261020/`，复制前先备份原卡；本发布未声称已做这组实体卡验收。

## 下载正确位流

1. 对照[发布指纹](RELEASE.md)，使用本发布目录的 `SafeVision_BASE_5cff94e.bit`。运行时ID与旧同功能位流相同，只看ID不足以区分管脚修复。
2. 先执行完整[离线复核](BUILD.md)，确认通过。
3. TD BitWriter 选择 PROGRAM_SRAM，JTAG下载；实际成功日志应包含器件验证和成功结束。已通过的下载日志见板测 `programming/`。
4. 保持供电。按 CONFIG1 或断电会重新加载Flash里原先程序；本发布验收只写过SRAM，没有更新Flash。
5. Type-C数据口连接板载串口，115200/8N1，不使用JTAG的USB-B口作串口。COM号以当前设备管理器为准，历史测试为COM6。

仓库保留原机专用 `burn_four_features_26102004.ps1`，内部绑定 `D:/Safe_Vision_FPGA_2026`、原厂工具和原机Python路径，不作为跨电脑通用下载器。新电脑用上述BitWriter步骤；先用新验证器准备的冻结包验证，再使用输出包中对应位流。不要直接套用旧版 `burn_verified_sram.ps1` 和旧ID脚本。

## 按键与菜单

所有按键按下为低电平。

| 实体按键 | 球位 / 端口 | 常态 | 菜单内 |
|---|---|---|---|
| KEY1 | A2 / rst_n | 媒体复位；不清启动计秒/配置 | 同左 |
| KEY2 | B2 / btn_next | 下一幅 | 短按增加，长按约1秒切下一字段 |
| KEY3 | B1 / btn_auto | 开关自动轮播 | 短按减少，长按约1秒退出 |
| KEY4 | C1 / btn_emergency | 应急 | 应急优先 |

KEY2+KEY3 同时长按约2秒进入菜单（实际操作可保持3秒），看到后松开，再做短按。不要一直按住组合键同时期待短按。选中字段会保留，重新进入时不保证总是亮度字段。用户已确认本位流菜单、亮度/对比度画面变化与退出正常。

| 参数 | 范围 / 默认 |
|---|---|
| 亮度 BRI | 0 至 100%，步长5，默认80%；RGB偏移为 `2*pct-100` |
| 对比度 CON | Q1.7系数64 至 255，步长8，默认128（1倍） |
| 音量 VOL | 0 至 100，默认70；静音波形应为零线 |
| 自动周期 | 2、5、10、30秒，默认5秒 |
| 缩放 | 最近邻或双线性；1:1/FIT/半尺寸/四分之一 |
| 转场/叠加 | 默认32帧Fade，四层Alpha，菜单可调对应字段 |

配置在KEY1或媒体恢复后保留，重新配置/断电恢复默认。画面左下 `UP … s` 从FPGA配置完成后的逻辑启动计秒，不包含电脑传输位流耗时。右下青色线是实际PCM波形；稳态正弦可能稳定，小振幅可能接近零线，不需要柱状图跳动。

## 串口验收

先关闭占用同一COM端口的终端；默认DTR/RTS关闭。下面会读卡状态并执行真实配置测试，不要同时操作按键。

```powershell
powershell -NoProfile -File safevision/tools/host/wait_ready.ps1 -Port COM6 -OutDir D:/sv_board/ready_new -DurationSeconds 90 -ExpectedId 0x26102004
powershell -NoProfile -File safevision/tools/host/exercise_configuration_26102004.ps1 -Port COM6 -OutDir D:/sv_board/config_new
python -B safevision/tools/host/audit_configuration_26102004.py D:/sv_board/config_new
```

使用新目录。正常应确认ID26102004、CACHE=15、STATUS=7、AUTO=1/PERIOD=5，并核查FAULT、WAVFALLBACK、INTEGRITY、PRESENTATION、RECOVERY、VUNDERFLOW、UNDERFLOW、OVERFLOW、LEVEL。ACK成功不能代替屏幕与声音观察。旧无后缀配置脚本面向26101802，不用于此版本。

## 常见现象

| 现象 | 排查顺序 |
|---|---|
| 只有SAFE/emergency画面 | 核验位流SHA及实际ID→TF格式/合法文件数量→CACHE/STATUS→完整性/恢复计数；不要先更改时序例外 |
| KEY2+KEY4才能开菜单 | 很可能运行旧交换管脚位流；核对SHA和B1/C1映射，不只看ID |
| 拔线后回旧界面 | SRAM丢失并从Flash重载；重新PROGRAM_SRAM本位流 |
| 波形很小或不明显变化 | 查实际音源/音量/PCM数据；当前是音频波形，稳定正弦可静止，不伪造柱高 |
| 最大图恢复回SAFE | 重扫可能超过4.9秒恢复预算；冷启动60秒预算和媒体健康要分别核查 |
| COM口消失/被占用 | Type-C数据线、CH340设备及当前COM号；保留错误日志，端口关闭不算通过 |

每次提交故障附位流SHA、板卡/工具、媒体列表、操作步骤、原始rx.bin/trace.jsonl和正常结束状态，参见 [CONTRIBUTING](../../../CONTRIBUTING.md)。
