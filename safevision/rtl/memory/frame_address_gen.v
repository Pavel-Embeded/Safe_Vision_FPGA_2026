// ============================================================================
// frame_address_gen.v — 二维像素坐标 -> 一维逻辑字节地址（纯组合）
// ----------------------------------------------------------------------------
// 依据：手册 7.10「Frame Buffer 帧缓存」：
//         Address = Base + (y × Width + x) × BytesPerPixel
//       本题代入即  slot_base + ((y×640)+x)×2
//       docs/interface_spec.md §一（RGB565，16bit，2 Byte/pixel；只传逻辑字节地址）
//       docs/interface_spec.md §五（冻结的存储地址表）
//
// 公式（must）：byte_addr = slot_base + (y*FRAME_WIDTH + x) * BYTES_PER_PIXEL
//
// ★ 手册 7.10 明确批评过"把行步长与图像宽度混为一谈 / 硬编码宽度"：
//   所以 FRAME_WIDTH 与 BYTES_PER_PIXEL 一律做成 parameter，禁止写死常数。
//   slot_base 只允许取自 interface_spec §五 的地址表常量。
//
// ★ 中间计算显式扩位防溢出：y*640 最大 479*640 = 306,560，y*640+x 最大 307,199，
//   需要 19 bit；本模块用 IDX_W=20 bit 中间量承载，先算 (y*W+x) 再乘每像素字节数，
//   绝不会因为截断而绕回。乘 2 放在最后一步，与手册公式的括号一致。
//
// ★ 附带输出（供写侧打包用）：
//   word_addr[29:0] = byte_addr >> 2 —— 该像素所在 32bit word 的字地址
//   word_phase      = byte_addr[1]  —— 一个 word 装 2 个像素，
//                                      phase=0 表示落在低半（先到像素），
//                                      phase=1 表示落在高半（后到像素）
//
// ★ 踩过的坑：漏乘每像素字节数（少乘 2）会让图像整体"压缩"一半；把行步长
//   当成 640（而不是 640×2=1280 Byte）会让画面斜切/错位。本模块把这两个量
//   显式分离开：FRAME_WIDTH 是像素数，行步长 = FRAME_WIDTH*BYTES_PER_PIXEL。
// ============================================================================

`include "safevision_defs.vh"

module frame_address_gen #(
    parameter [9:0]  FRAME_WIDTH     = `SV_FRAME_WIDTH,  // 行内像素数（不是行步长字节数！）
    parameter [31:0] BYTES_PER_PIXEL = `SV_RGB565_BYTES_PER_PX   // RGB565 = 2 Byte/pixel
)(
    input  wire [31:0] slot_base,     // 槽起始逻辑字节地址（取自 §5 地址表）
    input  wire [9:0]  x,             // 行内坐标 0..639
    input  wire [9:0]  y,             // 行坐标   0..479
    output wire [31:0] byte_addr,     // 逻辑字节地址
    output wire [29:0] word_addr,     // = byte_addr >> 2
    output wire        word_phase     // = byte_addr[1]
);

    // 中间量位宽：y*W + x 的最大值 = 480*640-1 = 307199，19 bit 足够，取 20 留裕量
    localparam IDX_W = 20;

    // 显式零扩展到中间位宽（防溢出）
    wire [IDX_W-1:0] yq = {{(IDX_W-10){1'b0}}, y};
    wire [IDX_W-1:0] xq = {{(IDX_W-10){1'b0}}, x};

    // 先算 (y*W + x)，再乘每像素字节数
    // ★ 640 = 2^9 + 2^7：写成移位相加，避免综合成乘法器阵列（2026-10-03 实测：
    //   乘法阵列使 y_cnt.ce 路径达 7.996ns / 4 级，125MHz 下 −0.067ns 违例）。
    //   仅当 FRAME_WIDTH==640 时用移位相加（编译期常数折叠，逐值等价），否则退回乘法。
    wire [IDX_W-1:0] row = (FRAME_WIDTH == 640) ?
                           ((yq << 9) + (yq << 7)) : (yq * FRAME_WIDTH);   // y*640
    wire [IDX_W-1:0] pix_idx = row + xq;           // y*640 + x
    wire [31:0]      offset  = pix_idx * BYTES_PER_PIXEL;  // (y*640+x)*2

    assign byte_addr  = slot_base + offset;
    assign word_addr  = byte_addr[31:2];           // >> 2
    assign word_phase = byte_addr[1];

endmodule