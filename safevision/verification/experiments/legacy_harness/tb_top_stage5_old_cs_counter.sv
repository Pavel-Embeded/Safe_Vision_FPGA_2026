


`timescale 1ns / 1ps
`include "safevision_defs.vh"

module tb_top_stage5_sector_rd;

    localparam integer CLK_HZ   = 50_000_000;
    localparam integer BAUD     = 115200;
    localparam integer DIV      = CLK_HZ / BAUD;
    localparam integer BIT_NS   = DIV * 20;
    localparam integer HALF_NS  = BIT_NS / 2;
    localparam integer NBYTES   = 512;
    localparam [31:0]  LBA      = 32'd1000;


    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #10 clk = ~clk;


    wire        sd_ncs, sd_dclk, sd_mosi, sd_miso, uart_txd;
    wire [3:0]  led;


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


    top_stage5_sector_rd #(
        .CLK_FREQ    (CLK_HZ),
        .BAUD        (BAUD),
        .TARGET_LBA  (LBA),
        .POWERUP_CYC (24'd200)
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


    reg [7:0] rx_bytes [0:NBYTES-1];
    integer   rx_cnt;

    task uart_rx_byte(output [7:0] b);
        integer k;
        begin
            @(negedge uart_txd);
            #(HALF_NS);
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                b[k] = uart_txd;
                #(BIT_NS);
            end
        end
    endtask


    initial begin
        #80_000_000;
        $display("[FAIL] T3 顶层看门狗超时，只收到 %0d Byte", rx_cnt);
        $finish;
    end


    integer   i;
    integer   mismatch;
    reg [7:0] exp_byte;

    initial begin
        rx_cnt   = 0;
        mismatch = 0;

        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;


        for (i = 0; i < NBYTES; i = i + 1) begin
            uart_rx_byte(rx_bytes[i]);
            rx_cnt = rx_cnt + 1;
        end


        if (rx_cnt === NBYTES)
            $display("[PASS] T3 UART 收满 512 Byte");
        else
            $display("[FAIL] T3 UART 只收到 %0d Byte", rx_cnt);


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


        if (o_cmd_cnt >= 8'd6 && o_acmd41_cnt >= 8'd1)
            $display("[PASS] T1 卡模型收到完整命令序列 cmd_cnt=%0d acmd41_cnt=%0d",
                     o_cmd_cnt, o_acmd41_cnt);
        else
            $display("[FAIL] T1 命令序列不完整 cmd_cnt=%0d acmd41_cnt=%0d",
                     o_cmd_cnt, o_acmd41_cnt);


        if (o_cmd === 6'd17 && o_arg === LBA)
            $display("[PASS] T2 CMD17 参数 = %0d", o_arg);
        else
            $display("[FAIL] T2 CMD17 参数错误 cmd=%0d arg=%0d", o_cmd, o_arg);


        if (led === 4'h8)
            $display("[PASS] T4 顶层到达成功态 led=%0h", led);
        else
            $display("[FAIL] T4 顶层未到成功态 led=%0h", led);

        $display("[TB] sim end at %0t ns", $time);
        $finish;
    end

endmodule
