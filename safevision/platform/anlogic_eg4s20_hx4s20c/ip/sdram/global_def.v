// Vendored from Anlogic example package (lab_ex4_tf / lab_ex5_i2s).
// Source: example/lab_ex4_tf/src/user_source/hdl_source/include/global_def.v
// Copyright (c) Anlogic Inc. Not our code. See README.md in this folder.
// NOTE: macro names below (DATA_WIDTH/ADDR_WIDTH/...) are vendor-global.
//       Do not rely on them elsewhere in this repo.

`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				1000000000/125000000
`define   SELF_REFRESH_INTERVAL			64000000/`SDR_CLK_PERIOD/2**(`ROW_WIDTH)