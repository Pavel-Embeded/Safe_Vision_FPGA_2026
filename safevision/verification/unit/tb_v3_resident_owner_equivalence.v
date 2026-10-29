`timescale 1ns/1ps
module tb_v3_resident_owner_equivalence;
 reg clk=0,rst=0,owner=0;always #5 clk=~clk;
 reg[444:0]local_cmd=0,external_cmd=0;reg[31:0]rng=32'h44502618;
 integer errors=0,comparisons=0,k,j,active_checks=0,gaps=0,resident_checks=0,local_checks=0;
 wire  a_sd_ncs,b_sd_ncs;
 wire  a_sd_dclk,b_sd_dclk;
 wire  a_sd_mosi,b_sd_mosi;
 wire [31:0] a_px_word,b_px_word;
 wire  a_px_word_valid,b_px_word_valid;
 wire  a_frame_active,b_frame_active;
 wire  a_top_down_o,b_top_down_o;
 wire [1:0] a_slot_o,b_slot_o;
 wire [3:0] a_state_o,b_state_o;
 wire [3:0] a_fail_stage,b_fail_stage;
 wire [7:0] a_err_code,b_err_code;
 wire [7:0] a_err_detail,b_err_detail;
 wire [7:0] a_init_r1,b_init_r1;
 wire [2:0] a_init_seq,b_init_seq;
 wire  a_sd_ready,b_sd_ready;
 wire  a_card_usable,b_card_usable;
 wire [3:0] a_file_cnt,b_file_cnt;
 wire [1:0] a_cur_file,b_cur_file;
 wire [31:0] a_cur_file_size,b_cur_file_size;
 wire [31:0] a_cur_bytes_rd,b_cur_bytes_rd;
 wire [18:0] a_cur_px_written,b_cur_px_written;
 wire  a_last_frame_ok_o,b_last_frame_ok_o;
 wire [15:0] a_frame_cnt,b_frame_cnt;
 wire [3:0] a_cache_valid,b_cache_valid;
 wire [2:0] a_cache_count,b_cache_count;
 wire [63:0] a_cache_keys,b_cache_keys;
 wire [15:0] a_rejected_files,b_rejected_files;
 wire [836:0] a_external_core_rsp,b_external_core_rsp;
 wire  a_external_service_ready,b_external_service_ready;
 wire  a_ext_rd_ready,b_ext_rd_ready;
 wire [7:0] a_ext_data,b_ext_data;
 wire  a_ext_data_valid,b_ext_data_valid;
 wire  a_ext_data_last,b_ext_data_last;
 wire  a_ext_rd_done,b_ext_rd_done;
 wire  a_ext_timeout,b_ext_timeout;
 wire  a_ext_crc_error,b_ext_crc_error;
 wire [7:0] a_ext_err_code,b_ext_err_code;
 wire [7:0] a_ext_err_detail,b_ext_err_detail;
 wire [7:0] a_fs_sec_per_clus,b_fs_sec_per_clus;
 wire [31:0] a_fs_fat_start_lba,b_fs_fat_start_lba;
 wire [31:0] a_fs_data_start_lba,b_fs_data_start_lba;
 wire [31:0] a_fs_root_dir_lba,b_fs_root_dir_lba;
 wire [31:0] a_fs_root_clus,b_fs_root_clus;
 wire [31:0] a_fs_total_clus,b_fs_total_clus;
 wire [31:0] a_progress_count,b_progress_count;
 wire [15:0] a_last_reject_error,b_last_reject_error;
 wire [15:0] a_last_reject_key,b_last_reject_key;
 sd_bmp_player #(.REGISTERED_RESIDENT_READY(1),.SHARED_SERVICE(1),.RESIDENT_CACHE(1)) d(.clk(clk),.rst_n(rst),.cs_guard_rst_n(1'b0),.run(1'b0),.btn_next(1'b0),.btn_auto(1'b0),.restart(1'b0),.sd_ncs(a_sd_ncs),.sd_dclk(a_sd_dclk),.sd_mosi(a_sd_mosi),.sd_miso(1'b1),.px_word(a_px_word),.px_word_valid(a_px_word_valid),.px_word_ready(1'b1),.frame_active(a_frame_active),.top_down_o(a_top_down_o),.slot_o(a_slot_o),.mem_ready(1'b1),.frame_done(1'b0),.last_frame_ok(1'b1),.state_o(a_state_o),.fail_stage(a_fail_stage),.err_code(a_err_code),.err_detail(a_err_detail),.init_r1(a_init_r1),.init_seq(a_init_seq),.sd_ready(a_sd_ready),.card_usable(a_card_usable),.file_cnt(a_file_cnt),.cur_file(a_cur_file),.cur_file_size(a_cur_file_size),.cur_bytes_rd(a_cur_bytes_rd),.cur_px_written(a_cur_px_written),.last_frame_ok_o(a_last_frame_ok_o),.frame_cnt(a_frame_cnt),.cache_valid(a_cache_valid),.cache_count(a_cache_count),.cache_keys(a_cache_keys),.rejected_files(a_rejected_files),.external_core_cmd(external_cmd),.external_core_rsp(a_external_core_rsp),.external_service_ready(a_external_service_ready),.ext_rd_en(1'b0),.ext_rd_addr(1'b0),.ext_rd_len(16'd1),.ext_rd_ready(a_ext_rd_ready),.ext_data(a_ext_data),.ext_data_valid(a_ext_data_valid),.ext_data_ready(1'b1),.ext_data_last(a_ext_data_last),.ext_rd_done(a_ext_rd_done),.ext_timeout(a_ext_timeout),.ext_crc_error(a_ext_crc_error),.ext_err_code(a_ext_err_code),.ext_err_detail(a_ext_err_detail),.fs_sec_per_clus(a_fs_sec_per_clus),.fs_fat_start_lba(a_fs_fat_start_lba),.fs_data_start_lba(a_fs_data_start_lba),.fs_root_dir_lba(a_fs_root_dir_lba),.fs_root_clus(a_fs_root_clus),.fs_total_clus(a_fs_total_clus),.progress_count(a_progress_count),.last_reject_error(a_last_reject_error),.last_reject_key(a_last_reject_key));
 v3_player_owner_reference #(.SHARED_SERVICE(1),.RESIDENT_CACHE(1)) original(.clk(clk),.rst_n(rst),.cs_guard_rst_n(1'b0),.run(1'b0),.btn_next(1'b0),.btn_auto(1'b0),.restart(1'b0),.sd_ncs(b_sd_ncs),.sd_dclk(b_sd_dclk),.sd_mosi(b_sd_mosi),.sd_miso(1'b1),.px_word(b_px_word),.px_word_valid(b_px_word_valid),.px_word_ready(1'b1),.frame_active(b_frame_active),.top_down_o(b_top_down_o),.slot_o(b_slot_o),.mem_ready(1'b1),.frame_done(1'b0),.last_frame_ok(1'b1),.state_o(b_state_o),.fail_stage(b_fail_stage),.err_code(b_err_code),.err_detail(b_err_detail),.init_r1(b_init_r1),.init_seq(b_init_seq),.sd_ready(b_sd_ready),.card_usable(b_card_usable),.file_cnt(b_file_cnt),.cur_file(b_cur_file),.cur_file_size(b_cur_file_size),.cur_bytes_rd(b_cur_bytes_rd),.cur_px_written(b_cur_px_written),.last_frame_ok_o(b_last_frame_ok_o),.frame_cnt(b_frame_cnt),.cache_valid(b_cache_valid),.cache_count(b_cache_count),.cache_keys(b_cache_keys),.rejected_files(b_rejected_files),.external_core_cmd(external_cmd),.external_core_rsp(b_external_core_rsp),.external_service_ready(b_external_service_ready),.ext_rd_en(1'b0),.ext_rd_addr(1'b0),.ext_rd_len(16'd1),.ext_rd_ready(b_ext_rd_ready),.ext_data(b_ext_data),.ext_data_valid(b_ext_data_valid),.ext_data_ready(1'b1),.ext_data_last(b_ext_data_last),.ext_rd_done(b_ext_rd_done),.ext_timeout(b_ext_timeout),.ext_crc_error(b_ext_crc_error),.ext_err_code(b_ext_err_code),.ext_err_detail(b_ext_err_detail),.fs_sec_per_clus(b_fs_sec_per_clus),.fs_fat_start_lba(b_fs_fat_start_lba),.fs_data_start_lba(b_fs_data_start_lba),.fs_root_dir_lba(b_fs_root_dir_lba),.fs_root_clus(b_fs_root_clus),.fs_total_clus(b_fs_total_clus),.progress_count(b_progress_count),.last_reject_error(b_last_reject_error),.last_reject_key(b_last_reject_key));
 initial begin
  force d.state_o=owner ? d.S_READY:d.S_IDLE;force original.state_o=owner ? original.S_READY:original.S_IDLE;
  force d.cache_count=owner ? 3'd4:3'd0;force original.cache_count=owner ? 3'd4:3'd0;
  force d.local_core_cmd=local_cmd;force original.local_core_cmd=local_cmd;
  repeat(4)@(negedge clk);rst=1;
  for(k=0;k<300000;k = k + 1)begin
   if(k%1009==0)begin rst=0;owner=0;end
   if(k%1009==17)owner=1;
   for(j=0;j<13;j = j + 1)begin rng=rng*1664525+1013904223;local_cmd[j*32+:32]=rng; rng=rng*1664525+1013904223;external_cmd[j*32+:32]=rng;end
   rng=rng*1664525+1013904223;local_cmd[444:416]=rng[28:0];rng=rng*1664525+1013904223;external_cmd[444:416]=rng[28:0];
   rst=k%1009!=0;
   if(!rst)begin #0.001;comparisons = comparisons + 1;
    if(a_external_service_ready!==0||b_external_service_ready!==0)begin errors = errors + 1;$display("[FAIL] asynchronous reset releases resident ownership immediately");end
   end
   @(negedge clk);
  end
  if(active_checks<100000||gaps<250||resident_checks<250000||local_checks<4000)begin errors = errors + 1;$display("[FAIL] insufficient stable-owner/reset-gap coverage");end
  if(errors==0)$display("[PASS] all real player public pins against frozen original, reachable resident handoff, arbitrary445-bit contexts, terminal ownership and asynchronous reset");
  $display("[TB] tb_v3_resident_owner_equivalence done errors=%0d comparisons=%0d active=%0d gaps=%0d",errors,comparisons,active_checks,gaps);$finish;
 end
 always@(posedge clk)begin #0.001;if(rst)begin
  comparisons = comparisons + 1;
  if(a_external_service_ready)resident_checks = resident_checks + 1;
  if(!owner)local_checks = local_checks + 1;
  if({a_sd_ncs,a_sd_dclk,a_sd_mosi,a_px_word,a_px_word_valid,a_frame_active,a_top_down_o,a_slot_o,a_state_o,a_fail_stage,a_err_code,a_err_detail,a_init_r1,a_init_seq,a_sd_ready,a_card_usable,a_file_cnt,a_cur_file,a_cur_file_size,a_cur_bytes_rd,a_cur_px_written,a_last_frame_ok_o,a_frame_cnt,a_cache_valid,a_cache_count,a_cache_keys,a_rejected_files,a_external_core_rsp,a_external_service_ready,a_ext_rd_ready,a_ext_data,a_ext_data_valid,a_ext_data_last,a_ext_rd_done,a_ext_timeout,a_ext_crc_error,a_ext_err_code,a_ext_err_detail,a_fs_sec_per_clus,a_fs_fat_start_lba,a_fs_data_start_lba,a_fs_root_dir_lba,a_fs_root_clus,a_fs_total_clus,a_progress_count,a_last_reject_error,a_last_reject_key}!=={b_sd_ncs,b_sd_dclk,b_sd_mosi,b_px_word,b_px_word_valid,b_frame_active,b_top_down_o,b_slot_o,b_state_o,b_fail_stage,b_err_code,b_err_detail,b_init_r1,b_init_seq,b_sd_ready,b_card_usable,b_file_cnt,b_cur_file,b_cur_file_size,b_cur_bytes_rd,b_cur_px_written,b_last_frame_ok_o,b_frame_cnt,b_cache_valid,b_cache_count,b_cache_keys,b_rejected_files,b_external_core_rsp,b_external_service_ready,b_ext_rd_ready,b_ext_data,b_ext_data_valid,b_ext_data_last,b_ext_rd_done,b_ext_timeout,b_ext_crc_error,b_ext_err_code,b_ext_err_detail,b_fs_sec_per_clus,b_fs_fat_start_lba,b_fs_data_start_lba,b_fs_root_dir_lba,b_fs_root_clus,b_fs_total_clus,b_progress_count,b_last_reject_error,b_last_reject_key})begin errors = errors + 1;if(errors<12)$display("[FAIL] actual player public interface differs");end
  if(d.service_ready_int)begin active_checks = active_checks + 1;comparisons = comparisons + 1;
   if(d.selected_core_cmd!==original.selected_core_cmd)begin errors = errors + 1;if(errors<12)$display("[FAIL] stable ownership must select identical commands");end
  end else gaps = gaps + 1;
 end end
endmodule
