// ============================================================================
// safevision_defs.vh — SafeVision 全链公共定义（平台无关）
// ----------------------------------------------------------------------------
// 依据：《安视 SafeVision 赛选手册 V2.0》
//       7.3   SD 卡基础（扇区、CMD0/CMD8/ACMD41/CMD58/CMD17）
//       7.4   Timeout 工程意识（各等待态独立超时出口）
//       6.2   错误码表（对外主码 + B 链内部细分码）
//       《工业级模块化架构蓝图》§4 的 rtl/include/ 约定：
//         safevision_defs.vh  通用定义（本文件）
//         fault_code_defs.vh  错误码登记（本文件已包含，单条 include 即可）
//         pixel_format_defs.vh / event_code_defs.vh 留给 A / C 链登记
// 对接：docs/interface_spec.md §3.1
//
// ★ 蓝图 §3.3 配置管理：禁止把 74_250_000、500ms 计数值、帧基地址等
//   magic number 散落在 RTL 内。本文件就是这些常数的唯一落点。
// ============================================================================
`ifndef SAFEVISION_DEFS_VH
`define SAFEVISION_DEFS_VH

// 错误码单独登记，这里一并引入，调用方只需 include 本文件
`include "fault_code_defs.vh"

// ---------------------------------------------------------------------------
// 1. SD SPI 命令索引
// ---------------------------------------------------------------------------
`define SD_CMD0     6'd0     // GO_IDLE_STATE
`define SD_CMD8     6'd8     // SEND_IF_COND
`define SD_CMD17    6'd17    // READ_SINGLE_BLOCK
`define SD_CMD18    6'd18    // READ_MULTIPLE_BLOCK（暂未实现）
`define SD_CMD55    6'd55    // APP_CMD 前缀
`define SD_CMD58    6'd58    // READ_OCR
`define SD_ACMD41   6'd41    // SD_SEND_OP_COND（APP 命令，须先发 CMD55）

// ---------------------------------------------------------------------------
// 2. 命令固定字段
// ---------------------------------------------------------------------------
// SPI 模式下命令帧 = 0x40|cmd(1) + arg(4, **MSB 先发**) + CRC7(1)
`define SD_CMD_PREFIX      8'h40
`define SD_CMD8_ARG        32'h0000_01AA   // 电压 2.7-3.6V(VHS=1) + 校验图案 0xAA
`define SD_CMD8_CHECK      8'hAA          // 卡应回显 0xAA
`define SD_ACMD41_HCS      32'h4000_0000  // HCS=1，询问是否为 SDHC/SDXC

// CRC7 字节：SPI 模式下仅 CMD0 与 CMD8 会被卡校验，其余可填 0x01
`define SD_CRC_CMD0        8'h95    // CMD0  : CRC7=0x4A, {crc7,1'b1}=0x95
`define SD_CRC_CMD8        8'h87    // CMD8  : CRC7=0x43, {crc7,1'b1}=0x87
`define SD_CRC_DONT_CARE   8'h01    // 其余命令（卡不校验）

// ---------------------------------------------------------------------------
// 3. 数据令牌
// ---------------------------------------------------------------------------
`define SD_TOKEN_DATA_START   8'hFE   // 单块/多块读数据起始令牌
`define SD_TOKEN_DATA_STOP    8'hFD   // CMD18 停止传输令牌

// ---------------------------------------------------------------------------
// 4. R1 响应标志位（R1 的 bit7 恒为 0，是"响应已到达"的判定依据）
// ---------------------------------------------------------------------------
`define SD_R1_IDLE_STATE      0        // bit0 : 1=卡仍在初始化中
`define SD_R1_ERASE_RESET     1        // bit1
`define SD_R1_ILLEGAL_CMD     2        // bit2 : 非法命令
`define SD_R1_CRC_ERR         3        // bit3 : CRC 错
`define SD_R1_ERASE_SEQ_ERR   4        // bit4
`define SD_R1_ADDR_ERR        5        // bit5 : 地址/参数越界
`define SD_R1_PARAM_ERR       6        // bit6 : 参数错

// ---------------------------------------------------------------------------
// 5 / 6. 错误码（对外主码 ERR_* 与内部细分码 DET_*）
// ---------------------------------------------------------------------------
// 已拆分到 rtl/include/fault_code_defs.vh，由本文件顶部统一 include。
// 需要错误码的模块只需 `include "safevision_defs.vh" 即可。

// ---------------------------------------------------------------------------
// 7. 超时拍数（手册 7.4：各等待态独立超时，禁止全模块共用一个计数器）
// ---------------------------------------------------------------------------
// sys_clk = 100 MHz  =>  1 拍 = 10 ns
//
// 推导（全部标记"待实测"，实测后回填 docs/interface_spec.md 的 O-4）：
//   TO_RESP   : SD 规范 NCR <= 8 字节。初始化段 SCLK=400kHz -> 1 字节 20us
//               -> 8 字节 160us；取 10 倍裕量 -> 1.6ms -> 160_000 拍
//   TO_DATA   : 单块读访问时间上限取 100ms（SD 规范量级）
//               -> 10_000_000 拍
//   TO_ACMD41 : 卡上电初始化最长约 1s；取 2s 总轮询上限
//               -> 200_000_000 拍
//   TO_BUSY   : 卡忙（CS 已释放、MISO 仍为 0）等待，取 250ms
//               -> 25_000_000 拍
//
// ★ 仿真用缩放值：定义 SIM_FAST_TO 时改用短超时，
//   目的是让"超时出口"这条分支在可接受的仿真时间内被真正跑到。
//   缩放值仍远大于正常操作耗时（初始化段 1 字节 = 250 拍 @400kHz），
//   所以不会把正常路径误判成超时。
//   真实产品值只能在板子上实测后回填（见 docs/B链待办与硬件验证清单.md）。
`ifdef SIM_FAST_TO
`define SD_TO_RESP        32'd20_000        // 200 us（正常 1 字节约 250 拍，留 80 倍）
`define SD_TO_DATA        32'd200_000       // 2 ms
`define SD_TO_ACMD41      32'd200_000       // 2 ms 总轮询上限
`define SD_TO_BUSY        32'd200_000
`else
`define SD_TO_RESP        32'd160_000       // 命令响应等待
`define SD_TO_DATA        32'd10_000_000    // 数据令牌等待
`define SD_TO_ACMD41      32'd200_000_000   // ACMD41 轮询总上限
`define SD_TO_BUSY        32'd25_000_000    // 卡忙等待
`endif

// 命令响应轮询的最大字节数（超过即判超时，防止无限发 0xFF）
`define SD_RESP_MAX_BYTES 8'd64

// ---------------------------------------------------------------------------
// 8. 时序常量
// ---------------------------------------------------------------------------
`define SD_DIV_INIT       16'd124    // SCLK = 100MHz/(2*(124+1)) = 400 kHz（初始化段）
`define SD_DIV_FAST       16'd1      // SCLK = 100MHz/(2*(1+1))   = 25 MHz（数据传输段）
`define SD_POWERUP_BYTES  4'd10      // 上电需 >=74 个 SCLK，发 10 字节 = 80 个
`define SD_SECTOR_BYTES   16'd512    // 一个扇区的字节数

`endif // SAFEVISION_DEFS_VH