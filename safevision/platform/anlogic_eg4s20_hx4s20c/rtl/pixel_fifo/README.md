# pixel_fifo（A 阶段11–15）

a_pixel_fifo封装A专用官方异步软FIFO，32写16读、低16先出、FWFT/NOREG；AW10容量2046pixel；写/读水位各在本域；不复用B的通用同步FIFO。

RTL、TB、接线/延迟和已执行验证见 `docs/A_stages11_15.md`；阶段16应急策略/17HDMI与整板验收尚未完成。入口 `safevision/tools/run_a_stage11_15_sim.ps1`。
