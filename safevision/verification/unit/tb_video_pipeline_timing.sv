`timescale 1ns/1ps
// Literal VGA/HD geometry oracle plus indexed history checks. Real scan
// timing drives a 16-bit RGB565 bundle. Invalid pixels must not alter sync.
module vp_scan_checker #(
    parameter integer HD=0, L=4
)(input wire clk, input wire rst_n, output reg done=0,
  output integer checks=0);
    localparam integer HT=HD?1650:800, VT=HD?750:525;
    localparam integer HA=HD?1280:640, VA=HD?720:480;
    localparam integer HB=HD?1390:656, HE=HD?1430:752;
    localparam integer VB=HD?725:490, VE=HD?730:492;
    localparam integer W=16+24+9;
    wire [11:0] sx,sy;
    wire hs,vs,de,ls,fs,afs,hbl,vbl;
    video_timing #(.H_ACTIVE(HA),.H_FRONT(HD?110:16),
        .H_SYNC(HD?40:96),.H_BACK(HD?220:48),.V_ACTIVE(VA),
        .V_FRONT(HD?5:10),.V_SYNC(HD?5:2),.V_BACK(HD?20:33),
        .HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) timing (
        .clk(clk),.rst_n(rst_n),.x(sx),.y(sy),.hsync(hs),.vsync(vs),
        .de(de),.line_start(ls),.frame_start(fs),.active_frame_start(afs),
        .hblank(hbl),.vblank(vbl));
    wire pv=de && ((sx%17)!=0) && ((sy%7)!=0);
    wire [15:0] rgb={sx[4:0],sy[5:0],sx[9:5]};
    wire [W-1:0] source={rgb,sx,sy,hs,vs,de,pv,ls,fs,afs,hbl,vbl};
    wire [W-1:0] first,second,actual;
    video_pipeline #(.PIXEL_WIDTH(16), .XY_WIDTH(12), .LATENCY(1),
        .HSYNC_ACTIVE((HD!=0)), .VSYNC_ACTIVE((HD!=0))) a (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(source[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_in(source[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_in(source[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .hsync_in(source[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(source[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(source[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(source[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(source[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(source[1 + 1 + 1 +: 1]),
        .active_frame_start_in(source[1 + 1 +: 1]),
        .hblank_in(source[1 +: 1]),
        .vblank_in(source[0 +: 1]),
        .pixel_out(first[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_out(first[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_out(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
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
    video_pipeline #(.PIXEL_WIDTH(16), .XY_WIDTH(12), .LATENCY(2),
        .HSYNC_ACTIVE((HD!=0)), .VSYNC_ACTIVE((HD!=0))) b (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(first[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_in(first[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .hsync_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(first[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(first[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(first[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(first[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(first[1 + 1 + 1 +: 1]),
        .active_frame_start_in(first[1 + 1 +: 1]),
        .hblank_in(first[1 +: 1]),
        .vblank_in(first[0 +: 1]),
        .pixel_out(second[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_out(second[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_out(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
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
    video_pipeline #(.PIXEL_WIDTH(16), .XY_WIDTH(12), .LATENCY(1),
        .HSYNC_ACTIVE((HD!=0)), .VSYNC_ACTIVE((HD!=0))) c (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(second[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_in(second[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .hsync_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .vsync_in(second[1 + 1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .de_in(second[1 + 1 + 1 + 1 + 1 + 1 +: 1]),
        .pixel_valid_in(second[1 + 1 + 1 + 1 + 1 +: 1]),
        .line_start_in(second[1 + 1 + 1 + 1 +: 1]),
        .frame_start_in(second[1 + 1 + 1 +: 1]),
        .active_frame_start_in(second[1 + 1 +: 1]),
        .hblank_in(second[1 +: 1]),
        .vblank_in(second[0 +: 1]),
        .pixel_out(actual[12 + 12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 16]),
        .x_out(actual[12 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
        .y_out(actual[1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 +: 12]),
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
    reg [W-1:0] history[0:7];
    reg [W-1:0] expected;
    integer n=0, samples=0, ix=0, iy=0;
    integer frame_de=0, frame_hs=0, frame_vs=0, frame_ls=0, frame_fs=0, frame_afs=0, holes=0;
    reg [W-1:0] pre;
    wire [15:0] out_rgb=actual[W-1 -:16];
    wire [11:0] ox=actual[32:21], oy=actual[20:9];
    wire ohs=actual[8], ovs=actual[7], ode=actual[6], opv=actual[5];
    wire ols=actual[4], ofs=actual[3], oafs=actual[2];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n=0; ix=0; iy=0; samples=0;
            frame_de=0;frame_hs=0;frame_vs=0;frame_ls=0;frame_fs=0;frame_afs=0;holes=0;
            expected={16'd0,12'd0,12'd0,!HD,!HD,5'b00000,2'b11};
            #1;
            if (actual !== expected) $fatal(1,"scan HD=%0d reset failed",HD);
        end else if (!done) begin
            // Inspect source BEFORE counters advance. Independent coordinate
            // arithmetic establishes that the input scanner is correct too.
            pre=source;
            if (sx !== ix || sy !== iy || de !== (ix<HA && iy<VA) ||
                hs !== ((ix>=HB && ix<HE)?(HD!=0):(HD==0)) ||
                vs !== ((iy>=VB && iy<VE)?(HD!=0):(HD==0)) ||
                ls !== (ix==0) || fs !== (ix==0 && iy==VA) ||
                afs !== (ix==0 && iy==0)) $fatal(1,"input geometry HD=%0d (%0d,%0d)",HD,ix,iy);
            history[n%8]=pre;
            expected=(n>=3)?history[(n-3)%8]:{16'd0,12'd0,12'd0,!HD,!HD,5'b00000,2'b11};
            if (ix==HT-1) begin ix=0; iy=(iy==VT-1)?0:iy+1; end
            else ix=ix+1;
            #1;
            if (actual !== expected) $fatal(1,"scan alignment HD=%0d sample=%0d",HD,n);
            checks=checks+1;
            if (n>=3 && samples<HT*VT) begin
                frame_de=frame_de+ode;
                frame_hs=frame_hs+(ohs==(HD!=0));
                frame_vs=frame_vs+(ovs==(HD!=0));
                frame_ls=frame_ls+ols;frame_fs=frame_fs+ofs;frame_afs=frame_afs+oafs;
                if (ode && !opv) holes=holes+1;
                samples=samples+1;
                if (samples==HT*VT) begin
                    if(frame_de!=HA*VA || frame_hs!=(HE-HB)*VT || frame_vs!=(VE-VB)*HT ||
                       frame_ls!=VT || frame_fs!=1 || frame_afs!=1 || holes==0)
                        $fatal(1,"scan output counts HD=%0d de=%0d hs=%0d vs=%0d ls=%0d fs=%0d afs=%0d holes=%0d",HD,frame_de,frame_hs,frame_vs,frame_ls,frame_fs,frame_afs,holes);
                    $display("PASS scan HD=%0d: pixels=%0d, active=%0d, invalid-active=%0d, delay=4",HD,samples,frame_de,holes);
                    done=1;
                end
            end
            n=n+1;
        end
    end
endmodule

module tb_video_pipeline_timing;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire base_done,hd_done;
    wire [31:0] base_checks,hd_checks;
    vp_scan_checker base(clk,rst_n,base_done,base_checks);
    vp_scan_checker #(.HD(1)) hd(clk,rst_n,hd_done,hd_checks);
    initial begin
        #20 rst_n=1;
        // Reset after a partial line; restart then check complete frames.
        #1132 rst_n=0; #18 rst_n=1;
        wait(base_done && hd_done);
        $display("PASS tb_video_pipeline_timing: BASE+HD full-frame checks=%0d",base_checks+hd_checks);
        $finish;
    end
    initial begin #14000000; $fatal(1,"tb_video_pipeline_timing watchdog"); end
endmodule
