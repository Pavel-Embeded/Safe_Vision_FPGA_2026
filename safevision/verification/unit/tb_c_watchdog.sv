


`timescale 1ns / 1ps

module tb_c_watchdog;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n;

    reg recover_ack, frame_heartbeat, mem_heartbeat, progress_token;
    wire        wdt_timeout;
    wire [1:0]  wdt_channel;
    wire [7:0]  wdt_reason;
    wire [31:0] wdt_ts;

    watchdog #(
        .CLK_HZ(1000), .TO_FRAME_CYC(5), .TO_MEM_CYC(7), .TO_PROG_CYC(10),
        .CODE_FRAME(8'h03), .CODE_MEM(8'h02), .CODE_PROG(8'h03)
    ) dut (
        .clk(clk), .rst_n(rst_n), .recover_ack(recover_ack),
        .frame_heartbeat(frame_heartbeat), .mem_heartbeat(mem_heartbeat),
        .progress_token(progress_token),
        .wdt_timeout(wdt_timeout), .wdt_channel(wdt_channel),
        .wdt_reason(wdt_reason), .wdt_ts(wdt_ts)
    );

    integer errors = 0, i;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask


    task step;
        input fh, mh, ph;
        begin
            @(negedge clk);
            frame_heartbeat = fh; mem_heartbeat = mh; progress_token = ph;
            @(posedge clk); #1;
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0; recover_ack = 1'b0;
            frame_heartbeat = 0; mem_heartbeat = 0; progress_token = 0;
            repeat (3) @(posedge clk); #1;
            rst_n = 1'b1;
        end
    endtask

    initial begin
        do_reset();
        check(wdt_timeout === 1'b0 && wdt_channel === 2'd0 && wdt_reason === 8'h00,
              "W1 复位 -> wdt_timeout=0 原因清零");


        for (i = 0; i < 20; i = i + 1) step(1, 1, 1);
        check(wdt_timeout === 1'b0, "W2 三路心跳正常 -> 不超时（不误判）");


        for (i = 0; i < 6; i = i + 1) step(0, 1, 1);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd0 && wdt_reason === 8'h03,
              "W3 frame 心跳停止 -> 超时 channel=0");
        check(wdt_ts !== 32'd0, "W3b 锁存了故障时刻");


        for (i = 0; i < 6; i = i + 1) step(1, 1, 1);
        check(wdt_timeout === 1'b1,
              "W4 恢复注入心跳【不自动清】timeout（红线一）");


        @(negedge clk);
        recover_ack = 1; frame_heartbeat = 1; mem_heartbeat = 1; progress_token = 1;
        @(posedge clk); #1; recover_ack = 0;
        check(wdt_timeout === 1'b0 && wdt_channel === 2'd0 && wdt_reason === 8'h00,
              "W5 recover_ack -> 清除 timeout 与原因");


        for (i = 0; i < 12; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1, "W9a 再次超时");
        for (i = 0; i < 20; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1, "W9 timeout 长时保持锁存（无自动清除）");


        do_reset();
        check(wdt_timeout === 1'b0, "W9b 全局复位清除 timeout");


        do_reset();
        for (i = 0; i < 9; i = i + 1) step(1, 0, 1);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd1,
              "W6 mem 心跳停止 -> channel=1（其他路已喂）");


        do_reset();
        for (i = 0; i < 12; i = i + 1) step(1, 1, 0);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd2,
              "W7 progress 心跳停止 -> channel=2（其他路已喂）");


        do_reset();
        for (i = 0; i < 6; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd0,
              "W8 三路径无心跳时最小阈值(frame)先触发（阈值互异）");


        do_reset();
        for (i = 0; i < 9; i = i + 1) step(0, 1, 0);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd0,
              "W10 仅 mem 心跳 -> frame 仍超时（喂狗只认本路真实活动）");

        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_watchdog done, errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] tb_c_watchdog 看门狗超时");
        $finish;
    end

endmodule
