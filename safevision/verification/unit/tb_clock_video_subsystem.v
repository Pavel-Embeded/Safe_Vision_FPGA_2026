`timescale 1ns/1ps


module tb_clock_measure #(
    parameter real EXPECT_NS = 10.0,
    parameter integer MODE = 0,
    parameter integer CLOCK_ID = 0,
    parameter real TOLERANCE_NS = 0.010
) (
    input wire clk,
    input wire enabled
);
    integer rises = 0;
    integer falls = 0;
    real last_rise = -1.0;
    real last_fall = -1.0;
    real measured_period = 0.0;
    real measured_high = 0.0;
    real measured_low = 0.0;
    real t;

    function automatic real abs_real(input real x);
        begin abs_real = (x < 0.0)  ?  -x : x;
     end endfunction

    always @(posedge clk or negedge enabled) begin
        if (!enabled) begin
            rises = 0;
            last_rise = -1.0;
            last_fall = -1.0;
            measured_period = 0.0;
        end else begin
            t = $realtime;
            if (last_rise >= 0.0) begin
                measured_period = t - last_rise;
                if (abs_real(measured_period - EXPECT_NS) > TOLERANCE_NS)
                    begin $display("[FAIL] FAIL mode=%0d clock=%0d period=%0.4f expected=%0.4f ns",
                           MODE, CLOCK_ID, measured_period, EXPECT_NS); $finish; end 
            end
            if (last_fall >= 0.0 && abs_real((t - last_fall) - EXPECT_NS/2.0) > TOLERANCE_NS)
                begin $display("[FAIL] FAIL mode=%0d clock=%0d low=%0.4f expected=%0.4f ns",
                       MODE, CLOCK_ID, t-last_fall, EXPECT_NS/2.0); $finish; end 
            if (last_fall >= 0.0) measured_low = t - last_fall;
            last_rise = t;
            rises = rises + 1;
        end
    end

    always @(negedge clk or negedge enabled) begin
        if (!enabled) begin
            falls = 0;
            last_rise = -1.0;
            last_fall = -1.0;
        end else begin
            t = $realtime;
            if (last_rise >= 0.0 && abs_real((t - last_rise) - EXPECT_NS/2.0) > TOLERANCE_NS)
                begin $display("[FAIL] FAIL mode=%0d clock=%0d high=%0.4f expected=%0.4f ns",
                       MODE, CLOCK_ID, t-last_rise, EXPECT_NS/2.0); $finish; end 
            if (last_rise >= 0.0) measured_high = t - last_rise;
            last_fall = t;
            falls = falls + 1;
        end
    end
endmodule

module tb_clock_video_probe #(
    parameter integer MODE = 0,
    parameter integer H_TOTAL = 800,
    parameter integer V_TOTAL = 525,
    parameter real PIXEL_NS = 39.705882353,
    parameter real SERIAL_NS = 7.941176471
) (
    input wire board_clk,
    output reg done );
 initial begin done =  1'b0
; end

    reg board_rst_n = 1'b0;
    reg media_reset_req = 1'b0;
    reg memory_client_reset_req = 1'b0;
    reg hdmi_reinit_req = 1'b0;
    reg audio_reset_req = 1'b0;

    wire sys_clk, mem_clk, pixel_clk, serial_clk, audio_clk;
    wire sys_pll_locked, mem_pll_locked, video_pll_locked, audio_pll_locked;
    wire sys_rst_n, mem_rst_n, pixel_rst_n, serial_rst_n, audio_rst_n;
    wire media_rst_n, memory_client_rst_n, hdmi_pixel_rst_n, hdmi_serial_rst_n;
    wire [11:0] x, y;
    wire hsync, vsync, de, line_start, frame_start, active_frame_start;
    wire hblank, vblank;

    clock_video_subsystem #(.VIDEO_MODE_HD(MODE)) dut (
        .board_clk(board_clk), .board_rst_n(board_rst_n),
        .media_reset_req(media_reset_req),
        .memory_client_reset_req(memory_client_reset_req),
        .hdmi_reinit_req(hdmi_reinit_req),
        .audio_reset_req(audio_reset_req),
        .sys_clk(sys_clk), .mem_clk(mem_clk),
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .audio_clk(audio_clk),
        .sys_pll_locked(sys_pll_locked), .mem_pll_locked(mem_pll_locked),
        .video_pll_locked(video_pll_locked), .audio_pll_locked(audio_pll_locked),
        .sys_rst_n(sys_rst_n), .mem_rst_n(mem_rst_n),
        .pixel_rst_n(pixel_rst_n), .serial_rst_n(serial_rst_n),
        .audio_rst_n(audio_rst_n), .media_rst_n(media_rst_n),
        .memory_client_rst_n(memory_client_rst_n),
        .hdmi_pixel_rst_n(hdmi_pixel_rst_n),
        .hdmi_serial_rst_n(hdmi_serial_rst_n),
        .x(x), .y(y), .hsync(hsync), .vsync(vsync), .de(de),
        .line_start(line_start), .frame_start(frame_start),
        .active_frame_start(active_frame_start),
        .hblank(hblank), .vblank(vblank)
    );

    wire all_locked = sys_pll_locked && mem_pll_locked &&
                      video_pll_locked && audio_pll_locked;
    wire measure_enabled = board_rst_n && all_locked;
    wire [8:0] resets = {sys_rst_n, mem_rst_n, pixel_rst_n,
                         serial_rst_n, audio_rst_n, media_rst_n,
                         memory_client_rst_n, hdmi_pixel_rst_n,
                         hdmi_serial_rst_n};

    tb_clock_measure #(10.0, MODE, 0) u_sys_measure(sys_clk, measure_enabled);
    tb_clock_measure #(8.0, MODE, 1) u_mem_measure(mem_clk, measure_enabled);
    tb_clock_measure #(PIXEL_NS, MODE, 2) u_pixel_measure(pixel_clk, measure_enabled);
    tb_clock_measure #(SERIAL_NS, MODE, 3) u_serial_measure(serial_clk, measure_enabled);
    tb_clock_measure #(81.379310345, MODE, 4) u_audio_measure(audio_clk, measure_enabled);

    function automatic real abs_real(input real v);
        begin abs_real = (v < 0.0)  ?  -v : v;
     end endfunction

    task automatic check(input reg condition, input [8*96-1:0] label);
        begin if (condition !== 1'b1)
            begin $display("[FAIL] FAIL mode=%0d %0s time=%0t", MODE, label, $time); $finish; end 
     end endtask

    task automatic check_all_clocks;
        begin begin
            check(u_sys_measure.rises > 100 && u_mem_measure.rises > 100 &&
                  u_pixel_measure.rises > 100 && u_serial_measure.rises > 100 &&
                  u_audio_measure.rises > 100,
                  "all five TD PLL clocks produced measured cycles");
            check(u_sys_measure.falls > 100 && u_mem_measure.falls > 100 &&
                  u_pixel_measure.falls > 100 && u_serial_measure.falls > 100 &&
                  u_audio_measure.falls > 100,
                  "all five TD PLL clocks produced complete duty cycles");
            check(abs_real(u_pixel_measure.measured_period -
                           5.0*u_serial_measure.measured_period) < 0.005,
                  "pixel and serial periods maintain real five-to-one ratio");
        end
     end endtask


    integer serial_rise_count = 0;
    integer last_pixel_serial_count = -1;
    integer ratio_windows = 0;
    always @(posedge serial_clk or negedge measure_enabled) begin
        if (!measure_enabled) serial_rise_count = 0;
        else serial_rise_count = serial_rise_count + 1;
    end
    always @(posedge pixel_clk or negedge measure_enabled) begin
        if (!measure_enabled) begin
            last_pixel_serial_count = -1;
            ratio_windows = 0;
        end else begin
            #0.001;
            if (last_pixel_serial_count >= 0) begin
                check(serial_rise_count - last_pixel_serial_count == 5,
                      "exactly five serial rising edges in every pixel period");
                ratio_windows = ratio_windows + 1;
            end
            last_pixel_serial_count = serial_rise_count;
        end
    end

    task automatic report_measurements;
        begin begin
            $display("MEASURE mode=%0d sys: period=%0.6f high=%0.6f low=%0.6f ns cycles=%0d", MODE,
                     u_sys_measure.measured_period, u_sys_measure.measured_high,
                     u_sys_measure.measured_low, u_sys_measure.rises);
            $display("MEASURE mode=%0d mem: period=%0.6f high=%0.6f low=%0.6f ns cycles=%0d", MODE,
                     u_mem_measure.measured_period, u_mem_measure.measured_high,
                     u_mem_measure.measured_low, u_mem_measure.rises);
            $display("MEASURE mode=%0d pixel: period=%0.6f high=%0.6f low=%0.6f ns cycles=%0d", MODE,
                     u_pixel_measure.measured_period, u_pixel_measure.measured_high,
                     u_pixel_measure.measured_low, u_pixel_measure.rises);
            $display("MEASURE mode=%0d serial: period=%0.6f high=%0.6f low=%0.6f ns cycles=%0d", MODE,
                     u_serial_measure.measured_period, u_serial_measure.measured_high,
                     u_serial_measure.measured_low, u_serial_measure.rises);
            $display("MEASURE mode=%0d audio: period=%0.6f high=%0.6f low=%0.6f ns cycles=%0d", MODE,
                     u_audio_measure.measured_period, u_audio_measure.measured_high,
                     u_audio_measure.measured_low, u_audio_measure.rises);
            check(ratio_windows > 100, "more than one hundred exact serial/pixel edge-count windows");
            $display("MEASURE mode=%0d serial/pixel: %0d consecutive pixel periods each contained exactly 5 serial rising edges", MODE, ratio_windows);
        end
     end endtask

    integer start_index;
    integer expected_index;
    initial begin
        repeat (10) @(negedge board_clk);
        #1;
        check(resets === 9'b000000000 && x == 0 && y == 0 &&
              de == 0 && line_start == 0 && frame_start == 0,
              "board reset holds all domains and scan in reset");
        board_rst_n = 1'b1;
        wait (all_locked === 1'b1);
        wait (resets === 9'b111111111);
        #10_000;
        check_all_clocks();
        report_measurements();
        check(resets === 9'b111111111,
              "all nine domain resets release after PLL lock");
        check(sys_pll_locked === mem_pll_locked,
              "system and memory use the same PLL lock");

        @(negedge board_clk);
        media_reset_req = 1'b1;
        memory_client_reset_req = 1'b1;
        hdmi_reinit_req = 1'b1;
        audio_reset_req = 1'b1;
        #1;
        check(sys_rst_n && mem_rst_n && pixel_rst_n && serial_rst_n,
              "soft reset preserves four foundational domains");
        check(!media_rst_n && !memory_client_rst_n && !audio_rst_n &&
              !hdmi_pixel_rst_n && !hdmi_serial_rst_n,
              "soft reset asserts only five consumer resets");
        @(posedge pixel_clk);
        #1;
        start_index = y*H_TOTAL + x;
        repeat (100) @(posedge pixel_clk);
        #1;
        expected_index = (start_index + 100) % (H_TOTAL*V_TOTAL);
        check(y*H_TOTAL + x == expected_index && pixel_rst_n,
              "scan advances 100 pixel cycles through local resets");
        @(negedge board_clk);
        media_reset_req = 1'b0;
        memory_client_reset_req = 1'b0;
        hdmi_reinit_req = 1'b0;
        audio_reset_req = 1'b0;
        wait (resets === 9'b111111111);

        @(negedge board_clk) board_rst_n = 1'b0;
        #1;
        check(resets === 9'b000000000 && x == 0 && y == 0 &&
              !de && !frame_start,
              "board reset asynchronously resets all domains and scan");
        repeat (10) @(negedge board_clk);
        board_rst_n = 1'b1;
        wait (all_locked === 1'b1);
        wait (resets === 9'b111111111);
        #10_000;
        check_all_clocks();
        report_measurements();
        check(resets === 9'b111111111 && pixel_rst_n && de,
              "PLL relock restarts all resets and active scan");
        $display("PASS clock_video_probe mode=%0d: five clock periods/duty, 5:1 video, nine resets, soft reset scan, board relock", MODE);
        done = 1'b1;
    end
endmodule

module tb_clock_video_subsystem;
    reg board_clk = 1'b0;
    wire base_done, hd_done;
    always #10 board_clk = ~board_clk;

    tb_clock_video_probe #(
        .MODE(0), .H_TOTAL(800), .V_TOTAL(525),
        .PIXEL_NS(39.705882353), .SERIAL_NS(7.941176471)
    ) u_base (.board_clk(board_clk), .done(base_done));
    tb_clock_video_probe #(
        .MODE(1), .H_TOTAL(1650), .V_TOTAL(750),
        .PIXEL_NS(13.483146067), .SERIAL_NS(2.696629213)
    ) u_hd (.board_clk(board_clk), .done(hd_done));

    initial begin
        wait (base_done && hd_done);
        $display("PASS tb_clock_video_subsystem: BASE and HD both verified with TD EG4 PLL models");
        $finish;
    end
    initial begin
        #200_000;
        begin $display("[FAIL] FAIL clock_video_subsystem watchdog"); $finish; end 
    end
endmodule


