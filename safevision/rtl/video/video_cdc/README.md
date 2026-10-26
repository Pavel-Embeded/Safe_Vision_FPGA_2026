# video_cdc（A 阶段11 至 15）

video_level_sync：稳定单bit两级；video_cdc_mailbox：valid/ready请求确认、整组payload保持到ACK；帧事件沿用B frame_swap_cdc。每域独立复位同步释放，TD载荷/Gray传播约束另有界。

RTL、TB、接线/延迟和已执行验证见 `docs/A_stages11_15.md`；阶段16应急策略/17HDMI与整板验收尚未完成。入口 `safevision/tools/run_a_stage11_15_sim.ps1`。
