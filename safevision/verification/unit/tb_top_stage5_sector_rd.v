


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


    integer observed_commands=0,observed_acmd41=0,sequence_errors=0;
    reg[2:0] command_phase=0;
    reg[31:0] observed_read_arg=0;
    always @(posedge o_cmd_valid or negedge rst_n)begin
        if(!rst_n)begin observed_commands=0;observed_acmd41=0;sequence_errors=0;command_phase=0;observed_read_arg=0;end
        else begin
            observed_commands=observed_commands+1;
            if(o_cmd==6'd41)observed_acmd41=observed_acmd41+1;
            if(o_cmd==6'd17)observed_read_arg=o_arg;
            case(command_phase)
             0:if(o_cmd==0)command_phase=1;else sequence_errors=sequence_errors+1;
             1:if(o_cmd==8)command_phase=2;else if(o_cmd!=0)sequence_errors=sequence_errors+1;
             2:if(o_cmd==55)command_phase=3;else sequence_errors=sequence_errors+1;
             3:if(o_cmd==41)command_phase=4;else sequence_errors=sequence_errors+1;
             4:if(o_cmd==55)command_phase=3;else if(o_cmd==58)command_phase=5;else sequence_errors=sequence_errors+1;
             5:if(o_cmd==17)command_phase=6;else sequence_errors=sequence_errors+1;
             default:sequence_errors=sequence_errors+1;
            endcase
        end
    end


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

     end endtask


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


        if (observed_commands>=6 && observed_acmd41>=1 && command_phase==6 && sequence_errors==0)
            $display("[PASS] T1 ordered command history 0/8/(55,41)+/58/17 count=%0d acmd41=%0d",observed_commands,observed_acmd41);
        else
            $display("[FAIL] T1 command history count=%0d acmd41=%0d phase=%0d order_errors=%0d",observed_commands,observed_acmd41,command_phase,sequence_errors);
        $display("[TB] per-CS diagnostic model_acmd41=%0d cumulative_observed=%0d",o_acmd41_cnt,observed_acmd41);


        if (o_cmd === 6'd17 && o_arg === LBA && observed_read_arg === LBA)
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
