# 完整性复核、构建与交付追溯

## 工具与环境

完整原始路径复核使用Windows、Git、Python3.11+、pypdf。原生构建需要已安装并合法配置的 **TD V6.2.168116**，实际工具路径曾为 `D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`。实际仿真使用XSim/Vivado2018.3。仓库不分发TD、许可证、驱动或厂商安装包。

所有运行目录用纯英文、仓库外、全新目录。不要把临时输出放进源码目录，也不要用 `python -O` 关闭验证断言。厂商加密IP位于平台层，源清单和内容指纹固定；仿真模型只进入仿真清单。

## 从新克隆完整复核（不接板）

```powershell
git clone https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026.git D:/sv_project
cd D:/sv_project
python -m pip install pypdf==6.10.0
python -B safevision/tools/verify_base_delivery.py --run-dir D:/sv_runs/base_verify_01
```

私有仓库使用本人现有GitHub身份登录。依赖版本见 `artifacts/releases/BASE_26102004_5cff94e/verification.environment.json`；命令以该清单实际验证的版本为准。

工具按顺序核对：根目录198物理源及完整证明依赖→原始ZIP/对象包/报告/位流→真实实板记录字节→安全解包→恢复只供原版审计器读取的原始Git对象→完整288/202、PDF/管脚/手势、GUI/CLI、ROM、采样及原始全角STA重放→再次检查发布字节。失败返回非零，不能作为批准。`--checksums-only`只做文件完整性检查，明确不代表全验收重放。

通过后输出 `verification.json`、`qualification.console.log`、原版重放收据及 `qualification/source` 冻结源。审计对象库只包含验证器实际读取的原始commit/tree/blob，不包含全部历史祖先或无关blob；不要把它作为完整仓库克隆使用或推到main。它保留原SHA，不改写旧收据，也不假装GitHub交付提交就是原构建提交。

## 重新综合与布局布线

完成上述完整复核后，使用输出的**冻结源**，该目录的Git指向隔离审计对象库。下面路径与首次输出一致：

```powershell
$src = 'D:/sv_runs/base_verify_01/qualification/source'
python -B "$src/safevision/tools/run_v3_board.py" --repo $src --source-repo $src --source-ref 9c789eaddd514997c534602026ca14d20b03edbe --run-dir D:/sv_runs/base_build_01 --mode base --td-root D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116
```

这是实际完整综合/布局/布线与最终STA入口。若安装路径不同显式指定 `--td-root`。构建必须正常完成、资源合法、所有实际路径/约束门槛通过；旧已通过报告不能替代新运行结果。新工具版本或参数、源、约束改变均需建立新的验证边界。

GUI入口：`safevision/platform/anlogic_eg4s20_hx4s20c/project/v3_board_verify/base/safevision_v3_base.al`，顶层`safevision_v3_top`，模式`base_mode.v`。生产清单`v3_board_sources.list`及模式profile、assets列表和SDC由同一工具读取；不通过扫描目录自动加入所有RTL。GUI供开发浏览/构建，正式验收以命令行原始记录和门槛收据为准。

## 生成 BASE 位流

完整新构建通过后执行严格终结器；显式BASE选项只批准BASE，不把HD缺项藏起来。

```powershell
python -B "$src/safevision/tools/finalize_v3_four_features.py" --repo $src --native-run D:/sv_runs/base_build_01 --functional-manifest evidence/v3/four_features_261020/acceptance.json --output D:/sv_runs/base_bitgen_01 --engineering-base-only
```

终结器重新检查功能证据、精确批准源码及新物理结果，再从相同route.db调用原厂bitgen。不同工具/运行环境不能预先保证位流逐字节相同；新产物必须单独记录SHA、工具、参数和新实板验收，不把它自动命名成已有合格位流。

## 仿真与开发修改

当前完整验收由acceptance/matrix映射到每个实际suite/top；可用 `run_v3_sim.py --suite <清单名> --top <测试顶层> --run-dir <新英文目录>` 重跑相应用例，XSim路径由 `--xsim-bin` 指定。例如当前 `key_gestures478` 清单及 `tb_v3_key_gestures478`。未修改RTL的本次上传复核实际证据，不冒充重新执行全部HDL或新TD构建。

修改RTL后先跑受影响单元/独立模型/负控，再完整回归、物理实现及相应实板验收。当前288/202证据有明确源码指纹，修改任意依赖后必须重新产生相应证据，禁止改清单中的hash让旧日志继续通过。

## Git 与发布

基于远端最新main整理本次增量，保留原有历史文件；以普通快进推送完成更新，不强推。发布清单绑定当前合格字节，Git提交记录发布清单本身；本地额外交付收据记录最终提交、远端读回和本地项目一致性，避免把提交自身SHA写进同一提交造成循环。

GitHub Actions仅复核源与证据，既不调用真实板卡也不重新授予硬件验收。没有Actions运行记录时不能宣称云端CI已通过；本地完整复核与推送后新克隆复核分别保存。
