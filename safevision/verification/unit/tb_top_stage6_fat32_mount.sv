// ============================================================================
// tb_top_stage6_fat32_mount.sv — 板级 bring-up 顶层验证（SafeVision B 链 · 阶段 6-7）
// ----------------------------------------------------------------------------
// 被测：safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage6_fat32_mount.v
//
// 为什么要有这个 TB：顶层错在例化 / 握手 / 总线复用 /【卷基址加法】/【报告字节
// 拼接】上，这些错误单元 TB 一个都抓不到（单元 TB 各自直连 DUT，不经过顶层的
// mux、加法器与 ASCII 报告引擎）。特别是 §3.2.1 的"卷基址只加一次"——这里用
// 【分区卡】模型把它钉死：假卡 VOL_BASE=16，分区 0 起点 = 卡 LBA 16。
//
// 模拟一张【分区卡】：
//   - 卡的 0 号扇区 = MBR（写在卡模型默认图案 sector[] 里；卡 LBA 0 落在卷外，
//     模型自动回落到 sector[]），分区 0 起始 LBA = 16。
//   - 卷（其 0 号扇区 = 卡 LBA 16）用一份微型 FAT32：
//       BytsPerSec=512, SecPerClus=1, RsvdSecCnt=32, NumFATs=2, FATSz32=1, RootClus=2
//         fat_start_lba  = 32                      （卷内相对）
//         data_start_lba = 32 + 2*1 = 34
//         root_dir_lba   = 34 + (2-2)*1 = 34
//         TotSec32 = 48 -> total_clus = (48-34)/1 = 14
//       卷内 LBA 0/32/33/34 都是 volume-relative；对应的【卡 LBA】=
//         +VOL_BASE(16) -> 16 / 48 / 49 / 50，全部 < 64，模型能覆盖。
//   - 根目录（卷内 LBA 34，簇 2 只 1 个扇区）：3 条 SV000x.BMP（attr=0x20，
//     size=0x000E1036），槽 3 是 0xE5；FAT[2]=EOC 让簇链正常收尾。
//
// 验证内容（分两个场景，串行跑，同一套 DUT + 卡模型 + UART 接收模型）：
//
//   场景 A（健康卡）—— 覆盖 Task 1（报告字节数 / 无前导 0x00 / 每行 CRLF）
//     与 Task 2 的连读成功路径：
//     T1  mbr_parser 读的是【卡的 0 号扇区】（CMD17 arg == 0）
//     T2  ★ FAT32 层的 0 号扇区读落在卡 LBA == VOL_BASE（卷基址只加一次）
//     T3  FAT 扇区读 = VOL_BASE + 32
//     T4  根目录扇区读 = VOL_BASE + 34
//     T5  顶层到达成功态（led=8）
//     T6  ★ UART 报告字节数 = 183 + 3*52 + 27 + 6 = 372（旧版多一个前导 0x00 => 373）
//     T7  报告首行
//     T8  ★ 报告首字节就是 'S'（没有前导 0x00）
//     T9  ★ 报告每个 0x0A 的前一字节都是 0x0D（行尾 CRLF，防 TD 吃掉 \r 转义）
//     T10..T15 报告各行内容（BASE / BPB / 目录项名+属性+大小 / ENT）
//     T16 ★ 连读汇总行 RPT=0064 OK=0064 BAD=0000
//     T17 末行 DONE
//     T18 ★ 连读内部计数 rep_ok=100 / rep_bad=0（报告之外再钉一次）
//
//   场景 B（挂载+扫目录成功，一进连读就把卡设成坏卡）—— 覆盖 Task 2 失败路径：
//     T19 ★ 报告字节数 = 183 + 3*52 + 27 + 8 = 374
//     T20 ★ 连读汇总行 RPT=0064 OK=0000 BAD=0064
//     T21 ★ 末行 ERR=02（对外主码 = 扇区读超时/CRC 错）
//     T22 ★ LED 显示错误主码低 4 位 = 2（不是成功态 8）
//     T23 ★ 顶层停在 ST_ERR（有限时间内进错误态、不挂死；看门狗没有触发）
//     T24 ★ 场景 B 报告同样每行以 0D 0A 结尾
//
// ★ 只为加速仿真把 POWERUP_CYC 从板上 50ms 缩到 4us；UART 仍是真实 115200 @50MHz
//   连读默认 RPT_N=100（与上板一致）。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_top_stage6_fat32_mount;

    localparam integer CLK_HZ   = 50_000_000;
    localparam integer BAUD     = 115200;
    localparam integer DIV      = CLK_HZ / BAUD;   // 434
    localparam integer BIT_NS   = DIV * 20;        // 8680 ns / bit
    localparam integer HALF_NS  = BIT_NS / 2;
    localparam integer MAXB     = 512;             // 报告最多缓存字节数
    localparam [31:0]  VOL_BASE = 32'd16;          // 分区 0 起始卡 LBA

    // 卷内相对 LBA -> 卡 LBA 的映射（= 各请求方相对地址 + 卷基址）
    localparam [31:0]  EXP_MBR_LBA  = 32'd0;                 // 卡 0 号扇区 = MBR
    localparam [31:0]  EXP_DBR_LBA  = VOL_BASE + 32'd0;      // 卷 0 号 = DBR
    localparam [31:0]  EXP_FAT_LBA  = VOL_BASE + 32'd32;     // FAT1 扇区
    localparam [31:0]  EXP_ROOT_LBA = VOL_BASE + 32'd34;     // 根目录扇区

    // 报告各段字节数（必须与 RTL 逐字节一致）：
    //   HDR 183 = 21+42+25+51+34+10
    //   ENT  52 = 2+4+1+22+1+2+1+8+1+8+2
    //   RPT  27 = 4+4+4+4+5+4+2
    //   ERR   8 = 4+2+2   DONE 6 = 4+2
    localparam integer HDR_BYTES  = 183;
    localparam integer ENT_BYTES  = 52;
    localparam integer RPT_BYTES  = 27;
    localparam integer ERR_BYTES  = 8;
    localparam integer DONE_BYTES = 6;
    localparam integer N_ENT      = 3;
    localparam integer OFF_ENT0   = HDR_BYTES;                        // 183
    localparam integer OFF_RPT    = HDR_BYTES + N_ENT*ENT_BYTES;      // 339
    localparam integer OFF_TAIL   = OFF_RPT  + RPT_BYTES;             // 366
    localparam integer TOTAL_OK   = OFF_TAIL + DONE_BYTES;            // 372
    localparam integer TOTAL_BAD  = OFF_TAIL + ERR_BYTES;             // 374

    // ★ 报告结束行用【显式字节】拼，绝不用字符串转义 "DONE\r\n"：
    //   ModelSim vlog 10.7 与 TD 6.2 一样，都不把字符串里的 \r 当转义，
    //   "DONE\r\n" 会得到 0x44 4F 4E 45 72 0A（字母 r + LF）。旧版 RTL 与旧版
    //   TB 都用这个转义，所以两边"错得一样"、仿真反而对上了——正是这种
    //   "仿真自洽但两边都不是 CR" 的坑。RTL 现已改显式字节，TB 也用显式字节。
    localparam [47:0] DONE_CRLF = {"DONE", 8'h0D, 8'h0A};

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;                          // 20 ns -> 50 MHz

    integer errors;

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // DUT 引脚
    // ------------------------------------------------------------------------
    wire        sd_ncs, sd_dclk, sd_mosi, sd_miso, uart_txd;
    wire [3:0]  led;

    // ------------------------------------------------------------------------
    // 拔卡控制：场景 B 用。kill_card=1 后，一旦 DUT 进入连读阶段
    // （st >= 12：ST_RPT / ST_RPTREQ / ST_RPTWAIT）就把卡设成"坏卡"。
    // （触发用的 always 块放在 DUT 例化之后，避免对 dut 的前向层次引用）
    // ------------------------------------------------------------------------
    reg  kill_card  = 1'b0;
    reg  dead_latch = 1'b0;
    wire card_dead  = dead_latch;

    // ------------------------------------------------------------------------
    // SD 卡行为模型（带卷基址 VOL_BASE=16）
    // ------------------------------------------------------------------------
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;

    sd_spi_card_model #(
        .VOL_BASE (VOL_BASE)
    ) u_card (
        .sclk         (sd_dclk),
        .cs_n         (sd_ncs),
        .mosi         (sd_mosi),
        .miso         (sd_miso),
        .i_dead       (card_dead),
        .o_cmd        (o_cmd),
        .o_arg        (o_arg),
        .o_acmd41_arg (o_acmd41_arg),
        .o_cmd_cnt    (o_cmd_cnt),
        .o_acmd41_cnt (o_acmd41_cnt),
        .o_cmd_valid  (o_cmd_valid)
    );

    // ------------------------------------------------------------------------
    // DUT：板级 bring-up 顶层
    // ------------------------------------------------------------------------
    top_stage6_fat32_mount #(
        .CLK_FREQ    (CLK_HZ),
        .BAUD        (BAUD),
        .POWERUP_CYC (24'd200),
        .RPT_N       (16'd100)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .sd_ncs   (sd_ncs),
        .sd_dclk  (sd_dclk),
        .sd_mosi  (sd_mosi),
        .sd_miso  (sd_miso),
        .uart_txd (uart_txd),
        .led      (led)
    );

    // ------------------------------------------------------------------------
    // 进入连读阶段即把卡设坏（场景 B）；放在 DUT 例化之后
    // ------------------------------------------------------------------------
    always @(posedge clk)
        if (kill_card && (dut.st >= 4'd12)) dead_latch <= 1'b1;

    // ------------------------------------------------------------------------
    // CMD17 参数监视：记录是否读到过各关键【卡 LBA】
    // ------------------------------------------------------------------------
    reg seen_arg0  = 1'b0;      // 卡 0 号（MBR）
    reg seen_base  = 1'b0;      // 卡 LBA = VOL_BASE（DBR）
    reg seen_fat   = 1'b0;      // 卡 LBA = VOL_BASE+32
    reg seen_root  = 1'b0;      // 卡 LBA = VOL_BASE+34

    always @(posedge clk) begin
        if (o_cmd === 6'd17) begin
            if (o_arg === EXP_MBR_LBA)  seen_arg0 <= 1'b1;
            if (o_arg === EXP_DBR_LBA)  seen_base <= 1'b1;
            if (o_arg === EXP_FAT_LBA)  seen_fat  <= 1'b1;
            if (o_arg === EXP_ROOT_LBA) seen_root <= 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // UART 接收模型：8N1，LSB 先收，位中点采样（同 tb_top_stage5_sector_rd）
    // ------------------------------------------------------------------------
    task uart_rx_byte(output [7:0] b);
        integer k;
        begin
            @(negedge uart_txd);        // 起始位下降沿
            #(HALF_NS);                 // -> 起始位中点
            #(BIT_NS);                  // -> 数据位 0 中点
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = uart_txd;
                #(BIT_NS);              // 移到下一位中点
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // 报告缓存：字节 j 放在 rep_bits[8*(MAXB-1-j) -: 8]（首字节在最高位，
    // 便于用字符串常量直接与左对齐切片比较）
    // ------------------------------------------------------------------------
    reg [8*MAXB-1:0] rep_bits;
    reg [47:0]       sh6;          // 最近 6 个字节（判 DONE\r\n）
    reg [31:0]       w4;           // 最近 4 个字节（识别 "ERR="）
    reg              seen_err;     // 已收到 "ERR="
    integer          err_tail;     // "ERR=" 之后又收到几个字节
    integer          rn;           // 已收字节数

    // 报告的每个 0x0A 前一字节是否都是 0x0D（回归 Task 1 的"TD 吃掉 \r 转义"）
    function integer crlf_okf;
        input integer n;
        integer k;
        reg ok;
        begin
            ok = 1'b1;
            for (k = 1; k < n; k = k + 1) begin
                if (rep_bits[8*(MAXB-1-k) -: 8] == 8'h0A)
                    if (rep_bits[8*(MAXB-1-(k-1)) -: 8] != 8'h0D)
                        ok = 1'b0;
            end
            crlf_okf = ok;
        end
    endfunction

    // ------------------------------------------------------------------------
    // 建卷 / 建 MBR
    // ------------------------------------------------------------------------
    // 卡的 0 号扇区 = MBR（写进卡模型默认图案 sector[]；卡 LBA 0 在卷外会回落）
    task mbr_set_card0;
        integer q;
        begin
            for (q = 0; q < 512; q = q + 1) u_card.sector[q] = 8'h00;
            u_card.sector[450] = 8'h0C;      // 分区类型 FAT32 XINT13
            u_card.sector[454] = 8'h10;      // 起始 LBA = 16（小端）
            u_card.sector[455] = 8'h00;
            u_card.sector[456] = 8'h00;
            u_card.sector[457] = 8'h00;
            u_card.sector[458] = 8'h00;      // 扇区数 = 0x00010000（小端）
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;      // 签名
            u_card.sector[511] = 8'hAA;
        end
    endtask

    task mk_vol;
        integer q2;
        begin
            // DBR：卷内 LBA 0
            u_card.mk_fat32_dbr(16'd512, 8'd1, 16'd32, 8'd2, 32'd1, 32'd2, 32'd48, 1'b1);
            // FAT1（卷内 LBA 32）：FAT[2] = EOC（根目录只 1 个簇）
            u_card.vol_zero(32'd32);
            u_card.vol_set_le(32'd32, 16'd8, 32'h0FFF_FFFF, 3'd4);
            // FAT2（卷内 LBA 33）：本 TB 不查，清零即可
            u_card.vol_zero(32'd33);
            // 根目录（卷内 LBA 34，簇 2 只 1 扇区）：槽 0..2 = 3 条文件；
            // 槽 3..15 首字节置 0xE5（已删除）——这样目录里没有 0x00，扫描器
            // 必须把整扇区读完后去 FAT 查下一簇（EOC），从而【顺带验证 FAT 读
            // 也加了一次卷基址】，同时仍只抛出 3 条目录项。
            u_card.vol_zero(32'd34);
            u_card.mk_dir_entry(32'd34, 16'd0,  "SV0001  BMP", 8'h20, 32'd5, 32'h000E1036);
            u_card.mk_dir_entry(32'd34, 16'd32, "SV0002  BMP", 8'h20, 32'd6, 32'h000E1036);
            u_card.mk_dir_entry(32'd34, 16'd64, "SV0003  BMP", 8'h20, 32'd7, 32'h000E1036);
            for (q2 = 3; q2 < 16; q2 = q2 + 1)
                u_card.vol_set(32'd34, q2*32, 8'hE5);
        end
    endtask

    // 把收到的 rn 个字节按原样打印（供人工看一眼实际报告文本）
    task dump_report;
        input integer start;
        input integer cnt;
        integer k;
        begin
            for (k = start; k < cnt; k = k + 1)
                $write("%c", rep_bits[8*(MAXB-1-k) -: 8]);
        end
    endtask

    // ------------------------------------------------------------------------
    // 看门狗：最后一根稻草。两个场景合计约 105 ms 仿真时间（连读 100 次
    // 用掉约 33 ms，两份报告各约 32 ms），留足裕量；卡住也能退出。
    // ------------------------------------------------------------------------
    initial begin
        #300_000_000;
        $display("[FAIL] T-WD 顶层看门狗超时，只收到 %0d Byte", rn);
        $write("[TB] raw report: ");
        dump_report(0, rn);
        $display("");
        $display("[TB] st=%0d top_err=%02x rep_err=%0b led=%h has_mbr=%0b vol_base=%08x",
                 dut.st, dut.top_err, dut.rep_err, led, dut.mbr_has, dut.mbr_vol_base);
        $display("[TB] mount_done=%0b mount_error=%0b fs_err=%02x/%02x bps=%04x spc=%02x nfat=%02x",
                 dut.fs_mount_done, dut.fs_mount_error, dut.fs_err_code, dut.fs_err_detail,
                 dut.fs_bps, dut.fs_spc, dut.fs_nfat);
        $display("[TB] scan_done=%0b dir_bad=%0b dir_err=%02x/%02x ent_total=%0d",
                 dut.scan_done, dut.dir_bad, dut.dir_err_code, dut.dir_err_detail,
                 dut.ent_total);
        $display("[TB] rep_ok=%0d rep_bad=%0d rep_idx=%0d card_dead=%0b kill=%0b",
                 dut.rep_ok, dut.rep_bad, dut.rep_idx, card_dead, kill_card);
        $display("[TB] last_cmd=%0d last_arg=%0d seen0=%b seenB=%b seenF=%b seenR=%b",
                 u_card.o_cmd, u_card.o_arg, seen_arg0, seen_base, seen_fat, seen_root);
        $finish;
    end

    // ------------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------------
    reg [7:0] rb;
    initial begin
        errors    = 0;
        rn        = 0;
        sh6       = 48'h0;
        w4        = 32'h0;
        seen_err  = 1'b0;
        err_tail  = 0;
        rep_bits  = {8*MAXB{1'b0}};
        kill_card = 1'b0;
        dead_latch= 1'b0;

        rst_n = 1'b0;

        // 等卡模型的 initial 跑完（避免与它写 sector[] 的时序竞争）
        #500;
        mk_vol;
        mbr_set_card0;
        #100;
        rst_n = 1'b1;

        // ====================================================================
        // 场景 A：健康卡 —— 连读 100 次全过
        // ====================================================================
        begin : capA
            while (1) begin
                uart_rx_byte(rb);
                rep_bits[8*(MAXB-1-rn) -: 8] = rb;
                rn  = rn + 1;
                sh6 = (sh6 << 8) | rb;
                if (sh6 == DONE_CRLF)  disable capA;
                if (rn >= 400)         disable capA;   // 兜底，交给看门狗
            end
        end

        repeat (20) @(posedge clk);

        $display("---- scenario A: UART report begin ----");
        dump_report(0, rn);
        $display("");
        $display("---- scenario A: UART report end ----");

        // ---- 卷基址只加一次：FAT32 层的 0 号扇区必须落在卡 LBA = base ----
        check(seen_arg0, "T1 mbr_parser 读卡 0 号扇区(arg=0)");
        check(seen_base, "T2 FAT32 层 0 号扇区读落在卡 LBA = base(16)");
        check(seen_fat,  "T3 FAT 扇区读 = base + 32");
        check(seen_root, "T4 根目录扇区读 = base + 34");
        check(led === 4'h8, "T5 顶层到达成功态 led=8");
        check(rn == TOTAL_OK, "T6 UART 报告字节数 = 372(无前导 0x00)");

        // ---- 报告逐行内容 ----
        // 19 字符 = 152 bit（旧版这里写 8*20，正好把多余的那个前导 0x00 也框进来，
        // 所以旧断言"通过"其实是在确认那个 NUL —— 现在必须按真实长度比）
        check(rep_bits[8*(MAXB-1-0) -: 8*19] === "SAFEVISION B STAGE6",
              "T7 报告首行");
        check(rep_bits[8*(MAXB-1-0) -: 8] === "S",
              "T8 报告首字节 S（无前导 0x00）");
        check(crlf_okf(rn) != 0,
              "T9 每行行尾均为 0D 0A");
        check(rep_bits[8*(MAXB-1-21) -: 8*40] === "MBR=00000001 BASE=00000010 SECS=00010000",
              "T10 MBR/BASE/SECS 行");
        check(rep_bits[8*(MAXB-1-63) -: 8*23] === "BPS=0200 SPC=01 NFAT=02",
              "T11 BPB 字段行");
        check(rep_bits[8*(MAXB-1-88) -: 8*49] === "FATLBA=00000020 DATALBA=00000022 ROOTLBA=00000022",
              "T12 FAT/数据/根目录起始 LBA");
        check(rep_bits[8*(MAXB-1-139) -: 8*32] === "TOTSEC=00000030 TOTCLUS=0000000E",
              "T13 TOTSEC/TOTCLUS 行");
        check(rep_bits[8*(MAXB-1-173) -: 8*8] === "ENT=0003",
              "T14 目录项数 ENT=0003");
        check(rep_bits[8*(MAXB-1-OFF_ENT0) -: 8*50] === "E 0000 5356303030312020424D50 20 00000005 000E1036",
              "T15 目录项0 名/属性/首簇/大小");
        check(rep_bits[8*(MAXB-1-(OFF_ENT0+52)) -: 8*50] === "E 0001 5356303030322020424D50 20 00000006 000E1036",
              "T16 目录项1 名/属性/首簇/大小");
        check(rep_bits[8*(MAXB-1-(OFF_ENT0+104)) -: 8*50] === "E 0002 5356303030332020424D50 20 00000007 000E1036",
              "T17 目录项2 名/属性/首簇/大小");
        check(rep_bits[8*(MAXB-1-OFF_RPT) -: 8*25] === "RPT=0064 OK=0064 BAD=0000",
              "T18 连读汇总 RPT OK=total BAD=0");
        check(rep_bits[8*(MAXB-1-OFF_TAIL) -: 8*4] === "DONE",
              "T19 报告结束行 DONE");
        check((dut.rep_ok === 16'd100) && (dut.rep_bad === 16'd0),
              "T20 连读内部计数 rep_ok=100 rep_bad=0");

        // ====================================================================
        // 场景 B：一进连读阶段就拔卡 —— 必须有限时间内进错误态、不挂死
        // ====================================================================
        kill_card  = 1'b1;          // 下次进入连读阶段即把卡设坏
        dead_latch = 1'b0;
        rn        = 0;
        sh6       = 48'h0;
        w4        = 32'h0;
        seen_err  = 1'b0;
        err_tail  = 0;
        rep_bits  = {8*MAXB{1'b0}};

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // 收到 "ERR=" 之后再收 4 个字节（2 位 hex + CRLF）即认为报告结束
        begin : capB
            while (1) begin
                uart_rx_byte(rb);
                rep_bits[8*(MAXB-1-rn) -: 8] = rb;
                rn  = rn + 1;
                sh6 = (sh6 << 8) | rb;
                w4  = {w4[23:0], rb};
                if (w4 == "ERR=") begin
                    seen_err = 1'b1;
                    err_tail = 0;
                end else if (seen_err) begin
                    err_tail = err_tail + 1;
                end
                if (seen_err && (err_tail >= 4)) disable capB;
                if (rn >= 400)                   disable capB;   // 兜底
            end
        end

        repeat (20) @(posedge clk);

        $display("---- scenario B: UART report begin ----");
        dump_report(0, rn);
        $display("");
        $display("---- scenario B: UART report end ----");

        check(rn == TOTAL_BAD, "T21 B 报告字节数 = 374");
        check(rep_bits[8*(MAXB-1-OFF_RPT) -: 8*25] === "RPT=0064 OK=0000 BAD=0064",
              "T22 连读失败 RPT OK=0 BAD=100");
        check(rep_bits[8*(MAXB-1-OFF_TAIL) -: 8*6] === "ERR=02",
              "T23 连读失败末行 ERR=02");
        check(led === 4'h2, "T24 失败态 LED = 错误主码低 4 位 = 2");
        check(dut.st === 4'd11, "T25 顶层停在 ST_ERR（不挂死）");
        check(crlf_okf(rn) != 0, "T26 B 报告每行行尾均为 0D 0A");

        $display("============================================");
        if (errors == 0) $display(" 全部通过 (PASS)");
        else             $display(" 失败项：%0d (FAIL)", errors);
        $display("============================================\n");
        $finish;
    end

endmodule