// Portable stage-15 A/B assembly: RGB scan/display + B arbitration/swap.
// Front-end BMP parser/unpacker/frame_writer run together in mem_clk; their
// ready/valid stream must NOT cross clocks directly. Frame-ready control enters
// this core in sys_clk through a bundled-data mailbox if produced in mem_clk.
// Unified memory transaction port attaches to B mem_ctrl / board SDRAM adapter.
// C config is sys_clk; emergency is pixel_clk with RAW scan coordinates.
// rst_n is a common assertion epoch; release is synchronized per domain.
// This module does not implement SD playback sequencing, HDMI PHY or pinout.
module safevision_core #(
    parameter integer HD=0,FIFO_AW=10,BURST_WORDS=64,MAX_BURSTS=4,STARVE_LIMIT=64,
    parameter [31:0] SWAP_TIMEOUT_N=32'd5_000_000,
    parameter FONT_FILE="../../../assets/fonts/font8x16.mem",
    parameter integer EMERGENCY_LATENCY=0,DMA_STREAMING=0
)(
    // SYS domain: producer retains payload until swap_state_o returns IDLE.
    input wire frame_ready,wr_frame_index,input wire [1:0] wr_slot_id,
    input wire [7:0] wr_generation,input wire wr_crc_ok,
    output reg active_commit,output wire [1:0] active_next,
    output wire [7:0] generation_next,output wire frame_index_next,swap_error,
    output wire [2:0] swap_state_o,
    output wire frame_start_evt_b,swap_ack_evt_b,
    // MEM domain: byte addresses, lengths in 32-bit words. Frame writer len=1.
    input wire wr_req,input wire [31:0] wr_addr,wr_data,input wire [15:0] wr_len,
    output wire wr_ack,wr_busy,
    input wire sd_req,sd_wr,input wire [31:0] sd_addr,sd_wdata,input wire [15:0] sd_len,
    output wire sd_ack,sd_busy,output wire [31:0] sd_rdata,output wire sd_rdata_valid,
    output wire mem_req,mem_wr,output wire [31:0] mem_addr,mem_wdata,
    output wire [3:0] mem_wstrb,input wire mem_ready,
    input wire [31:0] mem_rdata,input wire mem_rdata_valid,
    output wire [15:0] wr_starve_cnt,rd_starve_cnt,
    input wire sys_clk,mem_clk,pixel_clk,rst_n,
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
    wire srn,mrn;
    reset_sync sys_reset(.clk(sys_clk),.async_rst_n(rst_n),.rst_n(srn));
    reset_sync mem_reset(.clk(mem_clk),.async_rst_n(rst_n),.rst_n(mrn));
    wire swap_req_b,mb_frame_index_b,mb_crc_ok_b;
    wire [1:0] mb_slot_id_b;wire [7:0] mb_generation_b;
    wire rd_req,rd_ack,rd_busy,rd_data_valid;
    wire [31:0] rd_addr,rd_data;wire [15:0] rd_len;
    wire b_commit;
    reg commit_pending,ack_pending;
    // The B FSM can encounter a vblank before A's mailbox has settled when a
    // request arrives at the boundary. Publish slot ownership only after BOTH
    // B's decision and A's ACK. Either event may arrive first; neither is lost.
    always @(posedge sys_clk or negedge srn)begin
        if(!srn)begin active_commit<=0;commit_pending<=0;ack_pending<=0;end
        else begin
            active_commit<=0;
            if(b_commit)commit_pending<=1;
            if(swap_ack_evt_b)ack_pending<=1;
            if((b_commit || commit_pending) && (swap_ack_evt_b || ack_pending))begin
                active_commit<=1;commit_pending<=0;ack_pending<=0;
            end
        end
    end
    frame_swap_ctrl #(.TIMEOUT_N(SWAP_TIMEOUT_N)) swap_ctrl(
      .clk(sys_clk),.rst_n(srn),.frame_ready(frame_ready),
      .wr_frame_index(wr_frame_index),.wr_slot_id(wr_slot_id),
      .wr_generation(wr_generation),.wr_crc_ok(wr_crc_ok),
      .frame_start(frame_start_evt_b),.swap_ack(swap_ack_evt_b),
      .swap_req(swap_req_b),.frame_index(mb_frame_index_b),.slot_id(mb_slot_id_b),
      .generation(mb_generation_b),.crc_ok(mb_crc_ok_b),.swap_error(swap_error),
      .active_commit(b_commit),.active_next(active_next),
      .generation_next(generation_next),.frame_index_next(frame_index_next),.state_o(swap_state_o));
    // Priority uses a one-cycle MEM-domain water-level snapshot. DMA admission
    // still uses its live guarded FIFO level; this register changes neither
    // burst lengths nor the safety space check and breaks the priority path.
    reg [15:0] arbitration_level;
    always @(posedge mem_clk or negedge mrn)
        if(!mrn)arbitration_level<=0;else arbitration_level<=mem_fifo_pixels;
    memory_arbiter #(.MAX_BURSTS(MAX_BURSTS),.STARVE_LIMIT(STARVE_LIMIT),
      .COMPACT_CONSEC_COUNTER(1)) arbiter(
      .clk(mem_clk),.rst_n(mrn),.video_fifo_level(arbitration_level),
      .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),
      .rd_busy(rd_busy),.rd_data(rd_data),.rd_data_valid(rd_data_valid),
      .wr_req(wr_req),.wr_addr(wr_addr),.wr_data(wr_data),.wr_len(wr_len),
      .wr_ack(wr_ack),.wr_busy(wr_busy),
      .sd_req(sd_req),.sd_wr(sd_wr),.sd_addr(sd_addr),.sd_wdata(sd_wdata),.sd_len(sd_len),
      .sd_ack(sd_ack),.sd_busy(sd_busy),.sd_rdata(sd_rdata),.sd_rdata_valid(sd_rdata_valid),
      .mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),
      .mem_rdata_valid(mem_rdata_valid),.wr_starve_cnt(wr_starve_cnt),.rd_starve_cnt(rd_starve_cnt));
    a_video_display_core #(.HD(HD),.FIFO_AW(FIFO_AW),.BURST_WORDS(BURST_WORDS),.EMERGENCY_LATENCY(EMERGENCY_LATENCY),.DMA_STREAMING(DMA_STREAMING),.FONT_FILE(FONT_FILE)) display(
      .sys_clk(sys_clk),
      .mem_clk(mem_clk),
      .pixel_clk(pixel_clk),
      .rst_n(rst_n),
      .swap_req_b(swap_req_b),
      .mb_frame_index_b(mb_frame_index_b),
      .mb_slot_id_b(mb_slot_id_b),
      .mb_generation_b(mb_generation_b),
      .mb_crc_ok_b(mb_crc_ok_b),
      .frame_start_evt_b(frame_start_evt_b),
      .swap_ack_evt_b(swap_ack_evt_b),
      .rd_req(rd_req),
      .rd_addr(rd_addr),
      .rd_len(rd_len),
      .rd_ack(rd_ack),
      .rd_busy(rd_busy),
      .rd_data(rd_data),
      .rd_data_valid(rd_data_valid),
      .cfg_valid(cfg_valid),
      .cfg_ready(cfg_ready),
      .cfg_osd_enable(cfg_osd_enable),
      .cfg_mode(cfg_mode),
      .cfg_fps_tens(cfg_fps_tens),
      .cfg_fps_ones(cfg_fps_ones),
      .cfg_sd_ok(cfg_sd_ok),
      .cfg_origin_x(cfg_origin_x),
      .cfg_origin_y(cfg_origin_y),
      .cfg_foreground(cfg_foreground),
      .emergency_rgb(emergency_rgb),
      .emergency_valid(emergency_valid),
      .scan_x(scan_x),
      .scan_y(scan_y),
      .scan_de(scan_de),
      .scan_frame_start(scan_frame_start),
      .rgb(rgb),
      .x(x),
      .y(y),
      .hsync(hsync),
      .vsync(vsync),
      .de(de),
      .pixel_valid(pixel_valid),
      .line_start(line_start),
      .frame_start(frame_start),
      .active_frame_start(active_frame_start),
      .hblank(hblank),
      .vblank(vblank),
      .selected_layer(selected_layer),
      .pix_active_slot(pix_active_slot),
      .pix_generation(pix_generation),
      .pix_frame_index(pix_frame_index),
      .pix_active_valid(pix_active_valid),
      .pix_frame_fault(pix_frame_fault),
      .pix_underflow_count(pix_underflow_count),
      .pix_missed_frame_count(pix_missed_frame_count),
      .mem_overflow_count(mem_overflow_count),
      .mem_fifo_pixels(mem_fifo_pixels),
      .mem_dma_bytes(mem_dma_bytes),
      .mem_dma_active(mem_dma_active),
      .mem_dma_done(mem_dma_done),
      .mem_fetch_state(mem_fetch_state));
endmodule
