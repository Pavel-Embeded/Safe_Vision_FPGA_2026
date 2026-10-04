// All latency parameters describe the upstream delay from the RAW scan.
// Align each layer to MAX, then register selection once: output latency MAX+1.
// No ready/stall. Priority Emergency > OSD > Normal > safe background.
module video_compositor #(
    parameter integer NORMAL_LATENCY=1,OSD_LATENCY=4,EMERGENCY_LATENCY=0,
    parameter [23:0] SAFE_COLOR=24'h000000,
    parameter HSYNC_ACTIVE=1'b0,VSYNC_ACTIVE=1'b0
)(
    input wire clk,rst_n,
    input wire [23:0] normal_rgb,osd_rgb,emergency_rgb,
    input wire normal_valid,osd_valid,emergency_valid,
    input wire [11:0] x_in,y_in,input wire hsync_in,vsync_in,de_in,
    input wire line_start_in,frame_start_in,active_frame_start_in,hblank_in,vblank_in,
    output wire [23:0] rgb_out,output wire [11:0] x_out,y_out,
    output wire hsync_out,vsync_out,de_out,pixel_valid_out,
    output wire line_start_out,frame_start_out,active_frame_start_out,hblank_out,vblank_out,
    output wire [1:0] selected_layer
);
    localparam integer MAX_NO=(NORMAL_LATENCY>OSD_LATENCY)?NORMAL_LATENCY:OSD_LATENCY;
    localparam integer ALIGN=(MAX_NO>EMERGENCY_LATENCY)?MAX_NO:EMERGENCY_LATENCY;
    wire [23:0] n_rgb,o_rgb,e_rgb;wire nv,ov,ev;
    video_layer_delay #(.LATENCY(ALIGN-NORMAL_LATENCY)) nd(.clk(clk),.rst_n(rst_n),
      .rgb_in(normal_rgb),.valid_in(normal_valid),.rgb_out(n_rgb),.valid_out(nv));
    video_layer_delay #(.LATENCY(ALIGN-OSD_LATENCY)) od(.clk(clk),.rst_n(rst_n),
      .rgb_in(osd_rgb),.valid_in(osd_valid),.rgb_out(o_rgb),.valid_out(ov));
    video_layer_delay #(.LATENCY(ALIGN-EMERGENCY_LATENCY)) ed(.clk(clk),.rst_n(rst_n),
      .rgb_in(emergency_rgb),.valid_in(emergency_valid),.rgb_out(e_rgb),.valid_out(ev));
    reg [23:0] chosen;reg chosen_valid;reg [1:0] layer;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin chosen<=SAFE_COLOR;chosen_valid<=0;layer<=0;end
        else begin
            chosen_valid<=nv||ov||ev;
            if(ev)begin chosen<=e_rgb;layer<=3;end
            else if(ov)begin chosen<=o_rgb;layer<=2;end
            else if(nv)begin chosen<=n_rgb;layer<=1;end
            else begin chosen<=SAFE_COLOR;layer<=0;end
        end
    end
    assign rgb_out=de_out?chosen:24'd0;
    assign pixel_valid_out=de_out&&chosen_valid;
    assign selected_layer=de_out?layer:2'd0;
    video_pipeline #(.LATENCY(ALIGN+1),.HSYNC_ACTIVE(HSYNC_ACTIVE),.VSYNC_ACTIVE(VSYNC_ACTIVE)) tags(
      .clk(clk),.rst_n(rst_n),.pixel_in(24'd0),.x_in(x_in),.y_in(y_in),
      .hsync_in(hsync_in),.vsync_in(vsync_in),.de_in(de_in),.pixel_valid_in(1'b0),
      .line_start_in(line_start_in),.frame_start_in(frame_start_in),
      .active_frame_start_in(active_frame_start_in),.hblank_in(hblank_in),.vblank_in(vblank_in),
      .pixel_out(),.x_out(x_out),.y_out(y_out),.hsync_out(hsync_out),.vsync_out(vsync_out),
      .de_out(de_out),.pixel_valid_out(),.line_start_out(line_start_out),
      .frame_start_out(frame_start_out),.active_frame_start_out(active_frame_start_out),
      .hblank_out(hblank_out),.vblank_out(vblank_out));
    // synthesis translate_off
    initial if(NORMAL_LATENCY<0||OSD_LATENCY<0||EMERGENCY_LATENCY<0||ALIGN>31)
        $fatal(1,"video_compositor invalid latency");
    // synthesis translate_on
endmodule
