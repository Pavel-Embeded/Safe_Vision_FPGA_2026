


`timescale 1ns / 1ps

module tb_c_emergency_fsm;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n;

    reg        fire_in, alarm_in, media_fault, media_ok, fatal;
    reg [7:0]  fault_code_in;
    reg        confirm, confirm_stable, recover_ack, media_selftest_ok;
    reg [1:0]  direction_in;
    reg        direction_valid, warn_window_done, info_only;
    reg        ack_tog;

    wire commit_ack_toggle = ack_tog;
    wire       emergency_active;
    wire [1:0] warning_level, direction;
    wire       alarm_enable;
    wire [7:0] fault_reason;
    wire       commit_toggle;
    wire [2:0] state;
    wire       bram_req;

    emergency_fsm dut (
        .clk(clk), .rst_n(rst_n),
        .fire_in(fire_in), .alarm_in(alarm_in), .media_fault(media_fault),
        .media_ok(media_ok), .fault_code_in(fault_code_in), .fatal(fatal),
        .confirm(confirm), .confirm_stable(confirm_stable), .recover_ack(recover_ack),
        .media_selftest_ok(media_selftest_ok), .direction_in(direction_in),
        .direction_valid(direction_valid), .warn_window_done(warn_window_done),
        .info_only(info_only), .commit_ack_toggle(commit_ack_toggle),
        .emergency_active(emergency_active), .warning_level(warning_level),
        .direction(direction), .alarm_enable(alarm_enable),
        .fault_reason(fault_reason), .commit_toggle(commit_toggle),
        .state(state), .bram_req(bram_req)
    );


    always @(posedge clk or negedge rst_n)
        if (!rst_n) ack_tog <= 1'b0; else ack_tog <= commit_toggle;


    reg [13:0] p_pay = 14'd0;
    reg        p_tog = 1'b0;
    integer    mailbox_violation = 0;
    reg [13:0] cur_pay;
    always @(posedge clk) begin
        #1;
        if (rst_n === 1'b1) begin
            cur_pay = {emergency_active, warning_level, direction, alarm_enable, fault_reason};
            if ((cur_pay !== p_pay) && (commit_toggle === p_tog))
                mailbox_violation = mailbox_violation + 1;
            p_pay = cur_pay;
            p_tog = commit_toggle;
        end
    end

    localparam [2:0] S_NORMAL = 3'd0, S_WARNING = 3'd1, S_EMERGENCY = 3'd2,
                     S_EVACUATION = 3'd3, S_FAIL_SAFE = 3'd4;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end

     end endtask

    task ncyc;
        input integer n;
        integer k;
        begin  for (k = 0; k < n; k = k + 1) begin @(posedge clk); #1; end
     end endtask

    task do_reset;
        begin
            rst_n = 1'b0;
            fire_in = 0; alarm_in = 0; media_fault = 0; media_ok = 1; fatal = 0;
            fault_code_in = 8'h00; confirm = 0; confirm_stable = 0;
            recover_ack = 0; media_selftest_ok = 0;
            direction_in = 2'd0; direction_valid = 0;
            warn_window_done = 0; info_only = 0;
            repeat (4) @(posedge clk); #1;
            rst_n = 1'b1;
            ncyc(6);

     end endtask

    initial begin
        rst_n = 1'b0;
        fire_in = 0; alarm_in = 0; media_fault = 0; media_ok = 1; fatal = 0;
        fault_code_in = 8'h00; confirm = 0; confirm_stable = 0;
        recover_ack = 0; media_selftest_ok = 0;
        direction_in = 2'd0; direction_valid = 0; warn_window_done = 0; info_only = 0;

        do_reset();
        check(state === S_NORMAL && emergency_active === 1'b0 &&
              warning_level === 2'd0 && alarm_enable === 1'b0,
              "E1 复位 -> NORMAL，载荷清零");


        fire_in = 1; direction_valid = 0;
        @(posedge clk); #1; fire_in = 0;
        check(state === S_EMERGENCY, "E2 fire_in -> EMERGENCY");
        ncyc(6);
        check(emergency_active === 1'b1 && warning_level === 2'd2 && alarm_enable === 1'b1,
              "E2b EMERGENCY 载荷 active=1 level=2(红) alarm=1");


        direction_in = 2'd2; direction_valid = 1;
        @(posedge clk); #1;
        check(state === S_EVACUATION, "E3 fire 持续+方向有效 -> EVACUATION");
        ncyc(6);
        check(direction === 2'd2, "E3b EVACUATION 载荷 direction=2(双向)");


        direction_in = 2'd1;
        @(posedge clk); #1;
        ncyc(6);
        check(direction === 2'd1, "E4 EVACUATION 方向改变 -> direction 更新=1");


        confirm = 1; confirm_stable = 1; direction_valid = 0;
        @(posedge clk); #1; confirm = 0; confirm_stable = 0;
        check(state === S_NORMAL, "E5 人工确认且稳定窗口通过 -> NORMAL");
        ncyc(6);
        check(emergency_active === 1'b0 && alarm_enable === 1'b0 && direction === 2'd0,
              "E5b NORMAL 载荷清零 (active=0 alarm=0 dir=0)");


        media_fault = 1; media_ok = 0; fault_code_in = 8'h03;
        @(posedge clk); #1; media_fault = 0; media_ok = 1; fault_code_in = 8'h00;
        check(state === S_FAIL_SAFE && bram_req === 1'b1,
              "E6 媒体故障且不可用 -> FAIL_SAFE (bram_req=1)");
        ncyc(6);
        check(emergency_active === 1'b1 && direction === 2'd1 && alarm_enable === 1'b1,
              "E6b FAIL_SAFE 载荷 active=1 dir=1(右箭头) alarm=1");


        recover_ack = 1; media_selftest_ok = 1;
        @(posedge clk); #1; recover_ack = 0; media_selftest_ok = 0;
        check(state === S_NORMAL, "E7 FAIL_SAFE recover_ack+自检 -> NORMAL");
        ncyc(6);
        check(emergency_active === 1'b0, "E7b NORMAL 载荷清零");


        fatal = 1;
        @(posedge clk); #1; fatal = 0;
        check(state === S_FAIL_SAFE, "E8 fatal -> FAIL_SAFE");

        ncyc(6);
        confirm = 1; confirm_stable = 1;
        @(posedge clk); #1; confirm = 0; confirm_stable = 0;
        check(state === S_FAIL_SAFE, "E9 FAIL_SAFE 确认但媒体链未恢复 -> 保持（不自动退出）");


        do_reset();
        media_fault = 1; media_ok = 1; fault_code_in = 8'h03;
        @(posedge clk); #1; media_fault = 0; fault_code_in = 8'h00;
        check(state === S_WARNING, "E10 media_fault 且四图可播 -> WARNING");
        ncyc(6);
        check(emergency_active === 1'b1 && warning_level === 2'd1 && alarm_enable === 1'b1,
              "E10b WARNING 载荷 active=1 level=1(黄) alarm=1");

        warn_window_done = 1;
        @(posedge clk); #1; warn_window_done = 0;
        check(state === S_NORMAL, "E11 告警消失且窗口计满 -> NORMAL");
        ncyc(4);

        media_fault = 1; media_ok = 1;
        @(posedge clk); #1; media_fault = 0;
        check(state === S_WARNING, "E12 前置：WARNING");
        ncyc(4);
        fire_in = 1;
        @(posedge clk); #1; fire_in = 0;
        check(state === S_EMERGENCY, "E12b WARNING 中 fire_in -> EMERGENCY（高优先级覆盖）");

        do_reset();
        media_fault = 1; media_ok = 1;
        @(posedge clk); #1;
        check(state === S_WARNING, "E13 前置：WARNING");
        media_ok = 0;
        @(posedge clk); #1; media_fault = 0; media_ok = 1;
        check(state === S_FAIL_SAFE, "E14 WARNING 中媒体链完全失效 -> FAIL_SAFE");

        ncyc(6);
        check(mailbox_violation === 0,
              "E15 payload 只在 commit_toggle 翻转时改变（多位控制不逐位跨域）");
        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_emergency_fsm done, errors=%0d mailbox_violation=%0d",
                 errors, mailbox_violation);
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] tb_c_emergency_fsm 看门狗超时");
        $finish;
    end

endmodule
