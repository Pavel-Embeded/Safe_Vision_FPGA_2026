# A 阶段 1–9：接口与验收

> **[更新 2026-10-04]** 下文的 USR-6135 开放状态属于历史构建。`a1dba93` 已修正四个 PLL 的 C0 反馈连线及系统 C2 缓冲；本次 SDRAM 回环图案/报告缓存修正版复验未再出现 USR-6135、PHY-5079。SDRAM setup −6.826 ns 仍开放，不能登记为整板时序通过。当前说明见 [SDRAM/PLL 核查修正版](B链-SDRAM接口与PLL时序核查.md)。

范围依据手册第 6.1–6.9 节。阶段 1 的基础练习单独命名为 `a_*`，不替代 C 的产品控制器。阶段 3–5 复用已有官方 PLL、复位和扫描模块；阶段 6–9 新增测试图、片上字库、四级 OSD 和独立图形前端。

## 接口契约（先登记，再实现）

- `a_counter`：同域 `enable`，模 MODULO 计数；末值回零时 `tick` 高一拍；禁用保持计数、tick 清零。
- `a_debounce`：异步单比特 `key_async` 经两级同步；与当前输出相反的连续 STABLE_CYCLES 个采样才改变输出。不得用于数据总线。
- `a_edge_detect`：输入必须已同步到 clk；注册后的 rise/fall 各高一拍。
- `a_mode_fsm`：演示状态 IDLE=0、NORMAL=1、WARNING=2、EMERGENCY=3；emergency 优先，清除需无告警/应急输入。不是 C 的安全策略接口。
- `pattern_generator`：组合 RGB888，延迟 0；同域坐标、de 和选择。0 红、1 RGB 三条、2 32 像素棋盘、3 矩形、4 箭头、5 一像素白框；消隐/越界/复位输出黑。
- `font8x16_rom`：地址 `{ASCII[7:0],row[3:0]}`，同步读 1 拍，无复位；8 位行数据 bit7 在左。4096 字节初始化文件是源码资源。
- `osd_overlay`：全部输入同 pixel_clk；起点 12 位，字符数 8 位，单行 8×16。`char_index` 是当前输入像素的组合索引，调用者组合提供 `char_code`；区域内有效，区域外为无需使用的值，由 region 流水标记屏蔽。输入配置需已完成 CDC，并建议在帧边界更新。区域→地址→ROM→着色四级；RGB 和 9 个扫描/有效标签全部延迟 4 拍，无 ready/停顿。字模空位透明，消隐为黑；pixel_valid 只随输入传递，不代替 de。
- `osd_status_text`：38 字符 `SAFEVISION MODE:XXXXXXXXX FPS:NN SD:OK/--`；mode 是上述演示枚举，fps 十位/个位为 BCD（0–9），非法值显示 `?`。
- `osd_coordinate_text`：11 字符 `X:hhh Y:hhh`，显示 12 位十六进制坐标。
- `a_graphics_frontend`：静态 BASE/HD 扫描→测试图→状态/坐标文字→四级 OSD；`coordinate_text=1` 显示配置起点坐标，0 显示状态。输出 RGB888、12 位 x/y 和全部标签。同域配置输入。只含阶段 1–9 的图形功能；HDMI PHY、Frame Reader 和 C 控制在后续阶段接入。

复位使用低有效异步断言、调用者按域同步释放。沿用冻结约定：frame_start 为 (0,V_ACTIVE) 的垂直消隐入口；active_frame_start 为 (0,0)。不要把二者混用。

## 验证状态

2026-10-04 在 TD 6.2.168116 / XSim 2018.3 实跑；RTL 按 Verilog-2001 编译，TB 按 SystemVerilog 编译。

| 手册阶段 | 交付与实跑结果 |
|---|---|
| 1 基础时序 | 四个 `a_*` 模块；默认 1000 模计数、MODULO=1、暂停、抖动、两种复位初值、1/4 采样阈值、边沿、FSM 优先级与锁存；16,616 项检查通过 |
| 2 自检查 TB | task/独立模型/超时均已使用；将默认计数阈值从 999 改成 998 的临时变异在 9996 ns 被 TB 精确判错；正确源码恢复后全部通过。错误副本只在运行目录，不进 Git |
| 3 时钟与 PLL | 复用官方四套 PLL 和已有 `clock_gen`；官方功能模型与 PLL 参数审计通过。实际频率见下文，锁定/各域释放/失锁恢复已仿真 |
| 4 复位隔离 | 复用 `clock_reset_ctrl/reset_sync`；媒体、存储客户端、HDMI 和音频复位隔离五项功能套件及非法参数测试通过 |
| 5 视频时序 | BASE 800×525、HD 1650×750 的完整扫描、消隐、同步极性、事件检查通过；已有 clock/video 套件 5 个功能 TB + 41 个参数场景通过 |
| 6 测试图 | 五种必需图案 + 单像素边框；BASE/HD 的所有像素及右/左箭头、越界、禁用、复位，12,930,420 项检查通过；另有坐标文字 `X:00D Y:01B` 完整帧检查 |
| 7 同步 ROM | 全 4096 地址逐拍读取、读沿之前保持、独立 F/R/6/冒号点阵检查通过；字体/状态/全部 12 位坐标转字符合计 53,407 项检查。TD 单独字库推断 1 个逻辑 ROM，映射 4 块 9K BRAM；公开综合网表 INIT 回读 4096/4096 字节一致 |
| 8 字体 OSD | ASCII 32–126，共 95 个可打印字符，其他码为空；8×16 单行文字，任意起点，透明背景；(13,27) 的 FPS:60 扫描、动态输入、0/255 字符、4095 边界与复位冲刷流水，14,013 个整束检查通过 |
| 9 四级流水 | 区域/地址/读 ROM/颜色四级，每拍一个像素；三个完整图形帧：BASE 状态和 BASE 坐标各 420,005 个 bundle 检查，HD 状态 1,237,505 个；有效像素分别 307,200 / 921,600，逐像素 RGB、9 标签及 4 拍延迟全部一致；仿真生成帧图已检查文字方向、边框与起点 |

