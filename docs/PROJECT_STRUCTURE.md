# 项目目录与文件归属

本页是仓库目录导航。`[现有]` 表示盘点时已存在；`[规划]` 表示只确定落点，未实现 RTL/IP；`[骨架]` 表示已建目录但只含 README/占位说明，没有任何功能代码。2026-09-30 新增 A 的逐模块文件夹，只有板级 `rtl/clock/` 含复位 RTL；2026-10-02 板级层再落地 B 的 bring-up 顶层与引脚/时序约束。手册 V2.0 的第 2、6–12、17 章决定三条链、接口先行、分层测试和交付证据；目录粒度、板级适配层、评审模板是本项目的工程化补充。

```text
<仓库根>/
├─ README.md                         项目入口、当前能力与使用顺序
├─ .gitignore                        只跟踪源码、文档和可复核证据
├─ .github/                          PR/缺陷/任务模板
├─ docs/
│  ├─ PROJECT_STRUCTURE.md           本文件；目录用途和归属
│  ├─ interface_spec.md              [现有] B 链冻结接口基线
│  ├─ B链-*.md                       [现有] B 链说明与硬件待办
│  ├─ architecture/                  系统图、模块清单、移植边界
│  ├─ interfaces/                    新接口模板与评审规则
│  ├─ requirements/                  B01–B04/E01–E05 追踪
│  ├─ management/                    分工、待办、决策、变更记录
│  ├─ verification/                  验证策略与测试矩阵
│  └─ release/                       构建冻结、提交与回滚规则
├─ safevision/
│  ├─ rtl/                            可移植的业务逻辑，不含引脚/IP 实例
│  │  ├─ include/                    [现有] 全局常量与错误码
│  │  ├─ common/                     [现有] FIFO、握手、UART 等通用件
│  │  ├─ storage/                    [现有] SPI、SD、FAT32、文件流
│  │  ├─ media/                      [现有] BMP/WAV 解析与像素转换
│  │  ├─ memory/                     [现有] 帧缓存、仲裁、DMA、交换
│  │  ├─ video/                      [规划] A：时序、帧读取、合成与 OSD；逐模块 README
│  │  ├─ audio/                      [规划] C：音频调度与优先级
│  │  ├─ control/                    [规划] C：按键、播放状态、事件
│  │  ├─ safety/                     [规划] C：故障、看门狗与降级控制
│  │  └─ top/                        [规划] A：safevision_core/；不含板级引脚
│  ├─ platform/
│  │  ├─ anlogic_eg4s20_hx4s20c/    [部分实物] 板级层：`rtl/clock/` 复位控制（A）、
│  │  │                              `rtl/top_stage5_sector_rd.v` 板级 bring-up 顶层（B，接引脚）；
│  │  │                              TD 工程已建（`project/safevision.al`，器件 EG4S20BG256，
│  │  │                              35 条设计文件为相对路径，TOP_MODULE 已指向 bring-up 顶层）；
│  │  │                              `constraints/{pin.adc,timing.sdc}` 已写；PLL / HDMI / 产品顶层待接入
│  │  └─ sim/                        [规划] 非厂商仿真适配层
│  ├─ build/                         [骨架] 文件清单、参数配置、构建说明
│  ├─ verification/
│  │  ├─ unit/                        [现有] 单模块 Testbench
│  │  ├─ models/                      [现有] SD/SDRAM 行为模型
│  │  ├─ subsystem/                  [规划] SD→帧缓存、缓存→HDMI 等
│  │  ├─ system/                     [规划] 三链整机、故障与长稳
│  │  └─ board/                      [部分] 上板采集脚本 `capture_uart_512.ps1`（阶段 5 的 UART 回传比对）
│  ├─ assets/                        [骨架] 可再生字体、图案、SD 测试素材说明
│  └─ tools/                          [现有] B 仿真脚本；新增结构自检
└─ evidence/                         [骨架] 需求→测试→原始证据与索引
   ├─ requirements/                 需求评审与变更
   ├─ sim/                          自动测试日志、种子、golden
   ├─ waveform/                     原始波形与截图
   ├─ reports/                      综合、STA、资源、CDC、约束覆盖
   ├─ board/                        实机照片/录像与设备信息
   ├─ measurements/                 带宽、水位、延迟、长稳原始值
   └─ provenance/                   第三方许可、版本与来源
```

## 谁把文件放在哪里

| 文件类型 | 放置目录 | 负责人/复核 |
|---|---|---|
| SD/FAT、BMP/WAV 解码、帧写入、SDRAM 仲裁 | `safevision/rtl/{storage,media,memory}` | B / A 复核边界 |
| 视频时序、帧读取、OSD、合成、HDMI 前级 | `safevision/rtl/video` | A / B 或 C 复核交界 |
| 按键、播放、音频调度、故障与安全状态 | `safevision/rtl/{control,audio,safety}` | C / A 复核交界 |
| 可移植系统装配 | `safevision/rtl/top` | A / B、C 复核 |
| 安路器件实例、引脚、PLL、SDRAM PHY、HDMI PHY | `safevision/platform/anlogic_eg4s20_hx4s20c` | A 主集成，相关链负责人复核 |
| 单元/联调/整机测试 | `safevision/verification/{unit,subsystem,system,board}` | 开发者写、跨链复核 |
| 原始测试结果 | `evidence/<类型>` | 执行者落盘，C 维护索引 |

