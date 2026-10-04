// FWFT RGB565 consumer, one registered output stage (all labels latency=1).
// Scan is NEVER stopped. One underflow event per affected media frame;
// discard the remainder visually, stop reads, and recover after vblank + flush.
// Coordinates include blanking. Outside the image viewport emits BACKGROUND.
module frame_reader #(
    parameter integer IMAGE_W=640,IMAGE_H=480,ORIGIN_X=0,ORIGIN_Y=0,
    parameter [23:0] BACKGROUND=24'h000000,UNDERFLOW_COLOR=24'h000000,
    parameter HSYNC_ACTIVE=1'b0,VSYNC_ACTIVE=1'b0
)(
    input wire clk,rst_n,image_enable,stream_armed,
    input wire [15:0] fifo_data,input wire fifo_valid,fifo_empty,output wire fifo_rd_en,
    input wire [11:0] x_in,y_in,input wire hsync_in,vsync_in,de_in,
    input wire line_start_in,frame_start_in,active_frame_start_in,hblank_in,vblank_in,
    output wire [23:0] rgb_out,output wire [11:0] x_out,y_out,
    output wire hsync_out,vsync_out,de_out,pixel_valid_out,
    output wire line_start_out,frame_start_out,active_frame_start_out,hblank_out,vblank_out,
    output reg frame_fault,underflow_pulse,output reg [31:0] underflow_count
);
    wire media=de_in && x_in>=ORIGIN_X && x_in<ORIGIN_X+IMAGE_W &&
                            y_in>=ORIGIN_Y && y_in<ORIGIN_Y+IMAGE_H;
    wire available=image_enable && stream_armed && !frame_fault && !fifo_empty && fifo_valid;
    assign fifo_rd_en=rst_n && media && available;
    wire [23:0] expanded={fifo_data[15:11],fifo_data[15:13],fifo_data[10:5],
                          fifo_data[10:9],fifo_data[4:0],fifo_data[4:2]};
    wire [23:0] pixel=!de_in ? 24'd0 : (media ? (available?expanded:UNDERFLOW_COLOR) : BACKGROUND);
    wire valid_pixel=de_in && (!media || available);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin frame_fault<=0;underflow_pulse<=0;underflow_count<=0;end
        else begin
            underflow_pulse<=0;
            if(frame_start_in)frame_fault<=0;
            else if(media&&image_enable&&!available&&!frame_fault)begin
                frame_fault<=1;underflow_pulse<=1;
                if(underflow_count!=32'hffffffff)underflow_count<=underflow_count+1'b1;
            end
        end
    end
    video_pipeline #(.LATENCY(1),.HSYNC_ACTIVE(HSYNC_ACTIVE),.VSYNC_ACTIVE(VSYNC_ACTIVE)) output_stage(
      .clk(clk),.rst_n(rst_n),.pixel_in(pixel),.x_in(x_in),.y_in(y_in),
      .hsync_in(hsync_in),.vsync_in(vsync_in),.de_in(de_in),.pixel_valid_in(valid_pixel),
      .line_start_in(line_start_in),.frame_start_in(frame_start_in),
      .active_frame_start_in(active_frame_start_in),.hblank_in(hblank_in),.vblank_in(vblank_in),
      .pixel_out(rgb_out),.x_out(x_out),.y_out(y_out),.hsync_out(hsync_out),.vsync_out(vsync_out),
      .de_out(de_out),.pixel_valid_out(pixel_valid_out),.line_start_out(line_start_out),
      .frame_start_out(frame_start_out),.active_frame_start_out(active_frame_start_out),
      .hblank_out(hblank_out),.vblank_out(vblank_out));
    // synthesis translate_off
    initial if(IMAGE_W<1||IMAGE_H<1||ORIGIN_X<0||ORIGIN_Y<0||
      ORIGIN_X+IMAGE_W>4096||ORIGIN_Y+IMAGE_H>4096)$fatal(1,"frame_reader invalid viewport");
    // synthesis translate_on
endmodule
