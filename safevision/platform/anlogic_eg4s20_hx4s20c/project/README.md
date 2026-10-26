# 板级构建入口

BASE 26102301 使用 `v3_board_verify` 中的显式源表、资产、BASE 参数与物理管脚约束，顶层为 `safevision_v3_top`。构建入口见仓库 `safevision/tools/run_v3_board.py` 和 `finalize_v3_four_features.py`，BASE 发布按工具要求显式选择 `--engineering-base-only`。

TD 版本、源输入 SHA、约束及结果见 [当前发布包](../../../../artifacts/releases/BASE_26102301_6a957b0)。本目录内早期 `.al` 工程、回环和时钟试验保留其历史用途；它们的顶层与当前生产入口可能不同。

GUI 和命令行构建需核对相同的 top、源文件、参数、IP、管脚与时钟。当前源码和位流身份见 [版本入口](../../../../SAFEVISION_CURRENT.md)。
