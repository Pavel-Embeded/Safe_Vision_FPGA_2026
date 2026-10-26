# 数字媒体目录名压缩实验

此目录保留候选原始审计快照，不进入生产综合；经验证的同字节实现位于 `rtl/storage/fat32_directory_scanner.v`。SV_MEDIA_ONLY 默认 0，执行通用目录扫描；参数为 1 时仅发布 SVdddd  BMP 或 SVdddd  WAV，dddd 为四个 ASCII 十进制数字。候选保留完整 32bit 簇号、文件长度、原始目录槽位索引、属性过滤、删除和结束标记，反压期间字段保持稳定。

候选把11字节名称寄存替换为16bit数字及扩展名判定，接口仍重建完整88bit名称。它适用于本项目限定的媒体文件名，不能用来替代通用FAT目录枚举。

在仓库根运行：

    python safevision/tools/run_v3_sim.py --suite directory_sv --run-dir D:/Codex/runs/directory_sv

1000扇区独立字段/过滤/索引检查13890项通过；关闭参数时另有68902次逐拍旧实现对照。整机同路径 HD 对照为 18700→18590 等效 LUT、13534→13396 DFF，RAM/DSP不变，仍未达到资源门槛。五项音频 68502 次比较通过后，参数实现已保存到生产源码：默认参数仍为0，只有 `v3_shared_fs_service` 显式选择1。上述入口现测生产副本；真实SPI和最终冻结回归另行记录，不能用实验结果替代发布验收。
