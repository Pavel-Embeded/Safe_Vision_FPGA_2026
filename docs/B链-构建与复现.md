# B 链：构建与复现（2026-10-11）

本文是"**从零 clone 到复现板级效果**"的唯一入口说明。

## 一、外部依赖（不入库，必须自备）

仓库**不包含**厂商 HDMI 的三个文件（它们被 `.gitignore` 白名单排除）。构建前必须让
它们可见，二选一：

1. 保持官方例程目录存在，脚本自动查找：
   `7_lab_ex_2026_nosoft/example/lab_ex4_tf/src/user_source/hdl_source/` 下的
   - `hdmi_phy_warpper.v`
   - `lane_lvds_10_1.v`
   - `hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v`
2. 或显式指定：`-VendorRoot <该 hdl_source 目录>`

`run_board_sta.ps1` 会调用 `resolve_hdmi_vendor.ps1` 把它们复制到运行目录的
`vendor_hdmi/hdl_source`（本地忽略目录，不入库）。

其余依赖都在仓库里：SDRAM IP（`ip/sdram/*.enc.v` + `global_def.v`）、PLL、字库
（`assets/fonts/font8x16.mem`）、include（`rtl/include/*.vh`）、约束（`board_verify/board_b.adc`、
`board_b.sdc`、`board_cdc.sdc`）、源文件表（`board_verify/board_sources.list`，60 项）。

**工具链**：Anlogic TD 6.2.1（`-TdRoot` 默认 `D:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`）、
Python 3、ModelSim（跑回归时用 `-ModelSimBin`）。

## 二、构建（默认档 = 板级验证过的配置，**不需要任何宏**）

```powershell
# 时序门禁 + 生成位流（base = 640x480）
.\safevision\tools\run_board_sta.ps1 -Mode base -Bitgen -RunDir .\safevision\build\out\repro -Python <python.exe>

# 720p 同理：-Mode hd
# 只跑门禁不生成位流：去掉 -Bitgen
```

门禁是**严格**的：任何负的 setup/hold/recovery/removal 路径，或任何必需的时钟/约束健康检查
失败，都会拒绝构建（`run_board_sta.ps1` 与 `check_board_timing.py` 已不再提供任何豁免开关）。

## 三、已知最好配置与产物指纹

| 项 | 值 |
|---|---|
| 存储时钟 | MEM `clk1` = **40.000 MHz, 0°**；SDRAM `clk5` = **40.000 MHz, Rise +10.000 ns** |
| 时钟来源 | `sv_board_memory_pll.v` 默认档：`MEM_DIV=25, MEM_CPH=24, SFT_CPH=9` |
| SYS / 像素 | SYS 100 MHz；BASE 像素 ≈25.185 MHz，720p 74.25 MHz |
| 刷新 | `SAFEVISION_REFRESH_ROWS = 4096` |
| 完整性校验 | 关闭（`STORAGE_INTEGRITY=0`，guard 不例化） |
| 适配器读模式 | `FAST_READ=1`、`PREFETCH_READ=1`；dm 策略 = 细化版释放 |
| 时序门禁 | **`status=PASS`、`timing_passed=true`、负路径 0、`SWNS=+1.517 ns`、`HWNS=+0.003 ns`** |
| 资源 | LUT **11765** / REG **7822** / LE **13267** / BRAM **34 of 64** |
| 位流 | **633,127 字节** |
| 串口身份 | 抬头 **`SV-D40R`**（`53 56 2D 44 34 30 52`），`ID=2610100G` |

**位流 SHA-256 只作参考，不作为验收依据**：同一份网表（`route.area` 逐项相同、时序报告相同）
在 TD 里重跑，布线/bitgen 的字节会变。已观测：

| 构建 | 位流 SHA-256（前 16 位） |
|---|---|
| 原始 D40R 构建（`build/out/board_verify_d40r`） | `cc75ef5c71d321e4` |
| 收敛后严格重建（`build/out/repro_main`） | `bd27ab9879337369` |

