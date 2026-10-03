// ============================================================================
// top_stage6_fat32_mount.v — 板级最小验证顶层（SafeVision B 链 · 学习阶段 6）
// ----------------------------------------------------------------------------
// 依据：手册 7.6「FAT32 与图片装载」；本仓库 docs/interface_spec.md §3.2 与
//       §3.2.1「卷基址约定」。落点依据：docs/PROJECT_STRUCTURE.md
//       （板级相关一切归 platform/anlogic_eg4s20_hx4s20c/）。
//
// 定位：这是【接引脚、不属产品链】的 bring-up 顶层，不是 A 的产品顶层
//       safevision_top.v。它在阶段 5（top_stage5_sector_rd.v，已上板通过）之上
//       再往上推一层，把 FAT32 挂载链在真硬件上跑一遍：
//
//         上电等待 → SD 初始化(sd_initializer)
//           → mbr_parser（读卡的 0 号扇区 = MBR，解析出【卷基址】）
//           → fat32_boot_parser（读卷的 0 号扇区 = DBR，解析 BPB）
//           → fat32_directory_scanner(+fat32_cluster_walker)（遍历根目录）
//           → 用 uart_tx(115200) 发出【纯 ASCII 文本报告】 → 停在成功/失败态
//
// ----------------------------------------------------------------------------
// ★★ 本文件最要紧的一条：卷基址只加一次（interface_spec §3.2.1）★★
//
//   FAT32 层（fat32_boot_parser / fat32_directory_scanner / fat32_cluster_walker）
//   内部一律按【卷内相对 LBA】工作：卷的第一个扇区记作 0 号扇区
//   （fat32_boot_parser 里写死 sd_rd_addr <= 32'd0）。
//
//   但真实 TF 卡是【分区的】：卡的 0 号扇区是 MBR，真正的 FAT32 卷从
//   【分区起始物理 LBA】开始。实测这张 HX4S20C 卡的分区起始 = 物理扇区 8192。
//
//   ⇒ 本顶层做唯一的一次地址相加：
//        送给 sd_sector_reader 的地址 = 请求方的相对 LBA + mbr_vol_base
//     （见下面 rd_addr_to_reader 那一行的注释）。FAT32 层内部永远不碰这个偏移。
//     ★ 加两次是这类设计最难查的错；改这块前先读 interface_spec §3.2.1。
//
//   mbr_parser 自己读的是【卡的 0 号扇区】，它的相对地址就是 0；而它在读 MBR 的
//   那段时间里 mbr_vol_base 还是 0（要等到 M_EVAL 才写出来），所以同一个加法器
//   对它也恰好给出 0 + 0 = 0 = 卡的 MBR，无需特殊分支。
//
// ----------------------------------------------------------------------------
// ★ 时钟取舍：与 top_stage5_sector_rd.v 相同 —— 【不接 PLL】，全跑板载 50 MHz
//   （R7）。理由：bring-up 阶段先排除"IP 配置错"这一层变量。相关数值：
//     - uart_tx：50M/115200 = 434 分频（误差 0.007%）
//     - spi_master：SD_DIV_INIT=124 → 200 kHz；SD_DIV_FAST=1 → 12.5 MHz
//     - safevision_defs.vh 的 SD 超时拍数按 100 MHz 推导，50 MHz 下墙上时间翻倍，
//       只会更宽松。产品链仍按 interface_spec §一（100/125/25.175 MHz + PLL）。
//
// ★ 两个 SD 模块共用一条 SPI 总线：init_done 之前归 sd_initializer，之后归
//   sd_sector_reader；sd_ncs = 两个 cs（都低有效）相与。理由与 top_stage5 相同。
//
// ★ 读总线复用：mbr_parser / fat32_boot_parser / fat32_directory_scanner /
//   fat32_cluster_walker 共用一个 sd_sector_reader（四者分时使用，由顶层状态
//   选择；scanner 与 walker 之间用 wk_busy 选择，与 tb_fat32_directory_scanner.sv
//   同样的口径）。地址在复用之后、进 reader 之前统一加一次卷基址。
//
// ★ LED 状态码（led[3:0]，可直接看；一般是 引脚 → 1K → LED 阳极 → GND，
//   所以【高电平点亮】—— 亮 = 1）：
//     1 = 上电等待      2 = 发初始化请求   3 = 等 init_done
//     4 = MBR 解析中    5 = FAT32 挂载中   6 = 根目录扫描中
//     7 = 正在发 UART 报告
//     8 = 成功          9 = 连读（M-6）进行中
//     其它值 = 失败，显示错误主码低 4 位（1=SD 初始化、2=读超时/CRC、3=媒体非法…）
//
// ★ UART 报告（纯 ASCII / 大写十六进制 / 固定宽度 / CRLF 行尾，便于 PC 侧 diff）：
//     行1  SAFEVISION B STAGE6
//     行2  MBR=<8hex> BASE=<8hex> SECS=<8hex>
//     行3  BPS=<4hex> SPC=<2hex> NFAT=<2hex>
//     行4  FATLBA=<8hex> DATALBA=<8hex> ROOTLBA=<8hex>
//     行5  TOTSEC=<8hex> TOTCLUS=<8hex>
//     行6  ENT=<4hex>
//     每项 E <idx:4hex> <name:22hex> <attr:2hex> <clus:8hex> <size:8hex>
//     行7  RPT=<total:4hex> OK=<ok:4hex> BAD=<bad:4hex>   ← 连读汇总（M-6）
//     末行 DONE（连读全 OK）或 ERR=<2hex>（连读出现 BAD；若失败发生在连读之前，
//           则整份报告只有一行 ERR=<2hex>）
//   全部用十六进制，所以顶层不需要"二进制转十进制"的除法器，RTL 很小。
//
//   ★ 行尾一律写【显式字节】8'h0D / 8'h0A，绝不写字符串转义 "\r\n"：TD 6.2 不把
//     字符串里的 \r 当转义（硬件上会发成字母 r = 0x72），ModelSim 却当 0D ——
//     又一个"仿真与综合不一致"，见项目规则 §5 第 11 条与 §7 工具坑。
//   ★ 报告总字节数 = 各段之和（健康卡 183 + 每项 52 + 27 + 6；连读失败时末段换成 8）。
//     这条"逐段相加"的核对必须保留 —— 就是它缺失才让早期版本把报告头声明成
//     184 Byte（实际 183），Verilog 在 MSB 侧补零 ⇒ 整份报告多了一个前导 0x00。
//
// ----------------------------------------------------------------------------
// ★ 实卡（康芯 HX4S20C TF 卡）预期值 —— 上板时拿这份报告逐字段核对：
//
//   分区 0：起始物理扇区 8192（0x00002000），扇区数 15515648（0x00ECC000）。
//           => MBR=00000001 BASE=00002000 SECS=00ECC000
//
//   卷 DBR（物理 LBA 8192）：BytsPerSec=512 / SecPerClus=8 / RsvdSecCnt=2526 /
//           NumFATs=2 / FATSz32=15121 / RootClus=2 / TotSec32=15515648。
//           => BPS=0200 SPC=08 NFAT=02
//           => fat_start_lba = 2526  = 0x000009DE
//              data_start_lba = 2526 + 2*15121 = 32768 = 0x00008000
//              root_dir_lba   = 32768 + (2-2)*8 = 32768 = 0x00008000
//              total_clus = (15515648 - 32768) / 8 = 1935360 = 0x001D8800
//           => FATLBA=000009DE DATALBA=00008000 ROOTLBA=00008000
//              TOTSEC=00ECC000 TOTCLUS=001D8800
//
//   根目录内容（PC 侧已核对）：5 项 SV0001.BMP..SV0005.BMP，各
//           attr=0x20、size=921654=0x000E1036。=> ENT=0005，每行形如
//           E 0000 5356303030312020424D50 20 <clus> 000E1036
//
//   连读（M-6）：读的是根目录扇区（卷内 LBA = ROOTLBA = 00008000），
//           健康卡 100 次全部 CRC16 通过 => RPT=0064 OK=0064 BAD=0000，末行 DONE。
//   健康卡整份报告字节数 = 183 + 5*52 + 27 + 6 = 476 Byte。
// ============================================================================

