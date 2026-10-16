// ============================================================================
// tb_c_fault_manager.sv — 故障首因 / 等级 / 媒体复位隔离单元验证（表 8-4）
// ----------------------------------------------------------------------------
// 为加快仿真：CLK_HZ=1000（MS_DIV=1）。
//   过关标准：
//   F1  复位 -> fault_valid=0、fatal=0、fault_code=0
//   F2  一条故障 -> 主码/等级锁存，fault_valid=1
//   F3  ★首因粘滞：后续不同故障不覆盖首因（码与等级保持）
//   F4  media_fatal -> fatal 锁存，等级升级为 FATAL（码不覆盖）
//   F5  ★FATAL 只由全局复位清除：recover_ack 不能清
//   F6  INFO 等级（可选资源缺失）-> level=0，仍置 fault_valid
//   F7  recover_ack（无 FATAL）-> 清首因，且【同拍】给 media_rst_req
//   F8  看门狗超时 -> 用 wdt_reason 锁存，等级 SAFE
//   F9  media_rst_req 为单拍脉冲（只复位媒体链，不牵连安全画面）
//   F10 从干净态 media_fatal -> 等级 FATAL、fatal=1
// ============================================================================
`timescale 1ns / 1ps

module tb_c_fault_manager;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n;

    reg        err_push;
    reg [7:0]  err_code;
    reg [2:0]  err_level;
    reg        wdt_timeout;
    reg [7:0]  wdt_reason;
    reg        media_fatal, recover_ack;

    wire [7:0] fault_code;
    wire [2:0] fault_level;
    wire       fault_valid, fatal;
    wire [31:0] fault_ts;
    wire       media_rst_req;

    fault_manager #(.CLK_HZ(1000)) dut (
        .clk(clk), .rst_n(rst_n),
        .err_push(err_push), .err_code(err_code), .err_level(err_level),
        .wdt_timeout(wdt_timeout), .wdt_reason(wdt_reason),
        .media_fatal(media_fatal), .recover_ack(recover_ack),
        .fault_code(fault_code), .fault_level(fault_level), .fault_valid(fault_valid),
        .fatal(fatal), .fault_ts(fault_ts), .media_rst_req(media_rst_req)
    );

    localparam [2:0] LV_INFO = 3'd0, LV_WARNING = 3'd1, LV_DEGRADED = 3'd2,
                     LV_SAFE = 3'd3, LV_FATAL = 3'd4;

    integer errors = 0;
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

    task do_reset;
        begin
            rst_n = 1'b0;
            err_push = 0; err_code = 8'h00; err_level = 3'd0;
            wdt_timeout = 0; wdt_reason = 8'h00; media_fatal = 0; recover_ack = 0;
            repeat (3) @(posedge clk); #1;
            rst_n = 1'b1; ncyc(2);
        end
    endtask

    task push_err;
        input [7:0] c;
        input [2:0] l;
        begin
            @(negedge clk); err_push = 1; err_code = c; err_level = l;
            @(posedge clk); #1; err_push = 0; err_code = 8'h00; err_level = 3'd0;
        end
    endtask

    task pulse_ra;
        begin @(negedge clk); recover_ack = 1; @(posedge clk); #1; recover_ack = 0; end
    endtask

    task pulse_mfatal;
        begin @(negedge clk); media_fatal = 1; @(posedge clk); #1; media_fatal = 0; end
    endtask

    task pulse_wdt;
        input [7:0] r;
        begin @(negedge clk); wdt_timeout = 1; wdt_reason = r;
              @(posedge clk); #1; wdt_timeout = 0; wdt_reason = 8'h00; end
    endtask

    integer trial;
    reg[31:0] first_ts;
    initial begin
        rst_n = 1'b0;
        err_push = 0; err_code = 8'h00; err_level = 3'd0;
        wdt_timeout = 0; wdt_reason = 8'h00; media_fatal = 0; recover_ack = 0;

        do_reset();
        check(fault_valid === 1'b0 && fatal === 1'b0 && fault_code === 8'h00,
              "F1 复位 -> fault_valid=0 fatal=0 code=0");

        // F2 首条故障
        push_err(8'h03, LV_WARNING);
        check(fault_valid === 1'b1 && fault_code === 8'h03 && fault_level === LV_WARNING,
              "F2 首条故障 -> 主码/等级锁存");
        check(fault_ts !== 32'd0, "F2b 锁存了故障时刻");

        // F3 首因粘滞
        push_err(8'h07, LV_DEGRADED);
        check(fault_code === 8'h03 && fault_level === LV_DEGRADED,
              "F3 首因粘滞：后续故障不覆盖首因码，严重等级升级");

        // F4 media_fatal -> fatal 锁存 + 等级升级
        pulse_mfatal();
        check(fatal === 1'b1 && fault_level === LV_FATAL && fault_code === 8'h03,
              "F4 media_fatal -> fatal=1，等级升级 FATAL（码不覆盖）");

        // F5 FATAL 不可由 recover_ack 清除
        pulse_ra();
        check(fault_valid === 1'b1 && fatal === 1'b1,
              "F5 FATAL 只由全局复位清除：recover_ack 不清");

        // F6 INFO 等级
        do_reset();
        push_err(8'h07, LV_INFO);
        check(fault_valid === 1'b1 && fault_level === LV_INFO,
              "F6 INFO 等级（可选资源缺失）-> level=0 仍置 fault_valid");

        // F7 recover_ack 清除 + 同拍 media_rst_req
        @(negedge clk); recover_ack = 1; @(posedge clk); #1;
        check(fault_valid === 1'b0 && fault_code === 8'h00 && media_rst_req === 1'b1,
              "F7 recover_ack -> 清首因 + 同拍 media_rst_req");
        recover_ack = 0;
        @(posedge clk); #1;
        check(media_rst_req === 1'b0, "F9 media_rst_req 单拍脉冲（只复位媒体链）");

        // F8 看门狗超时路径
        do_reset();
        pulse_wdt(8'h02);
        check(fault_valid === 1'b1 && fault_code === 8'h02 && fault_level === LV_SAFE,
              "F8 看门狗超时 -> 用 wdt_reason 锁存，等级 SAFE");

        // F10 干净态 media_fatal
        do_reset();
        pulse_mfatal();
        check(fault_valid === 1'b1 && fault_level === LV_FATAL && fatal === 1'b1
              && fault_code === 8'h00,
              "F10 干净态 media_fatal -> 等级 FATAL 且 fatal=1");

        // 1000 independent injections, with different event/clear offsets.
        // A harmless first cause must never mask later SAFE/FATAL severity.
        for(trial=0;trial<1000;trial=trial+1)begin
            do_reset();ncyc(trial%7+1);push_err(8'h03,LV_WARNING);first_ts=fault_ts;
            ncyc(trial%5+1);push_err(8'h09,LV_SAFE);
            check(fault_code===8'h03 && fault_level===LV_SAFE && fault_ts===first_ts,
                  "F11 WARNING then SAFE preserves first code/time and escalates");
            @(negedge clk);recover_ack=1;err_push=1;err_code=8'h0f;err_level=LV_FATAL;
            @(posedge clk);#1;
            check(fatal && fault_valid && fault_level===LV_FATAL && fault_code===8'h03 && !media_rst_req,
                  "F12 simultaneous new fatal and clear keeps fatal");
            recover_ack=0;err_push=0;pulse_ra();
            check(fatal && fault_valid,"F13 FATAL ignores subsequent recovery acknowledgement");
            do_reset();push_err(8'h03,LV_WARNING);first_ts=fault_ts;pulse_wdt(8'h02);
            check(fault_code===8'h03 && fault_level===LV_SAFE && fault_ts===first_ts,
                  "F14 watchdog escalation cannot be hidden by warning");
            @(negedge clk);wdt_timeout=1;recover_ack=1;@(posedge clk);#1;
            check(!fault_valid && media_rst_req,"F15 paired watchdog clear has no old-sticky-value deadlock");
            wdt_timeout=0;recover_ack=0;ncyc(1);
        end
        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_fault_manager done, errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000;
        $display("[FAIL] tb_c_fault_manager 看门狗超时");
        $finish;
    end

endmodule
