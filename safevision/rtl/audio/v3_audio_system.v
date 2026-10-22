// V3 audio assembly. Clocks: REF=50MHz, production MEM=50MHz, AUDIO=12.288136MHz,
// SYS=100MHz, PIXEL=25.2/74.25MHz. 48k cadence is AUDIO / 256 (~48000.531Hz).
// Control/status cross via immutable bundled mailboxes; sample streams use the
// vendor TD equal-width FWFT FIFO. media_reset resets source/rings/media FIFOs;
// ROM tone, sample clock, priority ramp and HDMI packet cadence use global reset.
// PCM16 -> HDMI24 is LEFT ALIGNED (x256), preserving full-scale amplitude.
// commit_valid is retained until commit_ready. slot/generation change atomically.
// Only matching-generation samples can reach the output; mismatches drain at
// AUDIO clock speed. A missing/invalid WAV selects the same ROM as a quiet fallback.
module v3_audio_system #(parameter integer SAMPLE_DIV=256,PREFETCH=800,EXTERNAL_SERVICE=0,MEDIA_RESET_INCLUDES_GLOBAL=0,HANDBOOK_PROFILE=0,PREINDEXED=0)(
 input wire ref_clk,mem_clk,audio_clk,pixel_clk,sys_clk,rst_n,media_reset,
 input wire external_service_ready,output wire[444:0] core_cmd,input wire[836:0] core_rsp,
 input wire mounted,cache_ready,input wire [63:0] cache_keys,input wire [7:0] sec_per_clus,
 input wire [31:0] fat_start_lba,data_start_lba,root_dir_lba,root_clus,total_clus,
 input wire target_valid,input wire [1:0] target_slot,input wire [7:0] target_generation,
 input wire commit_valid,input wire [1:0] commit_slot,input wire [7:0] commit_generation,
 output wire commit_ready,input wire [6:0] volume,input wire alarm_req,
 output wire media_ready,output wire [7:0] media_ready_generation,
 output wire [6:0] energy,output wire [31:0] underflows,overflows,
 output wire [3:0] fallback,output wire wav_index_done,
 output wire rd_en,output wire [31:0] rd_addr,output wire [15:0] rd_len,
 input wire rd_ready,input wire [7:0] data,input wire data_valid,
 output wire data_ready,input wire data_last,rd_done,timeout_err,crc16_err,
 input wire [7:0] err_code,err_detail,
 output wire req,wr,output wire [31:0] addr,wdata,output wire [15:0] len,
 input wire ack,busy,input wire [31:0] rdata,input wire rvalid,
 output wire pcm_valid,output wire [23:0] left,right,
 output wire acr_valid,output wire [19:0] N,CTS,
 // All descriptor signals are REF-domain; accepted during resident preload.
 input wire media_descriptor_valid,output wire media_descriptor_ready,
 input wire[1:0] media_descriptor_slot,input wire[63:0] media_descriptor,
 input wire media_descriptor_found);
 // Every global endpoint has asynchronous assertion and local synchronous release.
 // All mailbox endpoints in a group share the SAME raw assertion epoch.
 wire ref_global_rst_n,mem_global_rst_n,audio_global_rst_n,pixel_global_rst_n,sys_global_rst_n;
 v3_audio_reset_release gr(.clk(ref_clk),.assert_reset(!rst_n),.rst_n(ref_global_rst_n));
 v3_audio_reset_release gm(.clk(mem_clk),.assert_reset(!rst_n),.rst_n(mem_global_rst_n));
 v3_audio_reset_release ga(.clk(audio_clk),.assert_reset(!rst_n),.rst_n(audio_global_rst_n));
 v3_audio_reset_release gp(.clk(pixel_clk),.assert_reset(!rst_n),.rst_n(pixel_global_rst_n));
 v3_audio_reset_release gs(.clk(sys_clk),.assert_reset(!rst_n),.rst_n(sys_global_rst_n));
 // Board mode receives the single canonical raw media epoch, including global reset.
 // Local two-stage releases and all data-path reset timing remain in place.
 (* keep="true" *) wire media_reset_any=MEDIA_RESET_INCLUDES_GLOBAL?media_reset:(!rst_n||media_reset);wire sys_media_rst_n;
 v3_audio_reset_release sm(.clk(sys_clk),.assert_reset(media_reset_any),.rst_n(sys_media_rst_n));
 (* async_reg="true" *) reg [1:0] rr,mr,ar;
 always @(posedge ref_clk or posedge media_reset_any)if(media_reset_any)rr<=0;else rr<={rr[0],1'b1};
 always @(posedge mem_clk or posedge media_reset_any)if(media_reset_any)mr<=0;else mr<={mr[0],1'b1};
 always @(posedge audio_clk or posedge media_reset_any)if(media_reset_any)ar<=0;else ar<={ar[0],1'b1};
 wire ref_rst_n=rr[1],mem_rst_n=mr[1];
 wire [127:0] source_data,ingress_data;wire [3:0] source_valid,source_ready,ingress_valid,ingress_ready;
 wire [3:0] room,fill;wire [8:0] ingress_wlevel[0:3];wire [3:0] fb_ref;
 wire index_ref;wire [63:0] ring_levels;wire [3:0] ring_prefetched;
 wire [63:0] ref_levels;wire ref_levels_valid,ref_levels_ready;
 wire [63:0] ref_level_cache=ref_levels;
 video_cdc_mailbox #(.WIDTH(64)) ring_to_ref(.src_clk(mem_clk),.src_rst_n(mem_rst_n),
 .src_data(ring_levels),.src_valid(1'b1),.src_ready(ref_levels_ready),.dst_clk(ref_clk),.dst_rst_n(ref_rst_n),
 .dst_data(ref_levels),.dst_valid(ref_levels_valid),.dst_ready(1'b1));

 wire[8:0] global_ingress_pairs;wire global_sector_room;
 wire[10:0] global_ingress_words;wire global_ingress_partial;
 v3_pcm_ingress_shared_fifo #(.AW(PREINDEXED?9:10)) ingress_shared(.rst(media_reset_any),.wr_clk(ref_clk),.rd_clk(mem_clk),
 .wr_data(source_data),.wr_valid(source_valid),.wr_ready(source_ready),.wr_pairs(global_ingress_pairs),
 .sector_room(global_sector_room),.wr_words(global_ingress_words),.wr_partial(global_ingress_partial),.rd_data(ingress_data),.rd_valid(ingress_valid),.rd_ready(ingress_ready));
 genvar g;generate for(g=0;g<4;g=g+1)begin:ingress_status
  assign ingress_wlevel[g]=global_ingress_pairs;
  v3_audio_prefill_compare #(.LIMIT(PREFETCH+128)) prefill_compare(
   .ring_level(ref_level_cache[g*16+:16]),.fifo_words(global_ingress_words[9:0]),
   .partial(global_ingress_partial),.fill(fill[g]));
  assign room[g]=global_sector_room;
 end endgenerate

 v3_wav_source #(.EXTERNAL_SERVICE(EXTERNAL_SERVICE),.PREINDEXED(PREINDEXED)) source(
 .media_descriptor_valid(media_descriptor_valid),.media_descriptor_ready(media_descriptor_ready),
 .media_descriptor_slot(media_descriptor_slot),.media_descriptor(media_descriptor),.media_descriptor_found(media_descriptor_found),
 .external_service_ready(external_service_ready),.core_cmd(core_cmd),.core_rsp(core_rsp),.clk(ref_clk),.rst_n(ref_rst_n),.mounted(mounted),.cache_ready(cache_ready),
 .cache_keys(cache_keys),.sec_per_clus(sec_per_clus),.fat_start_lba(fat_start_lba),.data_start_lba(data_start_lba),
 .root_dir_lba(root_dir_lba),.root_clus(root_clus),.total_clus(total_clus),.slot_fill(fill),.sector_room(room),
 .pcm_data(source_data),.pcm_valid(source_valid),.pcm_ready(source_ready),.index_done(index_ref),.fallback(fb_ref),
 .rd_en(rd_en),.rd_addr(rd_addr),.rd_len(rd_len),.rd_ready(rd_ready),.data(data),.data_valid(data_valid),
 .data_ready(data_ready),.data_last(data_last),.rd_done(rd_done),.timeout_err(timeout_err),.crc16_err(crc16_err),
 .err_code(err_code),.err_detail(err_detail));
 wire [4:0] index_sys,index_mem;wire index_sys_valid,index_mem_valid;
 video_cdc_mailbox #(.WIDTH(5)) index_to_sys(.src_clk(ref_clk),.src_rst_n(ref_rst_n),
 .src_data({index_ref,fb_ref}),.src_valid(1'b1),.dst_clk(sys_clk),.dst_rst_n(sys_media_rst_n),
 .dst_data(index_sys),.dst_valid(index_sys_valid),.dst_ready(1'b1));
 video_cdc_mailbox #(.WIDTH(5)) index_to_mem(.src_clk(ref_clk),.src_rst_n(ref_rst_n),
 .src_data({index_ref,fb_ref}),.src_valid(1'b1),.dst_clk(mem_clk),.dst_rst_n(mem_rst_n),
 .dst_data(index_mem),.dst_valid(index_mem_valid),.dst_ready(1'b1));
 wire [3:0] fb_mem=index_mem[3:0];
 wire [9:0] commit_mem;wire commit_mem_valid,ring_commit_ready;
 // Media epoch resets BOTH descriptor mailbox domains; callers reissue after recovery.
 video_cdc_mailbox #(.WIDTH(10)) commit_to_mem(.src_clk(sys_clk),.src_rst_n(sys_media_rst_n),
 .src_data({commit_generation,commit_slot}),.src_valid(commit_valid),.src_ready(commit_ready),
 .dst_clk(mem_clk),.dst_rst_n(mem_rst_n),.dst_data(commit_mem),.dst_valid(commit_mem_valid),.dst_ready(ring_commit_ready));
 wire [39:0] ring_data,pcm_head;wire ring_valid,ring_ready,pcm_head_valid,pcm_head_ready;
 wire [8:0] output_wlevel;wire [31:0] ring_overflows;
 v3_pcm_ring #(.PREFETCH(PREFETCH)) ring(.clk(mem_clk),.rst_n(mem_rst_n),.in_data(ingress_data),
 .in_valid(ingress_valid),.in_ready(ingress_ready),.commit_valid(commit_mem_valid),.commit_slot(commit_mem[1:0]),
 .commit_generation(commit_mem[9:2]),.commit_ready(ring_commit_ready),.fallback(fb_mem),.prefetched(ring_prefetched),
 .levels(ring_levels),.out_data(ring_data),.out_valid(ring_valid),.out_ready(ring_ready),.output_level({1'b0,output_wlevel}),
 .req(req),.wr(wr),.addr(addr),.wdata(wdata),.len(len),.ack(ack),.busy(busy),.rdata(rdata),.rvalid(rvalid),.overflow_count(ring_overflows));
 v3_pcm_sample_fifo samples(.rst(media_reset_any),.wr_clk(mem_clk),.rd_clk(audio_clk),
 .wr_data(ring_data),.wr_valid(ring_valid),.wr_ready(ring_ready),.wr_pairs(output_wlevel),
 .rd_data(pcm_head),.rd_valid(pcm_head_valid),.rd_ready(pcm_head_ready));
 wire [3:0] prefetched_sys;wire prefetched_valid;
 wire [3:0] prefetched_cache=prefetched_sys;
 video_cdc_mailbox #(.WIDTH(4)) ready_to_sys(.src_clk(mem_clk),.src_rst_n(mem_rst_n),
 .src_data(ring_prefetched),.src_valid(1'b1),.dst_clk(sys_clk),.dst_rst_n(sys_media_rst_n),
 .dst_data(prefetched_sys),.dst_valid(prefetched_valid),.dst_ready(1'b1));
 assign fallback=index_sys[3:0];assign wav_index_done=index_sys[4];
 assign media_ready=target_valid&&wav_index_done&&(fallback[target_slot]||prefetched_cache[target_slot]);
 assign media_ready_generation=target_generation;
 reg [1:0] active_sys;reg [7:0] gen_sys;reg play_sys;
 always @(posedge sys_clk or negedge sys_global_rst_n)if(!sys_global_rst_n)begin active_sys<=0;gen_sys<=0;play_sys<=0;end
 else if(!sys_media_rst_n)play_sys<=0;
 else if(commit_valid&&commit_ready)begin active_sys<=commit_slot;gen_sys<=commit_generation;play_sys<=1;end
 wire [17:0] ctrl_audio;wire ctrl_valid;
 video_cdc_mailbox #(.WIDTH(18)) control_to_audio(.src_clk(sys_clk),.src_rst_n(sys_global_rst_n),
 .src_data({play_sys,alarm_req,volume,fallback[active_sys],gen_sys}),.src_valid(1'b1),
 .dst_clk(audio_clk),.dst_rst_n(audio_global_rst_n),.dst_data(ctrl_audio),.dst_valid(ctrl_valid),.dst_ready(1'b1));
 wire [17:0] ctrl=ctrl_audio;
 reg [15:0] tick_count;wire tick=tick_count==SAMPLE_DIV-1;
 always @(posedge audio_clk or negedge audio_global_rst_n)if(!audio_global_rst_n)tick_count<=0;
 else if(tick)tick_count<=0;else tick_count<=tick_count+1'b1;
 wire matching=pcm_head_valid&&pcm_head[39:32]==ctrl[7:0];
 assign pcm_head_ready=pcm_head_valid&&(!matching||(tick&&ctrl[17]&&!ctrl[8]));
 reg [23:0] wav_l,wav_r;reg sample_valid;
 reg [31:0] underflow_audio;
 // A new generation is allowed up to one 60Hz frame (800 sample ticks) to
 // reach this clock domain. Once its first sample is accepted, every empty
 // tick is a true underflow. A failed priming window also counts failures.
 reg primed;reg [7:0] priming_generation;reg [9:0] priming_ticks;
 always @(posedge audio_clk or negedge audio_global_rst_n)begin
  if(!audio_global_rst_n)begin wav_l<=0;wav_r<=0;sample_valid<=0;underflow_audio<=0;primed<=0;priming_generation<=0;priming_ticks<=0;end
  else begin sample_valid<=0;
   if(!ar[1]||!ctrl[17]||ctrl[7:0]!=priming_generation)begin
    primed<=0;priming_ticks<=0;priming_generation<=ctrl[7:0];
   end
   if(tick)begin sample_valid<=1;wav_l<=0;wav_r<=0;
    if(ctrl[17]&&!ctrl[8])begin
     if(matching)begin
      wav_l<={pcm_head[15:0],8'd0};wav_r<={pcm_head[31:16],8'd0};
      primed<=1;priming_ticks<=0;
     end else if(ar[1]&&ctrl[7:0]==priming_generation)begin
      if(priming_ticks<800)priming_ticks<=priming_ticks+1'b1;
      if((primed||priming_ticks>=800)&&underflow_audio!=32'hffffffff)underflow_audio<=underflow_audio+1'b1;
     end
    end
   end
  end
 end
 wire [23:0] tone_l,tone_r,mix_l,mix_r;wire mix_valid;
 alarm_tone_gen rom(.audio_clk(audio_clk),.rst_n(audio_global_rst_n),.tick(tick),.enable(ctrl[16]||(ctrl[17]&&ctrl[8])),.tone_l(tone_l),.tone_r(tone_r));
 v3_audio_priority_serial u_priority(.audio_clk(audio_clk),.rst_n(audio_global_rst_n),.sample_valid(sample_valid),
 .alarm_req(ctrl[16]||(ctrl[17]&&ctrl[8])),.wav_l(wav_l),.wav_r(wav_r),.tone_l(tone_l),.tone_r(tone_r),
 .audio_l(mix_l),.audio_r(mix_r),.audio_valid(mix_valid));
 wire [47:0] pcm_scaled;wire scaled_valid;reg [31:0] pixel_overflows;
 wire pixel_wr_ready;wire [47:0] pcm_pixel;wire pixel_valid;
 v3_audio_volume volume_scale(.clk(audio_clk),.rst_n(audio_global_rst_n),.valid_in(mix_valid),
 .left_in(mix_l),.right_in(mix_r),.volume(ctrl[15:9]),.valid_out(scaled_valid),
 .left_out(pcm_scaled[23:0]),.right_out(pcm_scaled[47:24]));
 always @(posedge audio_clk or negedge audio_global_rst_n)begin
  if(!audio_global_rst_n)pixel_overflows<=0;
  else if(scaled_valid&&!pixel_wr_ready&&pixel_overflows!=32'hffffffff)pixel_overflows<=pixel_overflows+1'b1;
 end
 v3_pcm_packet_fifo hdmi_samples(.rst(!rst_n),.wr_clk(audio_clk),.rd_clk(pixel_clk),
 .wr_data(pcm_scaled),.wr_valid(scaled_valid),.wr_ready(pixel_wr_ready),.rd_data(pcm_pixel),.rd_valid(pixel_valid));
 assign pcm_valid=pixel_valid;assign left=pcm_pixel[23:0];assign right=pcm_pixel[47:24];
 hdmi_acr acr(.pixel_clk(pixel_clk),.rst_n(pixel_global_rst_n),.sample_valid(pixel_valid),.valid(acr_valid),.cts(CTS),.n(N));
 wire [6:0] energy_audio;wire energy_update;
 audio_energy #(.HANDBOOK_PROFILE(HANDBOOK_PROFILE)) meter(.clk(audio_clk),.rst_n(audio_global_rst_n),.sample_valid(HANDBOOK_PROFILE?mix_valid:scaled_valid),
 .pcm_l(HANDBOOK_PROFILE?mix_l[23:8]:pcm_scaled[23:8]),.pcm_r(HANDBOOK_PROFILE?mix_r[23:8]:pcm_scaled[47:32]),.energy(energy_audio),.update(energy_update));
 wire [70:0] status_sys;wire status_valid;
 video_cdc_mailbox #(.WIDTH(71)) status_to_sys(.src_clk(audio_clk),.src_rst_n(audio_global_rst_n),
 .src_data({energy_audio,underflow_audio,pixel_overflows}),.src_valid(1'b1),
 .dst_clk(sys_clk),.dst_rst_n(sys_global_rst_n),.dst_data(status_sys),.dst_valid(status_valid),.dst_ready(1'b1));
 assign energy=status_sys[70:64];assign underflows=status_sys[63:32];assign overflows=status_sys[31:0];
 // synthesis translate_off
 integer bounded_track;
 always @(posedge mem_clk)if(mem_rst_n)for(bounded_track=0;bounded_track<4;bounded_track=bounded_track+1)
  if(ring.count[bounded_track]>PREFETCH+640)$fatal(1,"tagged ingress prefill bound violated track=%0d count=%0d",bounded_track,ring.count[bounded_track]);
 initial if(SAMPLE_DIV<2||SAMPLE_DIV>65536)$fatal(1,"invalid audio divider");
 // synthesis translate_on
endmodule


// Reset synchronizer is the only custom CDC here; data FIFOs remain TD IP.
module v3_audio_reset_release(input wire clk,assert_reset,output wire rst_n);
 (* async_reg="true", keep="true" *) reg [1:0] release_ff;
 always @(posedge clk or posedge assert_reset)
  if(assert_reset)release_ff<=0;else release_ff<={release_ff[0],1'b1};
 assign rst_n=release_ff[1];
endmodule
