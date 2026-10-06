// ============================================================================
// sd_spi_card_model.v — SD 卡 SPI 从机行为模型（仅用于仿真，不参与综合）
// ----------------------------------------------------------------------------
// 用途：阶段 5 的"逐字节比对"必须有卡侧参照。本模型按 SD SPI 模式 0 应答：
//         CMD0  -> R1 = 0x01
//         CMD8  -> R7 = 0x01 00 00 01 AA
//         CMD55 -> R1 = 0x00
//         ACMD41-> R1 = 0x00（立刻 ready，避免仿真跑很久）
//         CMD58 -> R3 = 0x00 C0 FF 80 00（bit31 上电完成, bit30 CCS=1 -> SDHC）
//         CMD17 -> R1=0x00, 令牌 0xFE, 512 Byte 数据, 2 Byte CRC16
//
// 扇区内容：sector[i] = i[7:0] + 8'h11 —— 规律数据，便于一眼看出错位/漏字节。
// CRC16  ：与 sd_sector_reader 相同的 XMODEM 算法，用于验证 DUT 的 CRC 比对逻辑。
//
// ★ 本模型只在 SCLK 边沿工作（纯行为），不要求综合。
// ============================================================================
`include "safevision_defs.vh"

module sd_spi_card_model #(
    parameter [31:0] OCR_VALUE       = 32'hC0FF_8000,  // bit31=1 上电完成, bit30=1 CCS(SDHC)
    parameter [7:0]  SLOW_INIT_POLLS = 8'd0,           // ACMD41 前 N 次回 idle 态（模拟慢卡）
    parameter        CMD8_ILLEGAL    = 1'b0,           // 1 = v1.x 卡，CMD8 回 illegal command
    // ★ 2026-10-06 新增：CMD0 的 R1 值。真卡实测**并不总是 0x01** ——
    //   `evidence/board` 的 SVPLAY-CAP 抓到 `R1=03`（bit0 idle + bit1 erase reset）。
    //   旧 RTL 用 `r1 == 8'h01` 等值判断 ⇒ 把 0x03 判成失败（缺陷 27）。
    //   本参数让 TB 能构造"CMD0 回 0x03"的卡，守住"必须容忍 erase-reset 位"这条判据。
    parameter [7:0]  CMD0_R1         = 8'h01,
    // ★ 2026-10-06 新增（缺陷 28 守门用）：前 N 次 CMD0 故意回 `0x02`（非 idle），
    //   模拟"卡被上次复位打断、残留数据字节被当成 R1"。RTL 必须靠"重走前导 + CMD0"
    //   重新同步后仍能初始化成功。
    parameter [2:0]  CMD0_BAD_TRIES  = 3'd0,
    // ---- 卷基址（分区卡）支持，见 docs/interface_spec.md §3.2.1 ----
    // 默认 0 = 无分区表（卷 0 号扇区 = 卡 0 号扇区），所有既有 TB 行为完全不变。
    // 设成 N>0 时：卡 LBA [N, N+63] 映射到 vol[] 的卷内相对扇区 [0,63]，
    // 所以 vol_zero / vol_set / vol_set_le / mk_* 仍按【卷内相对 LBA】使用；
    // 卡 LBA 0..N-1（如 MBR）与其它未映射扇区回落到默认图案 sector[]。
    parameter [31:0] VOL_BASE        = 32'd0,
    parameter integer VOL_SECTORS = 64
)(
    input  wire        sclk,
    input  wire        cs_n,
    input  wire        mosi,
    output wire        miso,

    // ---- 运行时控制（供 testbench 动态切换）----
    input  wire        i_dead,         // 1 = 拔卡/坏卡：MISO 恒高，永不响应

    // ---- 观测口（供 testbench 检查）----
    output reg  [5:0]  o_cmd,          // 最近解出的命令索引
    output reg  [31:0] o_arg,          // 最近解出的参数
    output reg  [31:0] o_acmd41_arg,   // 最近一次 ACMD41 的参数（验证 v1 卡不带 HCS）
    output reg  [7:0]  o_cmd_cnt,      // 收到的命令条数
    output reg  [7:0]  o_acmd41_cnt,   // 收到的 ACMD41 次数
    output reg         o_cmd_valid     // 解出新命令时拉高 1 拍（sclk 域）
);

    // ------------------------------------------------------------------------
    // 扇区内容与 CRC
    // ------------------------------------------------------------------------
    reg [7:0] sector [0:511];       // 默认扇区内容（未显式写入某 LBA 时的兜底）
    reg [7:0] rd_buf [0:511];       // CMD17 本次要返回的 512 字节
    reg [7:0] vol    [0:VOL_SECTORS*512-1];     // 按 (lba*512 + off) 显式写入的卷内容（测试用，容量由 VOL_SECTORS 指定）
    reg       vol_used [0:VOL_SECTORS-1];      // 标记哪些 LBA 被显式写过
    integer   i;
    integer   j;
    integer   kk;
    initial begin
        for (i = 0; i < 512; i = i + 1)
            sector[i] = i[7:0] + 8'h11;
        for (i = 0; i < VOL_SECTORS; i = i + 1)
            vol_used[i] = 1'b0;
    end

    // ---- 卷内容写入工具（供 testbench 调用）----
    // 清零某个扇区并标记为"已显式写入"
    task vol_zero;
        input [31:0] lba;
        begin
            if (lba < VOL_SECTORS) begin
                for (kk = 0; kk < 512; kk = kk + 1)
                    vol[lba*32'd512 + kk] = 8'h00;
                vol_used[lba] = 1'b1;
            end else begin
                $display("[card_model] vol_zero: LBA %0d 超出模型支持范围(VOL_SECTORS)", lba);
            end
        end
    endtask

    // 往某个扇区的指定偏移写一个字节
    task vol_set;
        input [31:0] lba;
        input [15:0] off;
        input [7:0]  val;
        begin
            if (lba < VOL_SECTORS) begin
                vol[lba*32'd512 + off] = val;
                vol_used[lba] = 1'b1;
            end else begin
                $display("[card_model] vol_set: LBA %0d 超出模型支持范围(VOL_SECTORS)", lba);
            end
        end
    endtask

    // 往某个扇区的小端字段写一个值（len = 1/2/4 字节）
    task vol_set_le;
        input [31:0] lba;
        input [15:0] off;
        input [31:0] val;
        input [2:0]  len;
        begin
            vol_set(lba, off + 16'd0, val[7:0]);
            if (len >= 3'd2) vol_set(lba, off + 16'd1, val[15:8]);
            if (len >= 3'd4) begin
                vol_set(lba, off + 16'd2, val[23:16]);
                vol_set(lba, off + 16'd3, val[31:24]);
            end
        end
    endtask

    // 构造一个 BPB（可选择故意做成非 FAT32，用于负向测试）
    task mk_fat32_dbr;
        input [15:0] bytes_per_sec;   // 正常 512
        input [7:0]  sec_per_clus;    // 正常 8
        input [15:0] reserved_sec;    // 正常 32
        input [7:0]  num_fats;        // 正常 2
        input [31:0] fat_sz32;        // 正常 1024
        input [31:0] root_clus;       // 正常 2
        input [31:0] total_sec32;     // 正常 0x10000
        input        as_fat32;        // 0 = 故意破坏 FAT32 判别位
        begin
            vol_zero(32'd0);
            vol_set(32'd0, 16'd0, 8'hEB);   // jmp
            vol_set(32'd0, 16'd1, 8'h58);
            vol_set(32'd0, 16'd2, 8'h90);   // nop
            vol_set(32'd0, 16'd3, 8'h4D);   // "MSDOS5.0"
            vol_set(32'd0, 16'd4, 8'h53);
            vol_set(32'd0, 16'd5, 8'h44);
            vol_set(32'd0, 16'd6, 8'h4F);
            vol_set(32'd0, 16'd7, 8'h53);
            vol_set(32'd0, 16'd8, 8'h35);
            vol_set(32'd0, 16'd9, 8'h2E);
            vol_set(32'd0, 16'd10, 8'h30);
            // BPB
            vol_set_le(32'd0, 16'd11, {16'd0, bytes_per_sec}, 3'd2);  // BytsPerSec
            vol_set(32'd0, 16'd13, sec_per_clus);                     // SecPerClus
            vol_set_le(32'd0, 16'd14, {16'd0, reserved_sec}, 3'd2);   // RsvdSecCnt
            vol_set(32'd0, 16'd16, num_fats);                         // NumFATs
            vol_set_le(32'd0, 16'd17, 32'd0, 3'd2);                   // RootEntCnt = 0
            vol_set_le(32'd0, 16'd19, 32'd0, 3'd2);                   // TotSec16   = 0
            vol_set(32'd0, 16'd21, 8'hF8);                            // Media
            vol_set_le(32'd0, 16'd22, 32'd0, 3'd2);                   // FATSz16    = 0
            vol_set_le(32'd0, 16'd24, 32'd63,  3'd2);                 // SecPerTrk
            vol_set_le(32'd0, 16'd26, 32'd255, 3'd2);                 // NumHeads
            vol_set_le(32'd0, 16'd28, 32'd0,   3'd4);                 // HiddSec
            vol_set_le(32'd0, 16'd32, total_sec32, 3'd4);             // TotSec32
            // FAT32 扩展
            vol_set_le(32'd0, 16'd36, fat_sz32, 3'd4);                // FATSz32
            vol_set_le(32'd0, 16'd40, 32'd0,    3'd2);                // ExtFlags
            vol_set_le(32'd0, 16'd42, 32'd0,    3'd2);                // FSVer
            vol_set_le(32'd0, 16'd44, root_clus, 3'd4);               // RootClus
            vol_set_le(32'd0, 16'd48, 32'd1,    3'd2);                // FSInfo
            vol_set_le(32'd0, 16'd50, 32'd6,    3'd2);                // BkBootSec
            vol_set_le(32'd0, 16'd64, 32'd0,    3'd1);                // DrvNum
            if (!as_fat32) begin
                // 故意破坏 FAT32 判别位：三个字段全部非 0
                vol_set_le(32'd0, 16'd17, 32'd512, 3'd2);             // RootEntCnt != 0
                vol_set_le(32'd0, 16'd19, 32'd256, 3'd2);             // TotSec16   != 0
                vol_set_le(32'd0, 16'd22, 32'd64,  3'd2);             // FATSz16    != 0
            end
            vol_set(32'd0, 16'd510, 8'h55);                           // 签名
            vol_set(32'd0, 16'd511, 8'hAA);
        end
    endtask

    // ------------------------------------------------------------------------
    // 构造一条 32 Byte 目录项（阶段 6 fat32_directory_scanner 用）
    // ------------------------------------------------------------------------
    // FAT32 目录项字段偏移（全队冻结，改这里必须同步改 docs/interface_spec.md）：
    //   0x00..0x0A  DIR_Name[11]  8.3 短名，不足补 0x20(空格)
    //   0x0B        DIR_Attr      属性：0x20=归档, 0x0F=LFN, 0x08=卷标, 0x10=目录
    //   0x0C..0x13  保留 / NT 保留（这里写 0）
    //   0x14..0x15  DIR_FstClusHI 首簇号高 16 位
    //   0x16..0x19  保留（这里写 0）
    //   0x1A..0x1B  DIR_FstClusLO 首簇号低 16 位
    //   0x1C..0x1F  DIR_FileSize  文件字节数（小端）
    task mk_dir_entry;
        input [31:0] lba;          // 目录项所在扇区
        input [15:0] off;          // 扇区内偏移，必须 32 字节对齐（0,32,...,480）
        input [87:0] name83;       // 11 字节 8.3 名，如 "SV0001  BMP"
        input [7:0]  attr;
        input [31:0] first_clus;
        input [31:0] file_size;
        begin
            vol_set(lba, off + 16'd0,  name83[87:80]);
            vol_set(lba, off + 16'd1,  name83[79:72]);
            vol_set(lba, off + 16'd2,  name83[71:64]);
            vol_set(lba, off + 16'd3,  name83[63:56]);
            vol_set(lba, off + 16'd4,  name83[55:48]);
            vol_set(lba, off + 16'd5,  name83[47:40]);
            vol_set(lba, off + 16'd6,  name83[39:32]);
            vol_set(lba, off + 16'd7,  name83[31:24]);
            vol_set(lba, off + 16'd8,  name83[23:16]);
            vol_set(lba, off + 16'd9,  name83[15:8]);
            vol_set(lba, off + 16'd10, name83[7:0]);
            vol_set(lba, off + 16'd11, attr);              // DIR_Attr
            // 0x0C..0x13 保留字段留 0（调用前应先 vol_zero 本扇区）
            // ★★ 首簇号按【小端】写（与真卡/Windows 一致）：0x14=HI 低字节、0x15=HI 高字节、
            //   0x1A=LO 低字节、0x1B=LO 高字节。
            //   ⚠ 2026-10-06 修复（缺陷 24）：原来这里写成大端，与 `fat32_directory_scanner.v`
            //     的同款错误**互相抵消** ⇒ 全部 TB 绿、真卡全错。改这里是为了让 TB 具备
            //     发现该字段字节序问题的能力（改后若 RTL 再退回大端，本 TB 会立刻失败）。
            vol_set(lba, off + 16'd20, first_clus[23:16]); // FstClusHI 低字节
            vol_set(lba, off + 16'd21, first_clus[31:24]); // FstClusHI 高字节
            vol_set(lba, off + 16'd26, first_clus[7:0]);   // FstClusLO 低字节
            vol_set(lba, off + 16'd27, first_clus[15:8]);  // FstClusLO 高字节
            vol_set(lba, off + 16'd28, file_size[7:0]);    // FileSize 小端
            vol_set(lba, off + 16'd29, file_size[15:8]);
            vol_set(lba, off + 16'd30, file_size[23:16]);
            vol_set(lba, off + 16'd31, file_size[31:24]);
        end
    endtask

    // 把一个扇区（512 Byte = 16 条目录项）全填成同一条内容并清零其余字段。
    // 用途：构造"跨簇 / 判环"场景——目录里必须一条 0x00 都不能出现，
    //       否则 fat32_directory_scanner 会正常提前收工，走不到簇链那一支。
    task mk_dir_fill;
        input [31:0] lba;
        input [87:0] name83;
        input [7:0]  attr;
        input [31:0] first_clus;
        input [31:0] file_size;
        integer e;
        begin
            vol_zero(lba);
            for (e = 0; e < 16; e = e + 1)
                mk_dir_entry(lba, e*32, name83, attr, first_clus, file_size);
        end
    endtask

    // CRC16-CCITT (XMODEM)：与 sd_sector_reader 内的实现完全一致，算在 rd_buf 上
    function [15:0] crc16_of_rdbuf;
        input [15:0] len;
        integer    k;
        reg [15:0] c;
        begin
            c = 16'h0;
            for (k = 0; k < len; k = k + 1) begin
                c = c ^ {rd_buf[k], 8'h00};
                for (j = 0; j < 8; j = j + 1)
                    c = c[15] ? ((c << 1) ^ 16'h1021) : (c << 1);
            end
            crc16_of_rdbuf = c;
        end
    endfunction

    // ------------------------------------------------------------------------
    // 状态
    // ------------------------------------------------------------------------
    reg  [7:0]  tx_sh;         // 发送移位寄存器，MISO = tx_sh[7]
    reg  [7:0]  rx_sh;         // 接收移位寄存器
    reg  [3:0]  bitc;          // 窗口内已处理的位数

    reg  [47:0] cmd_buf;       // 6 字节命令帧
    reg  [2:0]  cmd_cnt;       // 已收命令字节数
    reg  [2:0]  cmd0_seen;     // ★ 已收到几次 CMD0（缺陷 28 场景用）
    reg  [5:0]  cur_cmd;       // 当前命令索引
    reg  [31:0] cur_arg;
    // 卷内相对 LBA（= cur_arg - VOL_BASE）。用 blocking 赋值的 reg 而非 wire：
    // 若用 continuous-assign 的 wire，在同一条 always 里刚 `cur_arg = ...` 之后
    // 立刻读它会读到【旧值】（连续赋值的更新不在同一时刻立即生效），
    // 导致 CMD17 选择卷/默认图案出错。用 blocking reg 才能"写完立刻读对"。
    reg  [31:0] cur_rel;
    reg         in_resp;       // 1 = 正在发响应
    reg         skip_byte;     // 1 = 跳过下一个字节（CS 拉低后的哑字节 / 命令间哑字节）
    reg  [15:0] rp;            // 响应位置
    reg  [15:0] rlen;          // 响应总长
    reg  [15:0] crc_val;

    assign miso = tx_sh[7];

    // ------------------------------------------------------------------------
    // 响应字节生成：按 (命令, 位置) 查表
    // ------------------------------------------------------------------------
    task do_resp_byte;
        output [7:0] b;
        begin
            b    = 8'hFF;
            rlen = 16'd1;

            if (i_dead) begin
                // 拔卡/坏卡：MISO 恒高，任何命令都得不到 bit7=0 的响应
                b = 8'hFF;
            end else begin
            case (cur_cmd)
                `SD_CMD0: begin
                    rlen = 16'd1;
                    // ★ 2026-10-06：前 CMD0_BAD_TRIES 次故意回 `0x02`（bit1 erase reset、
                    //   bit0=0 即**非 idle**）——模拟"卡被上次复位打断、残留一个数据字节
                    //   被主机当成 R1"的真实板级现象（板上抓到 `R1=02 SQ=0`）。
                    //   RTL 的处置是"重走 CS 高前导 + CMD0"重新同步（缺陷 28）。
                    if (rp == 16'd0)
                        b = (cmd0_seen <= CMD0_BAD_TRIES) ? 8'h02 : CMD0_R1;
                end
                `SD_CMD8: begin
                    rlen = 16'd5;
                    case (rp)
                        // v1.x 卡不认 CMD8：R1 = 0x05（bit0 idle + bit2 illegal command）
                        16'd0: b = CMD8_ILLEGAL ? 8'h05 : 8'h01;
                        16'd1: b = 8'h00;
                        16'd2: b = 8'h00;
                        16'd3: b = 8'h01;
                        16'd4: b = CMD8_ILLEGAL ? 8'hFF : 8'hAA;
                        default: b = 8'hFF;
                    endcase
                end
                `SD_CMD55: begin
                    rlen = 16'd1;
                    if (rp == 16'd0) b = 8'h00;
                end
                `SD_ACMD41: begin
                    rlen = 16'd1;
                    // 慢卡：前 SLOW_INIT_POLLS 次仍回 idle 态（0x01），之后才 ready（0x00）
                    if (rp == 16'd0)
                        b = (o_acmd41_cnt <= SLOW_INIT_POLLS) ? 8'h01 : 8'h00;
                end
                `SD_CMD58: begin
                    rlen = 16'd5;
                    case (rp)
                        16'd0: b = 8'h00;              // R1
                        16'd1: b = OCR_VALUE[31:24];
                        16'd2: b = OCR_VALUE[23:16];
                        16'd3: b = OCR_VALUE[15:8];
                        16'd4: b = OCR_VALUE[7:0];
                        default: b = 8'hFF;
                    endcase
                end
                `SD_CMD17: begin
                    rlen = 16'd516;                    // 1 R1 + 1 令牌 + 512 数据 + 2 CRC
                    if (rp == 16'd0)            b = 8'h00;
                    else if (rp == 16'd1)       b = `SD_TOKEN_DATA_START;
                    else if (rp <= 16'd513)     b = rd_buf[rp - 16'd2];
                    else if (rp == 16'd514)     b = crc_val[15:8];
                    else                        b = crc_val[7:0];
                end
                default: begin
                    rlen = 16'd1;
                    b    = 8'hFF;
                end
            endcase
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // SCLK 边沿驱动（行为模型，blocking 赋值）
    // ------------------------------------------------------------------------
    always @(sclk) begin
        if (cs_n) begin
            // ---- CS 高：复位所有状态，等下一次片选 ----
            bitc      = 4'd0;
            rx_sh     = 8'hFF;
            tx_sh     = 8'hFF;
            cmd_cnt   = 3'd0;
            cmd_buf   = 48'h0;
            in_resp   = 1'b0;
            skip_byte = 1'b1;      // CS 拉低后第一个字节是哑字节，跳过
            rp        = 16'd0;
            rlen      = 16'd0;
            o_cmd_valid  = 1'b0;
            o_acmd41_cnt = 8'd0;   // 本次片选周期内的 ACMD41 计数
        end else if (sclk == 1'b1) begin
            // ---- 上升沿：主机在本沿采样 MISO，同时我们采样 MOSI ----
            rx_sh = {rx_sh[6:0], mosi};
            bitc  = bitc + 4'd1;
        end else begin
            // ---- 下降沿：更新 MISO（保证下一个上升沿前稳定）----
            if (bitc == 4'd8) begin
                // 本窗口 8 位收完，rx_sh 已是完整字节
                bitc        = 4'd0;
                o_cmd_valid = 1'b0;

                if (skip_byte) begin
                    // 哑字节：忽略，回 0xFF
                    skip_byte = 1'b0;
                    tx_sh     = 8'hFF;
                end else if (!in_resp) begin
                    // ---- 收集命令字节（6 字节）----
                    cmd_buf = {cmd_buf[39:0], rx_sh};
                    cmd_cnt = cmd_cnt + 3'd1;
                    if (cmd_cnt == 3'd6) begin
                        // 6 字节收齐才解码：第 1 字节低 6 位 = 命令索引，
                        // 第 2~5 字节 = 32bit 参数（MSB 先收），第 6 字节 = CRC
                        cur_cmd     = cmd_buf[45:40];
                        cur_arg     = cmd_buf[39:8];
                        cur_rel     = cur_arg - VOL_BASE;   // blocking：写完立刻可读
                        // ★ 2026-10-06（缺陷 28 用）：数 CMD0 次数，供"前 N 次返回残留字节"场景
                        if (cur_cmd == `SD_CMD0) cmd0_seen = cmd0_seen + 3'd1;
                        if (cur_cmd == `SD_CMD17) begin
                            // SDHC 模式下 cur_arg 就是块号（卡的绝对 LBA）。
                            // 该 LBA 落在卷内(>= VOL_BASE 且相对偏移 < 64)且被显式写过
                            //   -> 用卷内容 vol[]（卷内相对索引，(cur_arg - VOL_BASE)）；
                            // 否则 -> 用默认图案 sector[]（兼容无分区表的老 TB；VOL_BASE=0
                            //   时本式与原式逐项等价，既有 TB 行为不变）。
                            for (kk = 0; kk < 512; kk = kk + 1)
                                rd_buf[kk] = ((cur_arg >= VOL_BASE) &&
                                              (cur_rel < VOL_SECTORS) &&
                                              vol_used[cur_rel])
                                             ? vol[cur_rel*32'd512 + kk]
                                             : sector[kk];
                            crc_val = crc16_of_rdbuf(16'd512);
                        end
                        in_resp     = 1'b1;
                        rp          = 16'd0;
                        o_cmd       = cur_cmd;
                        o_arg       = cur_arg;
                        o_cmd_cnt   = o_cmd_cnt + 8'd1;
                        o_cmd_valid = 1'b1;
                        if (cur_cmd == `SD_ACMD41) begin
                            o_acmd41_cnt = o_acmd41_cnt + 8'd1;
                            o_acmd41_arg = cur_arg;
                        end
                        // 为下一个窗口准备第一个响应字节
                        do_resp_byte(tx_sh);
                        rp = rp + 16'd1;
                    end else begin
                        tx_sh = 8'hFF;
                    end
                end else begin
                    // ---- 发响应 ----
                    if (rp >= rlen) begin
                        // 响应发完，回到收命令；命令之间主机会再发一个哑字节
                        in_resp   = 1'b0;
                        cmd_cnt   = 3'd0;
                        cmd_buf   = 48'h0;
                        rp        = 16'd0;
                        skip_byte = 1'b1;
                        tx_sh     = 8'hFF;
                    end else begin
                        do_resp_byte(tx_sh);
                        rp = rp + 16'd1;
                    end
                end
            end else begin
                // 窗口内移位输出
                tx_sh = {tx_sh[6:0], 1'b1};
            end
        end
    end

    initial begin
        cmd_cnt     = 3'd0;
        cmd0_seen   = 3'd0;
        cmd_buf     = 48'h0;
        in_resp     = 1'b0;
        skip_byte   = 1'b1;
        rp          = 16'd0;
        rlen        = 16'd0;
        bitc        = 4'd0;
        rx_sh       = 8'hFF;
        tx_sh       = 8'hFF;
        cur_cmd     = 6'h0;
        cur_arg     = 32'h0;
        cur_rel     = 32'h0;
        crc_val     = 16'h0;
        o_cmd       = 6'h0;
        o_arg       = 32'h0;
        o_acmd41_arg= 32'h0;
        o_cmd_cnt   = 8'h0;
        o_acmd41_cnt= 8'h0;
        o_cmd_valid = 1'b0;
    end

endmodule