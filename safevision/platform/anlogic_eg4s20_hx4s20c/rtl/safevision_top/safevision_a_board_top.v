


`include "pixel_format_defs.vh"

`ifndef SAFEVISION_BOARD_HD
`define SAFEVISION_BOARD_HD 0
`endif
module safevision_a_board_top #(
    parameter integer HD = `SAFEVISION_BOARD_HD,
    parameter integer BOOT_EMERGENCY=0, BOOT_DIRECTION=2, BOOT_LEVEL=1,
    parameter integer MEM_CLK_HZ = 125000000,
    parameter FONT_FILE = "../../../assets/fonts/font8x16.mem"
)(
    input wire clk, rst_n,
    output wire [3:0] led,
    output wire HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P,
    output wire HDMI_DDC_SCL,
    inout wire HDMI_DDC_SDA
);
    wire sys_clk, mem_clk, mem_clk_sft, pixel_clk, serial_clk;
    wire sys_lock, video_lock;
    wire ref_rst_n, common_rst_n, sys_rst_n, mem_rst_n, pixel_rst_n;
    reset_sync reset_ref(.clk(clk), .async_rst_n(rst_n), .rst_n(ref_rst_n));
    sv_system_pll system_pll(.refclk(clk), .reset(1'b0), .extlock(sys_lock),
        .clk0_out(sys_clk), .clk1_out(mem_clk), .clk2_out(mem_clk_sft));
    generate if (HD == 0) begin : video_base
        sv_video_vga_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
            .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
    end else begin : video_hd
        sv_video_hd_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
            .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
    end endgenerate
    assign common_rst_n = ref_rst_n && sys_lock && video_lock;
    reset_sync reset_sys(.clk(sys_clk), .async_rst_n(common_rst_n), .rst_n(sys_rst_n));
    reset_sync reset_mem(.clk(mem_clk), .async_rst_n(common_rst_n), .rst_n(mem_rst_n));
    reset_sync reset_pixel(.clk(pixel_clk), .async_rst_n(common_rst_n), .rst_n(pixel_rst_n));


    reg start = 1'b0, started = 1'b0;
    reg [9:0] src_x = 0, src_y = 0;
    reg src_valid = 1'b0;
    wire src_ready, wr_req, wr_ack, wr_busy, wr_done, wr_crc_ok, wr_error;
    wire [3:0] slot_valid;
    wire [31:0] wr_addr, wr_data;
    wire [15:0] wr_len;
    wire [18:0] wr_pixels;
    wire sdr_init_done;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            start <= 0; started <= 0; src_valid <= 0; src_x <= 0; src_y <= 0;
        end else begin
            start <= 0;
            if (sdr_init_done && !started) begin
                start <= 1; started <= 1;
            end
            if (started && !wr_done && !wr_error && !(src_x == 0 && src_y == `SV_FRAME_HEIGHT)) begin
                src_valid <= 1;
                if (src_valid && src_ready) begin
                    if (src_x == `SV_FRAME_WIDTH-1) begin
                        src_x <= 0;
                        src_y <= src_y + 1'b1;
                    end else src_x <= src_x + 1'b1;
                end
            end else src_valid <= 0;
        end
    end
    wire [15:0] src_rgb565 = {src_x[9:5], src_y[8:3], src_x[8:4]};
    frame_writer #(.GAP_TIMEOUT(32'd12500000)) writer(
        .clk(mem_clk), .rst_n(mem_rst_n), .start(start),
        .slot_sel(2'd0), .slot_base(`SV_IMG0_BASE),
        .din(src_rgb565), .din_valid(src_valid), .din_ready(src_ready),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ready(wr_ack), .wr_done(wr_done), .slot_valid(slot_valid),
        .crc_ok(wr_crc_ok), .crc_value(), .px_cnt(wr_pixels),
        .wr_error(wr_error), .err_code(), .err_detail());


    reg [9:0] drain = 0;
    reg submit_toggle = 0;
    reg submitted = 0;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin drain <= 0; submit_toggle <= 0; submitted <= 0; end
        else if (wr_done && wr_crc_ok && slot_valid[0] && !submitted) drain <= 10'd1;
        else if (drain != 0 && !submitted) begin
            drain <= drain + 1'b1;
            if (drain == 10'd1023) begin
                submit_toggle <= ~submit_toggle;
                submitted <= 1;
                drain <= 0;
            end
        end
    end
    reg [2:0] submit_sync = 0;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) submit_sync <= 0;
        else submit_sync <= {submit_sync[1:0], submit_toggle};
    end
    wire frame_ready = submit_sync[2] ^ submit_sync[1];

    wire mem_req, mem_wr, mem_ready, mem_rvalid, mem_error;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0] mem_wstrb;
    wire adapter_req, adapter_wr, adapter_ready, adapter_rvalid, adapter_init;
    wire [31:0] adapter_addr, adapter_wdata, adapter_rdata;
    wire [3:0] adapter_wstrb;
    wire sdr_ref_valid, sdr_busy, app_wr_en, app_rd_en, sdr_rd_en;
    wire [20:0] app_wr_addr, app_rd_addr;
    wire [3:0] app_wr_dm;
    wire [31:0] app_wr_data, sdr_rd_data;
    mem_ctrl memory(.clk(mem_clk), .rst_n(mem_rst_n), .init_done(),
        .req(mem_req), .wr(mem_wr), .addr(mem_addr), .wdata(mem_wdata),
        .wstrb(mem_wstrb), .rdata(mem_rdata), .rdata_valid(mem_rvalid),
        .ready(mem_ready), .mem_error(mem_error),
        .sdram_req(adapter_req), .sdram_wr(adapter_wr), .sdram_addr(adapter_addr),
        .sdram_wdata(adapter_wdata), .sdram_wstrb(adapter_wstrb),
        .sdram_rdata(adapter_rdata), .sdram_rdata_valid(adapter_rvalid),
        .sdram_ready(adapter_ready), .sdram_init_done(adapter_init));
    sdram_app_adapter adapter(.clk(mem_clk), .rst_n(mem_rst_n),
        .req(adapter_req), .wr(adapter_wr), .addr(adapter_addr),
        .wdata(adapter_wdata), .wstrb(adapter_wstrb),
        .rdata(adapter_rdata), .rdata_valid(adapter_rvalid),
        .ready(adapter_ready), .init_done(adapter_init),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_data));
    sdram memory_ip(.Clk(mem_clk), .Clk_sft(mem_clk_sft), .Rst(~mem_rst_n),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_data),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_data));

    wire [23:0] rgb;
    wire [11:0] out_x, out_y;
    wire out_de, out_vs, active, swap_error, frame_fault;
    wire [31:0] underflows, missed, overflows;
    wire [1:0] active_slot;
    reg demo_valid=0,demo_sent=0;wire demo_ready;
    always @(posedge sys_clk or negedge sys_rst_n)begin
        if(!sys_rst_n)begin demo_valid<=0;demo_sent<=0;end
        else if(!demo_sent)begin
            demo_valid<=1;
            if(demo_valid&&demo_ready)begin demo_valid<=0;demo_sent<=1;end
        end
    end
    a_video_system_core #(.HD(HD), .FONT_FILE(FONT_FILE)) core(
        .sys_clk(sys_clk), .mem_clk(mem_clk), .pixel_clk(pixel_clk), .rst_n(common_rst_n),
        .frame_ready(frame_ready), .wr_frame_index(1'b0), .wr_slot_id(2'd0),
        .wr_generation(8'd1), .wr_crc_ok(1'b1),
        .active_commit(), .active_next(), .generation_next(), .frame_index_next(),
        .swap_error(swap_error), .swap_state_o(), .frame_start_evt_b(), .swap_ack_evt_b(),
        .wr_req(wr_req), .wr_addr(wr_addr), .wr_data(wr_data), .wr_len(wr_len),
        .wr_ack(wr_ack), .wr_busy(wr_busy),
        .sd_req(1'b0), .sd_wr(1'b0), .sd_addr(32'd0), .sd_wdata(32'd0), .sd_len(16'd0),
        .sd_ack(), .sd_busy(), .sd_rdata(), .sd_rdata_valid(),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_rdata_valid(mem_rvalid),
        .wr_starve_cnt(), .rd_starve_cnt(),
        .cfg_valid(1'b0), .cfg_ready(), .cfg_osd_enable(1'b0), .cfg_mode(2'd0),
        .cfg_fps_tens(4'd6), .cfg_fps_ones(4'd0), .cfg_sd_ok(1'b1),
        .cfg_origin_x(12'd0), .cfg_origin_y(12'd0), .cfg_foreground(24'hffffff),
        .emergency_ctrl_valid(demo_valid),.emergency_ctrl_ready(demo_ready),
        .emergency_active(BOOT_EMERGENCY!=0),.direction(BOOT_DIRECTION[1:0]),.warning_level(BOOT_LEVEL[1:0]),
        .emergency_applied(),.emergency_pending(),.emergency_pixel_active(),.emergency_pixel_direction(),.emergency_pixel_level(),
        .pixel_debug(),.mem_debug(),.sys_debug(),
        .scan_x(), .scan_y(), .scan_de(), .scan_frame_start(),
        .rgb(rgb), .x(out_x), .y(out_y), .hsync(), .vsync(out_vs), .de(out_de),
        .pixel_valid(), .line_start(), .frame_start(), .active_frame_start(),
        .hblank(), .vblank(), .selected_layer(), .pix_active_slot(active_slot),
        .pix_generation(), .pix_frame_index(), .pix_active_valid(active),
        .pix_frame_fault(frame_fault), .pix_underflow_count(underflows),
        .pix_missed_frame_count(missed), .mem_overflow_count(overflows),
        .mem_fifo_pixels(), .mem_dma_bytes(), .mem_dma_active(), .mem_dma_done(),
        .mem_fetch_state());


    wire hdmi_locked,hdmi_connected,hdmi_overflow;wire [31:0] dropped;
    a_hdmi_output #(.HD(HD)) hdmi(
        .pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst_n(common_rst_n),
        .hpd(1'b1),.edid_reread(1'b0),.rgb(rgb),.de(out_de),.x(out_x),.y(out_y),
        .audio_valid(1'b0),.audio_left(24'd0),.audio_right(24'd0),
        .acr_valid(1'b0),.acr_cts(20'd0),.acr_n(20'd0),
        .tmds_d0_p(HDMI_D0_P),.tmds_d1_p(HDMI_D1_P),.tmds_d2_p(HDMI_D2_P),.tmds_clk_p(HDMI_CLK_P),
        .ddc_scl(HDMI_DDC_SCL),.ddc_sda(HDMI_DDC_SDA),.video_locked(hdmi_locked),
        .connected(hdmi_connected),.overflow_sticky(hdmi_overflow),.dropped_frames(dropped),
        .edid_valid(),.edid_data(),.queue_level());
    assign led={hdmi_locked&&hdmi_connected&&!hdmi_overflow&&!mem_error&&!frame_fault,
        active&&!swap_error,slot_valid[0],sys_lock&&video_lock&&sdr_init_done};
endmodule
