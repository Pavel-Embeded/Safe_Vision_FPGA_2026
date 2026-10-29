


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_fat32_cluster_walker;


    localparam [31:0] FAT_LBA0   = 32'd100;
    localparam [31:0] FAT_LBA1   = 32'd101;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer total  = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin begin
            total = total + 1;
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
     end endtask


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


    reg [7:0] fat [0:1023];

    task set_fat;
        input integer clus;
        input [31:0]  val;
        begin begin
            fat[clus*4 + 0] = val[7:0];
            fat[clus*4 + 1] = val[15:8];
            fat[clus*4 + 2] = val[23:16];
            fat[clus*4 + 3] = val[31:24];
        end
     end endtask


    integer   n;
    reg [31:0] lba_seen;

    task serve_ok;
        begin begin
            while (!sd_rd_en) @(negedge clk);
            lba_seen = sd_rd_addr;
            for (n = 0; n < 512; n = n + 1) begin
                sd_data       = (lba_seen == FAT_LBA0)  ?  fat[n] : fat[512 + n];
                sd_data_valid = 1'b1;
                sd_data_last  = (n == 511);
                @(negedge clk);
            end
            sd_data_valid = 1'b0;
            sd_data_last  = 1'b0;
        end
     end endtask


    task serve_crc_err;
        begin begin
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
     end endtask

    task pulse_rst_walk;
        begin begin
            @(negedge clk); rst_walk = 1'b1;
            @(negedge clk); rst_walk = 1'b0;
        end
     end endtask


    task walk_and_wait;
        input [31:0] clus;
        input [1:0]  mode;
        begin begin
            @(negedge clk);
            cur_clus = clus;
            start    = 1'b1;
            @(negedge clk);
            start    = 1'b0;
            case (mode)
            2'd0:    serve_ok;
            2'd1:    serve_crc_err;
            default: ;
            endcase
            wait (done == 1'b1);
            @(negedge clk);
            @(negedge clk);
        end
     end endtask


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


    integer i;

    initial begin

        for (i = 0; i < 1024; i = i + 1) fat[i] = 8'h00;

        set_fat(2,  32'd3);
        set_fat(3,  32'd4);
        set_fat(4,  32'hFFFF_FFFF);
        set_fat(5,  32'd1);
        set_fat(6,  32'hFFFF_FFF8);
        set_fat(7,  32'hFFFF_FFF7);
        set_fat(8,  32'd24);
        set_fat(10, 32'd11);
        set_fat(11, 32'd12);
        set_fat(12, 32'd10);
        set_fat(130, 32'd131);
        set_fat(131, 32'd132);
        set_fat(132, 32'hFFFF_FFFF);

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


        $display("==== A 正常跳簇 ====");
        walk_and_wait(32'd2, 2'd0);
        check(next_clus == 32'd3,           "WALK: 2 -> 3 正常跳簇");
        check(eoc == 1'b0 && error == 1'b0, "WALK: 正常跳簇时 eoc/error 均为 0");
        check(lba_seen == FAT_LBA0,         "WALK: 簇 2 的 FAT 入口在 LBA 100（(2*4)/512=0）");
        check(dbg_state == 4'd0,            "WALK: done 后状态机回到 IDLE");
        check(busy == 1'b0,                 "WALK: done 后 busy 归 0");


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


        walk_and_wait(32'd7, 2'd0);
        check(eoc == 1'b0, "WALK: 0x0FFFFFF7 不判链尾（EOC 边界只认 0x0FFFFFF8）");
        check(error == 1'b1 && err_code == `ERR_MEDIA_INVALID && err_detail == `DET_DIR_OOB,
              "WALK: 0x0FFFFFF7 判为越界簇 -> ERR_MEDIA_INVALID/DET_DIR_OOB");


        $display("==== C 越界 ====");
        total_clus = 32'd20;
        walk_and_wait(32'd5, 2'd0);
        check(error == 1'b1 && err_detail == `DET_DIR_OOB,
              "WALK: 下一簇 < 2 判为非法 -> DET_DIR_OOB");
        walk_and_wait(32'd8, 2'd0);
        check(error == 1'b1 && err_detail == `DET_DIR_OOB,
              "WALK: 下一簇 > total_clus+1 判为越界 -> DET_DIR_OOB");


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


        $display("==== E 判环 ====");
        total_clus = 32'd20;
        pulse_rst_walk;
        for (i = 0; i < 20; i = i + 1)
            walk_and_wait(32'd10 + (i % 3), 2'd0);
        check(error == 1'b0,        "WALK: 成环链前 20 跳都在 total_clus 之内，不报错");
        check(hop_cnt == 32'd20,    "WALK: 前 20 跳 hop_cnt 累计为 20");

        walk_and_wait(32'd10 + (20 % 3), 2'd0);
        check(error == 1'b1 && err_code == `ERR_MEDIA_INVALID && err_detail == `DET_FS_LOOP,
              "WALK: 跳簇数超过 total_clus 判为环 -> ERR_MEDIA_INVALID/DET_FS_LOOP");
        check(hop_cnt == 32'd20,    "WALK: 判环那一拍不再推进 hop_cnt");


        $display("==== F 错误透传 ====");
        walk_and_wait(32'd2, 2'd1);
        check(error == 1'b1,                           "WALK: sd_crc16_err 触发 error");
        check(err_code == `ERR_SD_IO,                  "WALK: SD 侧主码原样透传（ERR_SD_IO）");
        check(err_detail == `DET_SD_DATA_CRC,          "WALK: SD 侧细分码原样透传（DET_SD_DATA_CRC）");


        $display("==== G 读请求超时 ====");
        sd_rd_ready = 32'd0;
        walk_and_wait(32'd2, 2'd2);
        sd_rd_ready = 32'hFFFF_FFFF;
        check(error == 1'b1,                           "WALK: 卡一直不 ready 时读请求超时");
        check(err_code == `ERR_SD_IO && err_detail == `DET_SD_TOKEN_TO,
              "WALK: 读超时上报 ERR_SD_IO/DET_SD_TOKEN_TO");
        check(busy == 1'b0,                            "WALK: 超时后 busy 归 0");


        $display("==== H 全局监视 ====");
        check(done_cycles == 33,        "MON: done 总拍数 == 33（与 walk 次数一致）");
        check(done_two_in_a_row == 1'b0,"MON: done 全程都是单拍脉冲（无连续两拍）");


        $display("========================================");
        $display("  PASS = %0d   FAIL = %0d", total - errors, errors);
        $display("========================================");
        if (errors == 0) $display("[RESULT] ALL PASS");
        else             $display("[RESULT] %0d FAILED", errors);
        $finish;
    end


    initial begin
        #30_000_000;
        $display("[FAIL] tb_fat32_cluster_walker watchdog timeout");
        $finish;
    end

endmodule
