# 原生缓存时钟归属门禁

这些原样 TD 网表与 XML 时钟树仅用于验证实际时钟归属。

- native734：旧 SYS100 工程，serializer 实际使用正确的 MEM50/WRITE100。
- native803：BASE SYS50 误作 serializer 写时钟，PLL100 端点为零，必须拒绝。
- native852：独立 WRITE100、独立复位和 SYS50 的真实 gate/route 归属通过；该次整体 STA 存在违例，**本目录不批准其时序或位流**。

focused.original.json 是原始自检回执，focused.rerun.json 是对本目录原样复制输入的独立重跑：3 正控、24 拒绝。native852.rerun.json 记录新网表每阶段60项真实归属检查。

可从完整项目根目录调用 safevision/tools/check_v3_native_clock_selftest.py，传本目录 native734/base 与 native803/base；再调用 check_v3_native_clock_domains.py 检查 native852/base。复制的 checker_sources 仅冻结本次检查器原始字节；可执行入口仍为完整项目内同哈希的工具。

没有复制或虚构 STA 路径、路由数据库，也没有据此宣称上板通过。
