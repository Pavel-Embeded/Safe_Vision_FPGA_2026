`include "pixel_format_defs.vh"
// Stage1-15 display core; pixel output latency = 5 cycles from raw scan.
// B owns the external rd_* burst target/arbiter and the slot mailbox source.
// C configuration crosses as one atomic mailbox. Emergency RGB/valid already
// belong to pixel_clk and the RAW scan; the stage16 generator is external.
// rst_n asserts a COMMON epoch; each business domain releases synchronously.
// BASE displays stored640x480; HD centers that image in1280x720 (no scaling).
module a_video_display_core #(
    parameter integer HD=0,FIFO_AW=10,BURST_WORDS=64,
    parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
    parameter integer EMERGENCY_LATENCY=0
)(
    input wire sys_clk,mem_clk,pixel_clk,rst_n,
    input wire swap_req_b,mb_frame_index_b,input wire [1:0] mb_slot_id_b,
    input wire [7:0] mb_generation_b,input wire mb_crc_ok_b,
    output wire frame_start_evt_b,swap_ack_evt_b,
    output wire rd_req,output wire [31:0] rd_addr,output wire [15:0] rd_len,
    input wire rd_ack,rd_busy,input wire [31:0] rd_data,input wire rd_data_valid,
    input wire cfg_valid,output wire cfg_ready,
    input wire cfg_osd_enable,input wire [1:0] cfg_mode,input wire [3:0] cfg_fps_tens,cfg_fps_ones,
    input wire cfg_sd_ok,input wire [11:0] cfg_origin_x,cfg_origin_y,input wire [23:0] cfg_foreground,
    input wire [23:0] emergency_rgb,input wire emergency_valid,
    output wire [11:0] scan_x,scan_y,output wire scan_de,scan_frame_start,
    output wire [23:0] rgb,output wire [11:0] x,y,
    output wire hsync,vsync,de,pixel_valid,line_start,frame_start,active_frame_start,hblank,vblank,
    output wire [1:0] selected_layer,pix_active_slot,output wire [7:0] pix_generation,
    output wire pix_frame_index,pix_active_valid,pix_frame_fault,
    output wire [31:0] pix_underflow_count,pix_missed_frame_count,mem_overflow_count,
    output wire [15:0] mem_fifo_pixels,output wire [31:0] mem_dma_bytes,
    output wire mem_dma_active,mem_dma_done,output wire [2:0] mem_fetch_state
);
    wire srn,mrn,prn;
    reset_sync sys_reset(.clk(sys_clk),.async_rst_n(rst_n),.rst_n(srn));
    reset_sync mem_reset(.clk(mem_clk),.async_rst_n(rst_n),.rst_n(mrn));
    reset_sync pixel_reset(.clk(pixel_clk),.async_rst_n(rst_n),.rst_n(prn));
    wire hs,vs,ls,afs,hb,vb;
    video_timing #(.H_ACTIVE(HD?1280:640),.H_FRONT(HD?110:16),.H_SYNC(HD?40:96),
      .H_BACK(HD?220:48),.V_ACTIVE(HD?720:480),.V_FRONT(HD?5:10),.V_SYNC(HD?5:2),
      .V_BACK(HD?20:33),.HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) timing(
      .clk(pixel_clk),.rst_n(prn),.x(scan_x),.y(scan_y),.hsync(hs),.vsync(vs),.de(scan_de),
      .line_start(ls),.frame_start(scan_frame_start),.active_frame_start(afs),.hblank(hb),.vblank(vb));
    wire swap_evt,swap_lvl,fi_a,crc_a,mbv_a,ack_toggle;
    wire [1:0] slot_a;wire [7:0] gen_a;
    frame_swap_cdc swaps(.clk_b(sys_clk),.rst_b_n(srn),.swap_req_b(swap_req_b),
      .mb_frame_index_b(mb_frame_index_b),.mb_slot_id_b(mb_slot_id_b),
      .mb_generation_b(mb_generation_b),.mb_crc_ok_b(mb_crc_ok_b),
      .frame_start_evt_b(frame_start_evt_b),.swap_ack_evt_b(swap_ack_evt_b),
      .clk_a(pixel_clk),.rst_a_n(prn),.swap_req_evt_a(swap_evt),.swap_req_lvl_a(swap_lvl),
      .mb_frame_index_a(fi_a),.mb_slot_id_a(slot_a),.mb_generation_a(gen_a),
      .mb_crc_ok_a(crc_a),.mb_valid_a(mbv_a),.frame_start_a(scan_frame_start),.swap_ack_a(ack_toggle));
    wire [31:0] active_base,fetch_base;wire fetch_enable,commit,invalid_payload;
    frame_slot_commit slot(.clk(pixel_clk),.rst_n(prn),.frame_start(scan_frame_start),
      .req_evt(swap_evt),.mb_valid(mbv_a),.mb_crc_ok(crc_a),.mb_slot(slot_a),.mb_generation(gen_a),
      .mb_frame_index(fi_a),.swap_ack_toggle(ack_toggle),.active_valid(pix_active_valid),
      .active_slot(pix_active_slot),.generation(pix_generation),.frame_index(pix_frame_index),
      .active_base(active_base),.next_frame_base(fetch_base),.next_frame_valid(fetch_enable),
      .commit(commit),.invalid_payload(invalid_payload));
    wire [15:0] fifo_data;wire fifo_valid,fifo_empty,fifo_re,fifo_ae,armed;
    wire [FIFO_AW:0] fifo_pixels;
    a_frame_fetch_bridge #(.FIFO_AW(FIFO_AW),.BURST_WORDS(BURST_WORDS)) fetch(
      .pixel_clk(pixel_clk),.pixel_rst_n(prn),.mem_clk(mem_clk),.mem_rst_n(mrn),
      .frame_start(scan_frame_start),.frame_enable(fetch_enable),.frame_base(fetch_base),
      .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(rd_busy),
      .rd_data(rd_data),.rd_data_valid(rd_data_valid),.fifo_rd_en(fifo_re),.fifo_data(fifo_data),
      .fifo_valid(fifo_valid),.fifo_empty(fifo_empty),.fifo_almost_empty(fifo_ae),.fifo_rd_pixels(fifo_pixels),
      .stream_armed(armed),.fifo_mem_pixels(mem_fifo_pixels),.missed_frame_count(pix_missed_frame_count),
      .overflow_count(mem_overflow_count),.dma_bytes(mem_dma_bytes),.dma_active(mem_dma_active),
      .dma_done(mem_dma_done),.fetch_state(mem_fetch_state));
    wire [23:0] normal_rgb;wire normal_valid,underflow;
    frame_reader #(.IMAGE_W(`SV_FRAME_WIDTH),.IMAGE_H(`SV_FRAME_HEIGHT),
      .ORIGIN_X(HD?(1280-`SV_FRAME_WIDTH)/2:0),.ORIGIN_Y(HD?(720-`SV_FRAME_HEIGHT)/2:0),
      .HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) reader(
      .clk(pixel_clk),.rst_n(prn),.image_enable(pix_active_valid),.stream_armed(armed),
      .fifo_data(fifo_data),.fifo_valid(fifo_valid),.fifo_empty(fifo_empty),.fifo_rd_en(fifo_re),
      .x_in(scan_x),.y_in(scan_y),.hsync_in(hs),.vsync_in(vs),.de_in(scan_de),
      .line_start_in(ls),.frame_start_in(scan_frame_start),.active_frame_start_in(afs),.hblank_in(hb),.vblank_in(vb),
      .rgb_out(normal_rgb),.x_out(),.y_out(),.hsync_out(),.vsync_out(),.de_out(),.pixel_valid_out(normal_valid),
      .line_start_out(),.frame_start_out(),.active_frame_start_out(),.hblank_out(),.vblank_out(),
      .frame_fault(pix_frame_fault),.underflow_pulse(underflow),.underflow_count(pix_underflow_count));
    wire [59:0] config_data;wire config_valid;reg [59:0] config_latched;
    video_cdc_mailbox #(.WIDTH(60)) config_mailbox(
      .src_clk(sys_clk),.src_rst_n(srn),
      .src_data({cfg_osd_enable,cfg_mode,cfg_fps_tens,cfg_fps_ones,cfg_sd_ok,cfg_origin_x,cfg_origin_y,cfg_foreground}),
      .src_valid(cfg_valid),.src_ready(cfg_ready),.dst_clk(pixel_clk),.dst_rst_n(prn),
      .dst_data(config_data),.dst_valid(config_valid),.dst_ready(1'b1));
    always @(posedge pixel_clk or negedge prn)begin
        if(!prn)config_latched<=0;else if(config_valid)config_latched<=config_data;
    end
    wire osd_enable,sd_ok;wire [1:0] mode;wire [3:0] tens,ones;
    wire [11:0] origin_x,origin_y;wire [23:0] foreground;
    assign {osd_enable,mode,tens,ones,sd_ok,origin_x,origin_y,foreground}=config_latched;
    wire [7:0] char_index,char_code;wire [23:0] osd_rgb;wire osd_valid;
    osd_status_text status(.char_index(char_index),.mode(mode),.fps_tens(tens),.fps_ones(ones),
      .sd_ok(sd_ok),.char_code(char_code));
    osd_text_layer #(.FONT_FILE(FONT_FILE)) text_layer(.clk(pixel_clk),.rst_n(prn),.de(scan_de),
      .x(scan_x),.y(scan_y),.origin_x(origin_x),.origin_y(origin_y),.enable(osd_enable),
      .char_count(8'd38),.char_code(char_code),.foreground(foreground),
      .char_index(char_index),.rgb(osd_rgb),.valid(osd_valid));
    video_compositor #(.NORMAL_LATENCY(1),.OSD_LATENCY(4),.EMERGENCY_LATENCY(EMERGENCY_LATENCY),
      .HSYNC_ACTIVE(HD!=0),.VSYNC_ACTIVE(HD!=0)) compositor(
      .clk(pixel_clk),.rst_n(prn),.normal_rgb(normal_rgb),.normal_valid(normal_valid),
      .osd_rgb(osd_rgb),.osd_valid(osd_valid),.emergency_rgb(emergency_rgb),.emergency_valid(emergency_valid),
      .x_in(scan_x),.y_in(scan_y),.hsync_in(hs),.vsync_in(vs),.de_in(scan_de),
      .line_start_in(ls),.frame_start_in(scan_frame_start),.active_frame_start_in(afs),.hblank_in(hb),.vblank_in(vb),
      .rgb_out(rgb),.x_out(x),.y_out(y),.hsync_out(hsync),.vsync_out(vsync),.de_out(de),.pixel_valid_out(pixel_valid),
      .line_start_out(line_start),.frame_start_out(frame_start),.active_frame_start_out(active_frame_start),
      .hblank_out(hblank),.vblank_out(vblank),.selected_layer(selected_layer));
    // synthesis translate_off
    initial if(HD!=0&&HD!=1)$fatal(1,"a_video_display_core HD must be 0 or 1");
    // synthesis translate_on
endmodule
