# 代码与交付归属

| 范围 | 主责 | 必需复核 | 交付 |
|---|---|---|---|
| `rtl/video`、`rtl/top`、板级 HDMI/约束 | A | B/C 按接口 | 视频、顶层、STA、集成报告 |
| `rtl/storage`、`rtl/media`、`rtl/memory` | B | A（帧/内存）、C（音频） | 数据链、带宽、水位与板级读写 |
| `rtl/control`、`rtl/safety`、`rtl/audio` | C | A | 控制、故障、安全与音频 |
| `rtl/common`、`rtl/include` | 提议者 | 受影响的所有链 | 公共契约、兼容性回归 |
| `platform/anlogic_eg4s20_hx4s20c` | A 集成 | 对应 IP 的链负责人 | 引脚、PLL、IP、约束、bitstream |
| `evidence/` 与需求追踪 | C 维护索引 | 测试执行人/A 复核发布 | 原始记录可追溯 |

“主责”是评审责任，不限制队友协作。现有 B 文件不因新目录调整而迁移；需要改所有权时在 ADR 与接口规范同步登记。A 的 `frame_reader` 与 B 的 `video_read_dma/frame_swap_*` 以接口划界：B 保证内存请求与数据交付，A 保证固定扫描速率下的消费、像素/同步对齐和 HDMI 输出。
