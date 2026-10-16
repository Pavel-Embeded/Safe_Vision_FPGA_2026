# 106 项功能检查点：监督器并行比较与计时提前译码

当前功能验收为 106 个不同原生测试 top、19 个严格负控。正向测试全部正常结束且零失败；负控全部正常结束并检出。当前来源与生成输入逐字节审计见 `evidence/v3/resource_106_20261016/portable_audit.json`，原始日志/清单见同目录 `acceptance.json`。105 项及更早目录保留为历史证据。

本次在 [105 项实现](timing_closure_checkpoint_105.md) 上继续保留全部功能、原时钟和 I/O 预算。监督器的 32bit 比较改为四组字节并行计算大小/相等，再按高位优先合并；第33bit仍单独阻止溢出阈值误报。毫秒 tick 提前一拍计算“下一计数值是否终点”，窗口末尾标志在计数更新时计算。它们表示同一周期的原谓词，没有给事件、故障或恢复增加时钟延迟。

监督器参考测试在 65,536 周期中同时实例化原实现与新实现，分别检查每拍 tick 及十拍分频 tick 两种情况。345,455 项检查全部通过，含 101bit 公共输出、事件仲裁、有效时间戳槽、tick/window 谓词与64个边界窗口。另一个原生专项直接检查真实 RTL 比较器：每个字节位置全部 65,536 值对、100,000 组32bit随机输入和阈值溢出边界，共 724,608 比较，独立使用原 `a>=b && a-b>=8` 数学谓词核对，零错。

三个语义破坏用例分别删除最高字节“大于”条件、让 tick 预判错一拍、丢弃阈值溢出保护，全部正常结束并被检出。这里的进位负控保留33bit寄存器，只破坏溢出资格，避免用越界选择产生的 X 代替真实数值错误。

最新匹配功能 RTL 的 BASE 隔离路由完整门禁通过：setup +0.036ns、hold +0.030ns，17009 LUT、13073 DFF、51 RAM9K、13 DSP。HD 正在以相同 RTL/ROM/SDC 比较 ripple16 和模式专用 ripple32；最终结果登记到 `evidence/v3/release_status.json`。候选结果不替代最终提交的干净目录两模式构建。

复核入口：

```powershell
& $py safevision/tools/audit_v3_resource_checkpoint.py --repo . --output D:/SafeVisionRuns/current106.json
& $py safevision/tools/run_v3_sim.py --suite supervisor_threshold --run-dir D:/SafeVisionRuns/supervisor
& $py safevision/tools/run_v3_sim.py --suite supervisor_comparator --run-dir D:/SafeVisionRuns/comparator
```

后续仍需完成 HD 全角时序、精确提交绑定的两模式位流、干净目录复现，以及本地工程根目录/GitHub main 快进同步。实体 SDRAM、HDMI、音频、卡兼容和长稳尚无板测结果；本检查点不是上板签核版本。

发布入口另强制执行当前功能审计：本检查点的885项证明依赖，包括测试源码、原始日志、向量、生成器和元数据，都参与 Git 对象绑定及构建前后 SHA-256 检查。缺功能证据、缺正常结束、带前缀 FAIL、源码或向量改变、必需负控缺失、批准后日志字节变化，都阻止位流；Python `-O` 也不能跳过断言审计。9项隔离发布负控已通过，首次取样路径错误的自测保留为失败，不计通过。
