`timescale 1ns/1ps
module graphics_frame_checker #(parameter integer HD=0,COORD=0)(input wire clk,rst_n,output reg done);
 initial begin done = 0; end

    localparam integer W=HD ? 1280:640,H=HD ? 720:480,HT=HD ? 1650:800,VT=HD ? 750:525;
    wire [23:0] rgb;wire [11:0] x,y;wire [8:0] tags;
    a_graphics_frontend #(.HD(HD),.FONT_FILE("font8x16.mem")) dut(.pixel_clk(clk),.rst_n(rst_n),.pattern_select(3'd5),
        .arrow_right(1'b1),.osd_enable(1'b1),.coordinate_text(COORD!=0),.origin_x(12'd13),.origin_y(12'd27),
        .mode(2'd1),.fps_tens(4'd6),.fps_ones(4'd0),.sd_ok(1'b1),
        .rgb(rgb),.x(x),.y(y),.hsync(tags[8]),.vsync(tags[7]),.de(tags[6]),.pixel_valid(tags[5]),
        .line_start(tags[4]),.frame_start(tags[3]),.active_frame_start(tags[2]),.hblank(tags[1]),.vblank(tags[0]));
    reg [7:0] font[0:4095];reg [56:0] q[0:3];reg [8:0] expected_tags;
    reg [23:0] expected_rgb;reg [303:0] text="SAFEVISION MODE:NORMAL    FPS:60 SD:OK";
    integer rx=0,ry=0,j,cycles=0,checks=0,visible=0,fs=0,afs=0,ls=0,file_handle,char_no;
    reg [7:0] char_code;reg hs,vs,den;reg [11:0] ref_x,ref_y;
    initial begin
        $readmemh("font8x16.mem",font);
        file_handle=$fopen(COORD ? "graphics_coordinates.ppm":HD ? "graphics_hd.ppm":"graphics_base.ppm","wb");
        if(!file_handle) begin $display("[FAIL] cannot create frame image"); $finish; end 
        $fwrite(file_handle,"P6\n%0d %0d\n255\n",W,H);
    end
    always @(posedge clk) begin
        if(!done) begin
            if(!rst_n) begin
                rx=0;ry=0;cycles=0;
                for(j=0;j<4;j = j + 1) q[j]={24'd0,24'd0,{2{!HD}},5'b00000,2'b11};
            end else begin

                hs=((rx>=W+(HD ? 110:16)) && (rx<W+(HD ? 110:16)+(HD ? 40:96))) ? HD:!HD;
                vs=((ry>=H+(HD ? 5:10)) && (ry<H+(HD ? 5:10)+(HD ? 5:2))) ? HD:!HD;
                den=rx<W && ry<H;
                expected_tags={hs,vs,den,den,(rx==0),(rx==0 && ry==H),(rx==0 && ry==0),(rx>=W),(ry>=H)};
                expected_rgb=(den && (rx==0 || rx==W-1 || ry==0 || ry==H-1)) ? 24'hffffff:0;
                if(den && rx>=13 && rx<13+(COORD ? 11:38)*8 && ry>=27 && ry<43) begin
                    char_no=(rx-13)/8;char_code=text[(37-char_no)*8 +: 8];
                    if(COORD) case(char_no)
                        0:char_code="X";1:char_code=":";2:char_code="0";3:char_code="0";4:char_code="D";
                        5:char_code=" ";6:char_code="Y";7:char_code=":";8:char_code="0";9:char_code="1";10:char_code="B";
                    endcase
                    if(font[char_code*16+ry-27] & (8'h80>>((rx-13)%8))) expected_rgb=24'hffffff;
                end
                ref_x=rx;ref_y=ry;
                for(j=3;j>0;j = j - 1)q[j]=q[j-1];q[0]={expected_rgb,ref_x,ref_y,expected_tags};
                cycles = cycles + 1;
                if(rx==HT-1) begin rx=0;ry=(ry==VT-1) ? 0:ry+1;end else rx = rx + 1;
            end
            #1;checks = checks + 1;
            if({rgb,x,y,tags}!==q[3]) begin $display("[FAIL] frontend HD=%d cycle=%d actual=%h expected=%h",HD,cycles,{rgb,x,y,tags},q[3]); $finish; end 
            if(rst_n && cycles>=4 && cycles<HT*VT+4) begin
                if(tags[6]) begin
                    visible = visible + 1;
                    $fwrite(file_handle,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
                end
                fs = fs + (tags[3]);afs = afs + (tags[2]);ls = ls + (tags[4]);
            end
            if(cycles==HT*VT+3) begin
                if(visible!=W*H || fs!=1 || afs!=1 || ls!=VT)
                    begin $display("[FAIL] frontend frame counts HD=%d visible=%d fs=%d afs=%d ls=%d",HD,visible,fs,afs,ls); $finish; end 
                $fclose(file_handle);done=1;
                $display("FRAME HD=%0d COORD=%0d: %0d bundles active=%0d line=%0d blank-event=%0d active-event=%0d",HD,COORD,checks,visible,ls,fs,afs);
            end
        end
    end
endmodule
module tb_a_graphics_frontend;
    reg clk=0;always #5 clk=~clk;reg rst_n=0;wire base_done,hd_done,coord_done;
    graphics_frame_checker base(.clk(clk),.rst_n(rst_n),.done(base_done));
    graphics_frame_checker #(.HD(1)) hd(.clk(clk),.rst_n(rst_n),.done(hd_done));
    graphics_frame_checker #(.COORD(1)) coordinates(.clk(clk),.rst_n(rst_n),.done(coord_done));
    initial begin repeat(2)@(negedge clk);rst_n=1;wait(base_done && hd_done && coord_done);
        $display("PASS tb_a_graphics_frontend: BASE and HD complete frames, 4-cycle alignment");$finish;end
    initial begin #13000000;begin $display("[FAIL] tb_a_graphics_frontend watchdog"); $finish; end end
endmodule
