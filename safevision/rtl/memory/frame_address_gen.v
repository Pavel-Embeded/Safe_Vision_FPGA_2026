


`include "safevision_defs.vh"

module frame_address_gen #(
    parameter [9:0]  FRAME_WIDTH     = `SV_FRAME_WIDTH,
    parameter [31:0] BYTES_PER_PIXEL = `SV_RGB565_BYTES_PER_PX
)(
    input  wire [31:0] slot_base,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    output wire [31:0] byte_addr,
    output wire [29:0] word_addr,
    output wire        word_phase
);


    localparam IDX_W = 20;


    wire [IDX_W-1:0] yq = {{(IDX_W-10){1'b0}}, y};
    wire [IDX_W-1:0] xq = {{(IDX_W-10){1'b0}}, x};


    wire [IDX_W-1:0] row = (FRAME_WIDTH == 640) ?
                           ((yq << 9) + (yq << 7)) : (yq * FRAME_WIDTH);
    wire [IDX_W-1:0] pix_idx = row + xq;
    wire [31:0]      offset  = pix_idx * BYTES_PER_PIXEL;

    assign byte_addr  = slot_base + offset;
    assign word_addr  = byte_addr[31:2];
    assign word_phase = byte_addr[1];

endmodule
