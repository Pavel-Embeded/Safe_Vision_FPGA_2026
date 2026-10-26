# 可移植性边界

| 层 | 允许依赖 | 换板时做什么 |
|---|---|---|
| `safevision/rtl` | Verilog/SystemVerilog 可综合业务逻辑、明确的抽象端口 | 保持协议与单元测试，复核时序/容量参数 |
| `safevision/platform/anlogic_eg4s20_hx4s20c` | EG4S20 引脚、PLL、FIFO/BRAM/SDRAM/HDMI IP、TD 工程与约束 | 换掉整层并重新做 STA、IP 仿真和板级验收 |
| `safevision/platform/sim` + `verification/models` | 行为级模型和仿真替身 | 只用于协议验证，不等同真实 IP 性能 |
| `safevision/build` | 文件清单、目标配置、工具版本 | 每个目标显式选源，结果带 Git 提交号与工具版本 |

换板验收时，重新核对物理内存容量、逻辑字节地址转换、FIFO FWFT/同步读模式、复位极性、PLL 频率、HDMI 音频能力、引脚和时序约束。手册给出的频率/带宽/水位属于设计目标或示例，新板实测值另行记录。第三方代码/IP 的许可与版本记录于 `evidence/provenance/`。
