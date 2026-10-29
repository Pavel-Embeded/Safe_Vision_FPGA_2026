


`ifndef EVENT_CODE_DEFS_VH
`define EVENT_CODE_DEFS_VH


`define SV_EVT_SRC_NONE       4'h0
`define SV_EVT_SRC_STORAGE    4'h1
`define SV_EVT_SRC_VIDEO      4'h2
`define SV_EVT_SRC_MEMORY     4'h3
`define SV_EVT_SRC_FIFO       4'h4
`define SV_EVT_SRC_CONTROL    4'h5
`define SV_EVT_SRC_WATCHDOG   4'h6
`define SV_EVT_SRC_AUDIO      4'h7
`define SV_EVT_SRC_RECOVERY   4'h8
`define SV_EVT_SRC_DIAG       4'h9
`define SV_EVT_SRC_RESERVED   4'hA


`define SV_EVT_TYPE_FAULT     4'h0
`define SV_EVT_TYPE_RECOVER   4'h1
`define SV_EVT_TYPE_INFO      4'h2

`endif
