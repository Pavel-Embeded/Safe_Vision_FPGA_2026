# Clock / Video Timing 最终 XSim 验证报告

验证日期：2026-10-02（Asia/Shanghai）。本报告仅记录本次实际运行结果。

## 1. 工具、输入与复现

- 运行脚本：目标仓库 `safevision/tools/run_video_clock_sim.ps1`。
- 仿真器：本机 Vivado Simulator 2018.3（XSim），RTL / 安路模型按 Verilog 编译，测试台按 SystemVerilog 编译。
- 安路库：TD 6.2.1 Engineer 6.2.168.116 的 `sim_release/eg4/eg_logic_clk.v` 与 `eg_phy_pll.v`。
- PLL：实际使用 TD 官方生成的 `sv_system_pll.v`、`sv_video_vga_pll.v`、`sv_video_hd_pll.v`、`sv_audio_pll.v`。
- `source_sha256.txt`：25 个实际仿真输入（全部参与运行的 RTL、TB、五份头文件、runner 与两份安路库）的 SHA-256；包含 safevision_defs 递归引用的错误码、像素格式和事件码头。
- `repository_hdl_sha256.txt`：仓库 66 个 Git 非忽略 `.v/.sv/.vh` 文件的最终交付快照（包含随后新增的 TD 检查顶层）；此文件包含未在本次仿真中例化的其他模块，不能据此宣称它们通过仿真。
- `pll_config_sha256.txt`：4 份 canonical `.ipc` 配置文件 SHA-256。

实际运行命令（在 PowerShell 中）：

```powershell
& 'D:\Safe_Vision_FPGA_2026\safevision\tools\run_video_clock_sim.ps1' `
  -RepoRoot 'D:\Safe_Vision_FPGA_2026' `
  -RunDir 'D:\Codex\2026-09-30\sao\work\delivery_xsim'
```

最终进程退出码 **0**，5 个 case 的编译、展开、运行退出码均经过脚本检查，并且每个仿真日志均具有指定 PASS 标记。

## 2. 五项结果

| Case | 实际结果 | 证据 |
|---|---|---|
| `video_timing` | VGA、HD720 各检查 2,477,500 个像素周期；小参数实例检查 150 个周期；覆盖当前 x/y 与所有标签同拍、行/帧边界、空白、同步极性，以及扫描中异步复位 | `xsim/video_timing/xsim.log` |
| `clock_reset` | 88 pass，0 fail；包括 9 个复位出口、各局部请求隔离、每个锁定信号失锁/恢复、板级异步复位，以及 2/3 级同步释放 | `xsim/clock_reset/xsim.log` |
| `frame_swap_existing` | 原有 B 组测试台 23 pass，0 fail；正常换帧和故障/超时回退回归通过 | `xsim/frame_swap_existing/xsim.log` |
| `frame_swap_real_frame` | 两个边界相隔 1,666,667 个 100 MHz 周期；默认 5,000,000 周期超时未提前触发；2 次提交，0 错误 | `xsim/frame_swap_real_frame/xsim.log` |
| `clock_video_subsystem` | BASE 与 HD 两种真实 TD PLL 模型集成均通过：五个输出时钟的周期和高/低半周期、实际逐像素 5:1 边沿数、九复位、局部复位不断扫描、板级复位及 PLL 重锁 | `xsim/clock_video_subsystem/xsim.log` |

`video_timing` 单测采用便于运行的测试时钟，检查的是扫描几何及其逐周期行为；全帧物理秒数需结合 PLL 整数比计算。它并未把 100 MHz 测试时钟声称为 VGA 像素时钟。

## 3. 官方 PLL 模型实际测量

下表来自集成日志 `MEASURE` 行。两模式的 sys / mem / audio 测量相同。

| 时钟 | 仿真周期 ns | 高电平 ns | 低电平 ns |
|---|---:|---:|---:|
| sys | 10.000000 | 5.000000 | 5.000000 |
| mem | 8.000000 | 4.000000 | 4.000000 |
| BASE pixel | 39.708000 | 19.854000 | 19.854000 |
| BASE serial | 7.941600 | 3.970800 | 3.970800 |
| HD pixel | 13.482000 | 6.741000 | 6.741000 |
| HD serial | 2.696400 | 1.348200 | 1.348200 |
| audio | 81.379400 | 40.689700 | 40.689700 |

每个输出时钟在启动和重锁后均取得超过 100 个完整周期/高低半周期；每个观测周期都与整数比理论周期比较，容差为 **0.010 ns（10 ps）**。这不是仅观察 `locked` 或仅统计总边沿数。

串行/像素另做实际边沿计数：BASE 启动后 255 个连续像素窗口、重锁后 255 个窗口；HD 启动后 742 个窗口、重锁后 742 个窗口。**每一个**窗口都严格含 5 个 serial 上升沿。

局部复位同时保持 media、memory client、HDMI 两域和 audio consumer 处于复位时，基础 sys / mem / pixel / serial 仍运行；扫描索引在 100 个像素上升沿后精确增加 100。单测另验证每个请求独立隔离。

### 为什么测量值与整数比末位略不同

官方 `EG_PHY_PLL` 功能模型每个 VCO 半周期使用 100 fs 精度，输出分频会累积这类时间量化。测试台自身使用 1 ps 精度；本次集成仿真的全局精度是 100 fs。数 ps 的模型差异应按此解释。

硬件标称输出频率应按官方生成参数计算，而不能把上表末位量化结果当作板级频率测量：sys 100 MHz，mem 125 MHz，BASE pixel 25.185185185 MHz / serial 125.925925926 MHz，HD pixel 74.166666667 MHz / serial 370.833333333 MHz，audio 12.288135593 MHz。

## 4. 已处理的运行环境问题

首次运行未进入任何仿真：`xelab` 在生成 C 文件的 MinGW 编译阶段报 `XSIM 43-3409`。相同 GCC / 相同生成 C 文件的对照显示：本机中文用户 TEMP/TMP 路径下会挂起；临时切到本次工作目录中的 ASCII 路径后，直接 GCC 编译约 1 秒成功。

runner 已修正为：每个 case 在 `try/finally` 中仅临时设置当前进程的 TEMP/TMP 为自己的 ASCII `<caseDir>/tmp`，随后恢复原值。未修改 Windows 系统或用户环境变量。实际最终重跑已通过全部五项。

## 5. 日志警告和验证边界

1. XSim 对安路库未使用的 IEEE-1735 加密区域打印两条 `CRITICAL WARNING`。本次使用的 `EG_PHY_PLL`、`EG_LOGIC_BUFG` 及其实际例化的辅助逻辑是库中可编译部分；真实时钟与锁定输出均已驱动并通过测试。未更改或解密官方库。不能据此宣称库中其他加密模块可在 XSim 中验证。
2. 官方生成 IP 将 `load_reg` 接 `1'b0`，库内部将该同名线声明为 5 位，XSim 展开打印四条位宽警告；零扩展后仍是全零动态控制输入。保持官方生成源原样，静态时钟输出的实际行为通过了上述测量。
3. 本报告是 **RTL / 官方 PLL 功能模型仿真**，不涵盖真实器件 PLL 抖动、晶振误差、模拟锁定时间、亚稳概率或显示器兼容性。
4. TD 的布局布线、setup/hold/recovery/removal 时序结果应阅读相应独立 TD 报告；这些不能由本报告替代。
5. Frame Reader、FIFO 像素供给、TMDS DDR 串行化、HDMI 音频 ACR 等未在此集成测试台中实现，不能把本次模块通过称为完整 HDMI 链路或实物上板通过。
