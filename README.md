# SafeVision FPGA 2026

面向康芯 HX4S20C / 安路 EG4S20BG256 的 FPGA HDMI 多媒体与应急终端。

**当前稳定交付：BASE 640×480，固件 26102301。** 任意名称/不同尺寸 BMP 等比例读取、四图轮播、自动配音、真实音频频谱、秒级运行时间及实体菜单集成于同一位流；图片、声音、频谱和实体菜单已获用户反馈。Flash 已固化并完成重载后的完整串口验收，真实完全断电重启待验。

| 从这里开始 | 内容 |
| --- | --- |
| [当前版本](SAFEVISION_CURRENT.md) | 唯一推荐下载、SHA-256、源码与构建身份 |
| [版本交付](docs/releases/BASE_26102301/RELEASE.md) | 模块职责、资料入口与交付范围 |
| [实物菜单详解](docs/releases/BASE_26102301/MENU_CN.md) | 八项参数、按键、状态含义及真实照片 |
| [使用与恢复](docs/releases/BASE_26102301/OPERATIONS.md) | 媒体规则、Flash、旧版恢复和构建入口 |
| [分层验收](docs/releases/BASE_26102301/ACCEPTANCE.md) | 仿真、布局布线、位流、串口、实体效果与待验边界 |
| [媒体与频谱架构](docs/architecture/flexible-media-and-spectrum.md) | 名称排序、BMP/WAV、缓存、跨域和 FFT |

## 快速使用

1. 取当前 [BASE 位流](artifacts/releases/BASE_26102301_6a957b0/SafeVision_BASE_6a957b0.bit)，先核对 [release.index.json](artifacts/releases/BASE_26102301_6a957b0/release.index.json) 的 SHA-256。
2. FAT32 根目录放至少四张合法 BMP；中文/长名与不同长宽比均支持，按名称字典顺序取前四张有效图，等比例居中并补黑边。音频优先同名 WAV，再按目录候选回退。
3. 默认 5 秒自动轮播，音量 70。KEY2 换图、KEY3 切换自动；KEY2+KEY3 同时长按约 2 秒进菜单，按 [菜单说明](docs/releases/BASE_26102301/MENU_CN.md) 调参。
4. 仓库根目录执行 `node safevision/tools/verify_base_release.mjs`，离线核对本次交付与 206 个生产输入。

## 项目结构

```text
safevision/rtl/              存储、视频、音频、控制与安全实现
safevision/platform/         生产顶层、板级管脚、时钟、厂商 IP 与 TD 工程
safevision/build/manifests/  显式综合和仿真文件清单
safevision/verification/     单元、链路、整机、独立模型与负控
safevision/tools/            构建、审计、发布和只读交付验证器
docs/                       架构、接口、缺陷修正、使用与版本说明
evidence/v3/                绑定输入的原始测试证据与历史
artifacts/releases/         当前精简交付包及保留的成功历史包
```

## 验收摘要

| 项目 | BASE 26102301 |
| --- | --- |
| 既有离线功能 | 303 个独立正向 top、304 条含别名记录、221 项语义负控 |
| 原生 Slow/Fast 最小裕量 | setup +0.195 ns；hold +0.030 ns；recovery +3.767 ns；removal +0.038 ns |
| 芯片资源 | LUT 18749/19600；REG 13875/19600；等效 RAM 63/64；DSP 29/29 |
| Flash 重载后 UART | 40 项配置、八缩放组合、四周期、两次恢复、持续轮播；5016 帧 ACK 独立复核通过 |
| 实体效果 | 图片/声音/频谱及菜单用户反馈保留 |
| 真实完全断电启动 | 待用户方便后执行，未标通过 |

本轮交付未改动物理 RTL/约束/IP 和位流，不将文档提交冒充新的仿真或布局布线。HD 不在本次批准范围。芯片实际容量与原生时序通过是资源验收条件；厂商加密 IP 内部、其他卡/显示器兼容性及长期运行按各自证据单独验收。

协作与验证要求见 [CONTRIBUTING](CONTRIBUTING.md)，变更记录见 [CHANGELOG](CHANGELOG.md)。历史入口仅作追溯，以本页及 SAFEVISION_CURRENT 为当前版本。
