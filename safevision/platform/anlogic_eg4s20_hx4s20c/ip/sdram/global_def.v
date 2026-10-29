

// Copyright (c) Anlogic Inc. Not our code. See README.md in this folder.


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`ifndef SAFEVISION_SDRAM_CLK_HZ
`define SAFEVISION_SDRAM_CLK_HZ 125000000
`endif
`define   SDR_CLK_PERIOD                    (1000000000/`SAFEVISION_SDRAM_CLK_HZ)
`ifndef SAFEVISION_REFRESH_ROWS
`define SAFEVISION_REFRESH_ROWS (2**(`ROW_WIDTH))
`endif
`define   SELF_REFRESH_INTERVAL			64000000/`SDR_CLK_PERIOD/`SAFEVISION_REFRESH_ROWS
