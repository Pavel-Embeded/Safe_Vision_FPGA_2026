# 2026-10-16 当前实施检查点

功能仿真检查点已完成，发布验收尚未完成。当前选定的28组回归含100个不同正向测试top，全部正常结束、原始日志独立复审通过且来源指纹匹配当前源码。7个功能负控和6个音频负控全部正常结束并检出。BASE/HD仍需资源收敛、最终路由时序及位流构建，没有实体上板结果。

## 本轮修正

生产RTL延续e3e1ccc的FPS饱和、名义PLL频率参数链和FAT32地址等价网络修正。本轮另修正HD测试台的字符串补空格结束标签，并在audio_complete/audio_v3两份清单中显式声明音频生成器依赖；未放宽断言或验收规则，未改变生产RTL。

此前HD虽完成6451200像素且errors=0，结束标记不匹配仍判FAIL。失败结果保存在`evidence/v3/current_100_20261016/rejected_hd_completion`；修正标签后BASE/HD完整重新执行，分别比较2150400/6451200像素，各7个完整输出帧，覆盖默认32帧Fade。加两模式中点及HD1:1专项，共11673600个输出像素比较。

依赖补齐后，正式源码完整11项音频、6项音频子集及6项音频负控重新正常结束。100项清单只选择完整11项，重复子集不累加。候选缺依赖的原失败快照保留；候选接口变化引发的覆盖失败另列，不冒充生产通过。

## 当前来源匹配的100项

| 范围 | 不重复原生测试数 | 证据 |
|---|---:|---|
| 存量A/B/C | 5+28+8=41 | system_legacy_a、system_legacy_b、stable_c；B逐28原始日志复审672个成功检查 |
| 系统V3单元 | 13 | system_v3，含按键/命令/恢复/CRC/运算/能量与FAT移位 |
| BMP边界、全尺寸行CRC、媒体与末扇区CRC | 4 | system_bmp_bounds、system_row_integrity_full、system_media、system_media_crc |
| 板级装配、PLL标尺/FPS、音频模式、目录/FAT几何 | 9 | contract_*，双模式频率链为单一测试top内部覆盖 |
| 完整视频/中点/HD1:1 | 5 | video_final_base/hd、video_v3_midfade、video_v3_one_to_one |
| 完整音频及相位/音量/欠载矩阵 | 18 | audio_complete11、audio_priority_phase2、audio_priority_volume4、audio_priority_underflow1 |
| 图层、真实SPI、板级单元与串行音频运算 | 10 | layers1、shared_storage1、stable_v3_board4、stable_priority_serial3、stable_volume_serial1 |
| 合计 | 100 | 28个明确选定runset，无重复top |

真实SPI联合长测正常结束：四坏候选后四幅合法图、碎片簇链、614400个完整存储字、1920行CRC、四轨24000对PCM。原185000000周期看门狗与数据检查保持。每项测试的源文件、include、资产、TB、清单、runner和生成输入指纹随原始日志保留。机器可读总表：`evidence/v3/current_100_20261016/selected_acceptance.json`。

13项错误注入是验收检查器有效性的证据，不是正向功能通过次数。还保留三份runner的3正控/3带前缀FAIL负控、5种时钟参数漂移，以及FPS溢出/FAT移位专项负控。测试数与比较数不能替代覆盖完整性或物理验证。

## 资源与物理构建

硬门槛保持LUT/DFF各15680、RAM至多54个物理9K块，不删除扩展功能。正式GUI/CLI共有的6项参数已重新综合：BASE 17634 LUT/13183 DFF，HD 18340 LUT/13358 DFF，两模式RAM均50。生产依赖140项与e3e1ccc提交逐Git对象绑定，来源未变；两者明确RESOURCE_REJECTED，未进入发布位流。候选数值不能替代正式结果。

已完成的同路径候选综合：当前FAT网络在area_prior/control1/ripple64下为17286/17957 LUT。加入精确Alpha偏置与复用描述符RAM、保持原状态编码的infer_fsm=off配置后为16510/17322 LUT，DFF12960/13137、RAM50。仍高于门槛，尚未推广。infer_fsm=off保留RTL状态编码，不是关闭功能状态机。

FS104候选只进一步减少17/13 LUT，且其16字上下文与旧18字专项的内部覆盖契约不一致，当前不能算全部通过。独立HD菜单解码、事件FIFO换ERAM等候选整机收益不足或反而变差，未采用。CRC表达式重排的单模块收益仅约4 LUT；UART精确命令目录识别仍在隔离评估。不同研究的差额不可简单相加。

旧视频候选物理实验已明确失败/终止：MSlice超限，较强打包的BASE发生PHY-8023布线冲突；HD长期拥塞后终止，未完成任务不能记PASS。该结果不是当前生产RTL的最终时序结果。最终须在选定提交上重新完成两种模式Slow/Fast setup、hold、recovery、removal、例外路径、约束健康和资源检查，再生成发布位流。

## 保存、上传与边界

实现分支为`codex/safevision-v3-20261016`。此前e3e1ccc已普通推送、连接器读回关键文件并按Git对象保存至原项目目录的独立检查点。本轮源码、100项原始证据与文档另作新提交和读回；实际结果以outputs中的同步回执为准。GitHub main最近读回为98fb43b，最终快进及原工程根目录同步等待完整验收。

原项目已有safevision.al保持SHA-256 `183accc362ae8db3ffac3279579c14f3046907197fa65ec0c431ccb355088901`，备份已保存。独立检查点位于`D:/Safe_Vision_FPGA_2026/codex_v3_checkpoints`，不覆盖已有工程配置。

Git原始对象归档与Windows已验证工作树分别保存。`source`用于核对Git blob身份；`validated_worktree`保留仿真实际使用的换行符及SHA-256字节。后者可离线复核全部100项正向、13项负控和生成输入，避免把Git换行符转换误当成来源漂移。交付副本必须重新执行以下审计；工具审计通过本身不增加原生仿真测试数量。

## 可复现入口

在源码根目录执行，run-dir使用全新ASCII绝对路径：

```powershell
$py="C:/Users/曲梓铭/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe"
& $py safevision/tools/check_v3_clock_contract.py --output D:/SafeVisionRuns/clocks.json
& $py safevision/tools/check_v3_clock_selftest.py --output D:/SafeVisionRuns/clock_controls.json
& $py safevision/tools/run_v3_sim.py --suite v3 --run-dir D:/SafeVisionRuns/unit
& $py safevision/tools/run_v3_audio_sim.py --suite audio_complete --run-dir D:/SafeVisionRuns/audio
& $py safevision/tools/run_v3_shared_storage.py --run-dir D:/SafeVisionRuns/shared_storage
& $py safevision/tools/run_v3_sim.py --suite video_v3_final --run-dir D:/SafeVisionRuns/video_final
& $py safevision/tools/run_v3_negative_controls.py --run-dir D:/SafeVisionRuns/negative
& $py safevision/tools/run_v3_audio_negative.py --run-dir D:/SafeVisionRuns/audio_negative
& $py safevision/tools/audit_v3_selected_checkpoint.py --repo . --output D:/SafeVisionRuns/checkpoint_audit.json
```

模型替代了加密/物理IP边界。厂商HDMI核内部、PLL物理相位、PCB电气、实体显示/音频兼容、真实SD/SDRAM与硬件长稳均未验证；无板条件不能保证首次上板零错误。
