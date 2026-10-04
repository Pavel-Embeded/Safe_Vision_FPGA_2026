# A 异步像素 FIFO IP

取自本机 TD 6.2.168116 安装中的 `ip/soft_fifo/soft_fifo_al.dat` 公共源模板（2022-04-26），选择 ASYNC、BRAM_9K、SHOW_AHEAD=1、OUTREG=NOREG。`a_pixel_fifo_ip.v` 与 `a_pixel_fifo_eram.v` 是同一官方模板的参数化实例；只展开条件编译、设置参数默认值、给模块加A专用名称，保留官方指针、Gray同步、标志及RAM行为。没有使用其他IP的RAM模型，也没有用行为FIFO替代官方FIFO。

默认写32 bit×1024地址、读16 bit×2048地址；先输出word低16 bit。官方FIFO保留一个写地址，**实际可用1023 word/2046 pixel**。`wr_words` 是写域word计数，`rd_pixels` 是读域pixel计数，跨域统计含同步延迟。

调用平台包装 `rtl/pixel_fifo/a_pixel_fifo.v`，AW支持6–14。写入必须满足 `wr_en && wr_ready`；读取必须在 `!empty && rd_valid` 时使能。FWFT的当前数据在读沿之前已有效；读沿才推进。公共高有效复位清除两端指针，官方内部两域分别同步释放。

复现：`safevision/tools/run_a_stage11_15_sim.ps1 -Top tb_a_pixel_fifo`。测试直接编译这两份官方源码，在异步125/74 MHz下验证容量、full/empty、阈值、宽度转换、回绕、停顿和公共复位。TD验证工程实际映射为9K ERAM；XSim无需解密库。
