
`ifndef A_GRAPHICS_HD
`define A_GRAPHICS_HD 0
`endif
module a_graphics_verify_top(input wire board_clk,board_rst_n,
    input wire [2:0] pattern_select,input wire arrow_right,osd_enable,coordinate_text,
    input wire [11:0] origin_x,origin_y,input wire [1:0] mode,
    input wire [3:0] fps_tens,fps_ones,input wire sd_ok,
    output reg [56:0] probe);
    localparam integer HD=`A_GRAPHICS_HD;
    wire pixel_clk,lock,rst_n;
    generate if(HD) begin:hd
        sv_video_hd_pll pll(.refclk(board_clk),.reset(!board_rst_n),.extlock(lock),
            .clk0_out(),.clk1_out(pixel_clk),.clk2_out());
    end else begin:base
        sv_video_vga_pll pll(.refclk(board_clk),.reset(!board_rst_n),.extlock(lock),
            .clk0_out(),.clk1_out(pixel_clk),.clk2_out());
    end endgenerate
    reset_sync reset(.clk(pixel_clk),.async_rst_n(board_rst_n && lock),.rst_n(rst_n));
    wire [56:0] result;
    a_graphics_frontend #(.HD(HD)) graphics(.pixel_clk(pixel_clk),.rst_n(rst_n),
        .pattern_select(pattern_select),.arrow_right(arrow_right),.osd_enable(osd_enable),.coordinate_text(coordinate_text),
        .origin_x(origin_x),.origin_y(origin_y),.mode(mode),.fps_tens(fps_tens),.fps_ones(fps_ones),.sd_ok(sd_ok),
        .rgb(result[56:33]),.x(result[32:21]),.y(result[20:9]),
        .hsync(result[8]),.vsync(result[7]),.de(result[6]),.pixel_valid(result[5]),
        .line_start(result[4]),.frame_start(result[3]),.active_frame_start(result[2]),.hblank(result[1]),.vblank(result[0]));
    always @(posedge pixel_clk or negedge rst_n)
        if(!rst_n) probe<=0;else probe<=result;
endmodule
