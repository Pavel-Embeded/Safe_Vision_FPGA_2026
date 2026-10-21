// ============================================================================
// tb_c_watchdog.sv — 三路看门狗单元验证（手册 8.4，可靠性红线）
// ----------------------------------------------------------------------------
// 为加快仿真：CLK_HZ=1000（MS_DIV=1，1 拍 = 1 ms），三路阈值 5 / 7 / 10 拍。
//   过关标准：
//   W1 复位 -> wdt_timeout=0
//   W2 三路心跳正常 -> 永不超时（不误判正常路径）
//   W3 停止 frame 心跳 -> 超时且 channel=0（首因锁存）
//   W4 ★红线一：恢复注入心跳【不自动清 timeout】
//   W5 recover_ack -> 清除 timeout 与原因
//   W6 停止 mem 心跳（阈值 7）-> channel=1
//   W7 停止 progress 心跳（阈值 10）-> channel=2
//   W8 三阈值互不相同：无心跳时先触发最小者（frame）
//   W9 timeout 长时保持锁存；只有全局复位才清
//   W10 喂狗必须来自真实活动：单路心跳不能替另外两路喂狗
// ============================================================================
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

    // 一拍：在 negedge 驱动三路心跳，posedge 生效
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

        // W2 三路正常
        for (i = 0; i < 20; i = i + 1) step(1, 1, 1);
        check(wdt_timeout === 1'b0, "W2 三路心跳正常 -> 不超时（不误判）");

        // W3 停止 frame
        for (i = 0; i < 6; i = i + 1) step(0, 1, 1);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd0 && wdt_reason === 8'h03,
              "W3 frame 心跳停止 -> 超时 channel=0");
        check(wdt_ts !== 32'd0, "W3b 锁存了故障时刻");

        // W4 恢复心跳不自动清（红线一）
        for (i = 0; i < 6; i = i + 1) step(1, 1, 1);
        check(wdt_timeout === 1'b1,
              "W4 恢复注入心跳【不自动清】timeout（红线一）");

        // W5 recover_ack 清除
        @(negedge clk);
        recover_ack = 1; frame_heartbeat = 1; mem_heartbeat = 1; progress_token = 1;
        @(posedge clk); #1; recover_ack = 0;
        check(wdt_timeout === 1'b0 && wdt_channel === 2'd0 && wdt_reason === 8'h00,
              "W5 recover_ack -> 清除 timeout 与原因");

        // W9 长时无心跳 -> 保持锁存
        for (i = 0; i < 12; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1, "W9a 再次超时");
        for (i = 0; i < 20; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1, "W9 timeout 长时保持锁存（无自动清除）");

        // W9b 全局复位清除
        do_reset();
        check(wdt_timeout === 1'b0, "W9b 全局复位清除 timeout");

        // W6 停止 mem（阈值 7）-> channel=1
        do_reset();
        for (i = 0; i < 9; i = i + 1) step(1, 0, 1);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd1,
              "W6 mem 心跳停止 -> channel=1（其他路已喂）");

        // W7 停止 progress（阈值 10）-> channel=2
        do_reset();
        for (i = 0; i < 12; i = i + 1) step(1, 1, 0);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd2,
              "W7 progress 心跳停止 -> channel=2（其他路已喂）");

        // W8 三阈值互不相同：无心跳时先触发最小者 frame
        do_reset();
        for (i = 0; i < 6; i = i + 1) step(0, 0, 0);
        check(wdt_timeout === 1'b1 && wdt_channel === 2'd0,
              "W8 三路径无心跳时最小阈值(frame)先触发（阈值互异）");

        // W10 单路心跳不替其他路喂狗
        do_reset();
        for (i = 0; i < 9; i = i + 1) step(0, 1, 0);   // 只有 mem 心跳
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
