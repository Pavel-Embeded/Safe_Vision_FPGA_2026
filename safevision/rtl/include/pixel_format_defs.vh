// ============================================================================
// pixel_format_defs.vh — 像素格式、帧几何与四槽地址表（唯一来源）
// ----------------------------------------------------------------------------
// 依据：《工业级模块化架构蓝图》§4 的 rtl/include/ 约定
//        手册 7.6.2（图像装载与四槽地址规划）、7.10（Frame Buffer 帧缓存）
//        docs/interface_spec.md §5（★ 冻结地址表）
//
// ★ 为什么单独一个文件：蓝图 §3.3 明确禁止把 74_250_000、帧基地址这类
//   magic number 散落在 RTL 里。像素格式与帧几何会被 frame_address_gen /
//   frame_writer / bmp_unpack / frame_buffer_manager / video_read_dma 同时引用，
//   集中在这里才不会各处对不上。
//
// ★★ 命名前缀 `SV_` 是刻意的，不是啰嗦：
//   frame_address_gen.v / frame_writer.v 里有【同名 parameter】
//   （`parameter [9:0] FRAME_WIDTH = 10'd640`）。Verilog 宏只在写成
//   `` `名字 `` 时才展开，裸标识符不进宏展开，所以两者【不会编译冲突】；
//   但读代码的人容易把 `FRAME_WIDTH` 和 `` `SV_FRAME_WIDTH `` 看成一回事。
//   加前缀后一眼能分清：带反引号的是全项目常量，不带的是本模块可覆盖参数。
//
// ★ 约定（写新模块时照这个来）：
//   - 需要【可被顶层覆盖】的几何量 -> 保留 parameter，默认值取 `SV_*`；
//   - 不需要覆盖的常量 -> 直接用 `SV_*`，禁止再写裸数字。
//
// ★ 地址表是 A / B / C 三方共用的冻结契约，**只能取自本文件**，
//   业务模块内禁止出现裸物理地址运算（interface_spec §一）。
// ============================================================================
`ifndef PIXEL_FORMAT_DEFS_VH
`define PIXEL_FORMAT_DEFS_VH

// ---------------------------------------------------------------------------
// 1. 像素格式
// ---------------------------------------------------------------------------
`define SV_PIX_FMT_RGB565      8'd0     // 显示与帧缓存侧：16 bit
`define SV_PIX_FMT_BGR888      8'd1     // BMP 源文件侧：24 bit

`define SV_RGB565_BYTES_PER_PX 2        // 帧缓存每像素字节数
`define SV_BGR888_BYTES_PER_PX 3        // BMP 每像素字节数

`define SV_RGB565_R_BITS       5        // R[7:3]
`define SV_RGB565_G_BITS       6        // G[7:2]
`define SV_RGB565_B_BITS       5        // B[7:3]

// ---------------------------------------------------------------------------
// 2. 帧几何（本题固定 640x480；换分辨率只改这里 + 顶层 parameter 覆盖）
// ---------------------------------------------------------------------------
`define SV_FRAME_WIDTH         640
`define SV_FRAME_HEIGHT        480
`define SV_FRAME_STRIDE_BYTES  (640*`SV_RGB565_BYTES_PER_PX)        // 1280
`define SV_FRAME_PIXELS        (640*480)                           // 307200
`define SV_FRAME_BYTES         (640*480*`SV_RGB565_BYTES_PER_PX)   // 614400 一槽净数据
`define SV_BMP_SRC_BYTES       (640*480*`SV_BGR888_BYTES_PER_PX)   // 921600 一幅 24bit 源

// ---------------------------------------------------------------------------
// 3. 四槽地址表（逻辑【字节】地址，★ interface_spec §5 冻结）
//    每槽对齐到一个 0x0A0000 边界，为的是地址译码简单；代价是浪费一点空间
//    —— 8 MiB 里还剩约 4 MiB 余量，值得。
// ---------------------------------------------------------------------------
`define SV_IMG_ALIGN_BYTES     32'h000A_0000   // 每槽预留 640 KiB

`define SV_IMG0_BASE           32'h0000_0000
`define SV_IMG1_BASE           32'h000A_0000
`define SV_IMG2_BASE           32'h0014_0000
`define SV_IMG3_BASE           32'h001E_0000

`define SV_AUDIO_RING_BASE     32'h0028_0000   // 音频环形缓冲 256 KiB
`define SV_AUDIO_RING_BYTES    32'h0004_0000

`define SV_WORK_BASE           32'h002C_0000   // 目录 / CRC / 转场 / 压力测试工作区
`define SV_WORK_BYTES          32'h0014_0000

`define SV_MEM_VISIBLE_BASE    32'h0000_0000
`define SV_MEM_VISIBLE_BYTES   32'h0040_0000   // 对外声明可见 4 MiB

`define SV_SLOT_COUNT          4

// 槽号 -> 基地址（给不参数化的模块直接用）
`define SV_SLOT_BASE(n)        ((n)==2'd0 ? `SV_IMG0_BASE : \
                                (n)==2'd1 ? `SV_IMG1_BASE : \
                                (n)==2'd2 ? `SV_IMG2_BASE : `SV_IMG3_BASE)

`endif // PIXEL_FORMAT_DEFS_VH