新模块全部真实例化的内部 routed STA（slow/fast 两角，无 false_path/multicycle 放宽）：

| 实例工程 | 时钟 | setup WNS | hold WNS | setup/hold TNS |
|---|---|---|---|---|
| 基础四模块 | 50 MHz | +14.061 ns | +0.465 ns | 0 / 0 |
| BASE 图形链 | 25.185185 MHz | +27.906 ns | +0.030 ns | 0 / 0 |
| HD 图形链 | 74.166667 MHz | +0.674 ns | +0.023 ns | 0 / 0 |

图形链综合后每个模式实际保留 2 块 9K BRAM（固定 ASCII 文字源使地址/数据常量被优化）；独立 ROM 全地址验收保留完整 4096×8 的 4 块 9K。HD 最长路径仍是输入坐标减起点→文字选择→第一级寄存器；已去掉无意义的区域外索引清零比较链，保持四拍契约。无推断锁存器、无组合环、无无时钟叶节点，routing DRC / check_design 通过。

兼容性：共享 `.al` 为原 B `top_sdram_loopback`，原引脚/SDRAM约束不变；源表从 45 增为 56 个条目，路径与编译顺序无重复。最终源表完成 TD 分析、综合、布局、布线、位流生成；原 B 18 个 TB / 540 项检查全通过；原阶段十 25,124 + 1,657,732 项检查全通过。没有修改 B/C RTL、B TB 或原 ModelSim 入口。只是登记 A 模块，B 回环顶层不会自动显示测试图。

## 复现入口与接线

在仓库根目录运行：

```powershell
& ./safevision/tools/run_a_stage1_9_sim.ps1
& ./safevision/tools/run_video_clock_sim.ps1 -PythonExe '<python.exe 路径>'
& ./safevision/tools/run_b_xsim_compat.ps1
& ./safevision/tools/run_video_pipeline_sim.ps1
```

从 `safevision/platform/anlogic_eg4s20_hx4s20c/project/a_graphics_verify` 运行 `td_commands_prompt.exe base.tcl`、`hd.tcl`、`basics.tcl`、`font.tcl`。只接受实际结束标志，不以进程退出码代替报告。输出默认位于被忽略的 `safevision/build/out/a_graphics_verify/`，可用 `SAFEVISION_A_VERIFY_OUT` 重定向。字体映射后运行：

```powershell
python safevision/tools/check_font_bram_init.py safevision/build/out/a_graphics_verify/font/font_gate.v safevision/assets/fonts/font8x16.mem
```

`FONT_FILE` 默认 `../../../assets/fonts/font8x16.mem`，TD 按 ROM 源文件所在目录解析；XSim TB 显式覆写为 `font8x16.mem`，runner 复制资源到运行目录。自建仿真请指定可读路径。不要把 `.mem` 当波形/日志丢掉：缺它会导致硬件字库初始化错误。

使用 `a_graphics_frontend` 时接已有 pixel_clk 和 rst_pixel_n，静态 HD 参数与视频 PLL 一致。RGB 为 RGB888；B 输出 RGB565 时需后续显式转换/合成，禁止直接按位连错。C 产品 mode 枚举若不同，需映射后接 status_text。所有配置从其他域进入前需 CDC；本阶段未包含动态时钟切换或总线 CDC。

## 尚未通过的验收边界

- 官方整数 PLL 实际值：sys 100 / mem 125 MHz；BASE 25.185185185（目标 25.175，约 +0.0405%）、serial 125.925925926；HD 74.166666667（目标 74.25，约 −0.1122%）、serial 370.833333333；audio 12.288135593 MHz（目标 12.288，约 +11.035 ppm）。视频串行与像素时钟仍严格 5:1。当前参数没有宣称实现精确目标频率或证明显示器容差。
- BASE/HD 的内部数值 STA 为正，TD 仍报 USR-6135 PLL 反馈补偿健康告警，以及生成时钟关系/dummy 节点项；不能据正 WNS 宣称整机时钟健康全部过关。42 个配置/复位输入和 57 个探针输出没有板级 I/O delay 预算，测试壳不用于烧录。
- 原 SDRAM 回环整合工程仍为 setup WNS −6.826 ns / TNS −298.836 ns，hold +0.054 ns。这是既有 C1↔C2 / SDRAM DQ 路径问题；位流能生成，但全系统时序未收敛。本次没有用假路径隐藏它，也未改加密控制器。
- 没有本轮上板、ChipWatcher 实测时钟、真实 HDMI 显示或长期稳定测试；HDMI PHY 属后续阶段。手册要求队员闭卷重写/解释等个人学习考核，须由本人完成。这里交付的是可复现代码与已执行的开发验证，不能代替上述硬件/学习验收。

## 发布范围

上传 RTL、TB、字库 `.mem`、测试脚本、必要 `.al/.tcl/.sdc/.adc` 和精简接口/状态说明；不上传波形、运行日志、STA 长报告、综合网表、数据库或位流。已生成内容留在本机 `build/out` 或工作目录。
