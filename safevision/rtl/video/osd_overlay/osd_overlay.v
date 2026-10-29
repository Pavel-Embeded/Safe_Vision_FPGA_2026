


module osd_overlay #(
    parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
    parameter HSYNC_ACTIVE=1'b0, VSYNC_ACTIVE=1'b0
)(input wire clk, rst_n,
  input wire [23:0] rgb_in, input wire [11:0] x_in,y_in,
  input wire hsync_in,vsync_in,de_in,pixel_valid_in,
  input wire line_start_in,frame_start_in,active_frame_start_in,hblank_in,vblank_in,
  input wire osd_enable, input wire [11:0] origin_x,origin_y,
  input wire [7:0] char_count,char_code, input wire [23:0] foreground,
  output wire [7:0] char_index,
  output wire [23:0] rgb_out, output wire [11:0] x_out,y_out,
  output wire hsync_out,vsync_out,de_out,pixel_valid_out,
  output wire line_start_out,frame_start_out,active_frame_start_out,hblank_out,vblank_out);
    wire [12:0] dx={1'b0,x_in}-{1'b0,origin_x};
    wire [12:0] dy={1'b0,y_in}-{1'b0,origin_y};
    wire region=osd_enable && de_in && x_in>=origin_x && y_in>=origin_y &&
                dx < {2'b00,char_count,3'b000} && dy<13'd16;


    assign char_index=dx[10:3];
    reg region1,region2,region3,dot4;
    reg [7:0] code1;
    reg [3:0] row1;
    reg [2:0] col1,col2,col3;
    reg [11:0] addr2;
    reg [23:0] fg1,fg2,fg3,fg4;
    wire [7:0] row_bits;
    font8x16_rom #(.FONT_FILE(FONT_FILE)) font(.clk(clk),.addr(addr2),.row_bits(row_bits));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            region1<=0; region2<=0; region3<=0; dot4<=0;
            code1<=0; row1<=0; col1<=0; col2<=0; col3<=0; addr2<=0;
            fg1<=0; fg2<=0; fg3<=0; fg4<=0;
        end else begin
            region1<=region; code1<=char_code; row1<=dy[3:0]; col1<=dx[2:0]; fg1<=foreground;
            region2<=region1; addr2<={code1,row1}; col2<=col1; fg2<=fg1;
            region3<=region2; col3<=col2; fg3<=fg2;
            dot4<=region3 && row_bits[7-col3]; fg4<=fg3;
        end
    end
    wire [23:0] background;
    video_pipeline #(.LATENCY(4),.HSYNC_ACTIVE(HSYNC_ACTIVE),.VSYNC_ACTIVE(VSYNC_ACTIVE)) tags(
        .clk(clk),.rst_n(rst_n),.pixel_in(rgb_in),.x_in(x_in),.y_in(y_in),
        .hsync_in(hsync_in),.vsync_in(vsync_in),.de_in(de_in),.pixel_valid_in(pixel_valid_in),
        .line_start_in(line_start_in),.frame_start_in(frame_start_in),
        .active_frame_start_in(active_frame_start_in),.hblank_in(hblank_in),.vblank_in(vblank_in),
        .pixel_out(background),.x_out(x_out),.y_out(y_out),
        .hsync_out(hsync_out),.vsync_out(vsync_out),.de_out(de_out),.pixel_valid_out(pixel_valid_out),
        .line_start_out(line_start_out),.frame_start_out(frame_start_out),
        .active_frame_start_out(active_frame_start_out),.hblank_out(hblank_out),.vblank_out(vblank_out));
    assign rgb_out=de_out ? (dot4 ? fg4 : background) : 24'd0;
endmodule
