// ============================================================================
// tb_c_input_sync.sv — C 输入前级链单元验证（input_sync / key_debounce）
// ----------------------------------------------------------------------------
// 过关标准（手册 8.1 过关自测）：
//   I1 复位态：level=RESET_LEVEL、press=0、evt_pending=0
//   I2 干净上升沿 -> press 恰好一拍，level 置高，之后自动落回
//   I3 抖动快于去抖窗口 -> 不产生 press（一次按键不会触发多次）
//   I4 按住 1 秒（长时保持）-> 只产生一次事件（不是连续事件）
//   I5 窄事件锁存：press 后 evt_pending 保持，evt_clear 才清除
//   I6 press 宽度恰为 1 拍
//   I7 下降沿 -> 不产生 press（必须用上升沿，不是稳定电平）
//   I8 key_debounce：多路聚合，press_any 单拍、evt_key 锁存、clear 生效
//   I9 key_debounce：同拍多键 -> 最低编号优先（可复现的固定优先级）
// 为加快仿真，DEB_N 取 8（产品值 20 ms 由参数决定，不在此验证）。
// ============================================================================
`timescale 1ns / 1ps

module tb_c_input_sync;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---- DUT1: input_sync ----
    reg  rst_n, async_in, evt_clear;
    wire press, level, evt_pending;
    input_sync #(.DEB_N(8), .RESET_LEVEL(1'b0)) dut (
        .clk(clk), .rst_n(rst_n), .async_in(async_in), .evt_clear(evt_clear),
        .press(press), .level(level), .evt_pending(evt_pending)
    );

    // ---- DUT2: key_debounce ----
    reg  [3:0] key_async;
    reg        kclr;
    wire [3:0] key_level, press_vec;
    wire       press_any, evt_pending_k;
    wire [1:0] evt_key;
    key_debounce #(.KEYS(4), .DEB_N(8), .RESET_LEVEL(1'b0)) kd (
        .clk(clk), .rst_n(rst_n), .key_async(key_async), .evt_clear(kclr),
        .key_level(key_level), .press_vec(press_vec), .press_any(press_any),
        .evt_key(evt_key), .evt_pending(evt_pending_k)
    );

    integer errors = 0, cnt, i, pany, prev_press;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    task ncyc;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) begin @(posedge clk); #1; end end
    endtask

    // 在 n 拍内统计 press 高电平拍数（同时检查不连宽：宽度必须 <=1）
    task count_press;
        input  integer n;
        output integer c;
        integer k;
        begin
            c = 0; prev_press = 0;
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk); #1;
                if (press) begin
                    c = c + 1;
                    if (prev_press) begin
                        $display("[FAIL] press 宽度 > 1 拍");
                        errors = errors + 1;
                    end
                end
                prev_press = press;
            end
        end
    endtask

    initial begin
        // ================= DUT1 =================
        rst_n = 1'b0; async_in = 1'b0; evt_clear = 1'b0;
        key_async = 4'b0000; kclr = 1'b0;
        ncyc(4);
        check(level === 1'b0 && press === 1'b0 && evt_pending === 1'b0,
              "I1 复位态：level=0 press=0 evt_pending=0");

        // I2 干净上升沿（必须先释放复位，否则 DUT 一直停在复位态）
        rst_n = 1'b1;
        async_in = 1'b1;
        count_press(40, cnt);
        check(cnt == 1, "I2 干净上升沿 -> press 恰好一拍");
        check(level === 1'b1, "I2b 去抖后 level 稳定为高");
        ncyc(2);
        check(press === 1'b0, "I2c press 已自动落回（=1 拍脉冲）");

        // I4 长时保持不再产生事件
        count_press(60, cnt);
        check(cnt == 0, "I4 按住 1 秒 -> 不再产生事件（非连续事件）");

        // I7 下降沿不产生 press
        async_in = 1'b0;
        count_press(40, cnt);
        check(cnt == 0, "I7 下降沿 -> 不产生 press（必须用边沿）");
        check(level === 1'b0, "I7b 去抖后 level 稳定为低");

        // I3 快速抖动（每 2 拍翻转，远快于 DEB_N=8）
        ncyc(20);
        for (i = 0; i < 20; i = i + 1) begin
            async_in = 1'b1; ncyc(2);
            async_in = 1'b0; ncyc(2);
        end
        count_press(40, cnt);
        check(cnt == 0, "I3 抖动快于去抖窗口 -> 不产生 press（一次按键一次事件）");

        // I5 pending 锁存与清除
        rst_n = 1'b0; ncyc(2); rst_n = 1'b1;
        async_in = 1'b0; ncyc(20);
        async_in = 1'b1;
        count_press(40, cnt);
        check(evt_pending === 1'b1, "I5 press 后 evt_pending 锁存");
        ncyc(10);
        check(evt_pending === 1'b1, "I5b evt_pending 保持（防窄脉冲丢失）");
        evt_clear = 1'b1; ncyc(1);
        check(evt_pending === 1'b0, "I5c evt_clear 清除 pending");
        evt_clear = 1'b0;
        async_in = 1'b0; ncyc(20);

        // ================= DUT2: key_debounce =================
        rst_n = 1'b0; ncyc(2); rst_n = 1'b1;
        key_async = 4'b0000; kclr = 1'b0; ncyc(20);

        key_async = 4'b0001;                       // KEY0
        pany = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (press_any) pany = pany + 1;
        end
        check(pany == 1, "I8 key0 -> press_any 恰好一拍");
        check(evt_key === 2'd0 && evt_pending_k === 1'b1,
              "I8b evt_key=0 已锁存 (evt_pending=1)");
        kclr = 1'b1; ncyc(1);
        check(evt_pending_k === 1'b0, "I8c kclr 清除事件锁存");
        kclr = 1'b0; key_async = 4'b0000; ncyc(20);

        // I9 同拍多键 -> 最低编号优先
        key_async = 4'b0011;                       // KEY0 + KEY1 同拍
        pany = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (press_any) pany = pany + 1;
        end
        check(pany == 1, "I9 同拍双键 -> press_any 单拍");
        check(evt_key === 2'd0, "I9b 同拍双键 -> 最低编号 (KEY0) 优先（固定可复现）");
        kclr = 1'b1; ncyc(1); kclr = 1'b0;

        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_input_sync done, errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] tb_c_input_sync 看门狗超时");
        $finish;
    end

endmodule
