// Independent A bring-up frontend; not a replacement for B's SDRAM board top.
`include "video_mode_defs.vh"
module a_graphics_frontend #(
    parameter integer HD=0, parameter FONT_FILE="../../../assets/fonts/font8x16.mem"
)(input wire pixel_clk,rst_n, input wire [2:0] pattern_select,
  input wire arrow_right,osd_enable,coordinate_text, input wire [11:0] origin_x,origin_y,
  input wire [1:0] mode, input wire [3:0] fps_tens,fps_ones, input wire sd_ok,
  output wire [23:0] rgb, output wire [11:0] x,y,
  output wire hsync,vsync,de,pixel_valid,line_start,frame_start,active_frame_start,hblank,vblank);
    wire [11:0] sx,sy;
    wire hs,vs,den,ls,fs,afs,hb,vb;
    wire [23:0] pattern;
    wire [7:0] idx,status_code,coordinate_code;
    wire [7:0] code=coordinate_text?coordinate_code:status_code;
    video_timing #(.H_ACTIVE(HD?1280:640),.H_FRONT(HD?110:16),.H_SYNC(HD?40:96),
        .H_BACK(HD?220:48),.V_ACTIVE(HD?720:480),.V_FRONT(HD?5:10),.V_SYNC(HD?5:2),
        .V_BACK(HD?20:33),.HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) timing(
        .clk(pixel_clk),.rst_n(rst_n),.x(sx),.y(sy),.hsync(hs),.vsync(vs),.de(den),
        .line_start(ls),.frame_start(fs),.active_frame_start(afs),.hblank(hb),.vblank(vb));
    pattern_generator #(.H_ACTIVE(HD?1280:640),.V_ACTIVE(HD?720:480)) patterns(
        .rst_n(rst_n),.de(den),.x(sx),.y(sy),.pattern_select(pattern_select),
        .arrow_right(arrow_right),.rgb(pattern));
    osd_status_text text(.char_index(idx),.mode(mode),.fps_tens(fps_tens),
        .fps_ones(fps_ones),.sd_ok(sd_ok),.char_code(status_code));
    osd_coordinate_text coords(.char_index(idx),.x_value(origin_x),.y_value(origin_y),.char_code(coordinate_code));
    osd_overlay #(.FONT_FILE(FONT_FILE),.HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) overlay(
        .clk(pixel_clk),.rst_n(rst_n),.rgb_in(pattern),.x_in(sx),.y_in(sy),
        .hsync_in(hs),.vsync_in(vs),.de_in(den),.pixel_valid_in(den),
        .line_start_in(ls),.frame_start_in(fs),.active_frame_start_in(afs),.hblank_in(hb),.vblank_in(vb),
        .osd_enable(osd_enable),.origin_x(origin_x),.origin_y(origin_y),
        .char_count(coordinate_text?8'd11:8'd38),.char_code(code),.foreground(24'hffffff),.char_index(idx),
        .rgb_out(rgb),.x_out(x),.y_out(y),.hsync_out(hsync),.vsync_out(vsync),.de_out(de),
        .pixel_valid_out(pixel_valid),.line_start_out(line_start),.frame_start_out(frame_start),
        .active_frame_start_out(active_frame_start),.hblank_out(hblank),.vblank_out(vblank));
endmodule
