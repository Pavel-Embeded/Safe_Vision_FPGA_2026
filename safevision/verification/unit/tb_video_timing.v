`timescale 1ns/1ps


module tb_video_timing;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    wire [11:0] vga_x, vga_y, hd_x, hd_y, tiny_x, tiny_y;
    wire vga_hs, vga_vs, vga_de, vga_line, vga_frame, vga_active;
    wire vga_hblank, vga_vblank;
    wire hd_hs, hd_vs, hd_de, hd_line, hd_frame, hd_active;
    wire hd_hblank, hd_vblank;
    wire tiny_hs, tiny_vs, tiny_de, tiny_line, tiny_frame, tiny_active;
    wire tiny_hblank, tiny_vblank;

    video_timing u_vga (
        .clk(clk), .rst_n(rst_n), .x(vga_x), .y(vga_y),
        .hsync(vga_hs), .vsync(vga_vs), .de(vga_de),
        .line_start(vga_line), .frame_start(vga_frame),
        .active_frame_start(vga_active),
        .hblank(vga_hblank), .vblank(vga_vblank)
    );

    video_timing #(
        .H_ACTIVE(1280), .H_FRONT(110), .H_SYNC(40), .H_BACK(220),
        .V_ACTIVE(720), .V_FRONT(5), .V_SYNC(5), .V_BACK(20),
        .HSYNC_ACTIVE(1'b1), .VSYNC_ACTIVE(1'b1)
    ) u_hd (
        .clk(clk), .rst_n(rst_n), .x(hd_x), .y(hd_y),
        .hsync(hd_hs), .vsync(hd_vs), .de(hd_de),
        .line_start(hd_line), .frame_start(hd_frame),
        .active_frame_start(hd_active),
        .hblank(hd_hblank), .vblank(hd_vblank)
    );


    video_timing #(
        .H_ACTIVE(3), .H_FRONT(0), .H_SYNC(2), .H_BACK(0),
        .V_ACTIVE(2), .V_FRONT(0), .V_SYNC(1), .V_BACK(0),
        .HSYNC_ACTIVE(1'b1), .VSYNC_ACTIVE(1'b0)
    ) u_tiny (
        .clk(clk), .rst_n(rst_n), .x(tiny_x), .y(tiny_y),
        .hsync(tiny_hs), .vsync(tiny_vs), .de(tiny_de),
        .line_start(tiny_line), .frame_start(tiny_frame),
        .active_frame_start(tiny_active),
        .hblank(tiny_hblank), .vblank(tiny_vblank)
    );

    integer errors = 0;
    integer cycle;
    integer checked_vga = 0;
    integer checked_hd = 0;
    integer checked_tiny = 0;

    task automatic mismatch(input [8*8-1:0] mode_name,
                            input integer tick,
                            input [31:0] got,
                            input [31:0] expected);
        begin begin
            errors = errors + 1;
            $display("FAIL %0s cycle=%0d got=%08h expected=%08h",
                     mode_name, tick, got, expected);
            if (errors >= 8)
                begin $display("[FAIL] Too many video_timing mismatches"); $finish; end 
        end
     end endtask


    task automatic check_vga(input integer tick);
        reg [11:0] ex, ey;
        reg [31:0] got, expected;
        begin begin
            ex = tick % 800;
            ey = (tick / 800) % 525;
            got = {vga_x, vga_y, vga_hs, vga_vs, vga_de,
                   vga_line, vga_frame, vga_active, vga_hblank, vga_vblank};
            expected = {ex, ey,
                        !(ex >= 656 && ex < 752),
                        !(ey >= 490 && ey < 492),
                        (ex < 640 && ey < 480),
                        (ex == 0), (ex == 0 && ey == 480),
                        (ex == 0 && ey == 0),
                        (ex >= 640), (ey >= 480)};
            checked_vga = checked_vga + 1;
            if (got !== expected) mismatch("VGA", tick, got, expected);
        end
     end endtask

    task automatic check_hd(input integer tick);
        reg [11:0] ex, ey;
        reg [31:0] got, expected;
        begin begin
            ex = tick % 1650;
            ey = (tick / 1650) % 750;
            got = {hd_x, hd_y, hd_hs, hd_vs, hd_de,
                   hd_line, hd_frame, hd_active, hd_hblank, hd_vblank};
            expected = {ex, ey,
                        (ex >= 1390 && ex < 1430),
                        (ey >= 725 && ey < 730),
                        (ex < 1280 && ey < 720),
                        (ex == 0), (ex == 0 && ey == 720),
                        (ex == 0 && ey == 0),
                        (ex >= 1280), (ey >= 720)};
            checked_hd = checked_hd + 1;
            if (got !== expected) mismatch("HD720", tick, got, expected);
        end
     end endtask

    task automatic check_tiny(input integer tick);
        reg [11:0] ex, ey;
        reg [31:0] got, expected;
        begin begin
            ex = tick % 5;
            ey = (tick / 5) % 3;
            got = {tiny_x, tiny_y, tiny_hs, tiny_vs, tiny_de,
                   tiny_line, tiny_frame, tiny_active,
                   tiny_hblank, tiny_vblank};
            expected = {ex, ey,
                        (ex >= 3 && ex < 5),
                        !(ey >= 2 && ey < 3),
                        (ex < 3 && ey < 2),
                        (ex == 0), (ex == 0 && ey == 2),
                        (ex == 0 && ey == 0),
                        (ex >= 3), (ey >= 2)};
            checked_tiny = checked_tiny + 1;
            if (got !== expected) mismatch("TINY", tick, got, expected);
        end
     end endtask

    task automatic check_reset;
        begin begin
            if ({vga_x, vga_y, vga_hs, vga_vs, vga_de,
                 vga_line, vga_frame, vga_active,
                 vga_hblank, vga_vblank} !==
                {12'd0, 12'd0, 1'b1, 1'b1, 1'b0,
                 1'b0, 1'b0, 1'b0, 1'b1, 1'b1})
                begin $display("[FAIL] VGA asynchronous reset outputs incorrect"); $finish; end 
            if ({hd_x, hd_y, hd_hs, hd_vs, hd_de,
                 hd_line, hd_frame, hd_active,
                 hd_hblank, hd_vblank} !==
                {12'd0, 12'd0, 1'b0, 1'b0, 1'b0,
                 1'b0, 1'b0, 1'b0, 1'b1, 1'b1})
                begin $display("[FAIL] HD asynchronous reset outputs incorrect"); $finish; end 
            if ({tiny_x, tiny_y, tiny_hs, tiny_vs, tiny_de,
                 tiny_line, tiny_frame, tiny_active,
                 tiny_hblank, tiny_vblank} !==
                {12'd0, 12'd0, 1'b0, 1'b1, 1'b0,
                 1'b0, 1'b0, 1'b0, 1'b1, 1'b1})
                begin $display("[FAIL] Tiny asynchronous reset outputs incorrect"); $finish; end 
        end
     end endtask

    initial begin

        repeat (3) @(negedge clk);
        #1;
        check_reset();
        rst_n = 1'b1;
        #1;


        for (cycle = 0; cycle < 2500; cycle = cycle + 1) begin
            check_vga(cycle);
            check_hd(cycle);
            if (cycle < 60) check_tiny(cycle);
            @(negedge clk);
            #1;
        end
        #1 rst_n = 1'b0;
        #1 check_reset();
        repeat (2) @(negedge clk);
        #1 check_reset();
        rst_n = 1'b1;
        #1;


        for (cycle = 0; cycle < 2*1650*750; cycle = cycle + 1) begin
            check_vga(cycle);
            check_hd(cycle);
            if (cycle < 90) check_tiny(cycle);
            @(negedge clk);
            #1;
        end

        if (errors != 0)
            begin $display("[FAIL] video_timing had %0d mismatches", errors); $finish; end 
        $display("PASS tb_video_timing: VGA=%0d HD720=%0d TINY=%0d checked pixel periods; mid-scan async reset passed",
                 checked_vga, checked_hd, checked_tiny);
        $finish;
    end
endmodule
