


`ifndef SAFEVISION_DEFS_VH
`define SAFEVISION_DEFS_VH


`include "fault_code_defs.vh"
`include "pixel_format_defs.vh"
`include "event_code_defs.vh"


`define SD_CMD0     6'd0
`define SD_CMD8     6'd8
`define SD_CMD17    6'd17
`define SD_CMD18    6'd18
`define SD_CMD55    6'd55
`define SD_CMD58    6'd58
`define SD_ACMD41   6'd41


`define SD_CMD_PREFIX      8'h40
`define SD_CMD8_ARG        32'h0000_01AA
`define SD_CMD8_CHECK      8'hAA
`define SD_ACMD41_HCS      32'h4000_0000


`define SD_CRC_CMD0        8'h95
`define SD_CRC_CMD8        8'h87
`define SD_CRC_DONT_CARE   8'h01


`define SD_TOKEN_DATA_START   8'hFE
`define SD_TOKEN_DATA_STOP    8'hFD


`define SD_R1_IDLE_STATE      0
`define SD_R1_ERASE_RESET     1
`define SD_R1_ILLEGAL_CMD     2
`define SD_R1_CRC_ERR         3
`define SD_R1_ERASE_SEQ_ERR   4
`define SD_R1_ADDR_ERR        5
`define SD_R1_PARAM_ERR       6


`ifdef SIM_FAST_TO
`define SD_TO_RESP        32'd20_000
`define SD_TO_DATA        32'd200_000
`define SD_TO_ACMD41      32'd200_000
`define SD_TO_BUSY        32'd200_000
`else
`define SD_TO_RESP        32'd160_000
`define SD_TO_DATA        32'd10_000_000
`define SD_TO_ACMD41      32'd200_000_000
`define SD_TO_BUSY        32'd25_000_000
`endif


`define SD_RESP_MAX_BYTES 8'd64


`define SD_DIV_INIT       16'd124
`define SD_DIV_FAST       16'd1
`define SD_POWERUP_BYTES  4'd10
`define SD_SECTOR_BYTES   16'd512

`endif
