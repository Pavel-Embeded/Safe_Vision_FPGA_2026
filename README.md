# SafeVision FPGA 2026

SafeVision 在康芯 HX4S20C 开发板上运行，使用安路 EG4S20BG256。FPGA 完成 TF 卡读取、图像与声音处理、交互和故障恢复。BASE 26102801 输出 640×480 HDMI 画面和 48 kHz 立体声，底部显示中文滚动安全提示。

FAT32 根目录中的 BMP 可使用中文长文件名和不同尺寸。系统按确定的名称字典顺序选择前四张有效图片，保持比例、补黑边，再装载到 SDRAM。伴音先匹配同名 WAV，再按顺序回退；播放链支持 32 帧渐变、实体八项菜单、秒级运行时间和 512 点 FFT / 32 频段频谱。

| 入口 | 内容 |
| --- | --- |
| [当前版本](SAFEVISION_CURRENT.md) | 位流、源码、板测和 Flash 的版本关系 |
| [文档入口](docs/README.md) | 使用、模块、调试与历史资料 |
| [项目结构](docs/PROJECT_STRUCTURE.md) | 源码、约束、测试和交付目录 |
| [模块手册](docs/modules/README.md) | 接口、时钟、复位、握手和测试入口 |
| [中文字幕](docs/modules/scrolling_ticker.md) | 字模、位置、像素对齐与诊断 |
| [操作与恢复](docs/releases/BASE_26102801/OPERATIONS.md) | TF 卡、按键、Flash 固化及旧版恢复 |
| [菜单说明](docs/releases/BASE_26102301/MENU_CN.md) | 八项参数、状态数字及实体按键 |
| [调试记录](docs/debug/README.md) | 原始日志、逐次构建及故障修正 |
| [赛题对应](docs/requirements/official_problem1.md) | 四类基础要求和五类扩展方向 |

## 使用

1. 按 [当前版本](SAFEVISION_CURRENT.md) 核对位流 SHA-256，再按 [操作说明](docs/releases/BASE_26102801/OPERATIONS.md) 下载 SRAM 或固化 Flash。
2. TF 卡使用 FAT32，根目录至少放四张合法的 24 位或 32 位 BI_RGB BMP。伴音 WAV 使用 48 kHz、双声道、16 位 PCM。
3. 默认每张稳定停留 5 秒，随后进行 32 帧渐变。KEY2 换图，KEY3 切换自动轮播；KEY2+KEY3 同时长按约两秒进入菜单。
4. 按 [复查环境](docs/releases/BASE_26102801/OPERATIONS.md#离线复查环境) 准备 Python、Node.js 和固定依赖，再在仓库根目录运行 `python -B safevision/tools/verify_ticker_flash_delivery261029.py --run-dir <新的空目录>`，核对源码、位流、功能、时序和原始串口证据。

## 构建与验证数据

| 项目 | 本版记录 |
| --- | --- |
| 生产输入 | 226 份，另有 954 份批准依赖逐文件绑定 |
| 离线功能 | 325 个独立正向 top、278 项语义负向控制 |
| 原生 Slow/Fast 最小裕量 | setup +0.173 ns；hold +0.021 ns；recovery +3.478 ns；removal +0.030 ns |
| 资源 | LUT 18745/19600；DFF 13851/19600；RAM 64/64 等效单元；DSP 29/29 |
| 串口验收 | 40 组配置、8 组缩放、4 档周期；100 次有效换图、10 次恢复及 60 秒连续观察 |
| 证据复查 | 原始发送/接收字节、时序报告、源码指纹和位流校验值独立重放 |

BASE 26102801 已写入板载 Flash，完成厂商校验、两次完整读回及 Flash 重载后的串口检查。安装原件和旧成功位流一并保留，见 [当前版本](SAFEVISION_CURRENT.md)。用户已确认本版完全断电重接后各项正常，后续串口回读通过。

当前批准范围为 BASE。亮度由按键或串口设置，AUTO 控制图片轮播。记录中的性能和稳定性结论适用于所列板卡、媒体和显示器组合。厂商加密 IP 的接口验证、原生时序与实板采集分别记录。

开发约定见 [CONTRIBUTING](CONTRIBUTING.md)，依赖来源见 [第三方说明](THIRD_PARTY_NOTICES.md)。[GitHub Actions](https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026/actions/workflows/base-qualification.yml) 复查源码和已保存的证据。
