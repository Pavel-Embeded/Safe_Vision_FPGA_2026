# 验证、证据与可复核边界

## 分层结论

| 层 | 结论 | 原始材料 |
|---|---|---|
| 功能 | 288 个不同正向入口；289 条含别名记录；全部正常结束且零失败 | `evidence/v3/four_features_261020/acceptance.json` 及其 matrix/逐项路径 |
| 语义负控 | 202 个实际 HDL 语义错误被发现；正常 `$finish`、退出1、错误计数非零 | acceptance 的 `negative_controls`；工具崩溃/缺结束标记/跳过不算检出 |
| 实体管脚独立性 | 原 PDF 页19恢复 KEY1=A2、KEY2=B2、KEY3=B1、KEY4=C1；11 个负控拒绝，旧真实 PAD 报告拒绝 | acceptance 的 `physical_key_selftest` |
| 手势补充 | 8 组先后按下/松开/抖动场景，89 次实际 HDL 比较通过 | acceptance 的 `physical_gesture_selftest` |
| 完整物理实现 | BASE 综合、布局布线正常退出；独立进程最终 Slow/Fast STA 和所有健康门槛通过 | `artifacts/releases/BASE_26102004_5cff94e/native/base/` |
| 位流 | 原厂 bitgen 正常退出；绑定最终 route.db、源码、工具、参数和 SHA | 原始 approval/release 清单与 bitgen 日志 |
| SRAM实板下载 | 原厂 JTAG验证EG4S20BG256成功，精确位流SHA一致 | 板测目录 `programming/` |
| 串口配置 | 40项实际配置、540有效ACK、42健康观察通过；默认恢复 | `configuration/`、`configuration.audit.json` |
| 实体菜单 | 用户对修复位流回复“四步全部正常”：KEY2+KEY3、亮度、对比度、退出 | `physical_keys.acceptance.json`，属于直接用户观察 |
| 短时播放观察 | 60秒只读记录正常结束，12次观察/10次自动提交；媒体/音视频错误计数零 | `readonly_60s/observational.audit.json` |

所有相对板测路径均位于 [`artifacts/board_validation/four_features_BASE_KEYFIX_5cff94e/`](../../../artifacts/board_validation/four_features_BASE_KEYFIX_5cff94e/)。

最后一次修改仅涉及管脚/参考/检查器，功能 RTL 与 SDC 没变。288/202 使用原来实际运行日志并重新核对编译图、源字节、生成资产、参考模型及批准指纹；不把它表述为修改管脚后全体重新运行仿真。新的物理实现及补充管脚/手势检查有各自独立记录。

## 功能覆盖

独立图片模型用整数除法计算期望坐标；完整输出帧核对方向、填充、非整数缩放、黑边和反压。卡级覆盖完整SPI/FAT、碎片簇链、坏文件、最大1920×1080输入及四幅完整规范帧。波形覆盖静音、正弦、方波、斜坡、脉冲、伪随机输入和真实输出端最终RGB。控制覆盖去抖、组合/长短按、UART范围/响应、队列并发、generation、恢复及故障注入。精确用例和比较数量以 matrix 和每项 `result.json` 为准，不把候选研究记录相加为本发布的新测试数量。

原先参考表与 ADC 同错暴露了“两个副本一致”不足以证明物理正确。当前额外从未修改原厂 PDF 抽取实体标签，并核对最终物理 PAD，从来源和实现两端检查。

## 时序门槛

- 原始 `route.timing`、`route.check`、`route.exceptions` 及 `timing.gate.json` 一起评估。
- setup/hold/recovery/removal、Slow/Fast 均不得出现负裕量；全局 setup +0.145ns、hold +0.029ns。
- 时钟定义、I/O预算、例外路径依据、CDC实际对象与约束实际命中必须一致。不能用删除真实路径或放宽时钟取得通过。
- 独立新进程重开最终布局数据库，源、SDC、数据库前后哈希一致；原始工具进程必须退出0并有正常完成标记。
- 资源按物理容量判定；ROM初始化、独立源/总线32位采样及故障位在实际网表检查。

## 保留的未通过与待验项

`gesture_capture_incomplete/` 是一次120秒端口关闭前未捕获完整手势的记录，**不计为通过**。后续正常只读串口与用户直接操作确认分别留档，不覆盖这个失败事实。

60秒窗口使用约5秒轮询，有一次相邻GEN未变化；记录保留原始数据，不拿默认20秒采样假设的通用审计器硬套，也不声称精确测量了每次5秒提交间隔。

秒计时与青色波形的用户观察来自同功能 RTL 的前一按键映射位流；本修复版新获确认的是实体菜单/亮度/对比度。已存在功能字节等同和完整仿真证据，不伪造一次新的四项全实物确认。四图轮播与可听音频也保留其原验收轮次来源。

厂商加密IP内部未直接仿真。不同尺寸实卡、新版本24小时长稳、多设备HDMI音频兼容性及当前HD通过仍未验收。仿真、STA、编程成功、串口健康和人的画面/声音观察是不同证据层。

## 重新复核

运行 [BUILD](BUILD.md) 中的 `verify_base_delivery.py`。它核对根目录合格源文件与实板证据、完整ZIP及原始对象包，在新目录重放原版验收器；原始报告和绝对构建路径不修改。新交付文件在推送前复核，推送后从全新克隆再次复核；结果收据保存在本地交付输出目录。
