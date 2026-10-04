# video_compositor（A 阶段11–15）

video_layer_delay将RGB与透明mask同拍延迟；video_compositor按各层上游延迟补齐至最大值，Emergency > OSD > Normal，另寄存1拍；RGB与全部扫描标签一致，扫描不能被ready/valid暂停。

RTL、TB、接线/延迟和已执行验证见 `docs/A_stages11_15.md`；阶段16应急策略/17HDMI与整板验收尚未完成。入口 `safevision/tools/run_a_stage11_15_sim.ps1`。
