`timescale 1ns/1ps
module tb_osd_overlay;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [23:0] bg=0,fg=24'hffffff;reg [11:0] x=0,y=0,ox=13,oy=27;
    reg [8:0] tags=0;reg en=1;reg [7:0] len=6;wire [7:0] idx;reg [7:0] code;
    wire [23:0] rgb;wire [11:0] xo,yo;wire [8:0] ot;
    osd_overlay #(.FONT_FILE("font8x16.mem")) dut(.clk(clk),.rst_n(rst_n),.rgb_in(bg),.x_in(x),.y_in(y),
        .hsync_in(tags[8]),.vsync_in(tags[7]),.de_in(tags[6]),.pixel_valid_in(tags[5]),
        .line_start_in(tags[4]),.frame_start_in(tags[3]),.active_frame_start_in(tags[2]),
        .hblank_in(tags[1]),.vblank_in(tags[0]),.osd_enable(en),.origin_x(ox),.origin_y(oy),
        .char_count(len),.char_code(code),.foreground(fg),.char_index(idx),
        .rgb_out(rgb),.x_out(xo),.y_out(yo),.hsync_out(ot[8]),.vsync_out(ot[7]),
        .de_out(ot[6]),.pixel_valid_out(ot[5]),.line_start_out(ot[4]),.frame_start_out(ot[3]),
        .active_frame_start_out(ot[2]),.hblank_out(ot[1]),.vblank_out(ot[0]));
    always @* case(idx%6)
        0:code="F";1:code="P";2:code="S";3:code=":";4:code="6";default:code="0";
    endcase
    reg [7:0] font [0:4095];reg [56:0] q[0:3];
    integer checks=0,i,j,dx,dy,index,row,random_seed=32'h13579246;
    reg [23:0] expected_rgb;reg [7:0] expected_code;reg inside_region;
    task sample;
        begin
            @(posedge clk);
            if(!rst_n) for(j=0;j<4;j++) q[j]={24'd0,24'd0,2'b11,5'b00000,2'b11};
            else begin
                dx=integer'(x)-integer'(ox);dy=integer'(y)-integer'(oy);
                inside_region=en && tags[6] && dx>=0 && dy>=0 && dx<8*len && dy<16;
                index=(dx & 2047)/8; // raw index is don't-care outside the region
                case(index%6)
                    0:expected_code="F";1:expected_code="P";2:expected_code="S";
                    3:expected_code=":";4:expected_code="6";default:expected_code="0";
                endcase
                expected_rgb=tags[6]?bg:0;
                if(inside_region && (font[expected_code*16+dy] & (8'h80>>(dx%8)))) expected_rgb=fg;
                if(idx!==index[7:0] || code!==expected_code) $fatal(1,"OSD current text index");
                for(j=3;j>0;j--) q[j]=q[j-1];
                q[0]={expected_rgb,x,y,tags};
            end
            #1;checks++;
            if({rgb,xo,yo,ot} !== q[3])
                $fatal(1,"OSD latency/bit order/transparency sample=%d actual=%h expected=%h",checks,{rgb,xo,yo,ot},q[3]);
        end
    endtask
    initial begin
        $readmemh("font8x16.mem",font);sample();@(negedge clk);rst_n=1;sample();
        // Raster sweep includes every bit of FPS:60 at a non-aligned origin.
        for(i=0;i<6000;i++) begin
            @(negedge clk); x=i%100;y=i/100;bg=24'h183456;tags=9'b111100000;
            sample();
        end
        // Every cycle changes data/config; invalid pixels still advance tags.
        for(i=0;i<8000;i++) begin
            @(negedge clk);
            x=$random(random_seed);y=$random(random_seed);bg=$random(random_seed);fg=$random(random_seed);
            tags=$random(random_seed);en=i%3!=0;len=i%256;
            ox=(i%2)?4090:12;oy=(i%3)?4090:20;
            if(i%7==0) begin x=ox+i%90;y=oy+i%16; end
            if(i==100 || i==1100) rst_n=0;
            if(i==103 || i==1103) rst_n=1;
            sample();
        end
        // No wrap around at the 12-bit coordinate limit, zero-length text.
        @(negedge clk);rst_n=1;ox=4095;oy=4095;x=0;y=0;len=255;en=1;tags=9'h1ff;repeat(5)sample();
        @(negedge clk);ox=0;oy=0;x=0;y=0;len=0;repeat(5)sample();
        #2;rst_n=0;#1;checks++;
        if({rgb,xo,yo,ot}!=={24'd0,24'd0,2'b11,5'b00000,2'b11}) $fatal(1,"OSD async reset");
        $display("PASS tb_osd_overlay: %0d bundles",checks);$finish;
    end
    initial begin #200000;$fatal(1,"tb_osd_overlay watchdog");end
endmodule
