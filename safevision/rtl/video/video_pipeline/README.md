# video_pipeline（A 模块落点）

状态：已实现 `video_pipeline.v`（A 阶段十），配套两个 `.sv` testbench 和 XSim 入口。

用途：在 pixel_clk 域将像素、坐标、de/hsync/vsync、pixel_valid、三个行/帧事件与 hblank/vblank 作为同一个 bundle 延迟 LATENCY 拍。默认 24 位像素 / 12 位坐标 / 1 拍；B 的 RGB565 显式设置 PIXEL_WIDTH=16。LATENCY=0 支持组合旁路。

所有标签每拍无条件推进；de 与 pixel_valid 独立。复位清空整条链。本模块不是异步 FIFO，不自动修复上游已经存在的像素/标签错位。

端口、精确数拍约定、1+2+1=4 拍示例、队友接线边界、复现命令与实际验证结果见 [A 阶段十接口与验证](../../../../docs/A_stage10_latency.md)。已登记到 `safevision.al` 的 CompileOrder=45；当前 B 上板顶层保留。板级烧录与整机时序签核尚未完成。
