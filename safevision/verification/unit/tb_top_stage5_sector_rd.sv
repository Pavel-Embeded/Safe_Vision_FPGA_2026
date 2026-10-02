// ============================================================================
// tb_top_stage5_sector_rd.sv — 板级 bring-up 顶层验证（SafeVision B 链 · 阶段 5）
// ----------------------------------------------------------------------------
// 被测：safevision/platform/anlogic_eg4s20_hx4s20c/rtl/top_stage5_sector_rd.v
//
// 为什么要有这个 TB：顶层是"接引脚的那一层"，它错在例化/握手/总线复用上，
// 而这些错误单元 TB 一个都抓不到（单元 TB 各自直连 DUT，不经过顶层的 mux）。
// 板子到手之前先把它跑通，避免上板才发现接错。
//
// 验证内容：
//   T1  顶层自动完成 SD 初始化（卡模型看得到 CMD0/CMD8/CMD55/ACMD41/CMD58/CMD17）
//   T2  CMD17 参数 = 目标 LBA（1000）原样送出
//   T3  512 Byte 经 UART 按序发出，且逐字节与卡模型内容一致（手册 7.5 过关标准）
//   T4  顶层最终停在成功态（led = 8），即没有超时 / CRC16 错 / 非 0 错误码
//
// ★ 只为加速仿真把 POWERUP_CYC 从板上 50ms 缩到 4us；
//   UART 仍是真实 115200 @50MHz（每字节约 86.8us，512 Byte 约 44.5ms 仿真时间），
//   所以本 TB 会比其它单元 TB 慢一些，这是"真跑一遍完整回传"的代价。
// ============================================================================
`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_top_stage5_sector_rd;

    localparam integer CLK_HZ   = 50_000_000;
    localparam integer BAUD     = 115200;
    localparam integer DIV      = CLK_HZ / BAUD;   // 434
    localparam integer BIT_NS   = DIV * 20;        // 8680 ns / bit
    localparam integer HALF_NS  = BIT_NS / 2;
    localparam integer NBYTES   = 512;
    localparam [31:0]  LBA      = 32'd1000;
    // 注：本 TB 显式给 DUT 传 TARGET_LBA，所以它验证的是"给定的 LBA 原样送出"这条通用性质，
    //     与 DUT 的默认值无关。板上实际构建把默认值改成了 32'd8192（分区首扇区/FAT32 DBR，
    //     内容非零、便于逐字节比对；原因见 top_stage5_sector_rd.v 文件头）。
    //     这里刻意保留 1000，不动任何断言。

    // ------------------------------------------------------------------------
    // 时钟与复位：20 ns -> 50 MHz（与板载晶振同频）
    // ------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;

    // ------------------------------------------------------------------------
    // DUT 引脚
    // ------------------------------------------------------------------------
    wire        sd_ncs, sd_dclk, sd_mosi, sd_miso, uart_txd;
    wire [3:0]  led;

    // ------------------------------------------------------------------------
    // SD 卡行为模型（SPI 从机）
    // ------------------------------------------------------------------------
    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;

    sd_spi_card_model u_card (
        .sclk         (sd_dclk),
        .cs_n         (sd_ncs),
        .mosi         (sd_mosi),
        .miso         (sd_miso),
        .i_dead       (1'b0),
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
    top_stage5_sector_rd #(
        .CLK_FREQ    (CLK_HZ),
        .BAUD        (BAUD),
        .TARGET_LBA  (LBA),
        .POWERUP_CYC (24'd200)          // 仿真加速：4 us（板上是 50 ms）
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
    // UART 接收模型：8N1，LSB 先收，在位中点采样
    // 固定按 DIV 计时；如果顶层 uart_tx 的 CLK_FREQ/BAUD 参数接错，
    // 这里收出来的字节就会错位，T3 的逐字节比对会立刻报错。
    // ------------------------------------------------------------------------
    reg [7:0] rx_bytes [0:NBYTES-1];
    integer   rx_cnt;

    task uart_rx_byte(output [7:0] b);
        integer k;
        begin
            @(negedge uart_txd);        // 起始位下降沿
            #(HALF_NS);                 // -> 起始位中点
            #(BIT_NS);                  // -> 数据位 0 中点
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = uart_txd;
                #(BIT_NS);              // 移到下一位中点（收完 8 位落在停止位中点）
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // 看门狗：主流程 45 ms 左右结束，80 ms 还没收完就是卡住了
    // ------------------------------------------------------------------------
    initial begin
        #80_000_000;
        $display("[FAIL] T3 顶层看门狗超时，只收到 %0d Byte", rx_cnt);
        $finish;
    end

    // ------------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------------
    integer   i;
    integer   mismatch;
    reg [7:0] exp_byte;                 // 注意：不能叫 expect，它是 SV 保留字

    initial begin
        rx_cnt   = 0;
        mismatch = 0;

        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;

        // 收满一整个扇区
        for (i = 0; i < NBYTES; i = i + 1) begin
            uart_rx_byte(rx_bytes[i]);
            rx_cnt = rx_cnt + 1;
        end

        // ---- T3a: 字节数 ----
        if (rx_cnt === NBYTES)
            $display("[PASS] T3 UART 收满 512 Byte");
        else
            $display("[FAIL] T3 UART 只收到 %0d Byte", rx_cnt);

        // ---- T3b: 逐字节比对（卡模型默认扇区内容 = i[7:0] + 8'h11）----
        for (i = 0; i < NBYTES; i = i + 1) begin
            exp_byte = i[7:0] + 8'h11;
            if (rx_bytes[i] !== exp_byte) begin
                mismatch = mismatch + 1;
                if (mismatch <= 5)
                    $display("[TB] byte %0d got %02x expect %02x",
                             i, rx_bytes[i], exp_byte);
            end
        end
        if (mismatch == 0)
            $display("[PASS] T3 512 Byte 逐字节与卡模型一致");
        else
            $display("[FAIL] T3 逐字节比对不符 %0d 个", mismatch);

        // ---- T1: 初始化 + 读取的完整命令序列 ----
        if (o_cmd_cnt >= 8'd6 && o_acmd41_cnt >= 8'd1)
            $display("[PASS] T1 卡模型收到完整命令序列 cmd_cnt=%0d acmd41_cnt=%0d",
                     o_cmd_cnt, o_acmd41_cnt);
        else
            $display("[FAIL] T1 命令序列不完整 cmd_cnt=%0d acmd41_cnt=%0d",
                     o_cmd_cnt, o_acmd41_cnt);

        // ---- T2: CMD17 参数 ----
        if (o_cmd === 6'd17 && o_arg === LBA)
            $display("[PASS] T2 CMD17 参数 = %0d", o_arg);
        else
            $display("[FAIL] T2 CMD17 参数错误 cmd=%0d arg=%0d", o_cmd, o_arg);

        // ---- T4: 顶层停在成功态 ----
        // 最后一个字节被 uart 取走后，reader 还要收完 2 Byte CRC 才置 rd_done，
        // 所以本 TB 收满 512 Byte 的时刻一定晚于顶层进入成功态，这里直接查即可。
        if (led === 4'h8)
            $display("[PASS] T4 顶层到达成功态 led=%0h", led);
        else
            $display("[FAIL] T4 顶层未到成功态 led=%0h", led);

        $display("[TB] sim end at %0t ns", $time);
        $finish;
    end

endmodule