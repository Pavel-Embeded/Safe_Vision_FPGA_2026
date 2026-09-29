// ============================================================================
// fault_code_defs.vh — SafeVision 错误码登记（对外主码 + B 链内部细分码）
// ----------------------------------------------------------------------------
// 依据：手册表 9-3（对外主码，全队冻结）+ docs/interface_spec.md §6.2（细分码）
//       本工程约定：错误码从通用定义里拆出来单独登记，
//       便于和 docs/error_code_registry.md 对齐
//
// ★ 对外主码是 A / B / C 三方共用契约，**不得自行扩展**；新增只能走
//   docs/interface_spec.md 变更流程。
// ★ 细分码是 B 链内部调试用，可以扩展，但必须同步登记到 interface_spec.md §6.2。
// ============================================================================
`ifndef FAULT_CODE_DEFS_VH
`define FAULT_CODE_DEFS_VH

// ---------------------------------------------------------------------------
// 1. 对外错误主码（手册表 9-3，全队冻结，不得自行扩展）
// ---------------------------------------------------------------------------
`define ERR_NONE              8'h00
`define ERR_SD_INIT           8'h01   // SD 初始化失败
`define ERR_SD_IO             8'h02   // 扇区读超时或 CRC 错
`define ERR_MEDIA_INVALID     8'h03   // 媒体文件非法（目录项、簇链或 BMP 头）
`define ERR_WAV               8'h07   // WAV 编码或采样率不支持 -> 回退提示音
                                      // ★ interface_spec §6.1 表 9-3 的 0x07，
                                      //   §6.2 细分码 0x71–0x76，决策 D-7

// ---------------------------------------------------------------------------
// 2. B 链内部细分码（interface_spec.md §6.2）
// ---------------------------------------------------------------------------
`define DET_NONE              8'h00
`define DET_SD_INIT_CMD       8'h11   // CMD0/CMD8/ACMD41 协商失败
`define DET_SD_NO_OCR         8'h12   // 卡无 OCR 响应
`define DET_SD_RESP_TO        8'h21   // 命令响应超时
`define DET_SD_DATA_CRC       8'h22   // 数据 CRC16 校验失败
`define DET_SD_TOKEN_TO       8'h23   // 数据起始 token 异常 / 超时

// FAT32 / 目录 / 簇链（对应 interface_spec §6.2）
`define DET_FAT_BPB           8'h31   // BPB 非法（签名 / 每扇区字节数 / 每簇扇区数 / FAT 数量）
`define DET_FAT_NOT32         8'h32   // 非 FAT32（RootEntCnt/FATSz16/TotSec16 判别位不成立）
`define DET_DIR_OOB           8'h33   // 根目录项越界
`define DET_FS_LOOP           8'h34   // 簇链成环
`define DET_FS_EOC            8'h35   // EOC 异常 / 簇号越界
`define DET_FS_SHORT          8'h36   // 文件长度不足

// BMP 严格校验（对应 interface_spec §6.2 与手册 7.6.1 校验清单）
`define DET_BMP_SIG           8'h37   // 签名非 "BM"
`define DET_BMP_DIB           8'h38   // DIB 头长度不足 40
`define DET_BMP_SIZE          8'h39   // 尺寸非 640x480
`define DET_BMP_FMT           8'h3A   // planes/bpp/compression 不合法
`define DET_BMP_TRUNC         8'h3B   // 像素偏移或长度越界
`define DET_BMP_COUNT         8'h3C   // 合法图片少于 4 幅

// WAV / 音频链（对应 interface_spec §6.2 与决策 D-7，对外主码一律 0x07）
`define DET_WAV_RIFF          8'h71   // 非 RIFF / WAVE（含容器结构与长度越界）
`define DET_WAV_PCM           8'h72   // 非 PCM（format code != 1）
`define DET_WAV_RATE          8'h73   // 采样率非 48 kHz
`define DET_WAV_FMT           8'h74   // 非 16 bit 或非立体声
`define DET_WAV_MISSING       8'h75   // 同编号 WAV 不存在（不算 B01 失败）
`define DET_WAV_RING_OVF      8'h76   // 音频环形缓冲写溢出

`endif // FAULT_CODE_DEFS_VH