两次的 **`route.area` 逐项相同、时钟表相同、门禁数值相同、位流大小相同** ⇒ 判定为
**工具非确定性**，验收以"资源 + 时序 + 时钟 + 上板行为"等价为准。

## 四、上板核对方法

1. 用 TD 的下载工具把 `safevision_top.bit` 烧进 **SRAM**（`PROGRAM`，不必写 Flash）；
2. 打开板载 USB-UART（CH340G）对应的 COM 口，**115200 8N1**；
3. **先核对抬头**：第一行必须是 `SV-D40R …`，`SV-MEM` 行的 ID 必须是 `2610100G`。
   抬头不对 ⇒ 烧进去的不是这一版，重下；
4. 正常表现：`SD=1 CARD=1`、`F` 递增（帧已发布）、`CRC=1`、`EC=00`；HDMI 输出 SD 卡里的 BMP。

**已知偶发**：这块板的 SD 初始化成功率不高（板级备注记录过"约 1/10 成功"，`sd_miso` 已加内部
上拉）。若 `SD=0 CARD=0`、`EC=F3`、`F=0000`，**按复位重试**即可。

## 五、回归与检查

```powershell
.\safevision\tools\check_repo.ps1                                   # 目录/文件引用布局检查
.\safevision\tools\run_sim.ps1  -ModelSimBin <ModelSim win64 目录>   # B 链主回归
.\safevision\tools\run_clock_sim.ps1 -ModelSimBin <...>             # 时钟/复位检查
```

收敛时的实测结果：`check_repo.ps1` → `LAYOUT PASS`；`run_sim.ps1` → **TOTAL PASS=668, FAIL=0**；
`run_clock_sim.ps1` → **88 pass, 0 fail**。

## 六、已知问题与未收尾项

1. **完整性校验特性默认关闭**：`frame_integrity_guard.v` 与 `video_read_dma_checked.v` 都在仓库里，
   但 guard **没有例化**（它的写入侧跟踪是 MEM 域最差路径，14.683 ns / 12 级逻辑，会把存储时钟
   压到 66.8 MHz）。要重新启用：在 `safevision_top.v` 的 guard 位置恢复例化，并把
   `STORAGE_INTEGRITY` 置 1，然后重跑门禁与回归。特性与 TB 都保留着。
2. **显示画面**：这一档是全项目唯一"整帧发布 + 时序 0 负路径"的板级状态；早期 40 MHz 档曾出现
   整屏白（读回全 `0xFFFFFFFF`，根因是 SDRAM DQM 读掩码，修复见 `sdram_app_adapter.v` 注释），
   100/125 MHz 档出现过撕裂/花屏（那两档 SDRAM 边界时序未收敛，已弃用）。若后续仍要追画面质量，
   从 `archive/*` tag 与 `docs/B链-红框故障-定位结论与时钟档_20261011.md` 起步。
3. **DQM 修复的来源**：读掩码真根因由队友定位（`archive/teammate-dqm-7fb219c`），本仓库已移植；
   释放时机由本仓库细化为"延迟释放"，两个约束（尾拍仍被掩 / 读不被掩）同时满足。
4. **文档里的历史叙述**：`docs/` 中 2026-10-02～10-10 的阶段性记录保留原样，其中提到的
   `evidence/ab_multiround_*`、`releases/ab_multiround_*`、`top_stage10_framebuffer` 等已在本轮
   收敛中删除，取回方式见 [仓库收敛说明](仓库收敛说明_20261011.md)。

## 七、分支策略

**只保留 `main`**。收敛时的多余分支已删除，但**一个提交都没丢**；
队友那条并行线与 2026-10-05 的独立提交分别用 `archive/teammate-dqm-7fb219c`、
`archive/card-to-screen-2e97790` 两条 tag 留档。
