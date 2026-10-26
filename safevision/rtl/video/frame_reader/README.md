# frame_reader（A 阶段11 至 15）

frame_reader：RGB565 FWFT消费，RGB888/全扫描标签1拍；frame_slot_commit：B邮箱消费、垂直消隐原子换槽；pixel_word_packer：16bit低先合成32bit；a_frame_fetch_bridge：B DMA/官方FIFO、预取与排空后换epoch。

RTL、TB、接线/延迟和已执行验证见 `docs/A_stages11_15.md`；阶段16应急策略/17HDMI与整板验收尚未完成。入口 `safevision/tools/run_a_stage11_15_sim.ps1`。
