# project

可重建 TD 工程的脚本、文件表与目标器件设置。工程临时目录放 `safevision/build/out/`。

当前内容：`safevision.al`（安路 TD 6.2 工程文件，XML）。

- 器件：EG4 / **EG4S20BG256**；FileSet `design_1` 的 `IncludeDir = ../../../rtl/include`。
- 33 条设计文件**全部是相对路径**（`../../../rtl/...`，相对本目录），所以**换机器/换
  clone 路径都能直接用**，队友不需要重新添加文件。★ 别把它们改成绝对路径。
- `<Project Path="...">` 那一条是**绝对路径**，TD 打开时会按 `.al` 的实际位置刷新它；
  若换了位置后 TD 报找不到文件，检查这一条。
- `constraint_1`（ConstrainFiles）目前**是空的**——`pin.adc` / `timing.sdc` 写好并加进去
  之后，综合/布线才带约束。约束源文件放 `../constraints/`。
- ★ `TOP_MODULE` 必须指向板级顶层；否则 TD 做依赖分析时会把够不到的模块全部
  `AutoExcluded`（曾经顶层被默认设成 `crc7`，结果 33 个文件里 32 个被自动排除）。
- 以下**不进版本库**（`.gitignore` 已处理）：`*.lock.f`、`log/`、`td_*.logw`、
  `*.bit`、`*.fs`、`*.ngd`、`*.sdc.bak`；工具中间产物请配置到 `safevision/build/out/`。
