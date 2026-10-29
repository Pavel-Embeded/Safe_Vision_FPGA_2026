


`define SAFEVISION_MEM_CLK_HZ 40000000
`define SAFEVISION_SDRAM_CLK_HZ `SAFEVISION_MEM_CLK_HZ


`define SAFEVISION_REFRESH_ROWS 4096
`include "pixel_format_defs.vh"

`ifndef SAFEVISION_BOARD_HD
`define SAFEVISION_BOARD_HD 0
`endif


`define SV_INT_DEF 0
module safevision_top #(
    parameter integer HD = `SAFEVISION_BOARD_HD,
    parameter integer MEM_CLK_HZ = `SAFEVISION_MEM_CLK_HZ,


    parameter FONT_FILE = "font8x16.mem",

    parameter [31:0] MODE_TO_N = MEM_CLK_HZ*3/10,


    parameter [31:0] RPT_PERIOD_N = MEM_CLK_HZ/2,
    parameter [15:0] PLAYER_SPI_INIT_DIV=16'd249,
    parameter [15:0] PLAYER_SPI_FAST_DIV=16'd1,
    parameter integer STORAGE_INTEGRITY=`SV_INT_DEF
)(

    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn_next,
    input  wire        btn_auto,
    input  wire        btn_emergency,
    output wire        uart_txd,
    output wire [3:0]  led,

    output wire        sd_ncs,
    output wire        sd_dclk,
    output wire        sd_mosi,
    input  wire        sd_miso,

    output wire        HDMI_D0_P, HDMI_D1_P, HDMI_D2_P, HDMI_CLK_P,
    output wire        HDMI_DDC_SCL,
    inout  wire        HDMI_DDC_SDA
);


    wire sys_clk, mem_clk, mem_clk_sft, pixel_clk, serial_clk;
    wire sys_lock, video_lock;
    wire ref_rst_n, common_rst_n, mem_rst_n, pixel_rst_n, sys_rst_n;

    reset_sync reset_ref(.clk(clk), .async_rst_n(rst_n), .rst_n(ref_rst_n));

    sv_board_memory_pll system_pll(.refclk(clk), .reset(1'b0), .extlock(sys_lock),
        .clk0_out(sys_clk), .clk1_out(mem_clk), .clk2_out(mem_clk_sft));

    generate
        if (HD == 0) begin : video_base
            sv_video_vga_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
                .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
        end else begin : video_hd
            sv_video_hd_pll video_pll(.refclk(clk), .reset(1'b0), .extlock(video_lock),
                .clk0_out(), .clk1_out(pixel_clk), .clk2_out(serial_clk));
        end
    endgenerate

    assign common_rst_n = ref_rst_n && sys_lock && video_lock;
    reset_sync reset_mem  (.clk(mem_clk),   .async_rst_n(common_rst_n), .rst_n(mem_rst_n));
    reset_sync reset_pixel(.clk(pixel_clk), .async_rst_n(common_rst_n), .rst_n(pixel_rst_n));
    reset_sync reset_sys(.clk(sys_clk),.async_rst_n(common_rst_n),.rst_n(sys_rst_n));


    wire        sdr_init_done, sdr_ref_valid, sdr_busy;
    wire        app_wr_en, app_rd_en, sdr_rd_en;
    wire [20:0] app_wr_addr, app_rd_addr;
    wire [3:0]  app_wr_dm;
    wire [31:0] app_wr_din, sdr_rd_dout;

    sdram memory_ip(.Clk(mem_clk), .Clk_sft(mem_clk_sft), .Rst(~mem_rst_n),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout));

    wire        adapter_req, adapter_wr, adapter_ready, adapter_rvalid, adapter_init;
    wire adapter_write_idle;
    wire adapter_fault,memory_error;
    reg card_mode; reg [31:0] mode_cnt;
    wire [31:0] adapter_addr, adapter_wdata, adapter_rdata;
    wire [3:0]  adapter_wstrb;


    localparam integer ADAPTER_FAST_READ=1, ADAPTER_PREFETCH=1;
    sdram_app_adapter #(.FAST_READ(ADAPTER_FAST_READ),.PREFETCH_READ(ADAPTER_PREFETCH)) adapter(.clk(mem_clk), .rst_n(mem_rst_n),
        .req(adapter_req), .wr(adapter_wr), .addr(adapter_addr),
        .wdata(adapter_wdata), .wstrb(adapter_wstrb),
        .rdata(adapter_rdata), .rdata_valid(adapter_rvalid),
        .ready(adapter_ready), .init_done(adapter_init), .write_idle(adapter_write_idle),
        .protocol_fault(adapter_fault),
        .Sdr_init_done(sdr_init_done), .Sdr_init_ref_vld(sdr_ref_valid),
        .Sdr_busy(sdr_busy), .App_wr_en(app_wr_en), .App_wr_addr(app_wr_addr),
        .App_wr_dm(app_wr_dm), .App_wr_din(app_wr_din),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .Sdr_rd_en(sdr_rd_en), .Sdr_rd_dout(sdr_rd_dout));

    wire        mem_req, mem_wr, mem_ready, mem_rvalid;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;
    wire [3:0]  mem_wstrb;

    mem_ctrl memory(.clk(mem_clk), .rst_n(mem_rst_n), .init_done(),
        .req(mem_req), .wr(mem_wr), .addr(mem_addr), .wdata(mem_wdata),
        .wstrb(mem_wstrb), .rdata(mem_rdata), .rdata_valid(mem_rvalid),
        .ready(mem_ready), .mem_error(memory_error),
        .sdram_req(adapter_req), .sdram_wr(adapter_wr), .sdram_addr(adapter_addr),
        .sdram_wdata(adapter_wdata), .sdram_wstrb(adapter_wstrb),
        .sdram_rdata(adapter_rdata), .sdram_rdata_valid(adapter_rvalid),
        .sdram_ready(adapter_ready), .sdram_init_done(adapter_init));


    wire prod_wr_ack, prod_wr_busy;


    wire prod_word_accepted=prod_wr_busy&&mem_req&&mem_wr&&mem_ready;


    wire [31:0] pl_px_word;
    wire        pl_px_word_valid, pl_px_word_ready;
    wire        pl_frame_active, pl_top_down;
    wire [1:0]  pl_slot;
    wire [3:0]  pl_state, pl_fail_stage;
    wire [7:0]  pl_ec, pl_ed;
    wire [7:0]  pl_r1;
    wire [2:0]  pl_seq;
    wire        pl_sd_ready, pl_card_usable;
    wire [3:0]  pl_file_cnt;
    wire [1:0]  pl_cur_file;
    wire [31:0] pl_file_size, pl_bytes_rd;
    wire [18:0] pl_px_written;
    wire        pl_frame_ok;
    wire [15:0] pl_frame_cnt;


    wire integrity_begin,integrity_top_down,integrity_done,integrity_pass,integrity_fault;
    wire [1:0] integrity_slot;
    wire verify_req,verify_ack,verify_busy,verify_valid;
    wire [31:0] verify_addr,verify_data,lookup_addr,lookup_crc;
    wire lookup_valid,video_integrity_fault;
    wire [31:0] integrity_bad_addr,integrity_expected,integrity_actual;
    wire [31:0] video_bad_addr,video_expected,video_actual,integrity_words;
    wire [31:0] integrity_word_last;
    wire [11:0] integrity_fail_cnt;
    wire [15:0] integrity_blocks,display_fifo_level;
    wire display_dma_active;
    reg playback_fault;
    reg [31:0] playback_bad_addr,playback_expected,playback_actual;
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)begin playback_fault<=0;playback_bad_addr<=0;playback_expected<=0;playback_actual<=0;end
        else if(video_integrity_fault&&!playback_fault)begin
            playback_fault<=1;playback_bad_addr<=video_bad_addr;
            playback_expected<=video_expected;playback_actual<=video_actual;
        end
    wire        sk_wr_req;
    wire [31:0] sk_wr_addr, sk_wr_data;
    wire [15:0] sk_wr_len;
    wire        sk_swap_toggle, sk_swap_crc_ok;
    wire [1:0]  sk_swap_slot;
    wire [7:0]  sk_swap_gen;
    wire        sk_mem_ready, sk_frame_done, sk_frame_ok;
    wire [3:0]  sk_state;
    wire [7:0]  sk_ec, sk_ed;
    wire [15:0] sk_frame_cnt;
    wire [18:0] sk_px_written;
    reg         swap_busy_mem;


    (* keep = "true" *) reg [1:0] next_sync, auto_sync;


    wire next_pressed=~next_sync[1],auto_pressed=~auto_sync[1];
    reg [15:0] dn_cnt, da_cnt;
    reg        dn_s, da_s;
    reg        dn_db, dn_db_d, da_db;


    always @(posedge clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            next_sync<=2'b11;auto_sync<=2'b11;
            dn_cnt <= 16'd0; da_cnt <= 16'd0; dn_s <= 1'b0; da_s <= 1'b0;
            dn_db <= 1'b0; dn_db_d <= 1'b0; da_db <= 1'b0;
        end else begin
            next_sync<={next_sync[0],btn_next};auto_sync<={auto_sync[0],btn_auto};
            dn_s <= next_pressed; da_s <= auto_pressed;

            if (next_pressed != dn_s)        dn_cnt <= 16'd0;
            else if (dn_cnt != 16'hFFFF) dn_cnt <= dn_cnt + 16'd1;
            else                         dn_db  <= next_pressed;

            if (auto_pressed != da_s)        da_cnt <= 16'd0;
            else if (da_cnt != 16'hFFFF) da_cnt <= da_cnt + 16'd1;
            else                         da_db  <= auto_pressed;

            dn_db_d <= dn_db;
        end
    end

    wire btn_next_db = dn_db & ~dn_db_d;
    wire btn_auto_db = da_db;


    reg swap_fault_latched;
    wire sink_fatal_ref;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) swap_fault_latched <= 1'b0;
        else if (sk_ec == 8'hF1) swap_fault_latched <= 1'b1;
    end
    video_level_sync sink_fatal_sync(.clk(clk),.rst_n(ref_rst_n),
        .async_level(swap_fault_latched),.level(sink_fatal_ref));

    sd_bmp_player #(


        .CLK_HZ(50_000_000),.CLK_DIV_INIT(PLAYER_SPI_INIT_DIV),.CLK_DIV_FAST(PLAYER_SPI_FAST_DIV)
    ) player (
        .clk(clk), .rst_n(ref_rst_n),
        .run(1'b1),
        .btn_next(btn_next_db), .btn_auto(btn_auto_db),


        .restart(btn_next_db && !sink_fatal_ref && (pl_fail_stage == 4'd1)),
        .sd_ncs(sd_ncs), .sd_dclk(sd_dclk), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
        .px_word(pl_px_word), .px_word_valid(pl_px_word_valid),
        .px_word_ready(pl_px_word_ready),
        .frame_active(pl_frame_active), .top_down_o(pl_top_down), .slot_o(pl_slot),
        .mem_ready(sk_mem_ready && card_mode && adapter_init && !(STORAGE_INTEGRITY && (integrity_fault || playback_fault)) && !swap_fault_latched && (sk_ec != 8'hF1)), .frame_done(sk_frame_done),
        .last_frame_ok(sk_frame_ok),
        .state_o(pl_state), .fail_stage(pl_fail_stage),
        .err_code(pl_ec), .err_detail(pl_ed),
        .init_r1(pl_r1), .init_seq(pl_seq),
        .sd_ready(pl_sd_ready), .card_usable(pl_card_usable),
        .file_cnt(pl_file_cnt), .cur_file(pl_cur_file),
        .cur_file_size(pl_file_size), .cur_bytes_rd(pl_bytes_rd),
        .cur_px_written(pl_px_written), .last_frame_ok_o(pl_frame_ok),
        .frame_cnt(pl_frame_cnt)
    );


    bmp_frame_sink #(.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(STORAGE_INTEGRITY),
        .GAP_TIMEOUT(MEM_CLK_HZ/250),.SWAP_TO_N(MEM_CLK_HZ/10),.WRITE_TO_N(MEM_CLK_HZ/2)) sink (
        .clk(mem_clk), .rst_n(mem_rst_n), .wr_clk(clk),
        .px_word(pl_px_word), .px_word_valid(pl_px_word_valid),
        .px_word_ready(pl_px_word_ready),
        .frame_active(pl_frame_active), .top_down(pl_top_down), .slot(pl_slot),
        .mem_ready(sk_mem_ready), .frame_done(sk_frame_done),
        .last_frame_ok(sk_frame_ok),
        .wr_req(sk_wr_req), .wr_addr(sk_wr_addr), .wr_data(sk_wr_data),
        .wr_len(sk_wr_len), .wr_ready(prod_word_accepted && card_mode),
        .write_drained(adapter_write_idle && !prod_wr_busy),
        .verify_done(integrity_done),.verify_pass(integrity_pass),
        .source_begin(integrity_begin),.source_slot(integrity_slot),.source_top_down(integrity_top_down),
        .swap_toggle(sk_swap_toggle), .swap_slot(sk_swap_slot),
        .swap_generation(sk_swap_gen), .swap_crc_ok(sk_swap_crc_ok),
        .swap_busy(swap_busy_mem),
        .state_o(sk_state), .err_code(sk_ec), .err_detail(sk_ed),
        .frame_cnt(sk_frame_cnt), .px_written(sk_px_written)
    );


    reg [3:0]  t_state1, t_state, t_fail1, t_fail;
    reg [7:0]  t_ec1,    t_ec;
    reg [7:0]  t_ed1,    t_ed;
    reg [7:0]  t_r1_1,   t_r1;
    reg [2:0]  t_seq_1,  t_seq;
    reg        t_sd1,    t_sd,   t_card1, t_card, t_fok1, t_fok;
    reg [3:0]  t_fcnt1,  t_fcnt;
    reg [1:0]  t_cur1,   t_cur;
    reg [31:0] t_bytes1, t_bytes;
    reg [15:0] t_fcnt16_1, t_fcnt16;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            t_state1<=4'd0; t_state<=4'd0; t_fail1<=4'd0; t_fail<=4'd0;
            t_ec1<=8'd0;    t_ec<=8'd0;
            t_ed1<=8'd0;    t_ed<=8'd0;
            t_r1_1<=8'd0;   t_r1<=8'd0;
            t_seq_1<=3'd0;  t_seq<=3'd0;
            t_sd1<=1'b0;    t_sd<=1'b0;    t_card1<=1'b0; t_card<=1'b0;
            t_fok1<=1'b0;   t_fok<=1'b0;
            t_fcnt1<=4'd0;  t_fcnt<=4'd0;  t_cur1<=2'd0;  t_cur<=2'd0;
            t_bytes1<=32'd0;t_bytes<=32'd0;
            t_fcnt16_1<=16'd0; t_fcnt16<=16'd0;
        end else begin
            t_state1 <= pl_state;        t_state  <= t_state1;
            t_fail1  <= pl_fail_stage;   t_fail   <= t_fail1;
            t_ec1    <= pl_ec;           t_ec     <= t_ec1;
            t_ed1    <= pl_ed;           t_ed     <= t_ed1;
            t_r1_1   <= pl_r1;           t_r1     <= t_r1_1;
            t_seq_1  <= pl_seq;          t_seq    <= t_seq_1;
            t_sd1    <= pl_sd_ready;     t_sd     <= t_sd1;
            t_card1  <= pl_card_usable;  t_card   <= t_card1;
            t_fok1   <= pl_frame_ok;     t_fok    <= t_fok1;
            t_fcnt1  <= pl_file_cnt;     t_fcnt   <= t_fcnt1;
            t_cur1   <= pl_cur_file;     t_cur    <= t_cur1;
            t_bytes1 <= pl_bytes_rd;     t_bytes  <= t_bytes1;
            t_fcnt16_1 <= pl_frame_cnt;  t_fcnt16 <= t_fcnt16_1;
        end
    end


    reg  fb_start, fb_go, fb_valid, fb_toggle, fb_submitted, fb_drain_on;
    reg  [9:0] fb_x, fb_y, fb_drain;
    wire fb_ready, fb_wr_req, fb_wr_done, fb_crc_ok, fb_wr_error;
    wire [3:0] fb_slot_valid;
    wire [31:0] fb_wr_addr, fb_wr_data;
    wire [15:0] fb_wr_len;
    wire [18:0] fb_px;


    reg fb_swap_seen,fb_swap_acked;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            fb_start<=1'b0; fb_go<=1'b0; fb_valid<=1'b0; fb_x<=10'd0; fb_y<=10'd0;
            fb_toggle<=1'b0; fb_submitted<=1'b0; fb_drain_on<=1'b0; fb_drain<=10'd0;
        end else begin
            fb_start <= 1'b0;
            if (card_mode || fb_submitted) begin
                fb_valid <= 1'b0;
            end else begin
                if (sdr_init_done && !fb_go) begin fb_start <= 1'b1; fb_go <= 1'b1; end
                if (fb_go) begin

                    if (fb_valid && fb_ready) begin
                        if (fb_x == `SV_FRAME_WIDTH-1) begin
                            fb_x <= 10'd0;
                            if (fb_y == `SV_FRAME_HEIGHT-1) begin
                                fb_y <= `SV_FRAME_HEIGHT;
                                fb_valid <= 1'b0;
                            end else begin
                                fb_y <= fb_y + 10'd1;
                                fb_valid <= 1'b1;
                            end
                        end else begin
                            fb_x <= fb_x + 10'd1;
                            fb_valid <= 1'b1;
                        end
                    end else if (fb_y != `SV_FRAME_HEIGHT) begin
                        fb_valid <= 1'b1;
                    end


                    if (!fb_drain_on) begin
                        if (fb_wr_done && fb_crc_ok && fb_slot_valid[0]) fb_drain_on <= 1'b1;
                    end else if (fb_drain == 10'd1023 && adapter_write_idle && !prod_wr_busy) begin
                        fb_toggle   <= ~fb_toggle;
                        fb_submitted<= 1'b1;
                        fb_drain_on <= 1'b0;
                    end else begin
                        if(fb_drain!=10'd1023)fb_drain <= fb_drain + 10'd1;
                    end
                end
            end
        end
    end

    wire [15:0] fb_rgb565 = {fb_x[9:5], fb_y[8:3], fb_x[8:4]};

    frame_writer #(.GAP_TIMEOUT(32'd12500000)) fb_writer(
        .clk(mem_clk), .rst_n(mem_rst_n), .start(fb_start), .slot_sel(2'd0),
        .slot_base(`SV_IMG0_BASE),
        .din(fb_rgb565), .din_valid(fb_valid), .din_ready(fb_ready),
        .wr_req(fb_wr_req), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .wr_len(fb_wr_len), .wr_ready(prod_word_accepted && !card_mode), .wr_done(fb_wr_done),
        .slot_valid(fb_slot_valid), .crc_ok(fb_crc_ok), .crc_value(), .px_cnt(fb_px),
        .wr_error(fb_wr_error), .err_code(), .err_detail());


    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            card_mode<=1'b1;mode_cnt<=0;fb_swap_seen<=0;fb_swap_acked<=0;
        end else begin
            if(fb_submitted && swap_busy_mem)fb_swap_seen<=1;
            if(fb_swap_seen && !swap_busy_mem)fb_swap_acked<=1;


            if(!card_mode && fb_swap_acked && t_card && !prod_wr_busy)card_mode<=1;


            if (t_card && !fb_go) begin card_mode <= 1'b1; mode_cnt <= 32'd0; end
            else if (card_mode && !fb_go && t_fcnt16 == 16'd0) begin
                if (!STORAGE_INTEGRITY && mode_cnt >= MODE_TO_N) card_mode <= 1'b0;
                else mode_cnt <= mode_cnt + 32'd1;
            end
        end
    end


    wire        prod_wr_req  = card_mode ? sk_wr_req  : fb_wr_req;
    wire [31:0] prod_wr_addr = card_mode ? sk_wr_addr : fb_wr_addr;
    wire [31:0] prod_wr_data = card_mode ? sk_wr_data : fb_wr_data;
    wire [15:0] prod_wr_len  = card_mode ? sk_wr_len  : fb_wr_len;


    reg sk_toggle_d,fb_toggle_d,publish_toggle;
    reg [1:0] publish_slot;reg [7:0] publish_gen;reg publish_crc;
    always @(posedge mem_clk or negedge mem_rst_n)begin
      if(!mem_rst_n)begin
        sk_toggle_d<=0;fb_toggle_d<=0;publish_toggle<=0;
        publish_slot<=0;publish_gen<=0;publish_crc<=0;
      end else begin
        sk_toggle_d<=sk_swap_toggle;fb_toggle_d<=fb_toggle;
        if(card_mode && (sk_swap_toggle!=sk_toggle_d))begin
          publish_toggle<=~publish_toggle;publish_slot<=sk_swap_slot;
          publish_gen<=publish_gen+1'b1;publish_crc<=sk_swap_crc_ok;
        end else if(!card_mode && (fb_toggle!=fb_toggle_d))begin
          publish_toggle<=~publish_toggle;publish_slot<=0;
          publish_gen<=publish_gen+1'b1;publish_crc<=fb_crc_ok;
        end
      end
    end
    wire prod_toggle=publish_toggle;
    wire [1:0] prod_slot=publish_slot;
    wire [7:0] prod_gen=publish_gen;
    wire prod_crc_ok=publish_crc;


    wire [1:0] slot_sys;
    wire [7:0] gen_sys;
    wire crc_sys,frame_ready,submit_ready;
    reg sent_toggle;
    wire submit_valid=(prod_toggle!=sent_toggle);
    always @(posedge mem_clk or negedge mem_rst_n)begin
      if(!mem_rst_n)sent_toggle<=0;
      else if(submit_valid&&submit_ready)sent_toggle<=prod_toggle;
    end


    video_cdc_mailbox #(.WIDTH(11)) board_frame_mailbox(
      .src_clk(mem_clk),.src_rst_n(mem_rst_n),.src_data({prod_crc_ok,prod_slot,prod_gen}),
      .src_valid(submit_valid),.src_ready(submit_ready),
      .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_data({crc_sys,slot_sys,gen_sys}),
      .dst_valid(frame_ready),.dst_ready(1'b1));


    wire [23:0] rgb;
    wire [11:0] out_x, out_y;
    wire        out_de, out_vs, active, swap_error, frame_fault;
    wire [2:0]  swap_state;
    wire [31:0] underflows, missed, overflows;
    wire [11:0] scan_x,scan_y;
    wire scan_de,scan_frame_start,safety_active;
    wire [1:0] safety_level;
    wire [23:0] safety_rgb;wire safety_valid;
    reg media_fault_ref,storage_fault_mem;
    always @(posedge clk or negedge ref_rst_n)
        if(!ref_rst_n)media_fault_ref<=0;else media_fault_ref<=(pl_state==4'd10);
    always @(posedge mem_clk or negedge mem_rst_n)
        if(!mem_rst_n)storage_fault_mem<=0;
        else storage_fault_mem<=memory_error||adapter_fault||(STORAGE_INTEGRITY&&(integrity_fault||playback_fault))||swap_fault_latched||fb_wr_error||(sk_ec!=0);
    board_display_guard display_guard(
        .pixel_clk(pixel_clk),.rst_n(pixel_rst_n),.frame_start(scan_frame_start),
        .active_frame(active),.frame_fault(frame_fault),
        .media_fault_async(media_fault_ref),
        .storage_fault_async(storage_fault_mem),
        .manual_async(!btn_emergency),.safety_active(safety_active),.warning_level(safety_level));
    emergency_graphics #(.HD(HD),.FONT_FILE(FONT_FILE)) safety_scene(
        .clk(pixel_clk),.rst_n(pixel_rst_n),.de(scan_de),.frame_start(scan_frame_start),
        .x(scan_x),.y(scan_y),.active(safety_active),.direction(2'd2),
        .warning_level(safety_level),.rgb(safety_rgb),.valid(safety_valid));


    assign integrity_fault=1'b0, integrity_pass=1'b0, integrity_done=1'b0;
    assign integrity_bad_addr=32'd0, integrity_expected=32'd0, integrity_actual=32'd0;
    assign integrity_word_last=32'd0, integrity_fail_cnt=12'd0;
    assign integrity_words=32'd0, integrity_blocks=16'd0;
    assign lookup_crc=32'd0, lookup_valid=1'b0;
    assign verify_req=1'b0, verify_addr=32'd0;

    safevision_core #(.HD(HD), .FONT_FILE(FONT_FILE),.EMERGENCY_LATENCY(4),.DMA_STREAMING(1),.DMA_CHECKED(STORAGE_INTEGRITY),.FIFO_AW(STORAGE_INTEGRITY?11:12),.BURST_WORDS(STORAGE_INTEGRITY?64:256)) core(
        .sys_clk(sys_clk), .mem_clk(mem_clk), .pixel_clk(pixel_clk), .rst_n(common_rst_n),
        .frame_ready(frame_ready), .wr_frame_index(1'b0), .wr_slot_id(slot_sys),
        .wr_generation(gen_sys), .wr_crc_ok(crc_sys),
        .active_commit(), .active_next(), .generation_next(), .frame_index_next(),
        .swap_error(swap_error), .swap_state_o(swap_state),
        .frame_start_evt_b(), .swap_ack_evt_b(),
        .wr_req(prod_wr_req), .wr_addr(prod_wr_addr), .wr_data(prod_wr_data),
        .wr_len(prod_wr_len), .wr_ack(prod_wr_ack), .wr_busy(prod_wr_busy),
        .sd_req(verify_req&&STORAGE_INTEGRITY), .sd_wr(1'b0), .sd_addr(verify_addr), .sd_wdata(32'd0), .sd_len(16'd64),
        .sd_ack(verify_ack), .sd_busy(verify_busy), .sd_rdata(verify_data), .sd_rdata_valid(verify_valid),
        .mem_req(mem_req), .mem_wr(mem_wr), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_ready(mem_ready), .mem_rdata(mem_rdata), .mem_rdata_valid(mem_rvalid),
        .wr_starve_cnt(), .rd_starve_cnt(),
        .cfg_valid(1'b0), .cfg_ready(), .cfg_osd_enable(1'b0), .cfg_mode(2'd0),
        .cfg_fps_tens(4'd6), .cfg_fps_ones(4'd0), .cfg_sd_ok(1'b1),
        .cfg_origin_x(12'd0), .cfg_origin_y(12'd0), .cfg_foreground(24'hffffff),
        .emergency_rgb(safety_rgb), .emergency_valid(safety_valid),
        .scan_x(scan_x), .scan_y(scan_y), .scan_de(scan_de), .scan_frame_start(scan_frame_start),
        .rgb(rgb), .x(out_x), .y(out_y), .hsync(), .vsync(out_vs), .de(out_de),
        .pixel_valid(), .line_start(), .frame_start(), .active_frame_start(),
        .hblank(), .vblank(), .selected_layer(), .pix_active_slot(),
        .pix_generation(), .pix_frame_index(), .pix_active_valid(active),
        .pix_frame_fault(frame_fault), .pix_underflow_count(underflows),
        .pix_missed_frame_count(missed), .mem_overflow_count(overflows),
        .mem_fifo_pixels(display_fifo_level), .mem_dma_bytes(), .mem_dma_active(display_dma_active), .mem_dma_done(),
        .mem_fetch_state(),.expected_crc(lookup_crc),.expected_valid(lookup_valid),.crc_lookup_addr(lookup_addr),
        .integrity_fault(video_integrity_fault),.bad_addr(video_bad_addr),.bad_expected(video_expected),.bad_actual(video_actual));


    wire swap_busy_sys = (swap_state != 3'd0);
    reg  [2:0] sb_sync;
    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin sb_sync <= 3'd0; swap_busy_mem <= 1'b0; end
        else begin
            sb_sync <= {sb_sync[1:0], swap_busy_sys};
            swap_busy_mem <= sb_sync[2];
        end
    end


    wire [23:0] axis_data;
    wire axis_valid,axis_user,axis_last,axis_ready,hdmi_backpressure;
    wire hdmi_resync;wire [31:0] hdmi_dropped_frames;wire [4:0] hdmi_queue_level;


    hdmi_video_bridge #(.HD(HD),.QUEUE_AW(4)) hdmi_queue(
      .clk(pixel_clk),.rst_n(pixel_rst_n),.rgb(rgb),.de(out_de),.x(out_x),.y(out_y),
      .axis_valid(axis_valid),.axis_user(axis_user),.axis_last(axis_last),.axis_data(axis_data),
      .axis_ready(axis_ready),.resync(hdmi_resync),.overflow_sticky(hdmi_backpressure),
      .dropped_frames(hdmi_dropped_frames),.queue_level(hdmi_queue_level));
    wire tx_reset=!pixel_rst_n||hdmi_resync;
    wire phy_rst_n;
    reset_sync reset_phy(.clk(serial_clk),.async_rst_n(!tx_reset),.rst_n(phy_rst_n));


    reg [16:0] edid_count; reg edid_trig;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin edid_count <= 17'd0; edid_trig <= 1'b0; end
        else begin
            edid_trig <= 1'b0;


            if (tx_reset) edid_count <= 17'd0;
            else if (edid_count < 17'd100000) begin
                edid_count <= edid_count + 17'd1;
                if (edid_count == 17'd99999) edid_trig <= 1'b1;
            end
        end
    end

    wire [9:0] ch0, ch1, ch2, chclk;
    wire       hdmi_locked;

    hdmi_1_4b_transmitter_core_wrapper #(
        .DEVICE("EG"), .HTOTAL(HD ? 1650 : 800),
        .HSA(HD ? 40 : 96), .HFP(HD ? 110 : 16),
        .HBP(HD ? 220 : 48), .HACTIVE(HD ? 1280 : 640),
        .VTOTAL(HD ? 750 : 525), .VSA(HD ? 5 : 2),
        .VFP(HD ? 5 : 10), .VBP(HD ? 20 : 33),
        .VACTIVE(HD ? 720 : 480), .VIDEO_VIC(HD ? 4 : 1),
        .VIDEO_TPG("Disable"), .VIDEO_FORMAT("RGB"),
        .AUDIO_SAMPLE_RATE("48K"), .IIC_SCL_DIV(250)
    ) transmitter(
        .I_pixel_clk(pixel_clk), .I_rst(tx_reset),
        .I_edid_read_trig(edid_trig), .O_edid_read_valid(), .O_edid_read_data(),
        .I_axis_s_user(axis_user), .I_axis_s_valid(axis_valid),
        .I_axis_s_last(axis_last), .I_axis_s_data(axis_data),
        .O_axis_s_ready(axis_ready),
        .I_audio_valid(1'b0), .I_audio_left_data(24'd0), .I_audio_right_data(24'd0),
        .I_acr_valid(1'b0), .I_acr_cts(20'd0), .I_acr_n(20'd0),
        .O_video_locked(hdmi_locked),
        .O_ddc_scl(HDMI_DDC_SCL), .IO_ddc_sda(HDMI_DDC_SDA),
        .O_ch0_tmds_data(ch0), .O_ch1_tmds_data(ch1),
        .O_ch2_tmds_data(ch2), .O_clk_tmds_data(chclk));

    hdmi_phy_wrapper #(.DEVICE("EG")) serializer(
        .I_pixel_clk(pixel_clk), .I_serial_clk(serial_clk), .I_rst(!phy_rst_n),
        .I_tmds_channel_0(ch0), .I_tmds_channel_1(ch1),
        .I_tmds_channel_2(ch2), .I_tmds_channel_clk(chclk),
        .O_tmds_ch0_p(HDMI_D0_P), .O_tmds_ch1_p(HDMI_D1_P),
        .O_tmds_ch2_p(HDMI_D2_P), .O_tmds_clk_p(HDMI_CLK_P));


    localparam integer RPT_LEN    = 189;
    localparam [31:0]  RPT_PERIOD = RPT_PERIOD_N;


    reg [3:0] diagnostic_phase;
    reg [31:0] diagnostic_addr,diagnostic_expected,diagnostic_actual,diagnostic_words;
    reg [15:0] diagnostic_blocks;
    reg [7:0]  ridx;
    reg [31:0] rper;
    reg        rbusy, rload;
    reg        rwait;
    reg [7:0]  rbyte;
    wire       uart_ready;


    reg [7:0]  rbyte_c;

    always @(posedge mem_clk or negedge mem_rst_n) begin
        if (!mem_rst_n) begin
            ridx <= 8'd0; rper <= 32'd0; rbusy <= 1'b0; rload <= 1'b0; rbyte <= 8'd0;
            rwait <= 1'b0;
            diagnostic_phase<=0;diagnostic_addr<=0;diagnostic_expected<=0;
            diagnostic_actual<=0;diagnostic_words<=0;diagnostic_blocks<=0;
        end else begin
            if (!rbusy) begin
                if (rper >= RPT_PERIOD) begin
                    rper <= 32'd0; rbusy <= 1'b1; ridx <= 8'd0; rload <= 1'b1;
                    diagnostic_phase<=playback_fault?4:integrity_fault?3:integrity_pass?2:sk_state==4?1:0;
                    diagnostic_addr<=playback_fault?playback_bad_addr:integrity_bad_addr;
                    diagnostic_expected<=playback_fault?playback_expected:integrity_expected;
                    diagnostic_actual<=playback_fault?playback_actual:integrity_actual;
                    diagnostic_words<=integrity_words;diagnostic_blocks<=integrity_blocks;
                end else rper <= rper + 32'd1;
            end else if (rload) begin


                if (rwait) begin
                    rbyte <= rbyte_c;
                    rload <= 1'b0;
                    rwait <= 1'b0;
                end else rwait <= 1'b1;
            end else if (uart_ready) begin
                if (ridx == RPT_LEN-1) begin rbusy <= 1'b0; ridx <= 8'd0; end
                else begin ridx <= ridx + 8'd1; rload <= 1'b1; end
            end
        end
    end

    function [7:0] hexc;
        input [3:0] v;
        begin
            hexc = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h41 + {4'd0, v} - 8'd10);
        end
    endfunction


    wire [7:0] rpt_ec = (sk_ec != 8'h00) ? sk_ec : t_ec;

    always @* begin
        case (ridx)
            8'd0: rbyte_c = 8'h53; 8'd1: rbyte_c = 8'h56; 8'd2: rbyte_c = 8'h2D;

            8'd3: rbyte_c = 8'h44; 8'd4: rbyte_c = 8'h34; 8'd5: rbyte_c = 8'h30;
            8'd6: rbyte_c = 8'h52;
            8'd7: rbyte_c = 8'h20; 8'd8: rbyte_c = 8'h53;
            8'd9: rbyte_c = 8'h54; 8'd10: rbyte_c = 8'h3D;
            8'd11: rbyte_c = hexc(t_state);
            8'd12: rbyte_c = 8'h20; 8'd13: rbyte_c = 8'h46; 8'd14: rbyte_c = 8'h53;
            8'd15: rbyte_c = 8'h3D;
            8'd16: rbyte_c = hexc(t_fail);
            8'd17: rbyte_c = 8'h20; 8'd18: rbyte_c = 8'h45; 8'd19: rbyte_c = 8'h43;
            8'd20: rbyte_c = 8'h3D;
            8'd21: rbyte_c = hexc(rpt_ec[7:4]); 8'd22: rbyte_c = hexc(rpt_ec[3:0]);
            8'd23: rbyte_c = 8'h20; 8'd24: rbyte_c = 8'h53; 8'd25: rbyte_c = 8'h44;
            8'd26: rbyte_c = 8'h3D;
            8'd27: rbyte_c = hexc({3'd0, t_sd});
            8'd28: rbyte_c = 8'h20; 8'd29: rbyte_c = 8'h43; 8'd30: rbyte_c = 8'h41;
            8'd31: rbyte_c = 8'h52; 8'd32: rbyte_c = 8'h44; 8'd33: rbyte_c = 8'h3D;
            8'd34: rbyte_c = hexc({3'd0, t_card});
            8'd35: rbyte_c = 8'h20; 8'd36: rbyte_c = 8'h43; 8'd37: rbyte_c = 8'h4E;
            8'd38: rbyte_c = 8'h54; 8'd39: rbyte_c = 8'h3D;
            8'd40: rbyte_c = hexc(t_fcnt);
            8'd41: rbyte_c = 8'h20; 8'd42: rbyte_c = 8'h43; 8'd43: rbyte_c = 8'h55;
            8'd44: rbyte_c = 8'h52; 8'd45: rbyte_c = 8'h3D;
            8'd46: rbyte_c = hexc({2'd0, t_cur});
            8'd47: rbyte_c = 8'h20; 8'd48: rbyte_c = 8'h52; 8'd49: rbyte_c = 8'h44;
            8'd50: rbyte_c = 8'h3D;
            8'd51: rbyte_c = hexc(t_bytes[31:28]); 8'd52: rbyte_c = hexc(t_bytes[27:24]);
            8'd53: rbyte_c = hexc(t_bytes[23:20]); 8'd54: rbyte_c = hexc(t_bytes[19:16]);
            8'd55: rbyte_c = hexc(t_bytes[15:12]); 8'd56: rbyte_c = hexc(t_bytes[11:8]);
            8'd57: rbyte_c = hexc(t_bytes[7:4]);   8'd58: rbyte_c = hexc(t_bytes[3:0]);
            8'd59: rbyte_c = 8'h20; 8'd60: rbyte_c = 8'h50; 8'd61: rbyte_c = 8'h58;
            8'd62: rbyte_c = 8'h3D;
            8'd63: rbyte_c = hexc({1'b0, sk_px_written[18:16]});
            8'd64: rbyte_c = hexc(sk_px_written[15:12]); 8'd65: rbyte_c = hexc(sk_px_written[11:8]);
            8'd66: rbyte_c = hexc(sk_px_written[7:4]);   8'd67: rbyte_c = hexc(sk_px_written[3:0]);
            8'd68: rbyte_c = 8'h20; 8'd69: rbyte_c = 8'h46; 8'd70: rbyte_c = 8'h3D;
            8'd71: rbyte_c = hexc(sk_frame_cnt[15:12]); 8'd72: rbyte_c = hexc(sk_frame_cnt[11:8]);
            8'd73: rbyte_c = hexc(sk_frame_cnt[7:4]);   8'd74: rbyte_c = hexc(sk_frame_cnt[3:0]);
            8'd75: rbyte_c = 8'h20; 8'd76: rbyte_c = 8'h53; 8'd77: rbyte_c = 8'h4C;
            8'd78: rbyte_c = 8'h4F; 8'd79: rbyte_c = 8'h54; 8'd80: rbyte_c = 8'h3D;
            8'd81: rbyte_c = hexc({2'd0, sk_swap_slot});
            8'd82: rbyte_c = 8'h20; 8'd83: rbyte_c = 8'h43; 8'd84: rbyte_c = 8'h52;
            8'd85: rbyte_c = 8'h43; 8'd86: rbyte_c = 8'h3D;
            8'd87: rbyte_c = hexc({3'd0, sk_swap_crc_ok});
            8'd88: rbyte_c = 8'h20; 8'd89: rbyte_c = 8'h45; 8'd90: rbyte_c = 8'h44;
            8'd91: rbyte_c = 8'h3D;
            8'd92: rbyte_c = hexc(t_ed[7:4]); 8'd93: rbyte_c = hexc(t_ed[3:0]);
            8'd94: rbyte_c = 8'h20; 8'd95: rbyte_c = 8'h52; 8'd96: rbyte_c = 8'h31;
            8'd97: rbyte_c = 8'h3D;
            8'd98: rbyte_c = hexc(t_r1[7:4]); 8'd99: rbyte_c = hexc(t_r1[3:0]);
            8'd100: rbyte_c = 8'h20; 8'd101: rbyte_c = 8'h53; 8'd102: rbyte_c = 8'h51;
            8'd103: rbyte_c = 8'h3D;
            8'd104: rbyte_c = hexc({1'b0, t_seq});
            8'd105: rbyte_c = 8'h0D; 8'd106: rbyte_c = 8'h0A;
            8'd107: rbyte_c = 8'h53;
            8'd108: rbyte_c = 8'h56;
            8'd109: rbyte_c = 8'h2d;
            8'd110: rbyte_c = 8'h4d;
            8'd111: rbyte_c = 8'h45;
            8'd112: rbyte_c = 8'h4d;
            8'd113: rbyte_c = 8'h20;
            8'd114: rbyte_c = 8'h49;
            8'd115: rbyte_c = 8'h44;
            8'd116: rbyte_c = 8'h3d;
            8'd117: rbyte_c = 8'h32;
            8'd118: rbyte_c = 8'h36;
            8'd119: rbyte_c = 8'h31;
            8'd120: rbyte_c = 8'h30;
            8'd121: rbyte_c = 8'h31;
            8'd122: rbyte_c = 8'h30;
            8'd123: rbyte_c = 8'h30;
            8'd124: rbyte_c = 8'h47;
            8'd125: rbyte_c = 8'h20;
            8'd126: rbyte_c = 8'h50;
            8'd127: rbyte_c = 8'h48;
            8'd128: rbyte_c = 8'h3d;
            8'd129: rbyte_c = hexc(diagnostic_phase[3:0]);
            8'd130: rbyte_c = 8'h20;
            8'd131: rbyte_c = 8'h42;
            8'd132: rbyte_c = 8'h41;
            8'd133: rbyte_c = 8'h44;
            8'd134: rbyte_c = 8'h3d;
            8'd135: rbyte_c = hexc(diagnostic_addr[31:28]);
            8'd136: rbyte_c = hexc(diagnostic_addr[27:24]);
            8'd137: rbyte_c = hexc(diagnostic_addr[23:20]);
            8'd138: rbyte_c = hexc(diagnostic_addr[19:16]);
            8'd139: rbyte_c = hexc(diagnostic_addr[15:12]);
            8'd140: rbyte_c = hexc(diagnostic_addr[11:8]);
            8'd141: rbyte_c = hexc(diagnostic_addr[7:4]);
            8'd142: rbyte_c = hexc(diagnostic_addr[3:0]);
            8'd143: rbyte_c = 8'h20;
            8'd144: rbyte_c = 8'h45;
            8'd145: rbyte_c = 8'h58;
            8'd146: rbyte_c = 8'h50;
            8'd147: rbyte_c = 8'h3d;
            8'd148: rbyte_c = hexc(diagnostic_expected[31:28]);
            8'd149: rbyte_c = hexc(diagnostic_expected[27:24]);
            8'd150: rbyte_c = hexc(diagnostic_expected[23:20]);
            8'd151: rbyte_c = hexc(diagnostic_expected[19:16]);
            8'd152: rbyte_c = hexc(diagnostic_expected[15:12]);
            8'd153: rbyte_c = hexc(diagnostic_expected[11:8]);
            8'd154: rbyte_c = hexc(diagnostic_expected[7:4]);
            8'd155: rbyte_c = hexc(diagnostic_expected[3:0]);
            8'd156: rbyte_c = 8'h20;
            8'd157: rbyte_c = 8'h47;
            8'd158: rbyte_c = 8'h4f;
            8'd159: rbyte_c = 8'h54;
            8'd160: rbyte_c = 8'h3d;
            8'd161: rbyte_c = hexc(diagnostic_actual[31:28]);
            8'd162: rbyte_c = hexc(diagnostic_actual[27:24]);
            8'd163: rbyte_c = hexc(diagnostic_actual[23:20]);
            8'd164: rbyte_c = hexc(diagnostic_actual[19:16]);
            8'd165: rbyte_c = hexc(diagnostic_actual[15:12]);
            8'd166: rbyte_c = hexc(diagnostic_actual[11:8]);
            8'd167: rbyte_c = hexc(diagnostic_actual[7:4]);
            8'd168: rbyte_c = hexc(diagnostic_actual[3:0]);
            8'd169: rbyte_c = 8'h20;
            8'd170: rbyte_c = 8'h57;
            8'd171: rbyte_c = 8'h3d;
            8'd172: rbyte_c = hexc(diagnostic_words[31:28]);
            8'd173: rbyte_c = hexc(diagnostic_words[27:24]);
            8'd174: rbyte_c = hexc(diagnostic_words[23:20]);
            8'd175: rbyte_c = hexc(diagnostic_words[19:16]);
            8'd176: rbyte_c = hexc(diagnostic_words[15:12]);
            8'd177: rbyte_c = hexc(diagnostic_words[11:8]);
            8'd178: rbyte_c = hexc(diagnostic_words[7:4]);
            8'd179: rbyte_c = hexc(diagnostic_words[3:0]);
            8'd180: rbyte_c = 8'h20;
            8'd181: rbyte_c = 8'h42;
            8'd182: rbyte_c = 8'h3d;
            8'd183: rbyte_c = hexc(diagnostic_blocks[15:12]);
            8'd184: rbyte_c = hexc(diagnostic_blocks[11:8]);
            8'd185: rbyte_c = hexc(diagnostic_blocks[7:4]);
            8'd186: rbyte_c = hexc(diagnostic_blocks[3:0]);
            8'd187: rbyte_c = 8'h0d;
            8'd188: rbyte_c = 8'h0a;
            default: rbyte_c = 8'h20;
        endcase
    end

    uart_tx #(.CLK_FREQ(MEM_CLK_HZ), .BAUD(115200)) u_uart(
        .clk(mem_clk), .rst_n(mem_rst_n),
        .tx_valid(rbusy && !rload),
        .tx_data(rbyte),
        .tx_ready(uart_ready),
        .txd(uart_txd));


    wire frame_ok_any = card_mode ? t_fok : fb_crc_ok;
    assign led = { hdmi_locked && !hdmi_backpressure && !frame_fault && !swap_error,
                   active && !swap_error,
                   (card_mode ? t_card : fb_submitted) && frame_ok_any,
                   sys_lock && video_lock && sdr_init_done };

endmodule