`include "safevision_defs.vh"

module top_stage6_fat32_mount #(
    parameter integer CLK_FREQ    = 50_000_000,     // 板载晶振频率（R7）
    parameter integer BAUD        = 115200,
    parameter [23:0]  POWERUP_CYC = 24'd2_500_000,  // 上电等待 50ms @50MHz
    // M-6「连读 100 次」：挂载 + 扫目录之后，对同一 LBA 连读 RPT_N 次，
    //   每次由 sd_sector_reader 自带的 CRC16 校验判好坏，最后汇总成 RPT= 一行。
    //   可在例化时覆盖（TB 里用它做短场景）。
    parameter [15:0]  RPT_N       = 16'd100
)(
    // ---- 板级引脚（引脚号见同目录 constraints/pin.adc）----
    input  wire        clk,        // R7   FPGA_GCLK  50 MHz
    input  wire        rst_n,      // A2   KEY_1       低有效按键
    output wire        sd_ncs,     // A12  FPGA_SD_D3  SPI 模式下的片选
    output wire        sd_dclk,    // A14  FPGA_SD_CLK
    output wire        sd_mosi,    // A13  FPGA_SD_CMD
    input  wire        sd_miso,    // B14  FPGA_SD_D0
    output wire        uart_txd,   // D12  网络名 TXD（见 pin.adc 说明）
    output wire [3:0]  led         // A4/A3/C10/B12 = LED0..LED3
);

    // ========================================================================
    // 顶层超时（每个等待态各自独立，不与别态共用计数器）
    //   `SIM_FAST_TO 下用较小值（但要大于各被例化模块的仿真缩放超时，避免顶层
    //   抢先误判）；上板（无该宏）用 300_000_000 拍 ≈ 6s @50MHz，大于
    //   sd_initializer 的 ACMD41 轮询上限 200M、SD_TO_BUSY 25M、SD_TO_DATA 10M，
    //   保证正常路径总是由模块自己的超时先落定。
    // ========================================================================
    `ifdef SIM_FAST_TO
    localparam [31:0] TOP_TO = 32'd2_000_000;
    `else
    localparam [31:0] TOP_TO = 32'd300_000_000;
    `endif

    // ========================================================================
    // 报告文本辅助函数（纯组合，无状态）
    // ========================================================================
    // 十六进制 nibble -> ASCII（大写）
    function [7:0] hexd;
        input [3:0] n;
        begin
            hexd = (n <= 4'd9) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
        end
    endfunction

    // 32bit -> 8 个 ASCII 十六进制字符（MSB 先）
    function [63:0] h8;
        input [31:0] v;
        begin
            h8 = { hexd(v[31:28]), hexd(v[27:24]), hexd(v[23:20]), hexd(v[19:16]),
                   hexd(v[15:12]), hexd(v[11:8]),  hexd(v[7:4]),   hexd(v[3:0]) };
        end
    endfunction

    // 32bit -> 低 4 个 ASCII 十六进制字符（用于 16bit 字段）
    //   注意：4 个字符 = 4*8 = 32 bit；写成 [15:0] 会截断掉高 2 个字符。
    function [31:0] h4;
        input [31:0] v;
        begin
            h4 = { hexd(v[15:12]), hexd(v[11:8]), hexd(v[7:4]), hexd(v[3:0]) };
        end
    endfunction

    // 32bit -> 低 2 个 ASCII 十六进制字符（用于 8bit 字段）
    //   2 个字符 = 16 bit。
    function [15:0] h2;
        input [31:0] v;
        begin
            h2 = { hexd(v[7:4]), hexd(v[3:0]) };
        end
    endfunction

    // 88bit（11 Byte 8.3 名）-> 22 个 ASCII 十六进制字符（byte0 先）
    function [175:0] h11x;
        input [87:0] nm;
        begin
            h11x = {
                hexd(nm[87:84]), hexd(nm[83:80]), hexd(nm[79:76]), hexd(nm[75:72]),
                hexd(nm[71:68]), hexd(nm[67:64]), hexd(nm[63:60]), hexd(nm[59:56]),
                hexd(nm[55:52]), hexd(nm[51:48]), hexd(nm[47:44]), hexd(nm[43:40]),
                hexd(nm[39:36]), hexd(nm[35:32]), hexd(nm[31:28]), hexd(nm[27:24]),
                hexd(nm[23:20]), hexd(nm[19:16]), hexd(nm[15:12]), hexd(nm[11:8]),
                hexd(nm[7:4]),   hexd(nm[3:0])
            };
        end
    endfunction

    // ========================================================================
    // 复位同步（按键是异步源且带抖动）
    // ========================================================================
    wire rst_sync_n;
    reset_sync u_reset_sync (
        .clk        (clk),
        .async_rst_n(rst_n),
        .rst_n      (rst_sync_n)
    );

    // ========================================================================
    // 顶层序列状态
    // ========================================================================
    localparam [3:0] ST_POWER  = 4'd0,   // 上电等待
                     ST_INIT   = 4'd1,   // 发 init_start 一拍
                     ST_WINIT  = 4'd2,   // 等 init_done / init_error
                     ST_MBR    = 4'd3,   // 发 mbr_parser start 一拍
                     ST_WMBR   = 4'd4,   // 等 mbr parse_done
                     ST_MOUNT  = 4'd5,   // 发 fat32_boot_parser start 一拍
                     ST_WMNT   = 4'd6,   // 等 mount_done / mount_error
                     ST_SCAN   = 4'd7,   // 发 scan_en 一拍
                     ST_WSCAN  = 4'd8,   // 收目录项 + 等 scan_done
                     ST_REPORT = 4'd9,   // 逐字节发 UART 报告
                     ST_OK     = 4'd10,
                     ST_ERR    = 4'd11,
                     ST_RPT    = 4'd12,  // 连读（M-6）：清计数
                     ST_RPTREQ = 4'd13,  // 连读：发一次读请求
                     ST_RPTWAIT= 4'd14;  // 连读：等 reader 的 rd_done

    reg  [3:0]  st;
    reg  [23:0] pwr_cnt;

    // 顶层各等待态的独立超时计数器
    reg  [31:0] to_winit, to_wmbr, to_wmnt, to_wscan, to_rep;

    // 顶层错误主码（失败时锁存，供 LED 与报告 ERR= 用）
    reg  [7:0]  top_err;
    reg         rep_err;      // 1 = 本次报告走失败分支（只发 ERR=xx）

    // ---- 连读（M-6）计数：本模块里只由主状态机驱动（单一驱动源）----
    reg  [15:0] rep_ok;       // 连读中 CRC16 通过的次数
    reg  [15:0] rep_bad;      // 连读中失败（超时 / CRC16 错）的次数
    reg  [15:0] rep_idx;      // 连读进行到第几次（0-based）

    // ---- 报告引擎状态 ----
    localparam [2:0] R_IDLE = 3'd0,
                     R_HDR  = 3'd1,
                     R_ENT  = 3'd2,
                     R_RPT  = 3'd3,
                     R_ERR  = 3'd4,
                     R_DONE = 3'd5,
                     R_FIN  = 3'd6;

    reg  [2:0]  rstate;
    reg  [7:0]  pc;           // 报告当前行内的字节位置

    // 报告各段字节数（与下面的拼接严格对应；逐段相加必须等于声明的位宽/8）
    localparam integer HDR_BYTES  = 183;   // 21+42+25+51+34+10
    localparam integer ENT_BYTES  = 52;    // 2+4+1+22+1+2+1+8+1+8+2
    localparam integer RPT_BYTES  = 27;    // 4+4+4+4+5+4+2
    localparam integer ERR_BYTES  = 8;     // 4+2+2
    localparam integer DONE_BYTES = 6;     // 4+2

    // ---- 目录项收集缓冲（足够放实卡的 5 项；存不下的只计数不缓存）----
    localparam integer MAX_ENT = 8;
    reg  [87:0] en_name [0:MAX_ENT-1];
    reg  [7:0]  en_attr [0:MAX_ENT-1];
    reg  [31:0] en_clus [0:MAX_ENT-1];
    reg  [31:0] en_size [0:MAX_ENT-1];
    reg  [15:0] en_idx  [0:MAX_ENT-1];
    reg  [15:0] ent_total;    // 扫描到的合法目录项总数
    reg  [2:0]  ent_cur;      // 发报告时正在输出的第几项

    // ========================================================================
    // 与各被例化模块的连线
    // ========================================================================
    // sd_initializer
    wire        sdhc;
    wire        init_done, init_error;
    wire [7:0]  init_err_code;
    wire        init_cs_n;
    wire [15:0] init_clk_div;
    wire        init_tx_valid;
    wire [7:0]  init_tx_data;

    // mbr_parser
    wire        mbr_parse_done;
    wire [7:0]  mbr_err_code, mbr_err_detail;
    wire        mbr_has;
    wire [31:0] mbr_vol_base;
    wire [31:0] mbr_part_secs;
    wire [31:0] mbr_sd_rd_addr;
    wire [15:0] mbr_sd_rd_len;
    wire        mbr_sd_rd_en;
    wire        mbr_sd_data_ready;

    // fat32_boot_parser
    wire        fs_mount_done, fs_mount_error;
    wire [7:0]  fs_err_code, fs_err_detail;
    wire [15:0] fs_bps;
    wire [7:0]  fs_spc, fs_nfat;
    wire [31:0] fs_fat_lba, fs_root_clus, fs_root_lba, fs_data_lba;
    wire [31:0] fs_tot_sec, fs_tot_clus;
    wire [31:0] fs_sd_rd_addr;
    wire [15:0] fs_sd_rd_len;
    wire        fs_sd_rd_en;
    wire        fs_sd_data_ready;

    // fat32_directory_scanner
    wire        scan_done, dir_bad;
    wire [7:0]  dir_err_code, dir_err_detail;
    wire [87:0] ent_name;
    wire [7:0]  ent_attr;
    wire [31:0] ent_first_clus, ent_size;
    wire [15:0] ent_index;
    wire        ent_valid;
    wire [31:0] dn_sd_rd_addr;
    wire [15:0] dn_sd_rd_len;
    wire        dn_sd_rd_en;
    wire        dn_sd_data_ready;
    wire [31:0] wk_cur_clus, wk_next_clus;
    wire        wk_start, wk_rst_walk, wk_busy, wk_done, wk_eoc, wk_error;
    wire [7:0]  wk_err_code, wk_err_detail;

    // fat32_cluster_walker
    wire [31:0] wk_sd_rd_addr;
    wire [15:0] wk_sd_rd_len;
    wire        wk_sd_rd_en;
    wire        wk_sd_data_ready;

    // sd_sector_reader
    wire        rd_ready;
    wire [7:0]  rd_data;
    wire        rd_data_valid, rd_data_last;
    wire        rd_done, rd_timeout, rd_crc16_err;
    wire [7:0]  rd_err_code, rd_err_detail;
    wire        rd_cs_n;
    wire [15:0] rd_clk_div;
    wire        rd_tx_valid;
    wire [7:0]  rd_tx_data;

    // spi_master
    wire        spi_tx_ready;
    wire [7:0]  spi_rx_data;
    wire        spi_rx_valid;
    wire        spi_busy;

    // uart_tx
    wire        uart_ready;
    wire        uart_tx_valid;
    wire [7:0]  uart_tx_data;

    // ========================================================================
    // 请求脉冲（各只停一拍）与读总线选择
    // ========================================================================
    wire init_start = (st == ST_INIT);
    wire mbr_start  = (st == ST_MBR);
    wire boot_start = (st == ST_MOUNT);
    wire scan_en    = (st == ST_SCAN);

    // 读总线：请求实际发生在等待态（模块在该态才真正发起读）
    wire sel_mbr  = (st == ST_WMBR);
    wire sel_boot = (st == ST_WMNT);
    wire sel_scan = (st == ST_WSCAN);
    wire use_wk   = sel_scan & wk_busy;
    // 连读阶段（M-6）：本顶层自己就是第 5 个读请求方
    wire sel_rep  = (st == ST_RPTREQ) | (st == ST_RPTWAIT);

    // 连读请求：rd_en 与 rd_ready 同拍握手 ⇒ 恰好 1 拍脉冲。
    //   地址给的是【卷内相对 LBA】= 根目录扇区（fs_root_lba），
    //   卷基址照旧只由下面那唯一一个加法器加（interface_spec §3.2.1）。
    wire        rpt_rd_en   = (st == ST_RPTREQ) && rd_ready;
    wire [31:0] rpt_rd_addr = fs_root_lba;
    wire [15:0] rpt_rd_len  = 16'd1;

    wire        bus_rd_en   = sel_rep  ? rpt_rd_en   :
                              sel_mbr  ? mbr_sd_rd_en  :
                              sel_boot ? fs_sd_rd_en   :
                              use_wk   ? wk_sd_rd_en   : dn_sd_rd_en;
    wire [31:0] bus_rd_addr = sel_rep  ? rpt_rd_addr :
                              sel_mbr  ? mbr_sd_rd_addr:
                              sel_boot ? fs_sd_rd_addr :
                              use_wk   ? wk_sd_rd_addr : dn_sd_rd_addr;
    wire [15:0] bus_rd_len  = sel_rep  ? rpt_rd_len  :
                              sel_mbr  ? mbr_sd_rd_len :
                              sel_boot ? fs_sd_rd_len  :
                              use_wk   ? wk_sd_rd_len  : dn_sd_rd_len;
    // 连读阶段必须把 512 Byte 全部排空（data_ready 恒 1）；否则 reader 会停在
    //   S_DATA 等下游，而 S_DATA 本身无超时计数器 ⇒ 只能等顶层兜底超时。
    wire        bus_data_ready = sel_rep  ? 1'b1 :
                                 sel_mbr  ? mbr_sd_data_ready :
                                 sel_boot ? fs_sd_data_ready :
                                 use_wk   ? wk_sd_data_ready : dn_sd_data_ready;

    // ★★ 卷基址只在这里加一次（interface_spec §3.2.1）：★★
    //   请求方给的是【卷内相对 LBA】，reader 需要的是【卡的绝对物理 LBA】。
    //   FAT32 层内部不碰该偏移；mbr_parser 读 MBR 时自身相对地址=0 且此时
    //   mbr_vol_base 仍为 0，故也恰好落到卡的 0 号扇区。
    wire [31:0] rd_addr_to_reader = bus_rd_addr + mbr_vol_base;

    // ========================================================================
    // 报告：各字段的 32bit 视图（拼成 ASCII 行）
    // ========================================================================
    wire [31:0] rv_mbr     = {31'b0, mbr_has};
    wire [31:0] rv_base    = mbr_vol_base;
    wire [31:0] rv_secs    = mbr_part_secs;
    wire [31:0] rv_bps     = {16'b0, fs_bps};
    wire [31:0] rv_spc     = {24'b0, fs_spc};
    wire [31:0] rv_nfat    = {24'b0, fs_nfat};
    wire [31:0] rv_fat     = fs_fat_lba;
    wire [31:0] rv_data    = fs_data_lba;
    wire [31:0] rv_root    = fs_root_lba;
    wire [31:0] rv_totsec  = fs_tot_sec;
    wire [31:0] rv_totclus = fs_tot_clus;
    wire [31:0] rv_entcnt  = {16'b0, ent_total};
    wire [31:0] rv_err     = {24'b0, top_err};

    // 当前正在输出的目录项（组合读出）
    wire [87:0] cur_name = en_name[ent_cur];
    wire [31:0] cur_clus = en_clus[ent_cur];
    wire [31:0] cur_size = en_size[ent_cur];
    wire [7:0]  cur_attr = en_attr[ent_cur];
    wire [15:0] cur_idx  = en_idx [ent_cur];
    wire [31:0] rv_idx   = {16'b0, cur_idx};
    wire [31:0] rv_attr  = {24'b0, cur_attr};

    // 实际要打印的项数 = min(ent_total, MAX_ENT)（存不下的只计数）
    wire [3:0]  ent_show = (ent_total > 16'd8) ? 4'd8 : ent_total[3:0];

    // ---- 连读汇总的数值视图 ----
    wire [31:0] rv_rtot = {16'b0, RPT_N};
    wire [31:0] rv_rok  = {16'b0, rep_ok};
    wire [31:0] rv_rbad = {16'b0, rep_bad};

    // 固定报告头（183 Byte）。★ 各段字节数逐段相加必须等于 183（= 1464 bit）：
    //   行1 "SAFEVISION B STAGE6"(19) + CRLF(2)                          = 21
    //   行2 "MBR="(4) +8 +" BASE="(6) +8 +" SECS="(6) +8 + CRLF(2)       = 42
    //   行3 "BPS="(4) +4 +" SPC="(5) +2 +" NFAT="(6) +2 + CRLF(2)        = 25
    //   行4 "FATLBA="(7)+8 +" DATALBA="(9)+8 +" ROOTLBA="(9)+8 + CRLF(2) = 51
    //   行5 "TOTSEC="(7)+8 +" TOTCLUS="(9)+8 + CRLF(2)                   = 34
    //   行6 "ENT="(4) +4 + CRLF(2)                                       = 10
    //                                          合计 = 21+42+25+51+34+10 = 183
    // ★ 行尾全部写显式字节 8'h0D / 8'h0A，不用字符串转义（见文件头说明）。
    wire [1463:0] hdr_bits = {
        "SAFEVISION B STAGE6", 8'h0D, 8'h0A,
        "MBR=", h8(rv_mbr), " BASE=", h8(rv_base), " SECS=", h8(rv_secs), 8'h0D, 8'h0A,
        "BPS=", h4(rv_bps), " SPC=", h2(rv_spc), " NFAT=", h2(rv_nfat), 8'h0D, 8'h0A,
        "FATLBA=", h8(rv_fat), " DATALBA=", h8(rv_data), " ROOTLBA=", h8(rv_root), 8'h0D, 8'h0A,
        "TOTSEC=", h8(rv_totsec), " TOTCLUS=", h8(rv_totclus), 8'h0D, 8'h0A,
        "ENT=", h4(rv_entcnt), 8'h0D, 8'h0A
    };

    // 一条目录项（52 Byte）：2+4+1+22+1+2+1+8+1+8+2 = 52
    wire [415:0] ent_bits = {
        "E ", h4(rv_idx), " ", h11x(cur_name), " ",
        h2(rv_attr), " ", h8(cur_clus), " ", h8(cur_size), 8'h0D, 8'h0A
    };

    // 连读汇总行（27 Byte）："RPT="(4)+4+" OK="(4)+4+" BAD="(5)+4+CRLF(2) = 27
    wire [215:0] rpt_bits = {
        "RPT=", h4(rv_rtot), " OK=", h4(rv_rok), " BAD=", h4(rv_rbad), 8'h0D, 8'h0A
    };

    // 失败报告（8 Byte）："ERR="(4) +2 + CRLF(2) = 8
    wire [63:0] err_bits = { "ERR=", h2(rv_err), 8'h0D, 8'h0A };

    // 结束行（6 Byte）："DONE"(4) + CRLF(2) = 6
    wire [47:0] done_bits = { "DONE", 8'h0D, 8'h0A };

    // ========================================================================
    // 报告字节选择（组合）+ UART 握手
    // ========================================================================
    reg [7:0] rp_byte;
    always @(*) begin
        case (rstate)
            R_HDR : rp_byte = hdr_bits [(1463 - 8*pc) -: 8];
            R_ENT : rp_byte = ent_bits [(415  - 8*pc) -: 8];
            R_RPT : rp_byte = rpt_bits [(215  - 8*pc) -: 8];
            R_ERR : rp_byte = err_bits [(63   - 8*pc) -: 8];
            R_DONE: rp_byte = done_bits[(47   - 8*pc) -: 8];
            default: rp_byte = 8'h00;
        endcase
    end

    wire rep_shifting = (st == ST_REPORT) &&
                        ((rstate == R_HDR) || (rstate == R_ENT) ||
                         (rstate == R_RPT) || (rstate == R_ERR) ||
                         (rstate == R_DONE));
    assign uart_tx_valid = rep_shifting & uart_ready;   // valid/ready 同拍握手
    assign uart_tx_data  = rp_byte;

    // ========================================================================
    // SPI 归属二选一（同 top_stage5）：初始化没完成时归 initializer
    // ========================================================================
    wire spi_use_reader = init_done;
    wire        spi_tx_valid = spi_use_reader ? rd_tx_valid : init_tx_valid;
    wire [7:0]  spi_tx_data  = spi_use_reader ? rd_tx_data  : init_tx_data;
    wire [15:0] spi_clk_div  = spi_use_reader ? rd_clk_div  : init_clk_div;
    assign sd_ncs = init_cs_n & rd_cs_n;      // 两路低有效片选相与

    // ========================================================================
    // 顶层主序列
    // ========================================================================
    // 目录项下游反压：本顶层不需要反压（扫描与报告串行），恒 ready
    wire ent_ready = 1'b1;

    always @(posedge clk or negedge rst_sync_n) begin
        if (!rst_sync_n) begin
            st        <= ST_POWER;
            pwr_cnt   <= 24'd0;
            to_winit  <= 32'd0;
            to_wmbr   <= 32'd0;
            to_wmnt   <= 32'd0;
            to_wscan  <= 32'd0;
            to_rep    <= 32'd0;
            top_err   <= `ERR_NONE;
            rep_err   <= 1'b0;
            rstate    <= R_IDLE;
            pc        <= 8'd0;
            ent_cur   <= 3'd0;
            ent_total <= 16'd0;
            rep_ok    <= 16'd0;
            rep_bad   <= 16'd0;
            rep_idx   <= 16'd0;
        end else begin
            case (st)
            // ---- 上电等待：让 SD 卡电源稳定 --------------------------------
            ST_POWER: begin
                if (pwr_cnt >= POWERUP_CYC) st <= ST_INIT;
                else                        pwr_cnt <= pwr_cnt + 24'd1;
            end
            // ---- 发一次 init_start ----------------------------------------
            ST_INIT: begin
                to_winit <= 32'd0;
                st       <= ST_WINIT;
            end
            // ---- 等初始化结果（initializer 自带各态独立超时）--------------
            ST_WINIT: begin
                to_winit <= to_winit + 32'd1;
                if (init_error) begin
                    top_err  <= init_err_code;
                    rep_err  <= 1'b1;
                    rstate   <= R_IDLE;
                    pc       <= 8'd0;
                    st       <= ST_REPORT;
                end else if (init_done) begin
                    st <= ST_MBR;
                end else if (to_winit == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end
            // ---- 发一次 MBR 解析 ------------------------------------------
            ST_MBR: begin
                to_wmbr <= 32'd0;
                st      <= ST_WMBR;
            end
            // ---- 等 MBR 解析（SD 层错误会置 err_code；无分区表不算错）-----
            ST_WMBR: begin
                to_wmbr <= to_wmbr + 32'd1;
                if (mbr_parse_done) begin
                    if (mbr_err_code != `ERR_NONE) begin
                        top_err <= mbr_err_code;
                        rep_err <= 1'b1;
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        st      <= ST_REPORT;
                    end else begin
                        st <= ST_MOUNT;
                    end
                end else if (to_wmbr == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end
            // ---- 发一次 FAT32 挂载 ----------------------------------------
            ST_MOUNT: begin
                to_wmnt <= 32'd0;
                st      <= ST_WMNT;
            end
            // ---- 等挂载结果 -----------------------------------------------
            ST_WMNT: begin
                to_wmnt <= to_wmnt + 32'd1;
                if (fs_mount_error) begin
                    top_err <= fs_err_code;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end else if (fs_mount_done) begin
                    st <= ST_SCAN;
                end else if (to_wmnt == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end
            // ---- 发一次根目录扫描 -----------------------------------------
            ST_SCAN: begin
                ent_total <= 16'd0;
                to_wscan  <= 32'd0;
                st        <= ST_WSCAN;
            end
            // ---- 收目录项 + 等 scan_done ----------------------------------
            ST_WSCAN: begin
                to_wscan <= to_wscan + 32'd1;

                // 收集（下游恒 ready；同拍才算送达）
                if (ent_valid & ent_ready) begin
                    // 索引越界的只计数不缓存
                    if (ent_total < MAX_ENT) begin
                        en_name[ent_total[2:0]] <= ent_name;
                        en_attr[ent_total[2:0]] <= ent_attr;
                        en_clus[ent_total[2:0]] <= ent_first_clus;
                        en_size[ent_total[2:0]] <= ent_size;
                        en_idx [ent_total[2:0]] <= ent_index;
                    end
                    ent_total <= ent_total + 16'd1;
                end

                if (scan_done) begin
                    // 目录结构异常（簇链越界/成环）算失败；SD 层错误已透传到 err_code
                    if (dir_bad || (dir_err_code != `ERR_NONE)) begin
                        top_err <= (dir_err_code != `ERR_NONE) ? dir_err_code
                                                               : `ERR_MEDIA_INVALID;
                        rep_err <= 1'b1;
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        st      <= ST_REPORT;
                    end else begin
                        rep_err  <= 1'b0;
                        rstate   <= R_IDLE;
                        pc       <= 8'd0;
                        ent_cur  <= 3'd0;
                        to_rep   <= 32'd0;
                        st       <= ST_RPT;      // 扫描成功 -> 先进连读阶段（M-6）
                    end
                end else if (to_wscan == TOP_TO) begin
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    st      <= ST_REPORT;
                end
            end
            // ---- 连读阶段（M-6）：对同一 LBA 连读 RPT_N 次 -----------------
            // ★ 失败路径选择：无论成败都跑满 RPT_N 次，不提前退出。理由：
            //   ① 报告长度/行数固定，PC 侧逐字节 diff 永远成立；
            //   ②「100 次里坏 1 次」与「100 次全坏」能区分开——提前退出区分不了；
            //   ③ 拔卡时每次读由 reader 自己的出口兜底（S_R1 轮询到
            //      SD_RESP_MAX_BYTES 即退、数据段有 SD_TO_DATA），100 次仍在毫秒级，
            //      必然在有限时间内结束。任何一个等待态都有独立超时（手册 7.4）。
            ST_RPT: begin
                rep_ok  <= 16'd0;
                rep_bad <= 16'd0;
                rep_idx <= 16'd0;
                to_rep  <= 32'd0;
                st      <= ST_RPTREQ;
            end
            // ---- 发一次读请求（rd_en 与 rd_ready 同拍 => 恰好 1 拍）-------
            ST_RPTREQ: begin
                to_rep <= 32'd0;                 // 每次读独立计时（手册 7.4）
                if (rd_ready) st <= ST_RPTWAIT;
                else          st <= ST_RPTREQ;   // reader 尚未空闲，继续等
            end
            // ---- 等本次读结束（数据由 bus_data_ready 恒 1 排空）----------
            ST_RPTWAIT: begin
                to_rep <= to_rep + 32'd1;
                if (rd_done) begin
                    if (rd_timeout || rd_crc16_err) begin
                        rep_bad <= rep_bad + 16'd1;
                        top_err <= `ERR_SD_IO;      // 连读失败：对外主码=读超时/CRC 错
                    end else begin
                        rep_ok  <= rep_ok + 16'd1;
                    end
                    if (rep_idx == (RPT_N - 16'd1)) begin
                        rstate  <= R_IDLE;
                        pc      <= 8'd0;
                        ent_cur <= 3'd0;
                        to_rep  <= 32'd0;
                        st      <= ST_REPORT;       // 连读完毕 -> 发报告
                    end else begin
                        rep_idx <= rep_idx + 16'd1;
                        st      <= ST_RPTREQ;
                    end
                end else if (to_rep == TOP_TO) begin
                    // 兜底：reader 各态都有自己的超时，正常不会走到这里
                    top_err <= `ERR_SD_IO;
                    rep_err <= 1'b1;
                    rstate  <= R_IDLE;
                    pc      <= 8'd0;
                    to_rep  <= 32'd0;
                    st      <= ST_REPORT;
                end
            end
            // ---- 逐字节发 UART 报告 ---------------------------------------
            ST_REPORT: begin
                to_rep <= to_rep + 32'd1;
                if (to_rep == TOP_TO) st <= ST_ERR;   // UART 卡住的兜底出口
                case (rstate)
                R_IDLE: begin
                    if (rep_err) begin
                        rstate <= R_ERR;          // 连读之前的失败：整份报告只有 ERR=
                        pc     <= 8'd0;
                    end else begin
                        rstate <= R_HDR;          // 无目录项也走完整报告（ENT=0000）
                        pc     <= 8'd0;
                        ent_cur<= 3'd0;
                    end
                end
                R_HDR: if (uart_ready) begin
                    if (pc == HDR_BYTES - 1) begin
                        if (ent_show == 4'd0) begin
                            rstate <= R_RPT;      // 无目录项：跳过 ENT，直接汇总
                            pc     <= 8'd0;
                        end else begin
                            rstate <= R_ENT;
                            pc     <= 8'd0;
                            ent_cur<= 3'd0;
                        end
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_ENT: if (uart_ready) begin
                    if (pc == ENT_BYTES - 1) begin
                        if (({1'b0, ent_cur} + 4'd1) >= ent_show) begin
                            rstate <= R_RPT;
                            pc     <= 8'd0;
                        end else begin
                            ent_cur <= ent_cur + 3'd1;
                            pc      <= 8'd0;
                        end
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_RPT: if (uart_ready) begin
                    if (pc == RPT_BYTES - 1) begin
                        // 连读出现 BAD -> 末行 ERR=；全 OK -> 末行 DONE
                        if (rep_bad != 16'd0) rstate <= R_ERR;
                        else                  rstate <= R_DONE;
                        pc <= 8'd0;
                    end else begin
                        pc <= pc + 8'd1;
                    end
                end
                R_ERR: if (uart_ready) begin
                    if (pc == ERR_BYTES - 1) rstate <= R_FIN;
                    else                     pc     <= pc + 8'd1;
                end
                R_DONE: if (uart_ready) begin
                    if (pc == DONE_BYTES - 1) rstate <= R_FIN;
                    else                      pc     <= pc + 8'd1;
                end
                R_FIN: begin
                    if (rep_err || (rep_bad != 16'd0)) st <= ST_ERR;
                    else                               st <= ST_OK;
                end
                default: rstate <= R_IDLE;
                endcase
            end
            ST_OK:  st <= ST_OK;      // 停住，LED 保持 8
            ST_ERR: st <= ST_ERR;     // 停住，LED 显示错误主码低 4 位
            default: st <= ST_POWER;
            endcase
        end
    end

    // ========================================================================
    // LED 状态码（组合，纯观察用）
    // ========================================================================
    reg [3:0] led_code;
    always @(*) begin
        case (st)
            ST_POWER : led_code = 4'h1;
            ST_INIT  : led_code = 4'h2;
            ST_WINIT : led_code = 4'h3;
            ST_MBR   : led_code = 4'h4;
            ST_WMBR  : led_code = 4'h4;
            ST_MOUNT : led_code = 4'h5;
            ST_WMNT  : led_code = 4'h5;
            ST_SCAN  : led_code = 4'h6;
            ST_WSCAN : led_code = 4'h6;
            ST_RPT   : led_code = 4'h9;   // 连读（M-6）进行中
            ST_RPTREQ: led_code = 4'h9;
            ST_RPTWAIT:led_code = 4'h9;
            ST_REPORT: led_code = 4'h7;
            ST_OK    : led_code = 4'h8;
            default  : led_code = top_err[3:0];   // ST_ERR：错误主码低 4 位
        endcase
    end
    assign led = led_code;

    // ========================================================================
    // 例化 1：SD 初始化
    // ========================================================================
    sd_initializer u_sd_initializer (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .start         (init_start),
        .sdhc          (sdhc),
        .init_done     (init_done),
        .init_error    (init_error),
        .err_code      (init_err_code),
        .err_detail    (),
        .retry_cnt     (),
        .dbg_state     (),
        .spi_cs_n      (init_cs_n),
        .spi_clk_div   (init_clk_div),
        .spi_tx_valid  (init_tx_valid),
        .spi_tx_data   (init_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );

    // ========================================================================
    // 例化 2：MBR 解析（读卡的 0 号扇区，给出卷基址）
    // ========================================================================
    mbr_parser u_mbr_parser (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .start          (mbr_start),
        .parse_done     (mbr_parse_done),
        .err_code       (mbr_err_code),
        .err_detail     (mbr_err_detail),
        .dbg_state      (),
        .has_mbr        (mbr_has),
        .vol_base_lba   (mbr_vol_base),
        .part_secs      (mbr_part_secs),
        .sd_rd_addr     (mbr_sd_rd_addr),
        .sd_rd_len      (mbr_sd_rd_len),
        .sd_rd_en       (mbr_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (mbr_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );

    // ========================================================================
    // 例化 3：FAT32 挂载（读卷的 0 号扇区 = DBR；由卷基址加法器负责偏移）
    // ========================================================================
    fat32_boot_parser u_fat32_boot_parser (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .start          (boot_start),
        .mount_done     (fs_mount_done),
        .mount_error    (fs_mount_error),
        .err_code       (fs_err_code),
        .err_detail     (fs_err_detail),
        .dbg_state      (),
        .bytes_per_sec  (fs_bps),
        .sec_per_clus   (fs_spc),
        .num_fats       (fs_nfat),
        .fat_start_lba  (fs_fat_lba),
        .root_clus      (fs_root_clus),
        .root_dir_lba   (fs_root_lba),
        .data_start_lba (fs_data_lba),
        .total_sec      (fs_tot_sec),
        .total_clus     (fs_tot_clus),
        .sd_rd_addr     (fs_sd_rd_addr),
        .sd_rd_len      (fs_sd_rd_len),
        .sd_rd_en       (fs_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (fs_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );

    // ========================================================================
    // 例化 4：根目录遍历
    // ========================================================================
    fat32_directory_scanner u_fat32_directory_scanner (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .scan_en        (scan_en),
        .scan_done      (scan_done),
        .dir_bad        (dir_bad),
        .err_code       (dir_err_code),
        .err_detail     (dir_err_detail),
        .dbg_state      (),
        .sec_per_clus   (fs_spc),
        .root_clus      (fs_root_clus),
        .root_dir_lba   (fs_root_lba),
        .data_start_lba (fs_data_lba),
        .ent_name       (ent_name),
        .ent_attr       (ent_attr),
        .ent_first_clus (ent_first_clus),
        .ent_size       (ent_size),
        .ent_index      (ent_index),
        .ent_valid      (ent_valid),
        .ent_ready      (ent_ready),
        .sd_rd_addr     (dn_sd_rd_addr),
        .sd_rd_len      (dn_sd_rd_len),
        .sd_rd_en       (dn_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (dn_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail),
        .wk_cur_clus    (wk_cur_clus),
        .wk_start       (wk_start),
        .wk_rst_walk    (wk_rst_walk),
        .wk_busy        (wk_busy),
        .wk_done        (wk_done),
        .wk_next_clus   (wk_next_clus),
        .wk_eoc         (wk_eoc),
        .wk_error       (wk_error),
        .wk_err_code    (wk_err_code),
        .wk_err_detail  (wk_err_detail)
    );

    // ========================================================================
    // 例化 5：簇链跟踪（与 file_streamer 共用同一份逻辑，这里只给 scanner 用）
    // ========================================================================
    fat32_cluster_walker u_fat32_cluster_walker (
        .clk            (clk),
        .rst_n          (rst_sync_n),
        .rst_walk       (wk_rst_walk),
        .start          (wk_start),
        .cur_clus       (wk_cur_clus),
        .busy           (wk_busy),
        .done           (wk_done),
        .next_clus      (wk_next_clus),
        .eoc            (wk_eoc),
        .error          (wk_error),
        .err_code       (wk_err_code),
        .err_detail     (wk_err_detail),
        .hop_cnt        (),
        .dbg_state      (),
        .fat_start_lba  (fs_fat_lba),
        .total_clus     (fs_tot_clus),
        .sd_rd_addr     (wk_sd_rd_addr),
        .sd_rd_len      (wk_sd_rd_len),
        .sd_rd_en       (wk_sd_rd_en),
        .sd_rd_ready    (rd_ready),
        .sd_data        (rd_data),
        .sd_data_valid  (rd_data_valid),
        .sd_data_ready  (wk_sd_data_ready),
        .sd_data_last   (rd_data_last),
        .sd_rd_done     (rd_done),
        .sd_timeout_err (rd_timeout),
        .sd_crc16_err   (rd_crc16_err),
        .sd_err_code    (rd_err_code),
        .sd_err_detail  (rd_err_detail)
    );

    // ========================================================================
    // 例化 6：SD 单扇区读（被上面四个模块分时复用；地址已加过卷基址）
    // ========================================================================
    sd_sector_reader u_sd_sector_reader (
        .clk           (clk),
        .rst_n         (rst_sync_n),
        .sdhc          (sdhc),
        .rd_en         (bus_rd_en),
        .rd_addr       (rd_addr_to_reader),
        .rd_len        (bus_rd_len),
        .rd_ready      (rd_ready),
        .data          (rd_data),
        .data_valid    (rd_data_valid),
        .data_ready    (bus_data_ready),
        .data_last     (rd_data_last),
        .rd_done       (rd_done),
        .busy          (),
        .timeout_err   (rd_timeout),
        .crc16_err     (rd_crc16_err),
        .err_code      (rd_err_code),
        .err_detail    (rd_err_detail),
        .crc_rx        (),
        .dbg_state     (),
        .spi_cs_n      (rd_cs_n),
        .spi_clk_div   (rd_clk_div),
        .spi_tx_valid  (rd_tx_valid),
        .spi_tx_data   (rd_tx_data),
        .spi_tx_ready  (spi_tx_ready),
        .spi_rx_data   (spi_rx_data),
        .spi_rx_valid  (spi_rx_valid)
    );

    // ========================================================================
    // 例化 7：SPI 主机（唯一一份，被 initializer / reader 分时复用）
    // ========================================================================
    spi_master #(
        .CLK_FREQ (CLK_FREQ)
    ) u_spi_master (
        .clk        (clk),
        .rst_n      (rst_sync_n),
        .clk_div    (spi_clk_div),
        .cs_n       (sd_ncs),
        .tx_valid   (spi_tx_valid),
        .tx_data    (spi_tx_data),
        .tx_ready   (spi_tx_ready),
        .rx_data    (spi_rx_data),
        .rx_valid   (spi_rx_valid),
        .busy       (spi_busy),
        .sclk       (sd_dclk),
        .mosi       (sd_mosi),
        .miso       (sd_miso)
    );

    // ========================================================================
    // 例化 8：UART 发送（50 MHz 下 115200 8N1）—— 发 ASCII 报告
    // ========================================================================
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_sync_n),
        .tx_valid  (uart_tx_valid),
        .tx_data   (uart_tx_data),
        .tx_ready  (uart_ready),
        .txd       (uart_txd)
    );

endmodule