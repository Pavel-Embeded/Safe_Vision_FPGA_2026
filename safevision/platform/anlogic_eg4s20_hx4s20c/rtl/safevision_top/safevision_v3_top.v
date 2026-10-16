// SafeVision V3 production board assembly. Legacy safevision_top is kept as
// a separately buildable baseline. Every external producer retains data until
// acceptance; every telemetry bus crosses an acknowledged atomic mailbox.
`define SAFEVISION_MEM_CLK_HZ 50000000
`define SAFEVISION_SDRAM_CLK_HZ `SAFEVISION_MEM_CLK_HZ
`define SAFEVISION_REFRESH_ROWS 4096
`include "pixel_format_defs.vh"
`ifndef SAFEVISION_BOARD_HD
`define SAFEVISION_BOARD_HD 0
`endif
module safevision_v3_top #(parameter integer HD=`SAFEVISION_BOARD_HD)(
 input wire clk,rst_n,btn_next,btn_auto,btn_emergency,uart_rxd,
 output reg uart_txd,output reg[3:0] led,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,
 output wire HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P,HDMI_DDC_SCL,
 inout wire HDMI_DDC_SDA);
 // Official PLL counters, rounded to the nearest counter cycle per second.
 // BASE: 50MHz*17*4/(3*45); HD: 50MHz*1*89/(4*15).
 // These are configured nominal frequencies, not measured oscillator values.
 localparam integer PIXEL_HZ=HD?74166667:25185185;
 wire sys_clk,mem_clk,mem_clk_sft,pixel_clk,serial_clk,audio_clk;
 wire sys_lock,video_lock,audio_lock,ref_rst_n,common_rst_n,control_common_rst_n;
 wire sys_rst_n,mem_rst_n,pixel_rst_n,audio_rst_n;
 wire ref_media_rst_n,mem_media_rst_n,sys_media_rst_n,media_reset;
 reset_sync reset_ref(.clk(clk),.async_rst_n(rst_n),.rst_n(ref_rst_n));
 sv_v3_memory_pll system_pll(.refclk(clk),.reset(1'b0),.extlock(sys_lock),
 .clk0_out(sys_clk),.clk1_out(mem_clk),.clk2_out(mem_clk_sft));
 generate if(HD==0)begin:video_base
 sv_video_vga_pll video_pll(.refclk(clk),.reset(1'b0),.extlock(video_lock),
 .clk0_out(),.clk1_out(pixel_clk),.clk2_out(serial_clk));
 end else begin:video_hd
 sv_video_hd_pll video_pll(.refclk(clk),.reset(1'b0),.extlock(video_lock),
 .clk0_out(),.clk1_out(pixel_clk),.clk2_out(serial_clk));end endgenerate
 sv_audio_pll sound_pll(.refclk(clk),.reset(1'b0),.extlock(audio_lock),.clk0_out(),.clk1_out(audio_clk));
 assign control_common_rst_n=ref_rst_n && sys_lock;
 assign common_rst_n=control_common_rst_n && video_lock && audio_lock;
 // Video/audio loss must not clear the surviving SYS fault records/UART.
 reset_sync reset_sys(.clk(sys_clk),.async_rst_n(control_common_rst_n),.rst_n(sys_rst_n));
 reset_sync #(.RELEASE_FALLING(1)) reset_mem(.clk(mem_clk),.async_rst_n(control_common_rst_n),.rst_n(mem_rst_n));
 reset_sync reset_pixel(.clk(pixel_clk),.async_rst_n(control_common_rst_n && video_lock),.rst_n(pixel_rst_n));
 reset_sync reset_audio(.clk(audio_clk),.async_rst_n(control_common_rst_n && audio_lock),.rst_n(audio_rst_n));
 // Recovery assertions belong to one common media epoch. SYS safety, fixed
 // PIX raster, ROM, alarm and HDMI PHY remain on their global reset epoch.
 (* keep="true" *) wire media_common_rst_n=control_common_rst_n && !media_reset;
 reset_sync reset_media_ref(.clk(clk),.async_rst_n(media_common_rst_n),.rst_n(ref_media_rst_n));
 reset_sync #(.RELEASE_FALLING(1)) reset_media_mem(.clk(mem_clk),.async_rst_n(media_common_rst_n),.rst_n(mem_media_rst_n));
 reset_sync reset_media_sys(.clk(sys_clk),.async_rst_n(media_common_rst_n),.rst_n(sys_media_rst_n));

 wire sdr_init_done,sdr_ref_valid,sdr_busy,app_wr_en,app_rd_en,sdr_rd_en;
 wire[20:0] app_wr_addr,app_rd_addr;wire[3:0] app_wr_dm;wire[31:0] app_wr_din,sdr_rd_dout;
 sdram memory_ip(.Clk(mem_clk),.Clk_sft(mem_clk_sft),.Rst(!mem_media_rst_n),
 .Sdr_init_done(sdr_init_done),.Sdr_init_ref_vld(sdr_ref_valid),.Sdr_busy(sdr_busy),
 .App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),.App_wr_dm(app_wr_dm),.App_wr_din(app_wr_din),
 .App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),.Sdr_rd_en(sdr_rd_en),.Sdr_rd_dout(sdr_rd_dout));
 wire adapter_req,adapter_wr,adapter_ready,adapter_valid,adapter_init,adapter_idle,adapter_fault;
 wire[31:0] adapter_addr,adapter_wdata,adapter_rdata;wire[3:0] adapter_wstrb;
 sdram_app_adapter #(.FAST_READ(1),.PREFETCH_READ(1)) adapter(.clk(mem_clk),.rst_n(mem_media_rst_n),
 .req(adapter_req),.wr(adapter_wr),.addr(adapter_addr),.wdata(adapter_wdata),.wstrb(adapter_wstrb),
 .rdata(adapter_rdata),.rdata_valid(adapter_valid),.ready(adapter_ready),.init_done(adapter_init),
 .write_idle(adapter_idle),.protocol_fault(adapter_fault),.Sdr_init_done(sdr_init_done),
 .Sdr_init_ref_vld(sdr_ref_valid),.Sdr_busy(sdr_busy),.App_wr_en(app_wr_en),.App_wr_addr(app_wr_addr),
 .App_wr_dm(app_wr_dm),.App_wr_din(app_wr_din),.App_rd_en(app_rd_en),.App_rd_addr(app_rd_addr),
 .Sdr_rd_en(sdr_rd_en),.Sdr_rd_dout(sdr_rd_dout));
 wire mem_req,mem_wr,mem_ready,mem_valid,memory_error;
 wire[31:0] mem_addr,mem_wdata,mem_rdata;wire[3:0] mem_wstrb;
 mem_ctrl memory(.clk(mem_clk),.rst_n(mem_media_rst_n),.init_done(),.req(mem_req),.wr(mem_wr),
 .addr(mem_addr),.wdata(mem_wdata),.wstrb(mem_wstrb),.rdata(mem_rdata),.rdata_valid(mem_valid),
 .ready(mem_ready),.mem_error(memory_error),.sdram_req(adapter_req),.sdram_wr(adapter_wr),
 .sdram_addr(adapter_addr),.sdram_wdata(adapter_wdata),.sdram_wstrb(adapter_wstrb),
 .sdram_rdata(adapter_rdata),.sdram_rdata_valid(adapter_valid),.sdram_ready(adapter_ready),.sdram_init_done(adapter_init));

 wire[31:0] px_word;wire px_valid,px_ready,frame_active,top_down;
 wire[1:0] load_slot;wire[3:0] player_state,player_stage;
 wire[7:0] player_code,player_detail;wire sd_ready,card_usable;
 wire[3:0] cache_ref;wire[2:0] cache_count;wire[63:0] cache_keys;wire[15:0] rejected_files;
 wire[31:0] player_bytes,player_progress;wire[15:0] player_frames,last_reject_error,last_reject_key;
 wire sink_ready,sink_done,sink_ok;
 wire ext_req,ext_ready,ext_valid,ext_data_ready,ext_last,ext_done,ext_timeout,ext_crc;
 wire[31:0] ext_addr;wire[15:0] ext_len;wire[7:0] ext_data,ext_code,ext_detail;
 wire[7:0] sec_per_clus;wire[31:0] fat_start,data_start,root_lba,root_clus,total_clus;
 wire[444:0] fs_core_cmd;wire[836:0] fs_core_rsp;wire fs_service_ready;
 sd_bmp_player #(.GUARDED_CS(1),.SHARED_SERVICE(1),.RESIDENT_CACHE(1),.CLK_HZ(50000000),.CLK_DIV_INIT(249),.CLK_DIV_FAST(1),.MOUNT_TO_N(100000000)) player(
 .clk(clk),.rst_n(ref_media_rst_n),.cs_guard_rst_n(ref_rst_n),.run(1'b1),.btn_next(1'b0),.btn_auto(1'b0),.restart(1'b0),
 .sd_ncs(sd_ncs),.sd_dclk(sd_dclk),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
 .px_word(px_word),.px_word_valid(px_valid),.px_word_ready(px_ready),.frame_active(frame_active),
 .top_down_o(top_down),.slot_o(load_slot),.mem_ready(sink_ready),.frame_done(sink_done),.last_frame_ok(sink_ok),
 .state_o(player_state),.fail_stage(player_stage),.err_code(player_code),.err_detail(player_detail),
 .init_r1(),.init_seq(),.sd_ready(sd_ready),.card_usable(card_usable),.file_cnt(),.cur_file(),
 .cur_file_size(),.cur_bytes_rd(player_bytes),.cur_px_written(),.last_frame_ok_o(),.frame_cnt(player_frames),
 .cache_valid(cache_ref),.cache_count(cache_count),.cache_keys(cache_keys),.rejected_files(rejected_files),
 .progress_count(player_progress),.last_reject_error(last_reject_error),.last_reject_key(last_reject_key),
 .external_core_cmd(fs_core_cmd),.external_core_rsp(fs_core_rsp),.external_service_ready(fs_service_ready),
 .ext_rd_en(ext_req),.ext_rd_addr(ext_addr),.ext_rd_len(ext_len),.ext_rd_ready(ext_ready),
 .ext_data(ext_data),.ext_data_valid(ext_valid),.ext_data_ready(ext_data_ready),.ext_data_last(ext_last),
 .ext_rd_done(ext_done),.ext_timeout(ext_timeout),.ext_crc_error(ext_crc),.ext_err_code(ext_code),.ext_err_detail(ext_detail),
 .fs_sec_per_clus(sec_per_clus),.fs_fat_start_lba(fat_start),.fs_data_start_lba(data_start),
 .fs_root_dir_lba(root_lba),.fs_root_clus(root_clus),.fs_total_clus(total_clus));
 wire writer_req,writer_ack,writer_busy;wire[31:0] writer_addr,writer_data;wire[15:0] writer_len;
 wire[3:0] sink_state;wire[7:0] sink_code;wire source_begin,source_top_down;wire[1:0] source_slot;
 wire guard_done,guard_pass,guard_fault;wire[3:0] approved;
 wire writer_accepted=writer_busy && mem_req && mem_wr && mem_ready;
 wire write_drained=adapter_idle && !writer_busy;
 bmp_frame_sink #(.FIFO_AW(8),.REQUIRE_WRITE_DRAIN(1),.REQUIRE_READBACK(1),.RESIDENT_LOAD(1),
 .GAP_TIMEOUT(200000),.WRITE_TO_N(25000000),.SWAP_TO_N(5000000)) sink(
 .clk(mem_clk),.rst_n(mem_media_rst_n),.wr_clk(clk),.px_word(px_word),.px_word_valid(px_valid),
 .px_word_ready(px_ready),.frame_active(frame_active),.top_down(top_down),.slot(load_slot),
 .mem_ready(sink_ready),.frame_done(sink_done),.last_frame_ok(sink_ok),
 .wr_req(writer_req),.wr_addr(writer_addr),.wr_data(writer_data),.wr_len(writer_len),.wr_ready(writer_accepted),
 .swap_toggle(),.swap_slot(),.swap_generation(),.swap_crc_ok(),.swap_busy(1'b0),
 .state_o(sink_state),.err_code(sink_code),.err_detail(),.frame_cnt(),.px_written(),
 .write_drained(write_drained),.verify_done(guard_done),.verify_pass(guard_pass),
 .source_begin(source_begin),.source_slot(source_slot),.source_top_down(source_top_down));
 reg verify_sent;wire verify_start=sink_state==4 && write_drained && !verify_sent;
 always @(posedge mem_clk or negedge mem_media_rst_n)
 if(!mem_media_rst_n)verify_sent<=0;else if(source_begin)verify_sent<=0;else if(verify_start)verify_sent<=1;
 wire verify_req,verify_ack,verify_busy,verify_valid;wire[31:0] verify_addr,verify_data;wire[15:0] verify_len;
 wire[31:0] lookup_addr,lookup_crc;wire lookup_valid;
 v3_row_integrity #(.TIMEOUT(50000000)) row_guard(.clk(mem_clk),.rst_n(mem_media_rst_n),
 .frame_begin(source_begin),.frame_slot(source_slot),.top_down(source_top_down),
 .accepted(writer_accepted),.write_addr(mem_addr),.write_data(mem_wdata),
 .verify_start(verify_start),.verify_allow(write_drained),.verify_done(guard_done),.verify_pass(guard_pass),
 .fault(guard_fault),.approved(approved),.rd_req(verify_req),.rd_addr(verify_addr),.rd_len(verify_len),
 .rd_ack(verify_ack),.rd_busy(verify_busy),.rd_valid(verify_valid),.rd_data(verify_data),
 .lookup_addr(lookup_addr),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),
 .bad_addr(),.bad_expected(),.bad_actual(),.source_words(),.checked_rows());

 wire dma_busy,dma_progress;
 wire rd_req,rd_ack,rd_busy,rd_valid;wire[31:0] rd_addr,rd_data;wire[15:0] rd_len;
 wire audio_req,audio_wr,audio_ack,audio_busy,audio_mem_valid;
 wire[31:0] audio_addr,audio_wdata,audio_rdata;wire[15:0] audio_len;
 wire aux_req,aux_wr,aux_ack,aux_busy,aux_valid;
 wire[31:0] aux_addr,aux_data,aux_rdata;wire[15:0] aux_len;
 v3_aux_mux aux_mux(.clk(mem_clk),.rst_n(mem_media_rst_n),
 .verify_req(verify_req),.verify_addr(verify_addr),.verify_len(verify_len),.verify_ack(verify_ack),
 .verify_busy(verify_busy),.verify_valid(verify_valid),.verify_data(verify_data),
 .audio_req(audio_req),.audio_wr(audio_wr),.audio_addr(audio_addr),.audio_wdata(audio_wdata),.audio_len(audio_len),
 .audio_ack(audio_ack),.audio_busy(audio_busy),.audio_valid(audio_mem_valid),.audio_data(audio_rdata),
 .sd_req(aux_req),.sd_wr(aux_wr),.sd_addr(aux_addr),.sd_wdata(aux_data),.sd_len(aux_len),
 .sd_ack(aux_ack),.sd_busy(aux_busy),.sd_valid(aux_valid),.sd_data(aux_rdata));
 memory_arbiter #(.COMPACT_CONSEC_COUNTER(1),.HIGH_WATER(640),.CRITICAL_WATER(320)) arbiter(
 .clk(mem_clk),.rst_n(mem_media_rst_n),.video_fifo_level(dma_busy?16'd0:16'd1024),
 .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_data_valid(rd_valid),
 .wr_req(writer_req),.wr_addr(writer_addr),.wr_data(writer_data),.wr_len(writer_len),.wr_ack(writer_ack),.wr_busy(writer_busy),
 .sd_req(aux_req),.sd_wr(aux_wr),.sd_addr(aux_addr),.sd_wdata(aux_data),.sd_len(aux_len),.sd_ack(aux_ack),.sd_busy(aux_busy),
 .sd_rdata(aux_rdata),.sd_rdata_valid(aux_valid),.mem_req(mem_req),.mem_wr(mem_wr),.mem_addr(mem_addr),
 .mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),.mem_ready(mem_ready),.mem_rdata(mem_rdata),.mem_rdata_valid(mem_valid),
 .wr_starve_cnt(),.rd_starve_cnt());

 // Atomic media status and real transaction counters, all reset on the same
 // media epoch as their producers. No independently synchronized bus bits.
 wire[191:0] ref_status_data={cache_keys,last_reject_error,last_reject_key,rejected_files,player_progress,player_frames,player_code,player_detail,player_state,
 player_stage,cache_ref,cache_count,(sd_ready && card_usable)};
 wire[191:0] ref_status_sys;wire ref_status_valid;
 video_cdc_mailbox #(.WIDTH(192)) ref_status_mailbox(.src_clk(clk),.src_rst_n(ref_media_rst_n),
 .src_data(ref_status_data),.src_valid(1'b1),.src_ready(),.dst_clk(sys_clk),.dst_rst_n(sys_media_rst_n),
 .dst_data(ref_status_sys),.dst_valid(ref_status_valid),.dst_ready(1'b1));
 reg[31:0] mem_transactions;
 always @(posedge mem_clk or negedge mem_media_rst_n)if(!mem_media_rst_n)mem_transactions<=0;
 else if((mem_req && mem_ready) || mem_valid)mem_transactions<=mem_transactions+1'b1;
 wire[47:0] mem_status_data={mem_transactions,approved,guard_fault,adapter_fault,memory_error,
 (mem_req || rd_busy || writer_busy || aux_busy),sink_code};
 wire[47:0] mem_status_sys;wire mem_status_valid;
 video_cdc_mailbox #(.WIDTH(48)) mem_status_mailbox(.src_clk(mem_clk),.src_rst_n(mem_media_rst_n),
 .src_data(mem_status_data),.src_valid(1'b1),.src_ready(),.dst_clk(sys_clk),.dst_rst_n(sys_media_rst_n),
 .dst_data(mem_status_sys),.dst_valid(mem_status_valid),.dst_ready(1'b1));
 wire[3:0] cache_sys=ref_status_sys[7:4] & mem_status_sys[15:12] & {4{sys_media_rst_n}};
 wire cached=&cache_sys;
 reg[31:0] observed_transactions,observed_bytes;reg[3:0] observed_state;
 wire mem_progress=mem_status_valid && observed_transactions!=mem_status_sys[47:16];
 wire media_progress=ref_status_valid && (observed_bytes!=ref_status_sys[79:48] || observed_state!=ref_status_sys[15:12]);
 always @(posedge sys_clk or negedge sys_media_rst_n)if(!sys_media_rst_n)begin observed_transactions<=0;observed_bytes<=0;observed_state<=0;end
 else begin
 if(mem_status_valid)observed_transactions<=mem_status_sys[47:16];
 if(ref_status_valid)begin observed_bytes<=ref_status_sys[79:48];observed_state<=ref_status_sys[15:12];end
 end

 wire next_request,auto_enabled,manual_safe,recover_request,controls_reply,safe_active,recovery_busy;
 wire[7:0] controls_reply_code;wire signed[31:0] controls_reply_value;
 wire signed[8:0] brightness;wire[7:0] contrast,osd_alpha;wire bilinear,fit,fade_enable;
 wire[6:0] volume;wire[1:0] period_select;wire menu;wire[2:0] field;wire auto_tick;
 wire cmd_valid,cmd_query;wire[7:0] cmd_target;wire[95:0] cmd_name;wire signed[31:0] cmd_value;
 wire transition_busy,frame_commit;wire[1:0] active_slot;wire[7:0] generation;
 v3_user_controls controls(.clk(sys_clk),.rst_n(sys_rst_n),.next_async(btn_next),.auto_async(btn_auto),.emergency_async(btn_emergency),
 .command_valid(cmd_valid && cmd_target!=66),.command_target(cmd_target),.command_name(cmd_name),.command_value(cmd_value),.command_query(cmd_query),
 .cached(cached),.transition_busy(transition_busy || recovery_busy || safe_active || !cached),.frame_commit(frame_commit),.next_request(next_request),.auto_enabled(auto_enabled),
 .safety(manual_safe),.recover_request(recover_request),.reply_valid(controls_reply),.reply_code(controls_reply_code),.reply_value(controls_reply_value),
 .brightness(brightness),.contrast(contrast),.osd_alpha(osd_alpha),.bilinear(bilinear),.fit(fit),.fade_enabled(fade_enable),.volume(volume),
 .period_select(period_select),.menu(menu),.field(field),.auto_tick(auto_tick));
 wire fault_valid,fatal_latched,pll_loss_sys;wire[1:0] recovery_attempts;wire[2:0] recovery_state,fault_level;
 wire[7:0] fault_code;wire[31:0] fault_ts,video_underflows,audio_underflows,audio_overflows;wire[3:0] audio_fallback;
 wire video_fault,presentation_fault;wire[31:0] hdmi_drops_sys;
 wire raw_fs;reg frame_toggle;
 always @(posedge pixel_clk or negedge pixel_rst_n)if(!pixel_rst_n)frame_toggle<=0;else if(raw_fs)frame_toggle<=!frame_toggle;
 wire frame_toggle_sys;reg previous_frame_toggle;
 video_level_sync frame_heartbeat_sync(.clk(sys_clk),.rst_n(sys_rst_n),.async_level(frame_toggle),.level(frame_toggle_sys));
 always @(posedge sys_clk or negedge sys_rst_n)if(!sys_rst_n)previous_frame_toggle<=0;else previous_frame_toggle<=frame_toggle_sys;
 wire err_push;wire[7:0] err_code;wire[3:0] err_src;wire[2:0] err_level;wire[31:0] err_ts;
 v3_supervisor supervisor(.clk(sys_clk),.rst_n(sys_rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cached),
 .media_failed(ref_status_sys[15:12]==10 || mem_status_sys[7:0]!=0),
 .media_code((mem_status_sys[7:0]!=0)?mem_status_sys[7:0]:ref_status_sys[31:24]),
 .integrity_fault(mem_status_sys[11] || video_fault || presentation_fault),.bus_fault(mem_status_sys[10] || mem_status_sys[9]),.fatal(pll_loss_sys),
 .frame_heartbeat(frame_toggle_sys!=previous_frame_toggle),.mem_heartbeat(mem_progress),.progress_heartbeat(media_progress),
 .memory_active(mem_status_sys[8]),.media_active(ref_status_sys[15:12]>=2 && ref_status_sys[15:12]!=7 && ref_status_sys[15:12]!=10 && ref_status_sys[15:12]!=11),
 .video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops_sys),
 .rejected_files(ref_status_sys[95:80]),.audio_fallback(audio_fallback),
 .safe_active(safe_active),.media_reset(media_reset),.recovery_busy(recovery_busy),.recovery_attempts(recovery_attempts),.recovery_state(recovery_state),
 .fault_code(fault_code),.fault_level(fault_level),.fault_valid(fault_valid),.fatal_latched(fatal_latched),.fault_ts(fault_ts),
 .err_push(err_push),.err_code(err_code),.err_src(err_src),.err_level(err_level),.err_ts(err_ts));

 wire[6:0] energy;wire wav_index_done,media_ready;wire[7:0] media_ready_generation;
 wire target_valid;wire[1:0] target_slot;wire[7:0] target_generation;
 wire cfg_ready;wire[95:0] cfg_data={brightness,contrast,osd_alpha,bilinear,fit,fade_enable,volume,period_select,field,menu,
 energy,fault_code,audio_underflows,generation};
 wire[11:0] raw_x,raw_y,out_x,out_y;wire raw_de,raw_hs,raw_vs;
 wire[23:0] rgb;wire out_hs,out_vs,out_de;
 v3_video_display_core #(.HD(HD),.PIXEL_HZ(PIXEL_HZ),.PACKED_CACHE(1),.FADE_FRAMES(32),.MEM_TIMEOUT(5000000),.FONT_FILE("../../../assets/fonts/font8x16.mem")) video(.sys_clk(sys_clk),.mem_clk(mem_clk),.pixel_clk(pixel_clk),
 .sys_rst_n(sys_rst_n),.mem_rst_n(mem_rst_n),.pixel_rst_n(pixel_rst_n),.media_reset(media_reset),
 .cfg_valid(1'b1),.cfg_ready(cfg_ready),.cfg_data(cfg_data),.cache_valid(cache_sys),.next_request(next_request || auto_tick),
 .safety_active(safe_active),.media_ready(media_ready),.media_ready_generation(media_ready_generation),
 .transition_busy(transition_busy),.frame_commit(frame_commit),.active_slot(active_slot),.generation(generation),
 .target_valid(target_valid),.target_slot(target_slot),.target_generation(target_generation),.integrity_fault(video_fault),.presentation_fault(presentation_fault),
 .underflows(video_underflows),.dma_busy(dma_busy),.dma_progress(dma_progress),
 .rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ack(rd_ack),.rd_busy(rd_busy),.rd_data(rd_data),.rd_valid(rd_valid),
 .lookup_addr(lookup_addr),.lookup_crc(lookup_crc),.lookup_valid(lookup_valid),
 .raw_x(raw_x),.raw_y(raw_y),.raw_de(raw_de),.raw_hs(raw_hs),.raw_vs(raw_vs),.frame_start(raw_fs),
 .rgb(rgb),.hs(out_hs),.vs(out_vs),.de(out_de),.x(out_x),.y(out_y));
 reg audio_commit_valid;reg[1:0] audio_commit_slot;reg[7:0] audio_commit_gen;wire audio_commit_ready;
 always @(posedge sys_clk or negedge sys_rst_n)begin
 if(!sys_rst_n)begin audio_commit_valid<=0;audio_commit_slot<=0;audio_commit_gen<=0;end
 else if(media_reset)audio_commit_valid<=0;
 else begin
 if(audio_commit_valid && audio_commit_ready)audio_commit_valid<=0;
 if(frame_commit)begin audio_commit_valid<=1;audio_commit_slot<=active_slot;audio_commit_gen<=generation;end
 end end
 wire pcm_valid,acr_valid;wire[23:0] pcm_left,pcm_right;wire[19:0] acr_n,acr_cts;
 v3_audio_system #(.EXTERNAL_SERVICE(1)) audio(.external_service_ready(fs_service_ready),.core_cmd(fs_core_cmd),.core_rsp(fs_core_rsp),
 .ref_clk(clk),.mem_clk(mem_clk),.audio_clk(audio_clk),.pixel_clk(pixel_clk),.sys_clk(sys_clk),
 .rst_n(control_common_rst_n),.media_reset(media_reset),.mounted(card_usable && sd_ready),.cache_ready(&cache_ref),.cache_keys(cache_keys),
 .sec_per_clus(sec_per_clus),.fat_start_lba(fat_start),.data_start_lba(data_start),.root_dir_lba(root_lba),.root_clus(root_clus),.total_clus(total_clus),
 .target_valid(target_valid),.target_slot(target_slot),.target_generation(target_generation),
 .commit_valid(audio_commit_valid),.commit_slot(audio_commit_slot),.commit_generation(audio_commit_gen),.commit_ready(audio_commit_ready),
 .volume(volume),.alarm_req(safe_active),.media_ready(media_ready),.media_ready_generation(media_ready_generation),
 .energy(energy),.underflows(audio_underflows),.overflows(audio_overflows),.fallback(audio_fallback),.wav_index_done(wav_index_done),
 .rd_en(ext_req),.rd_addr(ext_addr),.rd_len(ext_len),.rd_ready(ext_ready),.data(ext_data),.data_valid(ext_valid),.data_ready(ext_data_ready),
 .data_last(ext_last),.rd_done(ext_done),.timeout_err(ext_timeout),.crc16_err(ext_crc),.err_code(ext_code),.err_detail(ext_detail),
 .req(audio_req),.wr(audio_wr),.addr(audio_addr),.wdata(audio_wdata),.len(audio_len),.ack(audio_ack),
 .busy(audio_busy),.rdata(audio_rdata),.rvalid(audio_mem_valid),
 .pcm_valid(pcm_valid),.left(pcm_left),.right(pcm_right),.acr_valid(acr_valid),.N(acr_n),.CTS(acr_cts));

 wire[3:0] evt_src;wire[15:0] evt_value;wire evt_valid,evt_ready,evt_full;wire[31:0] evt_ts;wire[15:0] evt_drops;
 error_report events(.clk(sys_clk),.rst_n(sys_rst_n),.err_push(err_push),.err_code(err_code),.err_src(err_src),.err_ts(err_ts),
 .evt_type(evt_src),.evt_value(evt_value),.evt_valid(evt_valid),.evt_full(evt_full),.evt_ready(evt_ready),.evt_ts(evt_ts),.drop_cnt(evt_drops));
 wire[31:0] uart_rejected,uart_framing,uart_overrun,uart_reply_dropped;
 reg b_reply;reg[7:0] b_reply_code;reg signed[31:0] b_reply_value;
 always @(posedge sys_clk or negedge sys_rst_n)begin
 if(!sys_rst_n)begin b_reply<=0;b_reply_code<=0;b_reply_value<=0;end
 else begin b_reply<=0;
 if(cmd_valid && cmd_target==66)begin b_reply<=1;b_reply_code<=0;b_reply_value<=0;
 if(!cmd_query)b_reply_code<=3;
 else if(cmd_name=="STATUS")b_reply_value<=ref_status_sys[15:12];
 else if(cmd_name=="SLOT")b_reply_value<=active_slot;
 else if(cmd_name=="CACHE")b_reply_value<=cache_sys;
 else if(cmd_name=="GEN")b_reply_value<=generation;
 else if(cmd_name=="UNDERFLOW")b_reply_value<=audio_underflows;
 else if(cmd_name=="VUNDERFLOW")b_reply_value<=video_underflows;
 else if(cmd_name=="FAULT")b_reply_value<=fault_code;
 else if(cmd_name=="PRESENTATION")b_reply_value<=presentation_fault;
 else if(cmd_name=="INTEGRITY")b_reply_value<=mem_status_sys[11] || video_fault;
 else if(cmd_name=="LEVEL")b_reply_value<=fault_level;
 else if(cmd_name=="RECOVERY")b_reply_value<=recovery_state;
 else if(cmd_name=="RETRIES")b_reply_value<=recovery_attempts;
 else if(cmd_name=="REJECTED")b_reply_value<=ref_status_sys[95:80];
 else if(cmd_name=="IDLOW")b_reply_value<=ref_status_sys[159:128];
 else if(cmd_name=="IDHIGH")b_reply_value<=ref_status_sys[191:160];
 else if(cmd_name=="BADERROR")b_reply_value<=ref_status_sys[127:112];
 else if(cmd_name=="BADID")b_reply_value<=ref_status_sys[111:96];
 else if(cmd_name=="WAVFALLBACK")b_reply_value<=audio_fallback;
 else if(cmd_name=="OVERFLOW")b_reply_value<=audio_overflows;
 else if(cmd_name=="EVENTDROP")b_reply_value<=evt_drops;
 else if(cmd_name=="UARTREJECT")b_reply_value<=uart_rejected;
 else if(cmd_name=="UARTFRAME")b_reply_value<=uart_framing;
 else if(cmd_name=="UARTOVERRUN")b_reply_value<=uart_overrun;
 else if(cmd_name=="UARTDROP")b_reply_value<=uart_reply_dropped;
 else b_reply_code<=3;
 end end end
 wire normal_uart_txd,fatal_uart_txd;

 v3_uart_link #(.BOARD_CATALOG(1)) uart(.clk(sys_clk),.rst_n(sys_rst_n),.rxd(uart_rxd),.txd(normal_uart_txd),
 .command_valid(cmd_valid),.command_target(cmd_target),.command_name(cmd_name),.command_value(cmd_value),.command_query(cmd_query),
 .reply_valid(controls_reply || b_reply),.reply_code(b_reply?b_reply_code:controls_reply_code),.reply_value(b_reply?b_reply_value:controls_reply_value),
 .evt_valid(evt_valid),.evt_code(evt_value[7:0]),.evt_src(evt_src),.evt_ts(evt_ts),.evt_ready(evt_ready),
 .parser_rejected(uart_rejected),.rx_framing(uart_framing),.rx_overrun(uart_overrun),.reply_dropped(uart_reply_dropped));
 // The 50 MHz oscillator survives a SYS PLL failure. This independent latch
 // and bounded reporter preserve a usable fatal indication when SYS stops.
 reg seen_sys_lock,seen_video_lock,seen_audio_lock;
 (* keep="true" *) reg sys_loss_ref,video_loss_ref,audio_loss_ref;
 (* async_reg="true" *) reg[2:0] locks_meta,locks_sync;
 always @(posedge clk or negedge ref_rst_n)begin
 if(!ref_rst_n)begin seen_sys_lock<=0;seen_video_lock<=0;seen_audio_lock<=0;
 sys_loss_ref<=0;video_loss_ref<=0;audio_loss_ref<=0;locks_meta<=0;locks_sync<=0;end
 else begin
 locks_meta<={sys_lock,video_lock,audio_lock};locks_sync<=locks_meta;
 if(locks_sync[2])seen_sys_lock<=1;else if(seen_sys_lock)sys_loss_ref<=1;
 if(locks_sync[1])seen_video_lock<=1;else if(seen_video_lock)video_loss_ref<=1;
 if(locks_sync[0])seen_audio_lock<=1;else if(seen_audio_lock)audio_loss_ref<=1;
 end end
 video_level_sync pll_loss_sync(.clk(sys_clk),.rst_n(sys_rst_n),
 .async_level(sys_loss_ref || video_loss_ref || audio_loss_ref),.level(pll_loss_sys));
 reg[3:0] fatal_pos;reg[25:0] fatal_delay;reg fatal_sending;
 wire fatal_ready;reg[7:0] fatal_byte;
 always @*case(fatal_pos)
 0:fatal_byte="F";1:fatal_byte="A";2:fatal_byte="T";3:fatal_byte="A";4:fatal_byte="L";
 5:fatal_byte=" ";6:fatal_byte="S";7:fatal_byte="Y";8:fatal_byte="S";
 9:fatal_byte="P";10:fatal_byte="L";11:fatal_byte="L";12:fatal_byte=13;default:fatal_byte=10;endcase
 always @(posedge clk or negedge ref_rst_n)begin
 if(!ref_rst_n)begin fatal_pos<=0;fatal_delay<=0;fatal_sending<=0;end
 else if(!sys_loss_ref)begin fatal_pos<=0;fatal_delay<=0;fatal_sending<=0;end
 else if(!fatal_sending)begin
 if(fatal_delay==24999999)begin fatal_delay<=0;fatal_sending<=1;fatal_pos<=0;end else fatal_delay<=fatal_delay+1'b1;
 end else if(fatal_ready)begin
 if(fatal_pos==13)begin fatal_pos<=0;fatal_sending<=0;end else fatal_pos<=fatal_pos+1'b1;
 end end
 uart_tx #(.CLK_FREQ(50000000),.BAUD(115200)) fatal_uart(.clk(clk),.rst_n(ref_rst_n),
 .tx_valid(fatal_sending),.tx_data(fatal_byte),.tx_ready(fatal_ready),.txd(fatal_uart_txd));
 // Related SYS100 -> REF50 publication: launch intermediate values on
 // falling SYS edges (5ns from REF rising edges). Ordinary setup/hold stays
 // enabled. The REF output register and independent FATAL transmitter remain
 // alive when SYS PLL stops; no data-path false path or clock waiver is used.
 reg normal_uart_half;reg[3:0] status_half;
 always @(negedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin normal_uart_half<=1'b1;status_half<=4'd0;end
  else begin normal_uart_half<=normal_uart_txd;
   status_half<={safe_active,recovery_busy,transition_busy,cached};end
 end
 always @(posedge clk or negedge ref_rst_n)begin
  if(!ref_rst_n)begin uart_txd<=1'b1;led<=4'd0;end
  else begin uart_txd<=sys_loss_ref?fatal_uart_txd:normal_uart_half;
   led<=sys_loss_ref?4'hf:status_half;end
 end

 wire[23:0] axis_data;wire axis_valid,axis_user,axis_last,axis_ready,resync,overflow;
 wire[31:0] dropped_frames;wire[4:0] queue_level;
 hdmi_video_bridge #(.HD(HD),.QUEUE_AW(4)) hdmi_queue(.clk(pixel_clk),.rst_n(pixel_rst_n),
 .rgb(rgb),.de(out_de),.x(out_x),.y(out_y),.axis_valid(axis_valid),.axis_user(axis_user),
 .axis_last(axis_last),.axis_data(axis_data),.axis_ready(axis_ready),.resync(resync),
 .overflow_sticky(overflow),.dropped_frames(dropped_frames),.queue_level(queue_level));
 video_cdc_mailbox #(.WIDTH(32)) hdmi_status_mailbox(.src_clk(pixel_clk),.src_rst_n(pixel_rst_n),
 .src_data(dropped_frames),.src_valid(1'b1),.src_ready(),.dst_clk(sys_clk),.dst_rst_n(sys_rst_n),
 .dst_data(hdmi_drops_sys),.dst_valid(),.dst_ready(1'b1));
 wire tx_reset=!pixel_rst_n || resync;
 wire phy_rst_n;
 reset_sync reset_phy(.clk(serial_clk),.async_rst_n(!tx_reset),.rst_n(phy_rst_n));
 reg[16:0] edid_count;reg edid_trig;
 always @(posedge pixel_clk or negedge pixel_rst_n)if(!pixel_rst_n)begin edid_count<=0;edid_trig<=0;end
 else begin edid_trig<=0;if(tx_reset)edid_count<=0;else if(edid_count<100000)begin edid_count<=edid_count+1'b1;if(edid_count==99999)edid_trig<=1;end end
 wire[9:0] ch0,ch1,ch2,chclk;wire hdmi_locked;
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(HD?1650:800),.HSA(HD?40:96),.HFP(HD?110:16),.HBP(HD?220:48),.HACTIVE(HD?1280:640),
 .VTOTAL(HD?750:525),.VSA(HD?5:2),.VFP(HD?5:10),.VBP(HD?20:33),.VACTIVE(HD?720:480),.VIDEO_VIC(HD?4:1),
 .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) transmitter(
 .I_pixel_clk(pixel_clk),.I_rst(tx_reset),.I_edid_read_trig(edid_trig),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
 .I_audio_valid(pcm_valid),.I_audio_left_data(pcm_left),.I_audio_right_data(pcm_right),
 .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(hdmi_locked),
 .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),.O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) serializer(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(!phy_rst_n),
 .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
endmodule
