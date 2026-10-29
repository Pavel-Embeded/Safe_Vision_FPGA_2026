


`ifndef FAULT_CODE_DEFS_VH
`define FAULT_CODE_DEFS_VH


`define ERR_NONE              8'h00
`define ERR_SD_INIT           8'h01
`define ERR_SD_IO             8'h02
`define ERR_MEDIA_INVALID     8'h03
`define ERR_WAV               8'h07


`define DET_NONE              8'h00
`define DET_SD_INIT_CMD       8'h11
`define DET_SD_NO_OCR         8'h12
`define DET_SD_RESP_TO        8'h21
`define DET_SD_DATA_CRC       8'h22
`define DET_SD_TOKEN_TO       8'h23


`define DET_FAT_BPB           8'h31
`define DET_FAT_NOT32         8'h32
`define DET_DIR_OOB           8'h33
`define DET_FS_LOOP           8'h34
`define DET_FS_EOC            8'h35
`define DET_FS_SHORT          8'h36


`define DET_BMP_SIG           8'h37
`define DET_BMP_DIB           8'h38
`define DET_BMP_SIZE          8'h39
`define DET_BMP_FMT           8'h3A
`define DET_BMP_TRUNC         8'h3B
`define DET_BMP_COUNT         8'h3C


`define DET_WAV_RIFF          8'h71
`define DET_WAV_PCM           8'h72
`define DET_WAV_RATE          8'h73
`define DET_WAV_FMT           8'h74
`define DET_WAV_MISSING       8'h75
`define DET_WAV_RING_OVF      8'h76

`endif