### A 模块文件夹（目录存在不等于实现）

| 分类 | 已建模块文件夹 | 当前代码 |
|---|---|---|
| `safevision/rtl/video/` | `video_timing/`、`pattern_generator/`、`graphics_rom/`、`osd_overlay/`、`video_pipeline/`、`frame_reader/`、`video_compositor/`、`safe_scene_gen/`、`emergency_mux/`、`video_cdc/` | 均仅 README；B 已有的 `rtl/memory/frame_swap_cdc.v` 不移动 |
| `safevision/rtl/top/` | `safevision_core/` | 仅 README |
| `safevision/platform/anlogic_eg4s20_hx4s20c/rtl/` | `clock/`、`pixel_fifo/`、`hdmi/`、`chipwatcher/`、`safevision_top/` | `clock/reset_sync.v`、`clock/clock_reset_ctrl.v`（A）与 `top_stage5_sector_rd.v`、`top_stage6_fat32_mount.v`、`top_sdram_loopback.v`（B 的 bring-up 顶层）为功能 RTL；其余仅 README |
| `safevision/platform/anlogic_eg4s20_hx4s20c/ip/` | `sdram/`、`pll/`、`pixel_fifo/`、`graphics_bram/`、`hdmi/` | `sdram/`（应用级 `sdram.v` + `global_def.v` + 3 个安路加密 `sdr_*.enc.v` + `sdram.ipc`）与 `pll/`（`sv_system_pll`、`sv_video_*_pll`、`sv_audio_pll`）为**厂商提供的 IP**（非本项目代码，版权与来源见各自 `README.md`）；其余仅 README |

模块文件在相应文件夹内；新增端口先更新 `docs/interface_spec.md` 和 `docs/architecture/module_registry.md`，再更新显式文件表。板级时钟由官方 TD PLL IP 产生，现有 `clock/` Verilog 只实现复位许可和分域释放。

每个待实现目录的 README 列出用途与边界。`module_registry.md` 登记 B 链 29 个 `.v`、板级 bring-up 顶层（`top_stage5_sector_rd.v` / `top_stage6_fat32_mount.v` / `top_sdram_loopback.v`）、厂商 IP（`ip/sdram/`、`ip/pll/`）与 A clock 的 2 个 `.v`，以及 4 个 `.vh`；目录存在不代表功能已实现或验证。目录的依赖关系和接口规则见 [系统架构](architecture/system_design.md)。

> ★ **B 链三份文档暂时留在 `docs/` 根目录，不要搬进任何子目录**：
> `docs/interface_spec.md`、`docs/B链-待办与硬件验证清单.md`、`docs/B链-原理讲解-入门版.md`。
> 它们被项目规则、`README.md`、`docs/architecture/module_registry.md` 等多处按此路径引用，
> 搬动会打断引用，且它们本身就是 B 链的交付物。

树上标 `[规划]` / `[骨架]` 的 A 视频、顶层及 IP 目录目前只有 README；`platform/.../rtl/` 已有面向综合的复位 RTL（A，已仿真通过）与板级 bring-up 顶层（B，已仿真通过，未上板），但**尚未通过 TD 综合或上板**。C 目录、build、assets、verification 的规划目录和 evidence 仍是骨架。本项目自定原则是先建落点和命名计划，不生成假 RTL。


## A Clock / Video Timing 发布补充（2026-10-02）

本次新增模块化 `video_timing.v`、`video_mode_defs.vh`、`clock_gen.v`、`clock_video_subsystem.v`、四套安路官方 PLL `.v/.ipc`，并加固 A 的 `reset_sync.v`。BASE/HD 按编译参数一致选择扫描几何和视频 PLL；输出五时钟、四锁定许可、九路复位和同拍扫描标签。详细用途、频率和验收边界见 [实施说明](clock_video_implementation.md)，端口/时钟域见 [A接口补充](A_clock_video_interfaces.md)。

新 XSim 入口包含五项测试；帧量级联调测试显式传入 TIMEOUT_N=5,000,000，B 模块默认值与 `safevision_defs.vh` 均保持原版本。本次不改 B/C RTL、原 B 单元测试、原 B 回归入口、B 专用文档或 B 上板工程/证据。共享文档保留最新远程原文，仅追加 A 说明；现有 B 验收记录仍按其原证据判断。

Clock/Timing 官方模型及整数/规格范围审计通过；归档 BASE/HD 内部 STA 的实际 A 输入与本提交一致，但 TD 健康告警仍开放（runner 返回 2）。尚未完成 A 产品顶层、完整 HDMI/Frame Reader/OSD/应急链与 A 板级验证。旧 `clock_video_20261002` 是过滤前工作树历史记录，不能把其中 B 默认超时变更或全工作树文件计数当成本提交内容。当前范围与新回归见 [A发布核对](A_PUSH_SCOPE_20261002.md)。
