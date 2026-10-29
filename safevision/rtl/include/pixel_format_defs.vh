


`ifndef PIXEL_FORMAT_DEFS_VH
`define PIXEL_FORMAT_DEFS_VH


`define SV_PIX_FMT_RGB565      8'd0
`define SV_PIX_FMT_BGR888      8'd1

`define SV_RGB565_BYTES_PER_PX 2
`define SV_BGR888_BYTES_PER_PX 3

`define SV_RGB565_R_BITS       5
`define SV_RGB565_G_BITS       6
`define SV_RGB565_B_BITS       5


`define SV_FRAME_WIDTH         640
`define SV_FRAME_HEIGHT        480
`define SV_FRAME_STRIDE_BYTES  (640*`SV_RGB565_BYTES_PER_PX)
`define SV_FRAME_PIXELS        (640*480)
`define SV_FRAME_BYTES         (640*480*`SV_RGB565_BYTES_PER_PX)
`define SV_BMP_SRC_BYTES       (640*480*`SV_BGR888_BYTES_PER_PX)


`define SV_IMG_ALIGN_BYTES     32'h000A_0000

`define SV_IMG0_BASE           32'h0000_0000
`define SV_IMG1_BASE           32'h000A_0000
`define SV_IMG2_BASE           32'h0014_0000
`define SV_IMG3_BASE           32'h001E_0000

`define SV_AUDIO_RING_BASE     32'h0028_0000
`define SV_AUDIO_RING_BYTES    32'h0004_0000

`define SV_WORK_BASE           32'h002C_0000
`define SV_WORK_BYTES          32'h0014_0000

`define SV_MEM_VISIBLE_BASE    32'h0000_0000
`define SV_MEM_VISIBLE_BYTES   32'h0040_0000

`define SV_SLOT_COUNT          4


`define SV_SLOT_BASE(n)        ((n)==2'd0 ? `SV_IMG0_BASE : \
                                (n)==2'd1 ? `SV_IMG1_BASE : \
                                (n)==2'd2 ? `SV_IMG2_BASE : `SV_IMG3_BASE)

`endif
