`timescale 1ns/1ps


module vp_latency_checker #(
    parameter integer PW=24, XW=12, L=1, CHAIN=0, ID=0,
    parameter HS=1'b0, VS=1'b0
)(input wire clk, input wire rst_n, output reg done=0,
  output integer checks=0);
    localparam integer W=PW+2*XW+9;
    localparam [W-1:0] EMPTY={{PW{1'b0}},{XW{1'b0}},{XW{1'b0}},
                             ~HS,~VS,5'b00000,2'b11};
    reg [W-1:0] stimulus=0;
    wire [W-1:0] actual;
    generate if (CHAIN) begin : chain
        wire [W-1:0] first, second;
        video_pipeline #(.PIXEL_WIDTH(PW), .XY_WIDTH(XW), .LATENCY(1),
        .HSYNC_ACTIVE(HS), .VSYNC_ACTIVE(VS)) a (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(stimulus[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_in(stimulus[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(stimulus[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(stimulus[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(stimulus[1 + 1 + 1 +: 1]),
        .active_frame_start_in(stimulus[1 + 1 +: 1]),
        .hblank_in(stimulus[1 +: 1]),
        .vblank_in(stimulus[0 +: 1]),
        .pixel_out(first[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_out(first[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_out(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_out(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_out(first[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_out(first[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_out(first[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_out(first[1 + 1 + 1 + 1 +: 1]),
        .frame_start_out(first[1 + 1 + 1 +: 1]),
        .active_frame_start_out(first[1 + 1 +: 1]),
        .hblank_out(first[1 +: 1]),
        .vblank_out(first[0 +: 1])
    );
        video_pipeline #(.PIXEL_WIDTH(PW), .XY_WIDTH(XW), .LATENCY(2),
        .HSYNC_ACTIVE(HS), .VSYNC_ACTIVE(VS)) b (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(first[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_in(first[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(first[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(first[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(first[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(first[1 + 1 + 1 +: 1]),
        .active_frame_start_in(first[1 + 1 +: 1]),
        .hblank_in(first[1 +: 1]),
        .vblank_in(first[0 +: 1]),
        .pixel_out(second[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_out(second[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_out(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_out(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_out(second[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_out(second[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_out(second[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_out(second[1 + 1 + 1 + 1 +: 1]),
        .frame_start_out(second[1 + 1 + 1 +: 1]),
        .active_frame_start_out(second[1 + 1 +: 1]),
        .hblank_out(second[1 +: 1]),
        .vblank_out(second[0 +: 1])
    );
        video_pipeline #(.PIXEL_WIDTH(PW), .XY_WIDTH(XW), .LATENCY(1),
        .HSYNC_ACTIVE(HS), .VSYNC_ACTIVE(VS)) c (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(second[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_in(second[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(second[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(second[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(second[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(second[1 + 1 + 1 +: 1]),
        .active_frame_start_in(second[1 + 1 +: 1]),
        .hblank_in(second[1 +: 1]),
        .vblank_in(second[0 +: 1]),
        .pixel_out(actual[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_out(actual[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_out(actual[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_out(actual[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_out(actual[1 + 1 + 1 + 1 +: 1]),
        .frame_start_out(actual[1 + 1 + 1 +: 1]),
        .active_frame_start_out(actual[1 + 1 +: 1]),
        .hblank_out(actual[1 +: 1]),
        .vblank_out(actual[0 +: 1])
    );
    end else begin : direct
        video_pipeline #(.PIXEL_WIDTH(PW), .XY_WIDTH(XW), .LATENCY(L),
        .HSYNC_ACTIVE(HS), .VSYNC_ACTIVE(VS)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(stimulus[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_in(stimulus[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(stimulus[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(stimulus[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(stimulus[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(stimulus[1 + 1 + 1 +: 1]),
        .active_frame_start_in(stimulus[1 + 1 +: 1]),
        .hblank_in(stimulus[1 +: 1]),
        .vblank_in(stimulus[0 +: 1]),
        .pixel_out(actual[XW + XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: PW]),
        .x_out(actual[XW + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .y_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: XW]),
        .hsync_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_out(actual[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_out(actual[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_out(actual[1 + 1 + 1 + 1 +: 1]),
        .frame_start_out(actual[1 + 1 + 1 +: 1]),
        .active_frame_start_out(actual[1 + 1 +: 1]),
        .hblank_out(actual[1 +: 1]),
        .vblank_out(actual[0 +: 1])
    );
    end endgenerate
    reg [W-1:0] history [0:8191];
    reg [W-1:0] expected;
    reg [31:0] rng=32'h971adc51 ^ ID;
    integer n=0, drive=0, j;
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};


        if (drive < W) stimulus = {{(W-1){1'b0}},1'b1} << drive;
        else if (drive < 2*W) stimulus = ~({{(W-1){1'b0}},1'b1} << (drive-W));
        else for (j=0;j<W;j=j+1) stimulus[j]=rng[(j+drive)%32];
        drive=drive+1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n=0;
            expected=EMPTY;
            #1;
            if (actual !== EMPTY) $fatal(1,"checker %0d asynchronous reset got %h expected %h",ID,actual,EMPTY);
            checks=checks+1;
        end else if (!done) begin
            history[n]=stimulus;
            if (L==0) expected=stimulus;
            else if (n >= L-1) expected=history[n-L+1];
            else expected=EMPTY;
            #1;
            if (actual !== expected) $fatal(1,"checker %0d latency %0d sample %0d got %h expected %h",ID,L,n,actual,expected);
            checks=checks+1;
            n=n+1;
            if (drive > 2500 && n > 100) done=1;
        end
    end

    generate if (L==0 && !CHAIN) begin : bypass_check
        always @(stimulus) begin
            #1;
            if (actual !== (rst_n ? stimulus : EMPTY))
                $fatal(1,"checker %0d zero-latency bypass failed", ID);
            checks=checks+1;
        end
    end endgenerate
endmodule

module tb_video_pipeline;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    wire [8:0] done;
    wire [31:0] checks[0:8];
    vp_latency_checker #(.PW(24),.XW(12),.L(0),.CHAIN(0),.ID(0),.HS(1'b0),.VS(1'b0)) c0(clk,rst_n,done[0],checks[0]);
    vp_latency_checker #(.PW(24),.XW(12),.L(1),.CHAIN(0),.ID(1),.HS(1'b0),.VS(1'b0)) c1(clk,rst_n,done[1],checks[1]);
    vp_latency_checker #(.PW(24),.XW(12),.L(2),.CHAIN(0),.ID(2),.HS(1'b1),.VS(1'b1)) c2(clk,rst_n,done[2],checks[2]);
    vp_latency_checker #(.PW(24),.XW(12),.L(4),.CHAIN(0),.ID(3),.HS(1'b0),.VS(1'b1)) c3(clk,rst_n,done[3],checks[3]);
    vp_latency_checker #(.PW(24),.XW(12),.L(7),.CHAIN(0),.ID(4),.HS(1'b1),.VS(1'b0)) c4(clk,rst_n,done[4],checks[4]);
    vp_latency_checker #(.PW(16),.XW(10),.L(4),.CHAIN(0),.ID(5),.HS(1'b0),.VS(1'b0)) c5(clk,rst_n,done[5],checks[5]);
    vp_latency_checker #(.PW(1),.XW(1),.L(31),.CHAIN(0),.ID(6),.HS(1'b1),.VS(1'b1)) c6(clk,rst_n,done[6],checks[6]);
    vp_latency_checker #(.PW(24),.XW(12),.L(4),.CHAIN(1),.ID(7),.HS(1'b0),.VS(1'b0)) c7(clk,rst_n,done[7],checks[7]);
    vp_latency_checker #(.PW(16),.XW(12),.L(0),.CHAIN(0),.ID(8),.HS(1'b1),.VS(1'b1)) c8(clk,rst_n,done[8],checks[8]);
    initial begin
        #20 rst_n=1;

        #1132 rst_n=0; #18 rst_n=1;
        #2902 rst_n=0; #18 rst_n=1;
        wait (&done);
        $display("PASS tb_video_pipeline: %0d bundle checks; L=0/1/2/4/7/31, 1+2+1 chain, widths 1/16/24, both polarities, bubbles, reset flush",checks[0]+checks[1]+checks[2]+checks[3]+checks[4]+checks[5]+checks[6]+checks[7]+checks[8]);
        $finish;
    end
    initial begin #100000; $fatal(1,"tb_video_pipeline watchdog"); end
endmodule
