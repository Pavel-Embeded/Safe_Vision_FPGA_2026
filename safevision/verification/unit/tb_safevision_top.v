


`timescale 1ns/1ps

module tb_safevision_top;


    reg clk   = 1'b0;   always #10 clk = ~clk;
    reg rst_n = 1'b0;

    integer errors = 0;
    task check;
        input        cond;
        input [4095:0] msg;
        begin
            if (cond) $display("[PASS] %s", msg);
            else begin $display("[FAIL] %s", msg); errors = errors + 1; end

     end endtask


    reg  btn_next = 1'b1, btn_auto = 1'b1;
    wire uart_txd;
    wire [3:0] led;
    wire sd_ncs, sd_dclk, sd_mosi, sd_miso;
    wire HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P, HDMI_DDC_SCL;
    wire HDMI_DDC_SDA;


    safevision_top #(.STORAGE_INTEGRITY(0),
        .HD(0),
        .MODE_TO_N(32'd200_000),
        .RPT_PERIOD_N(32'd150_000),
        .FONT_FILE("font8x16.mem")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .btn_next(btn_next), .btn_auto(btn_auto),.btn_emergency(1'b1),
        .uart_txd(uart_txd), .led(led),
        .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .HDMI_D0_P(HDMI_D0_P), .HDMI_D1_P(HDMI_D1_P), .HDMI_D2_P(HDMI_D2_P),
        .HDMI_CLK_P(HDMI_CLK_P),
        .HDMI_DDC_SCL(HDMI_DDC_SCL), .HDMI_DDC_SDA(HDMI_DDC_SDA)
    );


    wire [5:0]  o_cmd;
    wire [31:0] o_arg, o_acmd41_arg;
    wire [7:0]  o_cmd_cnt, o_acmd41_cnt;
    wire        o_cmd_valid;
    sd_spi_card_model #(.VOL_BASE(32'd16), .VOL_SECTORS(2048)) u_card (
        .sclk(sd_dclk), .cs_n(sd_ncs), .mosi(sd_mosi), .miso(sd_miso),
        .i_dead(1'b1),
        .o_cmd(o_cmd), .o_arg(o_arg), .o_acmd41_arg(o_acmd41_arg),
        .o_cmd_cnt(o_cmd_cnt), .o_acmd41_cnt(o_acmd41_cnt), .o_cmd_valid(o_cmd_valid)
    );


    localparam integer BIT_TICKS = 40_000_000 / 115_200;

    task uart_get_byte;
        output [7:0] b;
        output       ok;
        integer i;
        begin
            ok = 1'b0; b = 8'h00;
            @(negedge uart_txd);
            repeat (BIT_TICKS/2) @(posedge dut.mem_clk);
            if (uart_txd !== 1'b0) ok = 1'b0;
            else begin
                for (i = 0; i < 8; i = i + 1) begin
                    repeat (BIT_TICKS) @(posedge dut.mem_clk);
                    b[i] = uart_txd;
                end
                repeat (BIT_TICKS) @(posedge dut.mem_clk);
                ok = 1'b1;
            end

     end endtask


    reg [7:0] line [0:255];
    integer   line_len;
    task uart_get_line;
        integer n; reg [7:0] b; reg ok;
        begin
            line_len = 0;

            for (n = 0; n < 400; n = n + 1) begin
                uart_get_byte(b, ok);
                if (ok && b == 8'h53) begin
                    uart_get_byte(line[1], ok);
                    if (ok && line[1] == 8'h56) begin
                        line[0] = 8'h53; line_len = 2;

                        for (n = 2; n < 200; n = n + 1) begin
                            uart_get_byte(line[n], ok);
                            if (!ok) begin n = 200; end
                            else begin
                                line_len = line_len + 1;
                                if (line[n] == 8'h0A) n = 200;
                            end
                        end
                        n = 400;
                    end
                end
            end

     end endtask


    function integer find_str;
        input [8*8-1:0] pat;
        input integer   plen;
        integer i, j, hit;
        begin
            find_str = -1;
            for (i = 0; i <= line_len - plen; i = i + 1) begin
                hit = 1;
                for (j = 0; j < plen; j = j + 1)
                    if (line[i+j] !== pat[(plen-1-j)*8 +: 8]) hit = 0;
                if (hit && find_str < 0) find_str = i;
            end

     end endfunction

    function [3:0] hexval;
        input [7:0] c;
        begin
            if (c >= 8'h30 && c <= 8'h39) hexval = c - 8'h30;
            else if (c >= 8'h41 && c <= 8'h46) hexval = c - 8'h37;
            else hexval = 4'hF;

     end endfunction


    reg saw_next_pulse = 1'b0;
    reg saw_auto_hold  = 1'b0;
    always @(posedge clk) begin
        if (dut.btn_next_db) saw_next_pulse <= 1'b1;
        if (dut.btn_auto_db) saw_auto_hold  <= 1'b1;
    end


    integer fr_pulses = 0;
    always @(posedge dut.sys_clk) if (dut.frame_ready) fr_pulses <= fr_pulses + 1;


    integer vs_pulses = 0;
    reg pending_seen = 1'b0;
    always @(posedge dut.pixel_clk) begin
        if (dut.core.display.scan_frame_start) vs_pulses <= vs_pulses + 1;
        if (dut.core.display.slot.pending) pending_seen <= 1'b1;
    end


    localparam [3:0] T8_S_INIT  = 4'd1;
    localparam [3:0] T8_S_INITR = 4'd11;
    integer t8_retries = 0;
    integer t8_bad_arm = 0;
    reg     t8_prev_initr = 1'b0;
    always @(posedge dut.player.clk) begin
        t8_prev_initr <= (dut.player.state_o == T8_S_INITR);
        if (t8_prev_initr && (dut.player.state_o == T8_S_INIT)) begin
            t8_retries = t8_retries + 1;
            if (dut.player.init_arm !== 3'd0) t8_bad_arm = t8_bad_arm + 1;
        end
    end


    integer guard;
    reg [7:0] b; reg ok;
    initial begin
        btn_next = 1'b1; btn_auto = 1'b1;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);


        $display("[TB] T1: reset -> PLL lock + SDRAM init (led[0])");
        guard = 0;
        while (!led[0] && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(led[0] === 1'b1, "T1a) led[0]=1 (sys/video PLL locked + SDRAM init done)");


        $display("[TB] T2: UART status line format + fields (card unusable)");
        uart_get_line;
        check(line_len == 107, "T2a) status line is exactly 107 bytes");
        check(line[105] == 8'h0D && line[106] == 8'h0A, "T2b) status line ends with CRLF");
        check(find_str("SV-PLAY", 7) == 0, "T2c) status line starts with 'SV-PLAY'");
        check(find_str(" ST=", 4) > 0, "T2d) status line has ' ST=' field");
        check(find_str(" SD=", 4) > 0, "T2e) status line has ' SD=' field");
        check(find_str(" CARD=", 6) > 0, "T2f) status line has ' CARD=' field");
        check(find_str(" RD=", 4) > 0, "T2g) status line has ' RD=' field");
        check(find_str(" PX=", 4) > 0, "T2h) status line has ' PX=' field (from sink)");
        check(find_str(" F=", 3) > 0, "T2i) status line has ' F=' field (from sink)");
        check(find_str(" SLOT=", 6) > 0, "T2j) status line has ' SLOT=' field (from sink)");
        check(find_str(" CRC=", 5) > 0, "T2k) status line has ' CRC=' field (from sink)");
        check(find_str(" ED=", 4) > 0, "T2l) status line has ' ED=' field (err_detail)");


        begin : v_local_1
            integer ed_i;
            reg [7:0] e0, e1;
            ed_i = find_str(" ED=", 4);
            e0 = line[ed_i+4]; e1 = line[ed_i+5];
            check(((e0 >= 8'h30 && e0 <= 8'h39) || (e0 >= 8'h41 && e0 <= 8'h46)) &&
                  ((e1 >= 8'h30 && e1 <= 8'h39) || (e1 >= 8'h41 && e1 <= 8'h46)),
                  "T2m) ED= field carries two hex digits");
        end


        check(find_str(" R1=", 4) > 0, "T2n) status line has ' R1=' field (SD R1 byte)");
        check(find_str(" SQ=", 4) > 0, "T2o) status line has ' SQ=' field (SD command index)");

        begin : v_local_2
            integer i, sd_i, cd_i;
            sd_i = find_str(" SD=", 4);
            cd_i = find_str(" CARD=", 6);
            check(line[sd_i+4] === 8'h30, "T3a) SD=0 with an unusable card");
            check(line[cd_i+6] === 8'h30, "T3b) CARD=0 with an unusable card");
        end


        force dut.integrity_bad_addr=32'h12345678;
        force dut.integrity_expected=32'h89abcdef;
        force dut.integrity_actual=32'h76543210;
        uart_get_line;
        check(line_len==82 && line[80]==8'h0D && line[81]==8'h0A,"UART integrity line has 82 bytes and CRLF");
        check(find_str("SV-MEM",6)==0 && find_str("26101002",8)==10,"UART carries exact integrity build ID");
        check(find_str(" PH=0",5)==18,"UART snapshot phase matches packet start");
        check(find_str(" BAD=",5)==23 && line[28]==8'h30 && line[35]==8'h30,"UART bad address retains packet snapshot");
        check(find_str(" EXP=",5)==36 && line[41]==8'h30 && line[48]==8'h30,"UART expected CRC retains packet snapshot");
        check(find_str(" GOT=",5)==49 && line[54]==8'h30 && line[61]==8'h30,"UART actual CRC retains packet snapshot");
        release dut.integrity_bad_addr;release dut.integrity_expected;release dut.integrity_actual;


        $display("[TB] T4: fallback takes over when the card never becomes usable");
        guard = 0;
        while (dut.card_mode !== 1'b0 && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.card_mode === 1'b0, "T4a) card_mode fell back to 0 (card unusable)");
        guard = 0;
        while (!dut.fb_submitted && guard < 8_000_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.fb_submitted === 1'b1, "T4b) fallback pattern was written and submitted");

        check(led[1] === 1'b1, "T4c) led[1]=1 (fallback frame available + CRC ok)");


        guard=0;
        while(fr_pulses<1 && guard<100)begin @(posedge dut.sys_clk);guard=guard+1;end
        check(fr_pulses >= 1, "T4d) fallback swap event reached the core sys domain");
        check(dut.player.frame_cnt === 16'd0, "T4e) card path never produced a frame (frame_cnt=0)");


        $display("[TB] T5: HDMI AXI-Stream is alive");
        check(dut.transmitter.O_video_locked === 1'b1, "T5a) transmitter reports video_locked");
        check(dut.transmitter.axis_beats > 1000,
              "T5b) HDMI AXI-Stream beats are flowing (display chain alive)");
        check(dut.transmitter.axis_lasts > 10,
              "T5c) line 'last' beats are flowing (timing generator alive)");
        check(dut.hdmi_backpressure === 1'b0, "T5d) no HDMI backpressure fault latched");


        $display("[TB] T6: button debounce runs in the player's 50 MHz domain");
        check(dut.btn_next_db === 1'b0, "T6a) next-button idle low (released != pressed)");
        check(dut.btn_auto_db === 1'b0, "T6b) auto-play idle low");

        @(posedge clk); btn_next = 1'b0; btn_auto = 1'b0;

        guard = 0;
        while (!dut.dn_db && guard < 200_000) begin @(posedge clk); guard = guard + 1; end
        check(dut.dn_db === 1'b1, "T6c) debounced press level asserted");
        check(guard > 60_000,
              "T6d) debounce took ~65536 clk cycles (it really runs on the 50 MHz domain)");

        repeat (4) @(posedge clk);
        check(saw_next_pulse === 1'b1, "T6e) next-button produced a press pulse");
        check(saw_auto_hold  === 1'b1, "T6f) auto-play produced a held level");

        repeat (2000) @(posedge clk);
        check(dut.btn_next_db === 1'b0,
              "T6g) next-button stays low while held (one-shot pulse, not a level)");
        check(dut.btn_auto_db === 1'b1, "T6h) auto-play stays high while held (level)");
        @(posedge clk); btn_next = 1'b1; btn_auto = 1'b1;


        $display("[TB] T7: swap commit reaches the display (pending -> active)");
        guard = 0;
        while (dut.active !== 1'b1 && guard < 2_000_000) begin @(posedge clk); guard = guard + 1; end
        check(pending_seen === 1'b1, "T7a) swap request reached pixel-domain commit (pending set)");
        check(dut.active === 1'b1, "T7b) display activated (active=1) within 2 video frames");
        check(led[2] === 1'b1, "T7c) led[2]=1 (picture active, no swap error)");
        $display("[TB] T7 info: active=%b after %0d clk (vs_pulses=%0d swap_error=%b frame_fault=%b)",
                 dut.active, guard, vs_pulses, dut.swap_error, dut.frame_fault);


        $display("[TB] T8: SD init auto-retry settle window (defect 26)");
        $display("[TB] T8 info: retries seen=%0d, bad init_arm on entry=%0d",
                 t8_retries, t8_bad_arm);
        check(t8_retries > 0, "T8a) SD init failure did go through the auto-retry path");
        check(t8_bad_arm == 0, "T8b) init_arm was cleared on every retry entry (defect 26)");

        $display("============================================");
        if (errors == 0) $display("  SAFEVISION-TOP PASS (0 error)");
        else             $display("  SAFEVISION-TOP FAIL (%0d error)", errors);
        $display("============================================");
        $finish;
    end


    integer wd;
    initial begin
        wd = 0;
        while (wd < 60_000_000) begin @(posedge clk); wd = wd + 1; end
        $display("[FAIL] watchdog: card_mode=%b fb_submitted=%b pl_state=%0d pl_ec=0x%02x led=%b",
                 dut.card_mode, dut.fb_submitted, dut.pl_state, dut.pl_ec, led);
        $display("  SAFEVISION-TOP FAIL (watchdog)");
        $finish;
    end

endmodule
