# GitHub Actions 长路径与当前 BASE 校验修复

## 实际故障

提交 `2c9c639be0ce6b227e1f087741c53dc670a631e8` 的 [Actions 运行 39972735653](https://github.com/Pavel-Embeded/Safe_Vision_FPGA_2026/actions/runs/39972735653) 停在 `actions/checkout`。Git 报 `Filename too long`，退出码为 128，只展开了约 2% 的文件。Python 安装、功能证据重放和时序检查均未开始，这次红叉来自检出文件失败。

`failure` 是这次自动任务的失败结论。提交上传成功、仓库文件同步、自动检查通过、真实硬件通过分别记录；其中一项成功不能代替另一项。

## 修正

1. 在 checkout 前设置 `core.longpaths=true`，同时通过 Git 的命令级环境配置传递该值，避免 checkout 临时修改 HOME 后丢失设置。
2. 取完整可达 Git 历史，保留独立参考与构建提交的对象校验；工作树仅展开当前交付和完整源码/证据，历史交付仍留在 Git 中。
3. 原工作流还固定调用了 `26102004` 的旧校验器。旧工具保留用于历史包，当前工作流改为验证 `26102301` 的 206 个生产输入、303 个独立正向 top、221 项语义负控和当前位流。
4. 独立参考有部分提交并非 main 的祖先，不能假设 `fetch-depth: 0` 会自动取得它们。导入已发布、固定 SHA-256 的 7.2 MB 参考对象包，只给审计子进程设置备用对象目录，不改源码仓库的 `.git` 或历史。
5. 从当前交付原始报告重新解析 3320 条 Slow/Fast 时序路径、正式时钟健康、原生异常路径和实际资源；正式 `route.check` 取自既有合格构建，必须与冻结原生 gate 的 SHA-256 相符。
6. 对既有实板串口 trace/rx 原字节重新核对完整结束、命令/ACK 一一对应、校验和、5016 帧回执与健康计数。

## 检查入口

```text
safevision/tools/test_base_delivery.py          保留的 5 项交付边界测试
safevision/tools/test_current_base_ci.py        当前包、路径、时序/UART 损坏、对象导入与工作流回归
safevision/tools/verify_base_release.mjs        当前位流、82 份交付文件、206 个输入的字节校验
safevision/tools/verify_current_base_ci.py      当前完整功能/报告/UART 证据重放
```

新检查覆盖损坏位流、变更生产输入、越界清单、未列入的文件、虚报冷启动、负裕量路径、损坏串口原字节和缺少正常结束等情况。没有使用 `continue-on-error`，也没有通过跳过失败步骤取得绿色状态。原生 FPGA RTL、管脚、时钟、IP 参数及 `.bit` 字节保持不变。

本流程是原始证据重放和完整性检查，不在 GitHub 上重新调用 TD 布局布线，也不连接开发板；真实完全断电启动等硬件待验事项保持原状态。旧提交的失败记录留在历史中，修复结果以新提交实际 Actions 结论为准。
