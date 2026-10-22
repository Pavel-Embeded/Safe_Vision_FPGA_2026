// ============================================================================
// tb_crc.sv — 公共 CRC 单元测试（SafeVision 通用件）
// ----------------------------------------------------------------------------
// 被测：rtl/common/crc16_ccitt.v、rtl/common/crc7.v
//
// ★ 为什么必须单独测这两个模块：
//   1) CRC7 在工程里原本是【硬编码常数】（`SD_CRC_CMD0=0x95`、`SD_CRC_CMD8=0x87`），
//      抄错一个 bit 的后果是"上板后 CMD0 发出去卡毫无反应"，而仿真里
//      （卡模型不校验 CRC7）不会报任何错。本 TB 用可计算的 CRC7 反推
//      0x4A / 0x43 并把它们与宏对照，等于把这两个魔数钉死在对数上。
//   2) CRC16 现在被 sd_sector_reader（逐字节收）与 frame_writer（一次吃 4 字节）
//      共用同一份实现，但两边【喂字节的用法不同】。本 TB 既验证算法本身
//      （标准向量），也验证"大端 4 级级联 == 逐字节喂 4 次"这一约定
//      —— frame_writer 的抽样 CRC 正确性完全依赖后者。
//
// 测试卷：
//   T1 CRC16 标准向量：XMODEM("123456789") == 0x31C3
//   T2 CRC16 空报文 == 0x0000（init 值）
//   T3 CRC16 逐字节 == 大端 4 级级联（frame_writer 用法）
//   T4 CRC7 反推 CMD0：帧 {0x40,00,00,00,00} -> CRC7=0x4A，
//      {CRC7,1'b1} 必须等于 `SD_CRC_CMD0
//   T5 CRC7 反推 CMD8：帧 {0x48,00,00,01,0xAA} -> CRC7=0x43，
//      {CRC7,1'b1} 必须等于 `SD_CRC_CMD8
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_crc;

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
    // DUT：两个都是纯组合步进器（无状态），TB 自己维护累加寄存器
    // ------------------------------------------------------------------------
    reg  [15:0] c16_acc;
    reg  [7:0]  c16_data;
    wire [15:0] c16_out;
    crc16_ccitt u_crc16 (.crc_in(c16_acc), .data(c16_data), .crc_out(c16_out));

    reg  [6:0]  c7_acc;
    reg  [7:0]  c7_data;
    wire [6:0]  c7_out;
    crc7 u_crc7 (.crc_in(c7_acc), .data(c7_data), .crc_out(c7_out));

    // frame_writer 里的用法：4 级级联，大端（先高字节）
    reg  [31:0] w32;
    wire [15:0] w1, w2, w3, w4;
    crc16_ccitt u_w0 (.crc_in(c16_acc), .data(w32[31:24]), .crc_out(w1));
    crc16_ccitt u_w1 (.crc_in(w1),      .data(w32[23:16]), .crc_out(w2));
    crc16_ccitt u_w2 (.crc_in(w2),      .data(w32[15:8]),  .crc_out(w3));
    crc16_ccitt u_w3 (.crc_in(w3),      .data(w32[7:0]),   .crc_out(w4));

    // ------------------------------------------------------------------------
    // 喂字节任务（组合 DUT：置 data -> 等组合稳定 -> 锁存 crc_out）
    // ------------------------------------------------------------------------
    task feed16;
        input [7:0] b;
        begin
            c16_data = b;
            #1;
            c16_acc = c16_out;
        end
    endtask

    task feed7;
        input [7:0] b;
        begin
            c7_data = b;
            #1;
            c7_acc = c7_out;
        end
    endtask

    // 逐字节喂一整个命令帧（前 5 字节 = 1 Byte 命令 + 4 Byte 参数），回送 CRC7
    task crc7_of_frame;
        input  [7:0] b0, b1, b2, b3, b4;
        output [6:0] res;
        begin
            c7_acc = 7'h00;
            feed7(b0);
            feed7(b1);
            feed7(b2);
            feed7(b3);
            feed7(b4);
            res = c7_acc;
        end
    endtask

    reg [7:0]  crc7_val;
    reg [15:0] casc_acc;

    initial begin
        c16_acc = 16'h0000; c16_data = 8'h00;
        c7_acc  = 7'h00;    c7_data  = 8'h00;
        w32     = 32'h0000_0000;

        // ------------------------------------------------------------------
        // T1 CRC16 标准向量
        // ------------------------------------------------------------------
        c16_acc = 16'h0000;
        feed16(8'h31); feed16(8'h32); feed16(8'h33); feed16(8'h34);
        feed16(8'h35); feed16(8'h36); feed16(8'h37); feed16(8'h38);
        feed16(8'h39);   // "123456789"
        check(c16_acc == 16'h31C3, "CRC16 XMODEM(123456789)==0x31C3");

        // ------------------------------------------------------------------
        // T2 空报文 = init 值
        // ------------------------------------------------------------------
        c16_acc = 16'h0000;
        check(c16_acc == 16'h0000, "CRC16 empty message == init 0x0000");
        c7_acc = 7'h00;
        check(c7_acc == 7'h00, "CRC7 empty message == init 0x00");

        // ------------------------------------------------------------------
        // T3 逐字节 vs 大端 4 级级联（frame_writer 的用法）
        //    用"123456789"的前 8 个字节造两个 word，两种喂法结果必须一致
        // ------------------------------------------------------------------
        // 逐字节一侧
        c16_acc = 16'h0000;
        feed16(8'h31); feed16(8'h32); feed16(8'h33); feed16(8'h34);
        feed16(8'h35); feed16(8'h36); feed16(8'h37); feed16(8'h38);
        casc_acc = c16_acc;
        // 级联一侧（复现 frame_writer：crc 累加值 -> 一个 word 一次）
        c16_acc = 16'h0000;
        w32 = 32'h3132_3334;
        #1; c16_acc = w4;
        w32 = 32'h3536_3738;
        #1; c16_acc = w4;
        check(c16_acc == casc_acc, "CRC16 big-endian 4-stage cascade == byte-wise");

        // ------------------------------------------------------------------
        // T4 CRC7 反推 CMD0（手册 7.3：SPI 模式下 CMD0/CMD8 才校验 CRC7）
        // ------------------------------------------------------------------
        crc7_of_frame(8'h40, 8'h00, 8'h00, 8'h00, 8'h00, crc7_val);
        check(crc7_val == 7'h4A, "CRC7(CMD0) == 0x4A (from algorithm)");
        check({crc7_val, 1'b1} == `SD_CRC_CMD0,
              "CRC7(CMD0) end-bit byte == SD_CRC_CMD0 macro");
        check(8'h40 == (`SD_CMD_PREFIX | {2'b00, `SD_CMD0}),
              "CMD0 frame byte 0 == 0x40");

        // ------------------------------------------------------------------
        // T5 CRC7 反推 CMD8
        // ------------------------------------------------------------------
        crc7_of_frame(8'h48, 8'h00, 8'h00, 8'h01, 8'hAA, crc7_val);
        check(crc7_val == 7'h43, "CRC7(CMD8) == 0x43 (from algorithm)");
        check({crc7_val, 1'b1} == `SD_CRC_CMD8,
              "CRC7(CMD8) end-bit byte == SD_CRC_CMD8 macro");
        check(8'h48 == (`SD_CMD_PREFIX | {2'b00, `SD_CMD8}),
              "CMD8 frame byte 0 == 0x48");
        check(8'hAA == `SD_CMD8_CHECK, "CMD8 check pattern == 0xAA");

        // ------------------------------------------------------------------
        $display("");
        $display("============================================");
        $display("  tb_crc : PASS=%0d FAIL=%0d", total - errors, errors);
        $display("============================================");
        if (errors != 0) $display("[FAIL] tb_crc finished with %0d error(s)", errors);
        else             $display("[PASS] tb_crc all %0d checks passed", total);
        $finish;
    end

    // 兜底超时
    initial begin
        #100000;
        $display("[FAIL] tb_crc TIMEOUT");
        $finish;
    end

endmodule