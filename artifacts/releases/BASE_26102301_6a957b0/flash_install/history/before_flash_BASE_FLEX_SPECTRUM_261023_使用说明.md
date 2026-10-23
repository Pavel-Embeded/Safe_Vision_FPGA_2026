# 最新 BASE 本地交付

固件：`26102301`；源码批准提交：`6a957b0365adbc8d8b4069319d29c9fb63680428`。

位流：`D:\Safe_Vision_FPGA_2026\artifacts\releases\BASE_FLEX_SPECTRUM_261023_6a957b0\SafeVision_BASE_6a957b0.bit`

SHA-256：`95ace341ca3aa00363b1a5fc31108fe6d3cd352579906047a6bb02c0ac1a4c5e`

已自动 PROGRAM_SRAM 下载，并完成四槽装载、40项配置、两种缩放×四种几何、四种轮播周期、两次完整恢复及70秒动态轮播串口验收。原始收发字节、ACK、计数和主机脚本在 `D:\Safe_Vision_FPGA_2026\artifacts\board_acceptance\BASE_FLEX_261023_6a957b0\validation`。实体画面/声音/频谱：用户确认正常。

至少四张合法BMP放在FAT32根目录；允许中文和长名，按完整文件名顺序取前四张有效图。支持24/32位BI_RGB、单轴1–16384，等比例居中；同名WAV优先，随后按顺序回退，全部无效时用内置提示音。详见交付包说明。

KEY2+KEY3长按约2秒进入菜单，短按KEY2/KEY3增减，长按KEY2切项，长按KEY3退出。右下显示512点FFT频谱；持续纯音集中在少数频段是正常现象。

本轮只更新本地，不上传GitHub，不写Flash或TF。断电或CONFIG1会回到Flash旧程序；重新下载上述位流即可。成功历史版本和旧故障证据保留。
