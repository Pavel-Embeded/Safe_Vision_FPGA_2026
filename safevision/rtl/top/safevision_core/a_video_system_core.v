


module a_video_system_core #(
    parameter integer HD=0,FIFO_AW=10,BURST_WORDS=64,MAX_BURSTS=4,STARVE_LIMIT=64,
    parameter [31:0] SWAP_TIMEOUT_N=32'd5_000_000,
    parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
    parameter integer EMERGENCY_IMMEDIATE=0
)(

    input wire frame_ready,wr_frame_index,input wire [1:0] wr_slot_id,
    input wire [7:0] wr_generation,input wire wr_crc_ok,
    output wire active_commit,output wire [1:0] active_next,
    output wire [7:0] generation_next,output wire frame_index_next,swap_error,
    output wire [2:0] swap_state_o,
    output wire frame_start_evt_b,swap_ack_evt_b,

    input wire wr_req,input wire [31:0] wr_addr,wr_data,input wire [15:0] wr_len,
    output wire wr_ack,wr_busy,
    input wire sd_req,sd_wr,input wire [31:0] sd_addr,sd_wdata,input wire [15:0] sd_len,
    output wire sd_ack,sd_busy,output wire [31:0] sd_rdata,output wire sd_rdata_valid,
    output wire mem_req,mem_wr,output wire [31:0] mem_addr,mem_wdata,
    output wire [3:0] mem_wstrb,input wire mem_ready,
    input wire [31:0] mem_rdata,input wire mem_rdata_valid,
    output wire [15:0] wr_starve_cnt,rd_starve_cnt,
    input wire sys_clk,mem_clk,pixel_clk,rst_n,
    input wire emergency_ctrl_valid,output wire emergency_ctrl_ready,
    input wire emergency_active,input wire [1:0] direction,warning_level,
    output wire emergency_applied,emergency_pending,emergency_pixel_active,
    output wire [1:0] emergency_pixel_direction,emergency_pixel_level,
    (* keep="true" *) output reg [63:0] pixel_debug,mem_debug,
    (* keep="true" *) output reg [31:0] sys_debug,
    input wire cfg_valid,output wire cfg_ready,
    input wire cfg_osd_enable,input wire [1:0] cfg_mode,input wire [3:0] cfg_fps_tens,cfg_fps_ones,
    input wire cfg_sd_ok,input wire [11:0] cfg_origin_x,cfg_origin_y,input wire [23:0] cfg_foreground,
    output wire [11:0] scan_x,scan_y,output wire scan_de,scan_frame_start,
    output wire [23:0] rgb,output wire [11:0] x,y,
    output wire hsync,vsync,de,pixel_valid,line_start,frame_start,active_frame_start,hblank,vblank,
    output wire [1:0] selected_layer,pix_active_slot,output wire [7:0] pix_generation,
    output wire pix_frame_index,pix_active_valid,pix_frame_fault,
    output wire [31:0] pix_underflow_count,pix_missed_frame_count,mem_overflow_count,
    output wire [15:0] mem_fifo_pixels,output wire [31:0] mem_dma_bytes,
    output wire mem_dma_active,mem_dma_done,output wire [2:0] mem_fetch_state
);
    wire srn,mrn,prn;wire [23:0] em_rgb;wire em_valid;
    reset_sync sys_reset(.clk(sys_clk),.async_rst_n(rst_n),.rst_n(srn));
    reset_sync mem_reset(.clk(mem_clk),.async_rst_n(rst_n),.rst_n(mrn));
    reset_sync pixel_reset(.clk(pixel_clk),.async_rst_n(rst_n),.rst_n(prn));
    emergency_control_bridge #(.IMMEDIATE(EMERGENCY_IMMEDIATE)) emergency_control(
        .sys_clk(sys_clk),.sys_rst_n(srn),.pixel_clk(pixel_clk),.pixel_rst_n(prn),
        .ctrl_valid(emergency_ctrl_valid),.ctrl_ready(emergency_ctrl_ready),
        .emergency_active(emergency_active),.direction(direction),.warning_level(warning_level),
        .frame_start(scan_frame_start),.active(emergency_pixel_active),
        .active_direction(emergency_pixel_direction),.active_level(emergency_pixel_level),
        .applied(emergency_applied),.pending_o(emergency_pending));
    emergency_graphics #(.HD(HD),.FONT_FILE(FONT_FILE)) emergency_image(
        .clk(pixel_clk),.rst_n(prn),.de(scan_de),.frame_start(scan_frame_start),
        .x(scan_x),.y(scan_y),.active(emergency_pixel_active),
        .direction(emergency_pixel_direction),.warning_level(emergency_pixel_level),
        .rgb(em_rgb),.valid(em_valid));


    always @(posedge pixel_clk or negedge prn)begin
        if(!prn)pixel_debug<=0;
        else pixel_debug<={emergency_pixel_active,emergency_pixel_level,emergency_pixel_direction,
            emergency_applied,pix_generation,pix_active_slot,pix_active_valid,pix_frame_fault,
            de,pixel_valid,hsync,vsync,x,y,selected_layer,
            pix_underflow_count[7:0],pix_missed_frame_count[7:0]};
    end
    always @(posedge mem_clk or negedge mrn)begin
        if(!mrn)mem_debug<=0;
        else mem_debug<={mem_fetch_state,mem_dma_active,mem_dma_done,mem_fifo_pixels,
            mem_dma_bytes,wr_busy,rd_starve_cnt[9:0]};
    end
    always @(posedge sys_clk or negedge srn)begin
        if(!srn)sys_debug<=0;
        else sys_debug<={8'd0,wr_generation,wr_slot_id,wr_frame_index,wr_crc_ok,frame_ready,
            emergency_ctrl_valid,emergency_ctrl_ready,cfg_valid,cfg_ready,swap_state_o,
            swap_error,active_commit,frame_start_evt_b,swap_ack_evt_b};
    end
    safevision_core #(.HD(HD),.FIFO_AW(FIFO_AW),.BURST_WORDS(BURST_WORDS),
        .MAX_BURSTS(MAX_BURSTS),.STARVE_LIMIT(STARVE_LIMIT),.SWAP_TIMEOUT_N(SWAP_TIMEOUT_N),
        .FONT_FILE(FONT_FILE),.EMERGENCY_LATENCY(4)) video(
        .frame_ready(frame_ready),.wr_frame_index(wr_frame_index),.wr_slot_id(wr_slot_id),.wr_generation(wr_generation),
        .wr_crc_ok(wr_crc_ok),.active_commit(active_commit),.active_next(active_next),.generation_next(generation_next),
        .frame_index_next(frame_index_next),.swap_error(swap_error),.swap_state_o(swap_state_o),.frame_start_evt_b(frame_start_evt_b),
        .swap_ack_evt_b(swap_ack_evt_b),.wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),
        .wr_len(wr_len),.wr_ack(wr_ack),.wr_busy(wr_busy),.sd_req(sd_req),
        .sd_wr(sd_wr),.sd_addr(sd_addr),.sd_wdata(sd_wdata),.sd_len(sd_len),
        .sd_ack(sd_ack),.sd_busy(sd_busy),.sd_rdata(sd_rdata),.sd_rdata_valid(sd_rdata_valid),
        .mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),.mem_rdata_valid(mem_rdata_valid),
        .wr_starve_cnt(wr_starve_cnt),.rd_starve_cnt(rd_starve_cnt),.sys_clk(sys_clk),.mem_clk(mem_clk),
        .pixel_clk(pixel_clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_osd_enable(cfg_osd_enable),.cfg_mode(cfg_mode),.cfg_fps_tens(cfg_fps_tens),.cfg_fps_ones(cfg_fps_ones),
        .cfg_sd_ok(cfg_sd_ok),.cfg_origin_x(cfg_origin_x),.cfg_origin_y(cfg_origin_y),.cfg_foreground(cfg_foreground),
        .emergency_rgb(em_rgb),.emergency_valid(em_valid),.scan_x(scan_x),.scan_y(scan_y),
        .scan_de(scan_de),.scan_frame_start(scan_frame_start),.rgb(rgb),.x(x),
        .y(y),.hsync(hsync),.vsync(vsync),.de(de),
        .pixel_valid(pixel_valid),.line_start(line_start),.frame_start(frame_start),.active_frame_start(active_frame_start),
        .hblank(hblank),.vblank(vblank),.selected_layer(selected_layer),.pix_active_slot(pix_active_slot),
        .pix_generation(pix_generation),.pix_frame_index(pix_frame_index),.pix_active_valid(pix_active_valid),.pix_frame_fault(pix_frame_fault),
        .pix_underflow_count(pix_underflow_count),.pix_missed_frame_count(pix_missed_frame_count),.mem_overflow_count(mem_overflow_count),.mem_fifo_pixels(mem_fifo_pixels),
        .mem_dma_bytes(mem_dma_bytes),.mem_dma_active(mem_dma_active),.mem_dma_done(mem_dma_done),.mem_fetch_state(mem_fetch_state)
    );
endmodule
