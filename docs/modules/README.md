# 生产模块手册

此手册对应 BASE 26102301，生产入口为 `safevision_v3_top`。[发布索引](../../artifacts/releases/BASE_26102301_6a957b0/release.index.json) 记录 206 个实际输入的指纹。测试与综合各用显式文件清单，行为模型只参加仿真。

## 时钟与复位

| 域 | 当前职责 | 复位范围 |
| --- | --- | --- |
| REF，板载 50 MHz | SD、目录、媒体解析、启动计时 | 全局参考复位；媒体路径另有媒体复位 |
| SYS，BASE 50 MHz | 控制、UART、故障与恢复 | SYS 记录在媒体复位期间保留 |
| MEM，50 MHz | SDRAM 服务与环缓存 | 媒体复位及同步释放 |
| WRITE，100 MHz | packed cache 的两次 16 位写入 | 从共同媒体 epoch 异步置位、在写域同步释放 |
| PIXEL，标称约 25.185 MHz | 视频扫描、合成、频谱观察、HDMI 包服务 | 像素域复位；固定扫描与 SAFE 路径不随普通媒体复位清除 |
| AUDIO | 48 kHz PCM 调度、音量与报警 | 音频域复位；媒体部分和固定报警路径分开 |

频率来源于当前 PLL 配置，不是对晶振的仪器测量。参数按真实域频率换算。WRITE100 不能改接 SYS50；该错误曾造成实板缓存损坏，见 [修正记录](../changes/BASE_WRITE100_REPAIR_261023.md)。

## 模块职责与接口契约

| 模块/目录 | 输入输出与约束 | 验证重点 |
| --- | --- | --- |
| `storage/sd_initializer`、`sd_checked_sector_reader` | SPI 初始化和带检查的扇区读取；错误终止当前事务 | 初始化响应、超时、CRC、片选和完整扇区 |
| `storage/v3_shared_fs_service` | 共享扇区、目录与文件服务，按 owner 返回数据 | 地址两拍契约、反压、簇链边界和回绕 |
| `fat32_directory_scanner`、`v3_fat_name_store` | 目录项与完整 UTF-16 名称读口；LFN 顺序与校验和检查 | 长名、短名回退、目录末项、排序和扫描完成 |
| `v3_flexible_media_index` | 选前四张合法 BMP，查找同名或顺序回退 WAV | 名称比较、坏文件跳过、有界回退和目录超时 |
| `media/bmp_parser`、`v3_bmp_normalizer` | 24/32 位 BI_RGB 字节流变为 640×480 RGB565 画布 | 长度、偏移、padding、上下方向、等比例与黑边 |
| `storage/sd_bmp_player`、`memory/v3_row_integrity` | 装载槽、行 CRC 与读回批准；批准后才发布缓存有效 | 全帧像素、写入和读回时刻、错误拒绝 |
| `video/v3_packed_row_store`、`v3_line_cache` | packed 写入及显示行预取，按坐标返回当前/目标图样本 | WRITE100:MEM50 比例、刷新间隙、行标签和欠载 |
| `video/scaler` | 画布坐标和插值；BASE 常用模式为整数坐标 | 坐标、边缘夹紧、有效位及固定延迟 |
| `video/v3_presentation_ctrl` | 当前/目标槽、Fade alpha、generation 和提交事件 | 32 帧渐变、音频 ready、取消、超时和帧边界 |
| `video/video_compositor`、`v3_status_layers` | 颜色处理及背景、OSD、警告、HUD 合成 | Alpha 舍入、调色板、文字与同步标签；最终像素路径 21 拍 |
| `video/v3_audio_spectrum` | 实际左声道 PCM 产生 512 点 FFT 和 32 频段 | 去均值、Hann、FFT、频段与峰值、帧边界双银行发布 |
| [`video/v3_scrolling_ticker`](scrolling_ticker.md) | 中文安全提示、底条和帧边界位置更新 | 全部位置、独立字模、21 拍对齐、裁剪、诊断和媒体复位隔离 |
| `audio/v3_audio_system`、`v3_pcm_ring` | WAV 描述符、PCM 环缓存、48 kHz 调度、音量和报警 | 槽标签、声道、回绕、缺音频回退及媒体恢复 |
| `control/v3_user_controls` | 按键/UART 设置、轮播、菜单和配置回执 | 消抖、组合/长短按、范围、计时和配置保留 |
| `v3_supervisor`、`media_recovery_ctrl`、`safety/fault_manager` | 错误、心跳、欠载和进展驱动安全选择及最多三次恢复 | 错误并发、时间戳、无进展超时、恢复失败与 SAFE |
| `v3_frame_safe_select`、最终输出选择 | 在消隐窗口切换到文字和几何逻辑产生的安全画面 | 可见行内选择稳定、像素标签一致 |

## 握手与跨域

发送方在 `valid` 后保持载荷，直到 `ready` 接受。目录项、WAV 描述符和媒体代号不能只送单拍脉冲。多位数据使用异步 FIFO 或确认式邮箱跨域；配置在帧边界生效。

恢复清除媒体描述符及缓存批准状态，然后重新扫描和校验。图音提交需要目标 generation 对应的音频就绪。SAFE 图像和固定报警避免依赖 TF 卡/SDRAM 媒体内容，仍需要对应输出时钟和 HDMI 链路工作。

## 测试与变更

完整测试名称和分组保存在 [当前矩阵](../../safevision/build/qualification/four_features_261020.json)，执行证据由 [acceptance.json](../../evidence/v3/four_features_261020/acceptance.json) 绑定。目录、归一化、完整帧、PCM、FFT、菜单、跨域和恢复均有独立或整机检查。

修改接口时同时核对时钟、复位、端口顺序、握手与延迟。保留旧实例默认行为，更新明确的仿真/综合依赖；执行受影响测试后再检查完整资格。发布前重新核对资源和 Slow/Fast 的 setup、hold、recovery、removal。

源码入口：[RTL](../../safevision/rtl)、[生产顶层](../../safevision/platform/anlogic_eg4s20_hx4s20c/rtl/safevision_top/safevision_v3_top.v)。板级工程和厂商依赖保存在 [platform](../../safevision/platform/anlogic_eg4s20_hx4s20c)，具体接口补充见 [媒体与频谱架构](../architecture/flexible-media-and-spectrum.md)。
