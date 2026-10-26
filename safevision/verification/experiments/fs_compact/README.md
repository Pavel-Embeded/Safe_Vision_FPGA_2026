# 文件流136bit上下文实验

候选文件单独保存在此，不参加生产综合。`v3_file_streamer_compact_ctx` 仅在 `F_SEC_REQ && !valid` 的扇区边界保存上下文，父模块在 SAVE/LOAD 期间禁止 SD 请求和消费。持久状态为当前簇、当前 LBA、簇内扇区、已发字节和文件长度，共 136bit。LOAD 重建空闲命令、无效字节和零超时状态，`bytes_rd` 返回恢复后的当前轨计数。

在仓库根运行：

```powershell
python safevision/tools/run_v3_sim.py --suite fs_compact --run-dir D:/Codex/runs/fs_compact
```

独立文件字节模型覆盖四轨逐扇区轮换、所有SPC=1/2/4/8/16/32/64/128、32bit地址回卷、碎片链、反压、首末字节及准确长度，2163872项检查。它验证的是候选接口合同；接入V3共享文件系统后的PCM/循环上下文和真实SPI全链还须单独回归。

与WP111组合的音频层原生对照只比WP111再减少6个等效LUT、32FF；不能声称节省129个实体寄存器，也不能用该局部结果代替整机资源和布局布线验收。
