// ============================================================================
// tb_c_priority_arbiter.sv — 优先级仲裁单元验证（手册 8.3）
// ----------------------------------------------------------------------------
// 过关标准（手册 8.3 过关自测「四个输入两两组合全部仿真一遍」）：
//   P1 全 0 -> EV_NONE，valid=0
//   P2 仅 notice -> EV_NOTICE
//   P3 仅 mediaf -> EV_MEDIAFAULT
//   P4 mediaf+notice -> EV_MEDIAFAULT（媒体故障遮住普通提示）
//   P5 仅 fire -> EV_FIRE
//   P6 fire+notice -> EV_FIRE
//   P7 fire+mediaf -> EV_FIRE
//   P8 fire+mediaf+notice -> EV_FIRE
//   P9 ★关键考核点：FIRE 与 SD_ERROR（mediaf）同拍 -> EV_FIRE，屏幕必须火灾疏散，
//      而不是 SD CARD ERROR 提示条
//   P10 事件码稳定：同一输入组合连续多拍读到同一码（无抖动）
// 纯组合逻辑，无需时钟。
// ============================================================================
`timescale 1ns / 1ps

module tb_c_priority_arbiter;

    reg  fire, mediaf, notice;
    wire [1:0] evt_code;
    wire       valid;

    priority_arbiter dut (.fire(fire), .mediaf(mediaf), .notice(notice),
                          .evt_code(evt_code), .valid(valid));

    localparam [1:0] EV_NONE = 2'd0, EV_NOTICE = 2'd1,
                     EV_MEDIAFAULT = 2'd2, EV_FIRE = 2'd3;

    integer errors = 0;
    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) $display("[PASS] %0s", name);
            else begin $display("[FAIL] %0s", name); errors = errors + 1; end
        end
    endtask

    task try;
        input [255:0] name;
        input         exp_valid;
        input [1:0]   exp_code;
        begin
            #1;
            check((valid === exp_valid) && (evt_code === exp_code), name);
        end
    endtask

    integer k;
    initial begin
        fire = 0; mediaf = 0; notice = 0; try("P1 000 -> EV_NONE valid=0", 1'b0, EV_NONE);

        fire = 0; mediaf = 0; notice = 1; try("P2 001 -> EV_NOTICE", 1'b1, EV_NOTICE);
        fire = 0; mediaf = 1; notice = 0; try("P3 010 -> EV_MEDIAFAULT", 1'b1, EV_MEDIAFAULT);
        fire = 0; mediaf = 1; notice = 1; try("P4 011 -> EV_MEDIAFAULT (媒体遮普通)", 1'b1, EV_MEDIAFAULT);
        fire = 1; mediaf = 0; notice = 0; try("P5 100 -> EV_FIRE", 1'b1, EV_FIRE);
        fire = 1; mediaf = 0; notice = 1; try("P6 101 -> EV_FIRE", 1'b1, EV_FIRE);
        fire = 1; mediaf = 1; notice = 0; try("P7 110 -> EV_FIRE (火情遮媒体故障)", 1'b1, EV_FIRE);
        fire = 1; mediaf = 1; notice = 1; try("P8 111 -> EV_FIRE (全同时)", 1'b1, EV_FIRE);

        // P9 关键考核点
        fire = 1; mediaf = 1; notice = 0;
        #1;
        check(evt_code === EV_FIRE,
              "P9 FIRE + SD_ERROR -> EV_FIRE（屏幕火灾疏散，不是 SD 提示条）");

        // P10 稳定性：连续 50 次读同一码
        for (k = 0; k < 50; k = k + 1) begin
            #1;
            if (evt_code !== EV_FIRE) errors = errors + 1;
        end
        check(errors == 0, "P10 同一输入组合下事件码稳定（无抖动）");

        check(errors == 0, "suite 无错误");
        $display("[TB] tb_c_priority_arbiter done, errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("[FAIL] tb_c_priority_arbiter 看门狗超时");
        $finish;
    end

endmodule
