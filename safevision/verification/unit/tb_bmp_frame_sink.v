


`timescale 1ns/1ps
`include "pixel_format_defs.vh"

module tb_bmp_frame_sink;


    localparam integer W = `SV_FRAME_WIDTH;
    localparam integer H = `SV_FRAME_HEIGHT;
    localparam integer PIX = W*H;
    localparam integer WORDS = PIX/2;

    localparam [31:0] SLOT0_WORD = `SV_IMG0_BASE >> 2;
    localparam [31:0] SLOT1_WORD = `SV_IMG1_BASE >> 2;


    localparam [31:0] GAP_TO   = 32'd1_000_000;
    localparam [31:0] WRITE_TO = 32'd20_000;
    localparam [31:0] SWAP_TO  = 32'd3000;


    function [23:0] px24;
        input integer x;
        input integer y;
        reg[7:0] red,green,blue;
        begin begin
            red=x[7:0]^y[7:0];green=x[9:0]+y[9:0];blue=x[9:0]*3;
            px24 = {red,green,blue};
        end
     end endfunction

    function [15:0] px565;
        input integer x;
        input integer y;
        reg [23:0] p;
        begin begin
            p = px24(x, y);
            px565 = { p[23:19], p[15:10], p[7:3] };
        end
     end endfunction


    function [15:0] file_px;
        input integer j;
        input integer td;
        integer x, r, y;
        begin begin
            x = j % W;
            r = j / W;
            y = td  ?  r : (H - 1 - r);
            file_px = px565(x, y);
        end
     end endfunction


    function [15:0] raster_k;
        input integer k;
        begin begin
            raster_k = px565(k % W, k / W);
        end
     end endfunction


    reg clk    = 1'b0;   always #4  clk    = ~clk;
    reg wr_clk = 1'b0;   always #10 wr_clk = ~wr_clk;
    reg rst_n  = 1'b0;

    integer errors = 0;
    task check;
        input        cond;
        input [4095:0] msg;
        begin begin
            if (cond) $display("[PASS] %s", msg);
            else begin $display("[FAIL] %s", msg); errors = errors + 1; end
        end
     end endtask


    wire [31:0] px_word;
    wire        px_word_valid;
    wire        px_word_ready;
    reg         frame_active, top_down;
    reg  [1:0]  slot;

    wire        mem_ready, frame_done, last_frame_ok;

    wire        wr_req;
    wire [31:0] wr_addr, wr_data;
    wire [15:0] wr_len;
    reg         wr_ready;
    wire        swap_toggle, swap_crc_ok;
    wire [1:0]  swap_slot;
    wire [7:0]  swap_generation;
    reg         swap_busy;
    wire [3:0]  state_o;
    wire [7:0]  err_code, err_detail;
    wire [15:0] frame_cnt;
    wire [18:0] px_written;

    bmp_frame_sink #(
        .GAP_TIMEOUT (GAP_TO),
        .SWAP_TO_N   (SWAP_TO),
        .WRITE_TO_N  (WRITE_TO)
    ) dut (
        .clk(clk), .rst_n(rst_n), .wr_clk(wr_clk),
        .px_word(px_word), .px_word_valid(px_word_valid), .px_word_ready(px_word_ready),
        .frame_active(frame_active), .top_down(top_down), .slot(slot),
        .mem_ready(mem_ready), .frame_done(frame_done), .last_frame_ok(last_frame_ok),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ready),
        .swap_toggle(swap_toggle), .swap_slot(swap_slot),
        .swap_generation(swap_generation), .swap_crc_ok(swap_crc_ok),
        .swap_busy(swap_busy),
        .state_o(state_o), .err_code(err_code), .err_detail(err_detail),
        .frame_cnt(frame_cnt), .px_written(px_written)
    );

    localparam [3:0] S_DRAIN = 4'd0, S_WRITE = 4'd1, S_SWAP = 4'd2, S_ERROR = 4'd3;


    localparam integer MEM_WORDS = 1024*1024;
    reg [31:0] mem [0:MEM_WORDS-1];
    reg [4:0]  stall = 5'd0;
    always @(posedge clk) stall <= stall + 5'd1;
    always @(*) wr_ready = (stall != 5'd31);

    always @(posedge clk) begin
        if (wr_req && wr_ready) mem[wr_addr[21:2]] <= wr_data;
    end


    integer swap_mode = 0;
    reg        sw_d = 1'b0;
    reg [7:0]  sw_cnt = 8'd0;
    always @(posedge clk) begin
        if (swap_mode == 1) begin
            swap_busy <= 1'b1;
        end else if (swap_mode == 2) begin
            swap_busy <= 1'b0;
        end else begin
            sw_d <= swap_toggle;
            if (swap_toggle != sw_d) sw_cnt <= 8'd40;
            else if (sw_cnt != 8'd0) sw_cnt <= sw_cnt - 8'd1;
            swap_busy <= (sw_cnt != 8'd0);
        end
    end


    task cmp_frame;
        input [31:0] base_word;
        input [4095:0] label;
        integer n, b;
        reg [31:0] got, exp;
        begin begin
            b = 0;
            for (n = 0; n < WORDS; n = n + 1) begin
                got = mem[base_word + n];
                exp = { raster_k(2*n+1), raster_k(2*n) };
                if (got !== exp) begin
                    if (b == 0)
                        $display("       first mismatch word=%0d addr=0x%08x got=%08x exp=%08x",
                                 n, (base_word+n)<<2, got, exp);
                    b = b + 1;
                end
            end
            if (b == 0) $display("[PASS] %s : %0d words pixel-exact", label, WORDS);
            else begin
                $display("[FAIL] %s : %0d / %0d words differ", label, b, WORDS);
                errors = errors + 1;
            end
        end
     end endtask


    reg  [31:0] feed_word;
    reg         feed_valid;
    integer     feed_idx = 0, feed_total = 0, feed_td = 0, feed_mode = 0, pushed = 0;
    reg         feed_run = 1'b0;

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            feed_valid <= 1'b0; feed_run <= 1'b0; feed_idx <= 0;
        end else begin
            if (feed_valid && px_word_ready) feed_valid <= 1'b0;
            if (feed_run && !feed_valid && feed_idx < feed_total) begin
                feed_word  <= (feed_mode == 0)
                               ?  { file_px(2*feed_idx+1, feed_td), file_px(2*feed_idx, feed_td) }
                              : ((feed_idx == 0)  ?  32'hDEAD_BEEF : 32'h1234_5678);
                feed_valid <= 1'b1;
                feed_idx   <= feed_idx + 1;
                pushed     <= pushed + 1;
                if (feed_idx + 1 == feed_total) feed_run <= 1'b0;
            end
        end
    end
    assign px_word       = feed_word;
    assign px_word_valid = feed_valid;

    task start_feed;
        input integer n;
        input integer td;
        begin begin
            feed_idx = 0; feed_total = n; feed_td = td; feed_run = 1'b1;
        end
     end endtask

    task wait_feed_done;
        begin begin
            while (!(feed_idx == feed_total && !feed_valid)) @(posedge wr_clk);
        end
     end endtask


    task feed_frame;
        input integer npx;
        input integer td;
        begin begin
            feed_mode = 0;
            start_feed(npx, td);
            wait_feed_done();
        end
     end endtask


    integer fd_seen;
    reg     fd_d = 1'b0;
    task wait_frame_done;
        input integer limit;
        integer g;
        begin begin
            g = 0; fd_seen = 0;
            while (g < limit) begin
                @(posedge clk);
                if (frame_done != fd_d) begin fd_d = frame_done; fd_seen = 1; g = limit; end
                else g = g + 1;
            end
        end
     end endtask


    task wait_ready;
        input integer limit;
        integer g;
        begin begin
            g = 0;
            while (!mem_ready && g < limit) begin @(posedge clk); g = g + 1; end
        end
     end endtask


    reg t6_arm = 1'b0, t6_low = 1'b0;
    always @(posedge clk) if (t6_arm && !mem_ready) t6_low <= 1'b1;


    integer guard;
    initial begin
        frame_active = 1'b0; top_down = 1'b0; slot = 2'd1;
        swap_busy = 1'b0; swap_mode = 0;

        repeat (20) @(posedge wr_clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);


        $display("[TB] T6: stray words while idle must be drained before mem_ready");
        t6_arm = 1'b1; t6_low = 1'b0;
        feed_mode = 1; start_feed(2, 0); wait_feed_done();
        repeat (30) @(posedge clk);
        t6_arm = 1'b0;
        check(t6_low == 1'b1, "T6a) mem_ready dropped while the FIFO held stray words");
        wait_ready(20000);
        check(mem_ready === 1'b1, "T6b) mem_ready re-asserts after the FIFO is drained");
        check(mem[`SV_IMG0_BASE>>2] !== 32'hDEAD_BEEF,
              "T6c) stray words were drained, not written into a slot");
        check(state_o === S_DRAIN, "T6d) sink is in S_DRAIN after draining");


        $display("[TB] T1: normal frame, top_down=0 -> slot 1 (pixel-exact)");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T1a) frame_done toggled for frame 1");
        check(frame_cnt === 16'd1, "T1b) frame_cnt == 1");
        check(px_written === 19'd307200, "T1c) exactly 307200 pixels written by the bridge");
        check(swap_slot === 2'd1, "T1d) swap request carried slot 1");
        check(swap_crc_ok === 1'b1, "T1e) swap request carried crc_ok=1");
        check(last_frame_ok === 1'b1, "T1f) last_frame_ok = 1");
        check(err_code === 8'h00, "T1g) no error code after a good frame");
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T1h) back to S_DRAIN with mem_ready=1");
        cmp_frame(SLOT1_WORD, "T1i) slot 1 content (frame 1, top_down=0)");


        $display("[TB] T2: next frame with top_down=1 -> slot 0 (catches stale orientation)");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b1; slot <= 2'd0; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 1);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T2a) frame_done toggled for frame 2");
        check(frame_cnt === 16'd2, "T2b) frame_cnt == 2");
        check(swap_slot === 2'd0, "T2c) swap request carried slot 0");
        check(swap_generation === 8'd3, "T2d) swap_generation incremented twice (now 3)");
        wait_ready(20000);
        cmp_frame(SLOT0_WORD, "T2e) slot 0 content (frame 2, top_down=1)");


        $display("[TB] T3: swap_busy stuck HIGH must still time out (liveness)");
        wait_ready(20000);
        swap_mode = 1;
        swap_busy = 1'b1;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(SWAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T3a) frame_done still toggled while swap_busy stayed high");
        swap_mode = 0; swap_busy = 1'b0;
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T3b) recovered to S_DRAIN with mem_ready=1");


        $display("[TB] T4: swap_busy never asserts must still time out");
        wait_ready(20000);
        swap_mode = 2;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd0; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(SWAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T4a) frame_done toggled although swap_busy never asserted");
        swap_mode = 0;
        wait_ready(20000);
        check(state_o === S_DRAIN && mem_ready === 1'b1, "T4b) recovered to S_DRAIN with mem_ready=1");


        $display("[TB] T5: starve the frame -> S_WRITE no-progress timeout -> S_ERROR, sticky err_code");
        wait_ready(20000);
        swap_mode = 0;
        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);

        guard = 0;
        while (state_o !== S_ERROR && guard < 200000) begin @(posedge clk); guard = guard + 1; end
        check(state_o === S_ERROR, "T5a) sink entered S_ERROR on frame stall");
        check(err_code !== 8'h00, "T5b) sink latched a non-zero err_code");
        wait_frame_done(GAP_TO + 200000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T5c) frame_done toggled from S_ERROR (SD side can advance)");
        wait_ready(20000);
        check(state_o === S_DRAIN, "T5d) sink returned to S_DRAIN after the error");

        check(err_code !== 8'h00, "T5e) err_code is STICKY after leaving S_ERROR");


        @(posedge wr_clk);
        top_down <= 1'b0; slot <= 2'd1; frame_active <= 1'b1;
        @(posedge wr_clk);
        feed_frame(PIX, 0);
        wait_frame_done(4000000);
        @(posedge wr_clk);
        frame_active <= 1'b0;
        check(fd_seen == 1, "T5f) a subsequent good frame completes");
        check(err_code === 8'h00, "T5g) sticky err_code cleared by a successful frame");

        $display("============================================");
        if (errors == 0) $display("  BMP-FRAME-SINK PASS (0 error)");
        else             $display("  BMP-FRAME-SINK FAIL (%0d error)", errors);
        $display("============================================");
        $finish;
    end


    integer wd;
    initial begin
        wd = 0;
        while (wd < 60_000_000) begin @(posedge clk); wd = wd + 1; end
        $display("[FAIL] watchdog: state=%0d err=0x%02x/0x%02x cnt=%0d px=%0d",
                 state_o, err_code, err_detail, frame_cnt, px_written);
        $display("  BMP-FRAME-SINK FAIL (watchdog)");
        $finish;
    end

endmodule
