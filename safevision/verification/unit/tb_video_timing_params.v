`timescale 1ns/1ps


module tb_video_timing_params #(parameter integer CASE_ID = 0);
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    localparam integer HA = (CASE_ID == 1 || CASE_ID == 15)  ?  4095 :
        (CASE_ID == 7)  ?  0 : (CASE_ID == 17)  ?  2147483647 :
        (CASE_ID == 19)  ?  4097 : (CASE_ID == 25)  ?  32'hxxxxxxxx :
        (CASE_ID == 29)  ?  -1 : (CASE_ID == 2 || CASE_ID == 5 || CASE_ID == 6)  ?  2 : 1;
    localparam integer HF = (CASE_ID == 3)  ?  4094 : (CASE_ID == 9)  ?  -1 :
        (CASE_ID == 15)  ?  1 : (CASE_ID == 17)  ?  2147483647 :
        (CASE_ID == 26)  ?  32'hxxxxxxxx : (CASE_ID == 31)  ?  4097 : 0;
    localparam integer HS = (CASE_ID == 8)  ?  0 : (CASE_ID == 17)  ?  3 : 1;
    localparam integer HB = (CASE_ID == 4)  ?  4094 : (CASE_ID == 10)  ?  -1 :
        (CASE_ID == 17)  ?  3 : 0;
    localparam integer VA = (CASE_ID == 2 || CASE_ID == 16)  ?  4095 :
        (CASE_ID == 11)  ?  0 : (CASE_ID == 18)  ?  2147483647 :
        (CASE_ID == 20)  ?  4097 : (CASE_ID == 27)  ?  32'hxxxxxxxx :
        (CASE_ID == 30)  ?  -1 : (CASE_ID == 1 || CASE_ID == 3 || CASE_ID == 4)  ?  2 : 1;
    localparam integer VF = (CASE_ID == 5)  ?  4094 : (CASE_ID == 13)  ?  -1 :
        (CASE_ID == 16)  ?  1 : (CASE_ID == 18)  ?  2147483647 : 0;
    localparam integer VS = (CASE_ID == 12)  ?  0 : (CASE_ID == 18)  ?  3 : 1;
    localparam integer VB = (CASE_ID == 6)  ?  4094 : (CASE_ID == 14)  ?  -1 :
        (CASE_ID == 18)  ?  3 : (CASE_ID == 28)  ?  32'hzzzzzzzz : 0;
    localparam HSA = (CASE_ID == 21)  ?  2 : (CASE_ID == 23)  ?  1'bx : (CASE_ID == 0)  ?  0 : 1;
    localparam VSA = (CASE_ID == 22)  ?  2 : (CASE_ID == 24)  ?  1'bz : (CASE_ID == 0)  ?  1 : 0;

    wire [11:0] x, y;
    wire hsync, vsync, de, line_start, frame_start, active_frame_start, hblank, vblank;
    video_timing #(.H_ACTIVE(HA), .H_FRONT(HF), .H_SYNC(HS), .H_BACK(HB),
        .V_ACTIVE(VA), .V_FRONT(VF), .V_SYNC(VS), .V_BACK(VB),
        .HSYNC_ACTIVE(HSA), .VSYNC_ACTIVE(VSA)) dut (
        .clk(clk), .rst_n(rst_n), .x(x), .y(y), .hsync(hsync), .vsync(vsync),
        .de(de), .line_start(line_start), .frame_start(frame_start),
        .active_frame_start(active_frame_start), .hblank(hblank), .vblank(vblank));

    integer htotal, vtotal, hactive, vactive, hsync_at, vsync_at;
    integer tick;
    reg [11:0] ex, ey;
    reg ehs, evs;
    reg [31:0] expected, actual;
    initial begin
        if (CASE_ID < 0 || CASE_ID > 31) begin $display("[FAIL] FAIL unsupported CASE_ID"); $finish; end 
        if (CASE_ID >= 7) begin
            #100;
            begin $display("[FAIL] FAIL invalid video geometry/polarity accepted: CASE_ID=%0d", CASE_ID); $finish; end 
        end else begin

            case (CASE_ID)
                0: begin htotal=2; vtotal=2; hactive=1; vactive=1; hsync_at=1; vsync_at=1; end
                1: begin htotal=4096; vtotal=3; hactive=4095; vactive=2; hsync_at=4095; vsync_at=2; end
                2: begin htotal=3; vtotal=4096; hactive=2; vactive=4095; hsync_at=2; vsync_at=4095; end
                3: begin htotal=4096; vtotal=3; hactive=1; vactive=2; hsync_at=4095; vsync_at=2; end
                4: begin htotal=4096; vtotal=3; hactive=1; vactive=2; hsync_at=1; vsync_at=2; end
                5: begin htotal=3; vtotal=4096; hactive=2; vactive=1; hsync_at=2; vsync_at=4095; end
                6: begin htotal=3; vtotal=4096; hactive=2; vactive=1; hsync_at=2; vsync_at=1; end
            endcase
            repeat (3) @(negedge clk);
            #1;
            if (x !== 0 || y !== 0 || de !== 0 || line_start !== 0 ||
                frame_start !== 0 || active_frame_start !== 0 || hblank !== 1 || vblank !== 1)
                begin $display("[FAIL] FAIL reset outputs CASE_ID=%0d", CASE_ID); $finish; end 
            rst_n = 1'b1;
            #1;
            for (tick=0; tick<2*htotal*vtotal; tick=tick+1) begin
                ex = tick % htotal;
                ey = (tick / htotal) % vtotal;
                ehs = (CASE_ID == 0)  ?  !(ex == hsync_at) : (ex == hsync_at);
                evs = (CASE_ID == 0)  ?  (ey == vsync_at) : !(ey == vsync_at);
                expected = {ex,ey,ehs,evs,(ex<hactive && ey<vactive),
                    (ex==0),(ex==0 && ey==vactive),(ex==0 && ey==0),
                    (ex>=hactive),(ey>=vactive)};
                actual = {x,y,hsync,vsync,de,line_start,frame_start,active_frame_start,hblank,vblank};
                if (actual !== expected)
                    begin $display("[FAIL] FAIL CASE_ID=%0d tick=%0d got=%08h expected=%08h",CASE_ID,tick,actual,expected); $finish; end 
                @(negedge clk);
                #1;
            end
            $display("PASS tb_video_timing_params: CASE_ID=%0d checked=%0d two complete frames",CASE_ID,tick);
            $finish;
        end
    end
endmodule
