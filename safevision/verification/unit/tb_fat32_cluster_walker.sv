// ============================================================================
// tb_fat32_cluster_walker.sv — 阶段 7：FAT32 簇链跟踪
// ----------------------------------------------------------------------------
// 被测：rtl/storage/fat32_cluster_walker.v
//
// 依据：手册 7.6「FAT32 要回答的是：一个文件占用了哪些簇、按什么顺序串起来」
//       「fat32_cluster_walker.v — FAT 簇链、
//         EOF、环/坏簇/越界检测」、docs/interface_spec.md §6.2（err_detail）
//
// ★ 为什么必须单独测这个模块：
//   它此前只被"随编译"（没有 TB 直接驱动），也就是说**判 EOC / 判越界 /
//   判环这三条收尾分支从来没有被仿真跑过**。这三条里的任意一条写错，表现都是
//   "读文件读到一半停不下来"或"把坏簇当成链尾静默收尾"，而且上板才暴露。
//
// ★ 本 TB 用伪 FAT 扇区（TB 侧数组）当卡，直接驱动 walker：
//   - 只做字节级服务，不经过 spi_master/sd_sector_reader，故障可精确注入
//     （CRC 错、读请求无响应）——这在整链联调 TB 里没法做。
//   - FAT 入口寻址是 walker 最容易错的地方，本 TB 专门覆盖
//     "簇号 >= 128 时入口跨到下一个 FAT 扇区"这一情形（簇 130/131/132）。
//
// 测试卷：
//   A 正常跳簇：2->3->4，done 单拍、busy 时序、hop_cnt 计数
//   B EOC 判定：0xFFFFFFFF（含保留位）/ 0x0FFFFFF8（边界）判链尾；
//     0x0FFFFFF7（边界外一个）**不是** EOC，而是越界簇 -> DET_DIR_OOB
//   C 越界：下一簇 < 2；下一簇 > total_clus+1
//   D 跨扇区寻址：簇 130 的入口落在 FAT 的第二个扇区（LBA 101 偏移 8）
//   E 判环：10->11->12->10 循环，跳簇数超过 total_clus -> DET_FS_LOOP
//   F 错误透传：sd_crc16_err/sd_err_* 原样上抛
//   G 读请求超时：sd_rd_ready 一直不给 -> ERR_SD_IO / DET_SD_TOKEN_TO
//   H 全局监视：done 必须始终是单拍脉冲（不许连续两拍为高）
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_fat32_cluster_walker;

    // ---- 冻结的伪 FAT 基准 ----
    localparam [31:0] FAT_LBA0   = 32'd100;   // FAT1 第一个扇区
    localparam [31:0] FAT_LBA1   = 32'd101;   // 簇号 >= 128 时入口所在扇区

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;                     // 100 MHz

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    // ------------------------------------------------------------------------
    // DUT 互连
    // ------------------------------------------------------------------------
    reg         rst_walk;
    reg         start;
    reg  [31:0] cur_clus;
    reg  [31:0] fat_start_lba;
    reg  [31:0] total_clus;

    wire        busy;
    wire        done;
    wire [31:0] next_clus;
    wire        eoc;
    wire        error;
    wire [7:0]  err_code;
    wire [7:0]  err_detail;
    wire [31:0] hop_cnt;
    wire [3:0]  dbg_state;

    wire [31:0] sd_rd_addr;
    wire [15:0] sd_rd_len;
    wire        sd_rd_en;
    wire        sd_data_ready;

    reg  [31:0] sd_rd_ready;
    reg  [7:0]  sd_data;
    reg         sd_data_valid;
    reg         sd_data_last;
    reg         sd_rd_done;
    reg         sd_timeout_err;
    reg         sd_crc16_err;
    reg  [7:0]  sd_err_code;
    reg  [7:0]  sd_err_detail;

    fat32_cluster_walker u_walk (
        .clk(clk), .rst_n(rst_n),
        .rst_walk(rst_walk), .start(start), .cur_clus(cur_clus),
        .busy(busy), .done(done), .next_clus(next_clus),
        .eoc(eoc), .error(error), .err_code(err_code), .err_detail(err_detail),
        .hop_cnt(hop_cnt), .dbg_state(dbg_state),
        .fat_start_lba(fat_start_lba), .total_clus(total_clus),
        .sd_rd_addr(sd_rd_addr), .sd_rd_len(sd_rd_len), .sd_rd_en(sd_rd_en),
        .sd_rd_ready(sd_rd_ready),
        .sd_data(sd_data), .sd_data_valid(sd_data_valid),
        .sd_data_ready(sd_data_ready), .sd_data_last(sd_data_last),
        .sd_rd_done(sd_rd_done),
        .sd_timeout_err(sd_timeout_err), .sd_crc16_err(sd_crc16_err),
        .sd_err_code(sd_err_code), .sd_err_detail(sd_err_detail)
    );

    // ------------------------------------------------------------------------
    // 伪 FAT：字节下标 = 簇号*4（小端）。
    //   [0..511]   -> LBA 100（簇 0..127 的入口）
    //   [512..1023]-> LBA 101（簇 128..255 的入口）
    // ★ 特意按字节摆放，不走 32bit 数组：这样"入口是小端"这件事不会被
    //   TB 侧的主机字节序掩盖掉。
    // ------------------------------------------------------------------------
    reg [7:0] fat [0:1023];

    task set_fat;
        input integer clus;
        input [31:0]  val;
        begin
            fat[clus*4 + 0] = val[7:0];       // 最低地址 = bit[7:0]（小端）
            fat[clus*4 + 1] = val[15:8];
            fat[clus*4 + 2] = val[23:16];
            fat[clus*4 + 3] = val[31:24];
        end
    endtask

    // ------------------------------------------------------------------------
    // 伪卡：按 lba_seen 把一个扇区（512 Byte）流给 DUT
    // ------------------------------------------------------------------------
    integer   n;
    reg [31:0] lba_seen;

    task serve_ok;
        begin
            while (!sd_rd_en) @(negedge clk);
            lba_seen = sd_rd_addr;
            for (n = 0; n < 512; n = n + 1) begin
                sd_data       = (lba_seen == FAT_LBA0) ? fat[n] : fat[512 + n];
                sd_data_valid = 1'b1;
                sd_data_last  = (n == 511);
                @(negedge clk);
            end
            sd_data_valid = 1'b0;
            sd_data_last  = 1'b0;
        end
    endtask

    // CRC 错：不发数据，直接把 sd_sector_reader 会报的错码递上去
    task serve_crc_err;
        begin
            while (!sd_rd_en) @(negedge clk);
            lba_seen      = sd_rd_addr;
            sd_err_code   = `ERR_SD_IO;
            sd_err_detail = `DET_SD_DATA_CRC;
            sd_crc16_err  = 1'b1;
            @(negedge clk);
            sd_crc16_err  = 1'b0;
            sd_err_code   = `ERR_NONE;
            sd_err_detail = `DET_NONE;
        end
    endtask

    task pulse_rst_walk;
        begin
            @(negedge clk); rst_walk = 1'b1;
            @(negedge clk); rst_walk = 1'b0;
        end
    endtask

    // mode: 0 = 正常服务, 1 = CRC 错, 2 = 不响应（让 walker 自己超时）
    task walk_and_wait;
        input [31:0] clus;
        input [1:0]  mode;
        begin
            @(negedge clk);
            cur_clus = clus;
            start    = 1'b1;
            @(negedge clk);
            start    = 1'b0;
            case (mode)
            2'd0:    serve_ok;
            2'd1:    serve_crc_err;
            default: ;                       // 2'd2：什么都不给
            endcase
            wait (done == 1'b1);             // 结果与 done 同拍有效
            @(negedge clk);                  // done 脉冲这一拍：可读结果
            @(negedge clk);                  // 再等一拍：busy / dbg_state 才归位
        end
    endtask

    // ------------------------------------------------------------------------
    // 全局监视：done 必须是单拍脉冲
    // ------------------------------------------------------------------------
    reg     done_q = 1'b0;
    integer done_cycles = 0;
    reg     done_two_in_a_row = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_q <= 1'b0; done_cycles <= 0; done_two_in_a_row <= 1'b0;
        end else begin
            if (done) begin
                done_cycles <= done_cycles + 1;
                if (done_q) done_two_in_a_row <= 1'b1;
            end
            done_q <= done;
        end
    end

    // ------------------------------------------------------------------------
    // 测试流程
    // ------------------------------------------------------------------------
    integer i;

    initial begin
        // ---- 初始化 ----
        for (i = 0; i < 1024; i = i + 1) fat[i] = 8'h00;

        set_fat(2,  32'd3);            // 2 -> 3
        set_fat(3,  32'd4);            // 3 -> 4
        set_fat(4,  32'hFFFF_FFFF);    // 4 -> EOC（高 4 位是保留位，必须被掩掉）
        set_fat(5,  32'd1);            // 5 -> 1（< 2，非法）
        set_fat(6,  32'hFFFF_FFF8);    // 6 -> 0x0FFFFFF8（EOC 边界）
        set_fat(7,  32'hFFFF_FFF7);    // 7 -> 0x0FFFFFF7（边界外一个，不是 EOC）
        set_fat(8,  32'd24);           // 8 -> 24（total_clus=20 时越界）
        set_fat(10, 32'd11);           // 10 -> 11 -> 12 -> 10 成环
        set_fat(11, 32'd12);
        set_fat(12, 32'd10);
        set_fat(130, 32'd131);         // 跨扇区：入口在 LBA 101 偏移 8
        set_fat(131, 32'd132);
        set_fat(132, 32'hFFFF_FFFF);   // 132 -> EOC

        rst_walk = 1'b0; start = 1'b0; cur_clus = 32'd0;
        fat_start_lba = FAT_LBA0; total_clus = 32'd200;
        sd_rd_ready = 32'hFFFF_FFFF;
        sd_data = 8'h00; sd_data_valid = 1'b0; sd_data_last = 1'b0;
        sd_rd_done = 1'b0; sd_timeout_err = 1'b0; sd_crc16_err = 1'b0;
        sd_err_code = `ERR_NONE; sd_err_detail = `DET_NONE;
        lba_seen = 32'd0;

        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // ==================================================================
        // A 正常跳簇
        // ==================================================================
        $display("==== A 正常跳簇 ====");
        walk_and_wait(32'd2, 2'd0);
        check(next_clus == 32'd3,           "WALK: 2 -> 3 正常跳簇");
        check(eoc == 1'b0 && error == 1'b0, "WALK: 正常跳簇时 eoc/error 均为 0");
        check(lba_seen == FAT_LBA0,         "WALK: 簇 2 的 FAT 入口在 LBA 100（(2*4)/512=0）");
        check(dbg_state == 4'd0,            "WALK: done 后状态机回到 IDLE");
        check(busy == 1'b0,                 "WALK: done 后 busy 归 0");

        // ==================================================================
        // B EOC 判定
        // ==================================================================
        $display("==== B EOC 判定 ====");
        walk_and_wait(32'd3, 2'd0);
        check(next_clus == 32'd4, "WALK: 3 -> 4");

        walk_and_wait(32'd4, 2'd0);
        check(eoc == 1'b1,                  "WALK: 0xFFFFFFFF 判为链尾 EOC");
        check(next_clus == 32'h0FFF_FFFF,   "WALK: EOC 时 next_clus 已掩掉高 4 位保留位");
        check(error == 1'b0,                "WALK: EOC 是正常收尾，不算错误");
        check(hop_cnt == 32'd2,             "WALK: hop_cnt 只统计有效跳簇（此时为 2）");

        walk_and_wait(32'd6, 2'd0);
        check(eoc == 1'b1, "WALK: 0x0FFFFFF8 判为链尾（EOC 边界）");

        // ★ 边界外一个：0x0FFFFFF7 不是 EOC，而是"越界簇"。
        //   若这里写成 >= 0x0FFFFFF7，坏簇会被静默当成链尾，永远查不出来。
        walk_and_wait(32'd7, 2'd0);
        check(eoc == 1'b0, "WALK: 0x0FFFFFF7 不判链尾（EOC 边界只认 0x0FFFFFF8）");
        check(error == 1'b1 && err_code == `ERR_MEDIA_INVALID && err_detail == `DET_DIR_OOB,
              "WALK: 0x0FFFFFF7 判为越界簇 -> ERR_MEDIA_INVALID/DET_DIR_OOB");

        // ==================================================================
        // C 越界
        // ==================================================================
        $display("==== C 越界 ====");
        total_clus = 32'd20;
        walk_and_wait(32'd5, 2'd0);
        check(error == 1'b1 && err_detail == `DET_DIR_OOB,
              "WALK: 下一簇 < 2 判为非法 -> DET_DIR_OOB");
        walk_and_wait(32'd8, 2'd0);
        check(error == 1'b1 && err_detail == `DET_DIR_OOB,
              "WALK: 下一簇 > total_clus+1 判为越界 -> DET_DIR_OOB");

        // ==================================================================
        // D 跨扇区寻址（簇号 >= 128 时入口落在 FAT 的第二个扇区）
        // ==================================================================
        $display("==== D 跨扇区寻址 ====");
        total_clus = 32'd200;
        pulse_rst_walk;
        check(hop_cnt == 32'd0, "WALK: rst_walk 清零跳簇计数");

        walk_and_wait(32'd130, 2'd0);
        check(lba_seen == FAT_LBA1, "WALK: 簇 130 的 FAT 入口落在 LBA 101（512*1 = (130*4)/512 扇区）");
        check(next_clus == 32'd131, "WALK: 跨扇区读到的入口正确（130 -> 131）");

        walk_and_wait(32'd131, 2'd0);
        check(next_clus == 32'd132, "WALK: 131 -> 132");
        check(hop_cnt == 32'd2,     "WALK: rst_walk 后 hop_cnt 从 0 重新累计");

        walk_and_wait(32'd132, 2'd0);
        check(eoc == 1'b1, "WALK: 132 -> EOC");

        // ==================================================================
        // E 判环
        // ==================================================================
        $display("==== E 判环 ====");
        total_clus = 32'd20;
        pulse_rst_walk;
        for (i = 0; i < 20; i = i + 1)
            walk_and_wait(32'd10 + (i % 3), 2'd0);      // 10,11,12,10,...
        check(error == 1'b0,        "WALK: 成环链前 20 跳都在 total_clus 之内，不报错");
        check(hop_cnt == 32'd20,    "WALK: 前 20 跳 hop_cnt 累计为 20");

        walk_and_wait(32'd10 + (20 % 3), 2'd0);          // 第 21 跳
        check(error == 1'b1 && err_code == `ERR_MEDIA_INVALID && err_detail == `DET_FS_LOOP,
              "WALK: 跳簇数超过 total_clus 判为环 -> ERR_MEDIA_INVALID/DET_FS_LOOP");
        check(hop_cnt == 32'd20,    "WALK: 判环那一拍不再推进 hop_cnt");

        // ==================================================================
        // F 错误透传（sd_sector_reader 报的 CRC 错必须原样上抛）
        // ==================================================================
        $display("==== F 错误透传 ====");
        walk_and_wait(32'd2, 2'd1);
        check(error == 1'b1,                           "WALK: sd_crc16_err 触发 error");
        check(err_code == `ERR_SD_IO,                  "WALK: SD 侧主码原样透传（ERR_SD_IO）");
        check(err_detail == `DET_SD_DATA_CRC,          "WALK: SD 侧细分码原样透传（DET_SD_DATA_CRC）");

        // ==================================================================
        // G 读请求超时（卡一直不 ready）
        // ==================================================================
        $display("==== G 读请求超时 ====");
        sd_rd_ready = 32'd0;
        walk_and_wait(32'd2, 2'd2);
        sd_rd_ready = 32'hFFFF_FFFF;
        check(error == 1'b1,                           "WALK: 卡一直不 ready 时读请求超时");
        check(err_code == `ERR_SD_IO && err_detail == `DET_SD_TOKEN_TO,
              "WALK: 读超时上报 ERR_SD_IO/DET_SD_TOKEN_TO");
        check(busy == 1'b0,                            "WALK: 超时后 busy 归 0");

        // ==================================================================
        // H 全局监视
        // ==================================================================
        $display("==== H 全局监视 ====");
        check(done_cycles == 33,        "MON: done 总拍数 == 33（与 walk 次数一致）");
        check(done_two_in_a_row == 1'b0,"MON: done 全程都是单拍脉冲（无连续两拍）");

        // ---- 汇总 ----
        $display("========================================");
        $display("  PASS = %0d   FAIL = %0d", total - errors, errors);
        $display("========================================");
        if (errors == 0) $display("[RESULT] ALL PASS");
        else             $display("[RESULT] %0d FAILED", errors);
        $finish;
    end

    // 兜底看门狗（含 2 ms 的读超时用例，留足余量）
    initial begin
        #30_000_000;
        $display("[FAIL] tb_fat32_cluster_walker watchdog timeout");
        $finish;
    end

endmodule