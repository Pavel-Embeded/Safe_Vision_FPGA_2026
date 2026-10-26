> 历史阶段记录，版本、参数与结论按原记录日期理解。当前 BASE 的模块和验收状态见仓库首页。

# V3 需求到实现和验收

此次需求取自用户提供的手册 V3.0，整本原文件不上传仓库。BASE 与 HD 分别执行仿真和最终 TD 发布检查。

| 需求 | 实现位置 | 软件可验证的验收 | 实物验收 |
|---|---|---|---|
| B01 本地媒体 | sd_bmp_player、file_index、checked_sector、row_integrity | 至少四合法 BMP、坏文件跳过、碎片簇链、独立完整图核对、读回 CRC | 10 次冷启动，真实 SD 兼容 |
| B02 缓存稳定显示 | 四常驻槽、v3_line_cache、fixed video_timing、HDMI bridge | 完整帧逐像素、无欠载、固定同步、内存延迟/反压、CRC 故障退 SAFE | 连续 60min，无花屏/撕裂/黑屏 |
| B03 交互 | v3_user_controls、presentation、UART | 去抖、100 次转场、忙回执、2/5/10/30s、原子 vblank 提交 | 两实体按键与串口 |
| B04 HDMI 音频 | v3_wav_source、PCM环、优先级、ACR、官方 HDMI core | 48k 立体声逐样本、代号、声道/位对齐、N/CTS、恢复后继续 | 两台 HDMI 显示器枚举/出声，30min 音频 |
| E01 四层 Alpha/字幕 | alpha_blend、v3_status_layers、最终扫描管线 | 背景→OSD→应急→HUD，透明像素、/255 舍入、字形和全帧对齐 | 实际可读性/显示色彩 |
| E02 Fade | presentation 32 帧、audio generation ready | alpha 轨迹、最终一帧提交、100 次转场、不匹配代号拒绝 | 主观流畅性 |
| E03 缩放 | scaler_coords、bilinear、源行复用 | BASE 1:1、HD 4:3 fit/居中、近邻与双线性独立参考、边缘夹紧 | 两分辨率显示 |
| E04 参数/HUD/恢复 | controls、status、supervisor、recovery | 亮度/对比度/音量/滤波/缩放/alpha；真实计数；1000 故障注入；3 次失败锁定 | 拔卡/键入/PLL 故障响应与长稳 |
| E05 音频可视化 | audio_energy、HUD LEVEL | 1024 样本窗口与能量值、菜单关闭仍显示 | 音画联动观感 |

实体 HDMI 音频/显示兼容和 24h 长稳尚需真实板卡，未因仿真通过而勾选。缺失、超时、工具崩溃、SKIP、没有正常结束标记均不计通过。
