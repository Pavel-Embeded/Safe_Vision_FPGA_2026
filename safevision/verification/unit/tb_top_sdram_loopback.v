


`timescale 1ns / 1ps

module tb_top_sdram_loopback;


    reg clk = 1'b0;
    always #10 clk = ~clk;


    reg clk125 = 1'b0;
    always #4 clk125 = ~clk125;

    reg  rst_n = 1'b0;
    wire uart_txd;
    wire [3:0] led;


    top_sdram_loopback #(
        .POWERUP_CYC    (24'd200),
        .INIT_TO_CYC    (24'd2000),
        .RD_WAIT_TO_CYC (20'd20000),
        .ROUNDS         (32'd3)
    ) u_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_txd (uart_txd),
        .led      (led)
    );


    localparam integer DIV = 1085;

    reg [7:0] rxbuf [0:511];
    integer   rx_n;
    integer   base;
    integer   b;
    reg [7:0] rx_byte;

    initial begin
        rx_n = 0;
        forever begin
            @(negedge uart_txd);
            repeat (DIV + DIV/2) @(posedge clk125);
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = uart_txd;
                if (b != 7) repeat (DIV) @(posedge clk125);
            end
            if (rx_n < 512) begin
                rxbuf[rx_n] = rx_byte;
                rx_n = rx_n + 1;
            end
            repeat (DIV/2) @(posedge clk125);
        end
    end


    integer errors = 0;

    task check;
        input         cond;
        input [255:0] name;
        begin begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
     end endtask


    localparam [8*190-1:0] EXP1 = {
        "SV-SDRAM-LOOP",                               8'h0D, 8'h0A,
        "INIT=01 LOCK=01",                             8'h0D, 8'h0A,
        "CFG=0B1 BASE=000000 N=000400",                8'h0D, 8'h0A,
        "RND=00000003/00000003 PAT=2",                 8'h0D, 8'h0A,
        "W=0400 R=0400 CAP=0400 BAD=0000",             8'h0D, 8'h0A,
        "TOT=0000000C00",                              8'h0D, 8'h0A,
        "BAD0=FFFFFFFF:FFFFFF E=00000000 A=00000000",  8'h0D, 8'h0A,
        "DONE",                                        8'h0D, 8'h0A
    };


    localparam [8*190-1:0] EXP2 = {
        "SV-SDRAM-LOOP",                               8'h0D, 8'h0A,
        "INIT=01 LOCK=01",                             8'h0D, 8'h0A,
        "CFG=0B1 BASE=000000 N=000400",                8'h0D, 8'h0A,
        "RND=00000002/00000003 PAT=1",                 8'h0D, 8'h0A,
        "W=0400 R=0400 CAP=0400 BAD=0001",             8'h0D, 8'h0A,
        "TOT=0000000800",                              8'h0D, 8'h0A,
        "BAD0=00000002:002805 E=64F2D804 A=64F2D805",  8'h0D, 8'h0A,
        "DONE",                                        8'h0D, 8'h0A
    };


    localparam [8*27-1:0] RND1_EXP   = "RND=00000003/00000003 PAT=2";
    localparam [8*42-1:0] BAD0_2_EXP = "BAD0=00000002:002805 E=64F2D804 A=64F2D805";


    localparam [10:0] RND_LO  = 8*(189-88);
    localparam [10:0] BAD0_LO = 8*(189-181);

    reg [8*190-1:0] got;
    integer i;


    initial begin
        #200_000_000;
        $display("[FAIL] tb_top_sdram_loopback 看门狗超时（rx_n=%0d, led=%0d）", rx_n, led);
        $finish;
    end


    initial begin
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;


        wait (rx_n >= 190);
        #100000;

        check(rx_n == 190, "T1 报告恰好 190 Byte（3 轮）");

        got = 0;
        for (i = 0; i < 190; i = i + 1)
            got = { got[8*189-1:0], rxbuf[i] };
        if (got !== EXP1) begin
            $display("[INFO] got[0..7]     = %02x %02x %02x %02x %02x %02x %02x %02x",
                     rxbuf[0], rxbuf[1], rxbuf[2], rxbuf[3],
                     rxbuf[4], rxbuf[5], rxbuf[6], rxbuf[7]);
            $display("[INFO] got[62..67]   = %02x %02x %02x %02x %02x %02x",
                     rxbuf[62], rxbuf[63], rxbuf[64], rxbuf[65], rxbuf[66], rxbuf[67]);
            $display("[INFO] got[124..129] = %02x %02x %02x %02x %02x %02x",
                     rxbuf[124], rxbuf[125], rxbuf[126], rxbuf[127], rxbuf[128], rxbuf[129]);
        end
        check(got === EXP1, "T2 报告逐字节正确（190 Byte，3 轮全过）");
        check(got[RND_LO +: 8*27] === RND1_EXP,
              "T2b RND 行正确（RND=00000003/00000003 PAT=2）");
        check(led === 4'h8, "T3 led = 8（成功态）");


        base = rx_n;
        rst_n = 1'b0;
        #200;
        rst_n = 1'b1;


        wait ((u_top.rnd === 32'd1) && (u_top.st === 4'd3));
        u_top.u_sdram.STUB_ERR_ADDR = 21'h002805;
        u_top.u_sdram.STUB_ERR_XOR  = 32'h00000001;

        wait (rx_n >= base + 190);
        #100000;

        check((rx_n - base) == 190, "T4 报告恰好 190 Byte（注入故障后只跑 1 轮）");

        got = 0;
        for (i = 0; i < 190; i = i + 1)
            got = { got[8*189-1:0], rxbuf[base + i] };
        if (got !== EXP2) begin
            $display("[INFO] got[62..67]   = %02x %02x %02x %02x %02x %02x",
                     rxbuf[base+62], rxbuf[base+63], rxbuf[base+64],
                     rxbuf[base+65], rxbuf[base+66], rxbuf[base+67]);
            $display("[INFO] got[140..147] = %02x %02x %02x %02x %02x %02x %02x %02x",
                     rxbuf[base+140], rxbuf[base+141], rxbuf[base+142], rxbuf[base+143],
                     rxbuf[base+144], rxbuf[base+145], rxbuf[base+146], rxbuf[base+147]);
        end
        check(got === EXP2, "T5 报告逐字节正确（含 BAD=0001 与 BAD0 定位）");
        check(got[BAD0_LO +: 8*42] === BAD0_2_EXP,
              "T5b BAD0 定位正确（轮次:地址 期望 实际）");
        check(led === 4'h3, "T6 led = 3（数据不一致）");

        $display("[TB] tb_top_sdram_loopback done, errors=%0d (rx_n=%0d, led=%0h)", errors, rx_n, led);
        $finish;
    end

endmodule
