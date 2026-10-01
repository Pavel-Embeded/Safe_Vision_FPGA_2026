// ============================================================================
// tb_clock_reset_ctrl.sv - board clock/reset-domain unit test
// ----------------------------------------------------------------------------
// DUT: platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v
//      platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v
//
// Checks asynchronous assertion, exactly two local rising edges before release,
// independent PLL lock loss, and isolation of each local reset request. The
// clocks intentionally have unrelated periods so a wrong clock-domain hookup
// does not accidentally satisfy the release checks.
//
// Example (Icarus Verilog):
//   iverilog -g2012 -s tb_clock_reset_ctrl -o tb_clock_reset_ctrl.vvp \
//     platform/anlogic_eg4s20_hx4s20c/rtl/clock/reset_sync.v \
//     platform/anlogic_eg4s20_hx4s20c/rtl/clock/clock_reset_ctrl.v \
//     verification/unit/tb_clock_reset_ctrl.sv
//   vvp tb_clock_reset_ctrl.vvp
// ============================================================================
`timescale 1ns / 1ps

module tb_clock_reset_ctrl;

    localparam integer SYS = 0, MEM = 1, PIXEL = 2, SERIAL = 3, AUDIO = 4;
    localparam integer R_SYS = 0, R_MEM = 1, R_PIXEL = 2, R_SERIAL = 3;
    localparam integer R_AUDIO = 4, R_MEDIA = 5, R_MEMORY_CLIENT = 6;
    localparam integer R_HDMI_PIXEL = 7, R_HDMI_SERIAL = 8;

    reg sys_clk = 1'b0;
    reg mem_clk = 1'b0;
    reg pixel_clk = 1'b0;
    reg serial_clk = 1'b0;
    reg audio_clk = 1'b0;
    reg sync_clk = 1'b0;
    always #5  sys_clk = ~sys_clk;
    always #7  mem_clk = ~mem_clk;
    always #13 pixel_clk = ~pixel_clk;
    always #3  serial_clk = ~serial_clk;
    always #11 audio_clk = ~audio_clk;
    always #4  sync_clk = ~sync_clk;

    reg board_rst_n = 1'b0;
    reg sys_pll_locked = 1'b1;
    reg mem_pll_locked = 1'b1;
    reg video_pll_locked = 1'b1;
    reg audio_pll_locked = 1'b1;
    reg media_reset_req = 1'b0;
    reg memory_client_reset_req = 1'b0;
    reg hdmi_reinit_req = 1'b0;
    reg audio_reset_req = 1'b0;

    wire sys_rst_n, mem_rst_n, pixel_rst_n, serial_rst_n, audio_rst_n;
    wire media_rst_n, memory_client_rst_n, hdmi_pixel_rst_n, hdmi_serial_rst_n;
    wire [8:0] resets = {
        hdmi_serial_rst_n, hdmi_pixel_rst_n, memory_client_rst_n,
        media_rst_n, audio_rst_n, serial_rst_n, pixel_rst_n,
        mem_rst_n, sys_rst_n
    };

    clock_reset_ctrl dut (
        .board_rst_n(board_rst_n),
        .sys_clk(sys_clk), .mem_clk(mem_clk), .pixel_clk(pixel_clk),
        .serial_clk(serial_clk), .audio_clk(audio_clk),
        .sys_pll_locked(sys_pll_locked), .mem_pll_locked(mem_pll_locked),
        .video_pll_locked(video_pll_locked), .audio_pll_locked(audio_pll_locked),
        .media_reset_req(media_reset_req),
        .memory_client_reset_req(memory_client_reset_req),
        .hdmi_reinit_req(hdmi_reinit_req), .audio_reset_req(audio_reset_req),
        .sys_rst_n(sys_rst_n), .mem_rst_n(mem_rst_n),
        .pixel_rst_n(pixel_rst_n), .serial_rst_n(serial_rst_n),
        .audio_rst_n(audio_rst_n), .media_rst_n(media_rst_n),
        .memory_client_rst_n(memory_client_rst_n),
        .hdmi_pixel_rst_n(hdmi_pixel_rst_n),
        .hdmi_serial_rst_n(hdmi_serial_rst_n)
    );

    reg sync_async_rst_n = 1'b0;
    wire sync2_rst_n, sync3_rst_n;
    reset_sync #(.STAGES(2)) sync2 (
        .clk(sync_clk), .async_rst_n(sync_async_rst_n), .rst_n(sync2_rst_n)
    );
    reset_sync #(.STAGES(3)) sync3 (
        .clk(sync_clk), .async_rst_n(sync_async_rst_n), .rst_n(sync3_rst_n)
    );

    integer passes = 0;
    integer errors = 0;

    task automatic check;
        input condition;
        input string label;
        begin
            if (condition === 1'b1) begin
                passes = passes + 1;
                $display("[PASS] %0s", label);
            end else begin
                errors = errors + 1;
                $display("[FAIL] %0s at %0t, resets=%09b", label, $time, resets);
            end
        end
    endtask

    function automatic logic reset_at;
        input integer index;
        begin
            case (index)
                R_SYS:           reset_at = sys_rst_n;
                R_MEM:           reset_at = mem_rst_n;
                R_PIXEL:         reset_at = pixel_rst_n;
                R_SERIAL:        reset_at = serial_rst_n;
                R_AUDIO:         reset_at = audio_rst_n;
                R_MEDIA:         reset_at = media_rst_n;
                R_MEMORY_CLIENT: reset_at = memory_client_rst_n;
                R_HDMI_PIXEL:    reset_at = hdmi_pixel_rst_n;
                R_HDMI_SERIAL:   reset_at = hdmi_serial_rst_n;
                default:         reset_at = 1'bx;
            endcase
        end
    endfunction

    task automatic domain_edge;
        input integer domain;
        begin
            case (domain)
                SYS:    @(posedge sys_clk);
                MEM:    @(posedge mem_clk);
                PIXEL:  @(posedge pixel_clk);
                SERIAL: @(posedge serial_clk);
                AUDIO:  @(posedge audio_clk);
                default: $fatal(1, "Invalid clock domain %0d", domain);
            endcase
        end
    endtask

    // Call immediately after releasing the corresponding asynchronous source.
    // The small delay observes nonblocking assignments from the sampled edge.
    task automatic expect_two_edges;
        input integer domain;
        input integer reset_index;
        input string label;
        begin
            domain_edge(domain);
            #0.1;
            check(reset_at(reset_index) === 1'b0,
                  {label, " held through first edge"});
            domain_edge(domain);
            #0.1;
            check(reset_at(reset_index) === 1'b1,
                  {label, " released at second edge"});
        end
    endtask

    task automatic expect_all_two_edges;
        begin
            fork
                expect_two_edges(SYS,    R_SYS,           "sys");
                expect_two_edges(MEM,    R_MEM,           "mem");
                expect_two_edges(PIXEL,  R_PIXEL,         "pixel");
                expect_two_edges(SERIAL, R_SERIAL,        "serial");
                expect_two_edges(AUDIO,  R_AUDIO,         "audio");
                expect_two_edges(SYS,    R_MEDIA,         "media");
                expect_two_edges(MEM,    R_MEMORY_CLIENT, "memory client");
                expect_two_edges(PIXEL,  R_HDMI_PIXEL,    "HDMI pixel");
                expect_two_edges(SERIAL, R_HDMI_SERIAL,   "HDMI serial");
            join
        end
    endtask

    initial begin : stimulus
        // Initial board reset must dominate already locked PLLs.
        #0.5;
        check(resets === 9'b0, "board reset holds all nine outputs low");
        #0.5;
        board_rst_n = 1'b1;
        expect_all_two_edges();
        check(resets === 9'h1ff, "all domains released after board reset");

        // Media restart must not reset its sys clock parent or any other client.
        @(negedge sys_clk); #0.2;
        media_reset_req = 1'b1;
        #0.1;
        check(media_rst_n === 1'b0, "media request asserts asynchronously");
        check((resets & 9'h1df) === 9'h1df,
              "media request leaves all other outputs running");
        @(negedge sys_clk); #0.2;
        media_reset_req = 1'b0;
        expect_two_edges(SYS, R_MEDIA, "media local restart");

        @(negedge mem_clk); #0.2;
        memory_client_reset_req = 1'b1;
        #0.1;
        check(memory_client_rst_n === 1'b0,
              "memory client request asserts asynchronously");
        check((resets & 9'h1bf) === 9'h1bf,
              "memory client request leaves mem controller and other outputs running");
        @(negedge mem_clk); #0.2;
        memory_client_reset_req = 1'b0;
        expect_two_edges(MEM, R_MEMORY_CLIENT, "memory client local restart");

        @(negedge pixel_clk); #0.2;
        hdmi_reinit_req = 1'b1;
        #0.1;
        check(hdmi_pixel_rst_n === 1'b0 && hdmi_serial_rst_n === 1'b0,
              "HDMI reinit asserts both HDMI resets asynchronously");
        check((resets & 9'h07f) === 9'h07f,
              "HDMI reinit leaves video clocks and other outputs running");
        @(negedge pixel_clk); #0.2;
        hdmi_reinit_req = 1'b0;
        fork
            expect_two_edges(PIXEL, R_HDMI_PIXEL, "HDMI pixel local restart");
            expect_two_edges(SERIAL, R_HDMI_SERIAL, "HDMI serial local restart");
        join

        @(negedge audio_clk); #0.2;
        audio_reset_req = 1'b1;
        #0.1;
        check(audio_rst_n === 1'b0, "audio request asserts asynchronously");
        check((resets & 9'h1ef) === 9'h1ef,
              "audio request leaves all other outputs running");
        @(negedge audio_clk); #0.2;
        audio_reset_req = 1'b0;
        expect_two_edges(AUDIO, R_AUDIO, "audio local restart");

        // A lost lock resets only the corresponding clock tree and dependents.
        @(negedge pixel_clk); #0.2;
        video_pll_locked = 1'b0;
        #0.1;
        check(pixel_rst_n === 1'b0 && serial_rst_n === 1'b0 &&
              hdmi_pixel_rst_n === 1'b0 && hdmi_serial_rst_n === 1'b0,
              "video lock loss asserts video/HDMI resets asynchronously");
        check(sys_rst_n && mem_rst_n && audio_rst_n &&
              media_rst_n && memory_client_rst_n,
              "video lock loss is isolated from system, memory, audio");
        @(negedge pixel_clk); #0.2;
        video_pll_locked = 1'b1;
        fork
            expect_two_edges(PIXEL,  R_PIXEL,       "pixel lock recovery");
            expect_two_edges(SERIAL, R_SERIAL,      "serial lock recovery");
            expect_two_edges(PIXEL,  R_HDMI_PIXEL,  "HDMI pixel lock recovery");
            expect_two_edges(SERIAL, R_HDMI_SERIAL, "HDMI serial lock recovery");
        join

        @(negedge mem_clk); #0.2;
        mem_pll_locked = 1'b0;
        #0.1;
        check(mem_rst_n === 1'b0 && memory_client_rst_n === 1'b0,
              "memory lock loss asserts memory resets asynchronously");
        check(sys_rst_n && pixel_rst_n && serial_rst_n && audio_rst_n &&
              media_rst_n && hdmi_pixel_rst_n && hdmi_serial_rst_n,
              "memory lock loss leaves other domains running");
        @(negedge mem_clk); #0.2;
        mem_pll_locked = 1'b1;
        fork
            expect_two_edges(MEM, R_MEM, "memory lock recovery");
            expect_two_edges(MEM, R_MEMORY_CLIENT, "memory client lock recovery");
        join

        @(negedge sys_clk); #0.2;
        sys_pll_locked = 1'b0;
        #0.1;
        check(sys_rst_n === 1'b0 && media_rst_n === 1'b0,
              "system lock loss asserts system/media resets asynchronously");
        check(mem_rst_n && pixel_rst_n && serial_rst_n && audio_rst_n &&
              memory_client_rst_n && hdmi_pixel_rst_n && hdmi_serial_rst_n,
              "system lock loss leaves other domains running");
        @(negedge sys_clk); #0.2;
        sys_pll_locked = 1'b1;
        fork
            expect_two_edges(SYS, R_SYS, "system lock recovery");
            expect_two_edges(SYS, R_MEDIA, "media system-lock recovery");
        join

        @(negedge audio_clk); #0.2;
        audio_pll_locked = 1'b0;
        #0.1;
        check(audio_rst_n === 1'b0, "audio lock loss asserts asynchronously");
        check((resets & 9'h1ef) === 9'h1ef,
              "audio lock loss leaves other domains running");
        @(negedge audio_clk); #0.2;
        audio_pll_locked = 1'b1;
        expect_two_edges(AUDIO, R_AUDIO, "audio lock recovery");

        // Exercise global asynchronous assertion once the whole design is on.
        @(negedge sys_clk); #0.2;
        board_rst_n = 1'b0;
        #0.1;
        check(resets === 9'b0, "board reset reasserts all outputs asynchronously");
        @(negedge sys_clk); #0.2;
        board_rst_n = 1'b1;
        expect_all_two_edges();
        check(resets === 9'h1ff, "all domains recover from board reset");

        // Test reset_sync directly, including its STAGES parameter.
        @(negedge sync_clk); #0.2;
        sync_async_rst_n = 1'b1;
        @(posedge sync_clk); #0.1;
        check(sync2_rst_n === 1'b0 && sync3_rst_n === 1'b0,
              "reset_sync 2/3 stages hold through first edge");
        @(posedge sync_clk); #0.1;
        check(sync2_rst_n === 1'b1 && sync3_rst_n === 1'b0,
              "reset_sync releases two-stage output on edge two");
        @(posedge sync_clk); #0.1;
        check(sync3_rst_n === 1'b1,
              "reset_sync releases three-stage output on edge three");
        @(negedge sync_clk); #0.2;
        sync_async_rst_n = 1'b0;
        #0.1;
        check(sync2_rst_n === 1'b0 && sync3_rst_n === 1'b0,
              "reset_sync asynchronously reasserts both outputs");

        $display("clock/reset checks: %0d pass, %0d fail", passes, errors);
        if (errors != 0) $fatal(1, "tb_clock_reset_ctrl failed");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "tb_clock_reset_ctrl watchdog timeout");
    end

endmodule
