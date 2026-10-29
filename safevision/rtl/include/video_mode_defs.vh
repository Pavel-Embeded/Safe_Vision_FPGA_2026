

`ifndef SV_VIDEO_MODE_DEFS_VH
`define SV_VIDEO_MODE_DEFS_VH


`define SV_VIDEO_BASE_H_ACTIVE       640
`define SV_VIDEO_BASE_H_FRONT        16
`define SV_VIDEO_BASE_H_SYNC         96
`define SV_VIDEO_BASE_H_BACK         48
`define SV_VIDEO_BASE_V_ACTIVE       480
`define SV_VIDEO_BASE_V_FRONT        10
`define SV_VIDEO_BASE_V_SYNC         2
`define SV_VIDEO_BASE_V_BACK         33
`define SV_VIDEO_BASE_HSYNC_ACTIVE   1'b0
`define SV_VIDEO_BASE_VSYNC_ACTIVE   1'b0
`define SV_VIDEO_BASE_PIXEL_CLK_HZ   25175000


`define SV_VIDEO_HD_H_ACTIVE         1280
`define SV_VIDEO_HD_H_FRONT          110
`define SV_VIDEO_HD_H_SYNC           40
`define SV_VIDEO_HD_H_BACK           220
`define SV_VIDEO_HD_V_ACTIVE         720
`define SV_VIDEO_HD_V_FRONT          5
`define SV_VIDEO_HD_V_SYNC           5
`define SV_VIDEO_HD_V_BACK           20
`define SV_VIDEO_HD_HSYNC_ACTIVE     1'b1
`define SV_VIDEO_HD_VSYNC_ACTIVE     1'b1
`define SV_VIDEO_HD_PIXEL_CLK_HZ     74250000

`endif
