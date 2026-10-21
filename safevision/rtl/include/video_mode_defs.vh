// Video scan geometry, independent of pixel_format_defs.vh frame storage.
// Handbook V2.0 table 6-4. Frequencies are PLL targets, not generated here.
`ifndef SV_VIDEO_MODE_DEFS_VH
`define SV_VIDEO_MODE_DEFS_VH

// BASE: 640x480, total 800x525, negative sync, about 59.94 Hz.
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

// HD: 1280x720, total 1650x750, positive sync, 60 Hz.
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
