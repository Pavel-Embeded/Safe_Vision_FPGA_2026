


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_top_stage6_fat32_mount;

    localparam integer CLK_HZ   = 50_000_000;
    localparam integer BAUD     = 115200;
    localparam integer DIV      = CLK_HZ / BAUD;
    localparam integer BIT_NS   = DIV * 20;
    localparam integer HALF_NS  = BIT_NS / 2;
    localparam integer MAXB     = 512;
    localparam [31:0]  VOL_BASE = 32'd16;


    localparam [31:0]  EXP_MBR_LBA  = 32'd0;
    localparam [31:0]  EXP_DBR_LBA  = VOL_BASE + 32'd0;
    localparam [31:0]  EXP_FAT_LBA  = VOL_BASE + 32'd32;
    localparam [31:0]  EXP_ROOT_LBA = VOL_BASE + 32'd34;


    localparam integer HDR_BYTES  = 183;
    localparam integer ENT_BYTES  = 52;
    localparam integer RPT_BYTES  = 27;
    localparam integer ERR_BYTES  = 8;
    localparam integer DONE_BYTES = 6;
    localparam integer N_ENT      = 3;
    localparam integer OFF_ENT0   = HDR_BYTES;
    localparam integer OFF_RPT    = HDR_BYTES + N_ENT*ENT_BYTES;
    localparam integer OFF_TAIL   = OFF_RPT  + RPT_BYTES;
    localparam integer TOTAL_OK   = OFF_TAIL + DONE_BYTES;
    localparam integer TOTAL_BAD  = OFF_TAIL + ERR_BYTES;


    localparam [47:0] DONE_CRLF = {"DONE", 8'h0D, 8'h0A};

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    integer errors;

    task check;
        input         cond;
        input [255:0] name;
        begin begin
            if (cond) begin
                $display("[PASS] %0s", name);
            end else begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
        end
     end endtask


    wire        sd_ncs, sd_dclk, sd_mosi, sd_miso, uart_txd;
    wire [3:0]  led;


    reg  kill_card  = 1'b0;
    reg  dead_latch = 1'b0;
    wire card_dead  = dead_latch;


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


    always @(posedge clk)
        if (kill_card && (dut.st >= 4'd12)) dead_latch <= 1'b1;


    reg seen_arg0  = 1'b0;
    reg seen_base  = 1'b0;
    reg seen_fat   = 1'b0;
    reg seen_root  = 1'b0;

    always @(posedge clk) begin
        if (o_cmd === 6'd17) begin
            if (o_arg === EXP_MBR_LBA)  seen_arg0 <= 1'b1;
            if (o_arg === EXP_DBR_LBA)  seen_base <= 1'b1;
            if (o_arg === EXP_FAT_LBA)  seen_fat  <= 1'b1;
            if (o_arg === EXP_ROOT_LBA) seen_root <= 1'b1;
        end
    end


    task uart_rx_byte(output [7:0] b);
        integer k;
        begin begin
            @(negedge uart_txd);
            #(HALF_NS);
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = uart_txd;
                #(BIT_NS);
            end
        end
     end endtask


    reg [8*MAXB-1:0] rep_bits;
    reg [47:0]       sh6;
    reg [31:0]       w4;
    reg              seen_err;
    integer          err_tail;
    integer          rn;


    function integer crlf_okf;
        input integer n;
        integer k;
        reg ok;
        begin begin
            ok = 1'b1;
            for (k = 1; k < n; k = k + 1) begin
                if (rep_bits[8*(MAXB-1-k) -: 8] == 8'h0A)
                    if (rep_bits[8*(MAXB-1-(k-1)) -: 8] != 8'h0D)
                        ok = 1'b0;
            end
            crlf_okf = ok;
        end
     end endfunction


    task mbr_set_card0;
        integer q;
        begin begin
            for (q = 0; q < 512; q = q + 1) u_card.sector[q] = 8'h00;
            u_card.sector[450] = 8'h0C;
            u_card.sector[454] = 8'h10;
            u_card.sector[455] = 8'h00;
            u_card.sector[456] = 8'h00;
            u_card.sector[457] = 8'h00;
            u_card.sector[458] = 8'h00;
            u_card.sector[459] = 8'h00;
            u_card.sector[460] = 8'h01;
            u_card.sector[461] = 8'h00;
            u_card.sector[510] = 8'h55;
            u_card.sector[511] = 8'hAA;
        end
     end endtask

    task mk_vol;
        integer q2;
        begin begin

            u_card.mk_fat32_dbr(16'd512, 8'd1, 16'd32, 8'd2, 32'd1, 32'd2, 32'd48, 1'b1);

            u_card.vol_zero(32'd32);
            u_card.vol_set_le(32'd32, 16'd8, 32'h0FFF_FFFF, 3'd4);

            u_card.vol_zero(32'd33);


            u_card.vol_zero(32'd34);
            u_card.mk_dir_entry(32'd34, 16'd0,  "SV0001  BMP", 8'h20, 32'd5, 32'h000E1036);
            u_card.mk_dir_entry(32'd34, 16'd32, "SV0002  BMP", 8'h20, 32'd6, 32'h000E1036);
            u_card.mk_dir_entry(32'd34, 16'd64, "SV0003  BMP", 8'h20, 32'd7, 32'h000E1036);
            for (q2 = 3; q2 < 16; q2 = q2 + 1)
                u_card.vol_set(32'd34, q2*32, 8'hE5);
        end
     end endtask


    task dump_report;
        input integer start;
        input integer cnt;
        integer k;
        begin begin
            for (k = start; k < cnt; k = k + 1)
                $write("%c", rep_bits[8*(MAXB-1-k) -: 8]);
        end
     end endtask


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


        #500;
        mk_vol;
        mbr_set_card0;
        #100;
        rst_n = 1'b1;


        begin : capA
            while (1) begin
                uart_rx_byte(rb);
                rep_bits[8*(MAXB-1-rn) -: 8] = rb;
                rn  = rn + 1;
                sh6 = (sh6 << 8) | rb;
                if (sh6 == DONE_CRLF)  disable capA;
                if (rn >= 400)         disable capA;
            end
        end

        repeat (20) @(posedge clk);

        $display("---- scenario A: UART report begin ----");
        dump_report(0, rn);
        $display("");
        $display("---- scenario A: UART report end ----");


        check(seen_arg0, "T1 mbr_parser 读卡 0 号扇区(arg=0)");
        check(seen_base, "T2 FAT32 层 0 号扇区读落在卡 LBA = base(16)");
        check(seen_fat,  "T3 FAT 扇区读 = base + 32");
        check(seen_root, "T4 根目录扇区读 = base + 34");
        check(led === 4'h8, "T5 顶层到达成功态 led=8");
        check(rn == TOTAL_OK, "T6 UART 报告字节数 = 372(无前导 0x00)");


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


        kill_card  = 1'b1;
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
                if (rn >= 400)                   disable capB;
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
