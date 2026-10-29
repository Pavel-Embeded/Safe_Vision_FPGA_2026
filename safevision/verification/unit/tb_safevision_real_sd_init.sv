`timescale 1ns/1ps
`include "safevision_defs.vh"


module tb_safevision_real_sd_init;
    defparam tb_safevision_card_display.dut.PLAYER_SPI_INIT_DIV = 16'd249;
    integer rises = 0;
    time previous_rise = 0;
    time minimum_period = 64'h7fffffffffffffff;
    time delta;
    always @(posedge tb_safevision_card_display.sd_dclk) begin
        if (tb_safevision_card_display.rst_n &&
            !tb_safevision_card_display.dut.pl_sd_ready) begin
            rises = rises + 1;
            if (previous_rise != 0) begin
                delta = $time - previous_rise;
                if (delta < 10000)
                    $fatal(1,"REAL INIT SCLK too fast: period=%0t",delta);
                if (delta < minimum_period) minimum_period = delta;
            end
            previous_rise = $time;
        end
    end
    initial begin
        if (`SD_TO_RESP != 160000 || `SD_TO_DATA != 10000000 ||
            `SD_TO_ACMD41 != 200000000 || `SD_TO_BUSY != 25000000)
            $fatal(1,"REAL INIT requires product timeout constants");
        if (tb_safevision_card_display.dut.PLAYER_SPI_INIT_DIV != 249)
            $fatal(1,"REAL INIT divider override did not apply");
        wait(tb_safevision_card_display.dut.pl_sd_ready === 1'b1);
        if (rises < 74 || minimum_period != 10000)
            $fatal(1,"REAL INIT clock coverage rises=%0d min=%0t",rises,minimum_period);
        if (tb_safevision_card_display.dut.pl_ec !== 8'h00)
            $fatal(1,"REAL INIT player error ec=%02x",tb_safevision_card_display.dut.pl_ec);
        $display("[PASS] REAL INIT: default divider=249; init SCLK=100kHz; rises=%0d; min_period=%0t; ready_at=%0t; product timeouts",rises,minimum_period,$time);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"REAL INIT watchdog: state=%0d ec=%02x sd_ready=%b",tb_safevision_card_display.dut.pl_state,tb_safevision_card_display.dut.pl_ec,tb_safevision_card_display.dut.pl_sd_ready);
    end
endmodule
