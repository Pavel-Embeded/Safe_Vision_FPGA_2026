`include "safevision_defs.vh"
// One physical scanner/file/walker, shared only between disjoint lifetimes.
// All ports use REF clk. Ownership changes reset rst_n for at least one REF edge.
// No arbitration/CDC lives in this module: callers retain their sector owners.
module v3_shared_fs_service #(parameter integer FLEX_FILES=0)(input wire clk,rst_n,
 input wire[7:0] sec_per_clus,input wire[31:0] fat_start_lba,data_start_lba,root_dir_lba,root_clus,total_clus,
 input wire[444:0] core_cmd,output wire[836:0] core_rsp,
 // Optional full-name sideband appends to the verified legacy port order.
 input wire[7:0] name_address,output wire[15:0] name_data,output wire[8:0] name_length);
wire c_kernel_rst_n;
wire c_scan_start;
wire c_ent_ready;
wire c_fs_load;
wire c_fs_enable;
wire c_fs_start;
wire [31:0] c_fs_first;
wire [31:0] c_fs_size;
wire c_fs_ready;
wire [264:0] c_fs_context;
wire c_wk_load;
wire [31:0] c_wk_hop;
wire c_wk_rst;
wire c_wk_start;
wire [31:0] c_wk_cur;
wire [2:0] c_sd_ready;
wire [2:0] c_sd_valid;
wire [2:0] c_sd_last;
wire [2:0] c_sd_done;
wire [2:0] c_sd_timeout;
wire [2:0] c_sd_crc;
wire [7:0] c_sd_data;
wire [7:0] c_sd_ec;
wire [7:0] c_sd_ed;
assign {c_kernel_rst_n,c_scan_start,c_ent_ready,c_fs_load,c_fs_enable,c_fs_start,c_fs_first,c_fs_size,c_fs_ready,c_fs_context,c_wk_load,c_wk_hop,c_wk_rst,c_wk_start,c_wk_cur,c_sd_ready,c_sd_valid,c_sd_last,c_sd_done,c_sd_timeout,c_sd_crc,c_sd_data,c_sd_ec,c_sd_ed}=core_cmd;
wire d_scan_done;
wire d_dir_bad;
wire [7:0] d_err_code;
wire [7:0] d_err_detail;
wire [3:0] d_dbg_state;
wire [87:0] d_ent_name;
wire [7:0] d_ent_attr;
wire [31:0] d_ent_first_clus;
wire [31:0] d_ent_size;
wire [15:0] d_ent_index;
wire d_ent_valid;
wire [31:0] d_sd_rd_addr;
wire [15:0] d_sd_rd_len;
wire d_sd_rd_en;
wire d_sd_data_ready;
wire [31:0] d_wk_cur_clus;
wire d_wk_start;
wire d_wk_rst_walk;
wire f_busy;
wire f_done;
wire f_error;
wire [7:0] f_err_code;
wire [7:0] f_err_detail;
wire [31:0] f_bytes_rd;
wire [3:0] f_dbg_state;
wire [7:0] f_data;
wire f_valid;
wire f_sof;
wire f_eof;
wire f_idle_between_sectors;
wire [264:0] f_context_out;
wire [31:0] f_sd_rd_addr;
wire [15:0] f_sd_rd_len;
wire f_sd_rd_en;
wire f_sd_data_ready;
wire [31:0] f_wk_cur_clus;
wire f_wk_start;
wire f_wk_rst_walk;
wire w_busy;
wire w_done;
wire [31:0] w_next_clus;
wire w_eoc;
wire w_error;
wire [7:0] w_err_code;
wire [7:0] w_err_detail;
wire [31:0] w_hop_cnt;
wire [3:0] w_dbg_state;
wire [31:0] w_sd_rd_addr;
wire [15:0] w_sd_rd_len;
wire w_sd_rd_en;
wire w_sd_data_ready;
// One combinational LBA converter serves disjoint scanner/file lifetimes.
// Scanner owns it only in D_WALK; neither caller takes an extra clock edge.
wire directory_lba_active;
localparam integer SHARED_TO_W=$clog2(`SD_TO_DATA+32'd2);
reg[SHARED_TO_W-1:0] shared_timeout;
wire[2:0] timeout_ticks,timeout_resets;
always @(posedge clk or negedge rst_n)
 if(!rst_n)shared_timeout<=0;
 else if(|timeout_resets)shared_timeout<=0;
 else if(|timeout_ticks)shared_timeout<=shared_timeout+1'b1;

// Requests are captured only after the caller has registered its cluster.
// Two REF stages separate multiplication and LBA addition. Callers wait in
// bounded LBA states; context save is still allowed only between SD sectors.
wire[31:0] file_lba_cluster,directory_lba_cluster;
wire file_lba_request,directory_lba_request,file_lba_valid,directory_lba_valid;
wire[31:0] shared_cluster=directory_lba_active?directory_lba_cluster:file_lba_cluster;
wire shared_spc_legal=(sec_per_clus!=0)&&((sec_per_clus&(sec_per_clus-8'd1))==0);
(* use_ripple=1 *) wire[31:0] shared_lba_bias=data_start_lba-(shared_spc_legal?{23'd0,sec_per_clus,1'b0}:32'd0);
wire[31:0] shared_lba;
generate if(FLEX_FILES)begin:registered_lba
 // Keep both products in REF registers: the owner MUX follows the DSPs.
 // The sampled owner1 selects the same input epoch as bias_q/legal_q; valid
 // and owner publication retain their original two-edge contract.
 wire[7:0] product_factor=sec_per_clus;
 (* use_dsp=1, keep="true" *) reg[31:0] directory_product_q,file_product_q;
 reg[31:0] bias_q,lba_q;reg legal_q;
 reg valid1,valid2,owner1,owner2;
 wire[31:0] selected_product=owner1?directory_product_q:file_product_q;
 always @(posedge clk)begin
  directory_product_q<=directory_lba_cluster*product_factor;
  file_product_q<=file_lba_cluster*product_factor;
  bias_q<=shared_lba_bias;legal_q<=shared_spc_legal;
  lba_q<=bias_q+(legal_q?selected_product:32'd0);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin valid1<=0;valid2<=0;owner1<=0;owner2<=0;end
  else begin
   valid1<=directory_lba_request||file_lba_request;valid2<=valid1;
   owner1<=directory_lba_active;owner2<=owner1;
  end
 end
 assign shared_lba=lba_q;
 assign directory_lba_valid=valid2&&owner2;
 assign file_lba_valid=valid2&&!owner2;
end else begin:legacy_lba
 assign shared_lba=32'd0;
 assign directory_lba_valid=1'b0;assign file_lba_valid=1'b0;
end endgenerate
assign core_rsp={d_scan_done,d_dir_bad,d_err_code,d_err_detail,d_dbg_state,d_ent_name,d_ent_attr,d_ent_first_clus,d_ent_size,d_ent_index,d_ent_valid,d_sd_rd_addr,d_sd_rd_len,d_sd_rd_en,d_sd_data_ready,d_wk_cur_clus,d_wk_start,d_wk_rst_walk,f_busy,f_done,f_error,f_err_code,f_err_detail,f_bytes_rd,f_dbg_state,f_data,f_valid,f_sof,f_eof,f_idle_between_sectors,f_context_out,f_sd_rd_addr,f_sd_rd_len,f_sd_rd_en,f_sd_data_ready,f_wk_cur_clus,f_wk_start,f_wk_rst_walk,w_busy,w_done,w_next_clus,w_eoc,w_error,w_err_code,w_err_detail,w_hop_cnt,w_dbg_state,w_sd_rd_addr,w_sd_rd_len,w_sd_rd_en,w_sd_data_ready};
fat32_directory_scanner #(.SV_MEDIA_ONLY(FLEX_FILES?0:1),.FULL_NAMES(FLEX_FILES),.EXTERNAL_LBA(FLEX_FILES),.EXTERNAL_TIMER(FLEX_FILES),.PIPELINED_LBA(FLEX_FILES)) ds(.clk(clk),
 .external_timeout_count({32'd0,shared_timeout}),.timeout_tick(timeout_ticks[0]),.timeout_reset(timeout_resets[0]),
 .external_lba(shared_lba),.lba_active(directory_lba_active),
 .external_lba_valid(directory_lba_valid),.lba_request(directory_lba_request),.lba_cluster(directory_lba_cluster),
 .name_address(name_address),.name_data(name_data),.name_length(name_length),
 .rst_n(rst_n),
 .sec_per_clus(sec_per_clus),
 .root_clus(root_clus),
 .root_dir_lba(root_dir_lba),
 .data_start_lba(data_start_lba),
 .scan_en(c_scan_start),
 .ent_ready(c_ent_ready),
 .wk_busy(w_busy),
 .wk_done(w_done),
 .wk_next_clus(w_next_clus),
 .wk_eoc(w_eoc),
 .wk_error(w_error),
 .wk_err_code(w_err_code),
 .wk_err_detail(w_err_detail),
 .sd_rd_ready(c_sd_ready[0]),
 .sd_data(c_sd_data),
 .sd_data_valid(c_sd_valid[0]),
 .sd_data_last(c_sd_last[0]),
 .sd_rd_done(c_sd_done[0]),
 .sd_timeout_err(c_sd_timeout[0]),
 .sd_crc16_err(c_sd_crc[0]),
 .sd_err_code(c_sd_ec),
 .sd_err_detail(c_sd_ed),
 .scan_done(d_scan_done),
 .dir_bad(d_dir_bad),
 .err_code(d_err_code),
 .err_detail(d_err_detail),
 .dbg_state(d_dbg_state),
 .ent_name(d_ent_name),
 .ent_attr(d_ent_attr),
 .ent_first_clus(d_ent_first_clus),
 .ent_size(d_ent_size),
 .ent_index(d_ent_index),
 .ent_valid(d_ent_valid),
 .sd_rd_addr(d_sd_rd_addr),
 .sd_rd_len(d_sd_rd_len),
 .sd_rd_en(d_sd_rd_en),
 .sd_data_ready(d_sd_data_ready),
 .wk_cur_clus(d_wk_cur_clus),
 .wk_start(d_wk_start),
 .wk_rst_walk(d_wk_rst_walk));
wire[135:0] compact_fs_context;
assign f_context_out={129'd0,compact_fs_context};
v3_file_streamer_compact_ctx #(.EXTERNAL_LBA(FLEX_FILES),.EXTERNAL_TIMER(FLEX_FILES),.DIRECT_REQUEST_ADDRESS(FLEX_FILES),.PIPELINED_LBA(FLEX_FILES),.REGISTERED_TIMEOUT_EDGE(FLEX_FILES)) fs(.clk(clk),
 .external_timeout_count({32'd0,shared_timeout}),.timeout_tick(timeout_ticks[1]),.timeout_reset(timeout_resets[1]),
 .external_lba(shared_lba),.lba_cluster(file_lba_cluster),
 .external_lba_valid(file_lba_valid),.lba_request(file_lba_request),
 .rst_n(rst_n&&c_kernel_rst_n),
 .context_load(c_fs_load),
 .context_in(c_fs_context[135:0]),
 .context_enable(c_fs_enable),
 .stream_enable(1'b1),
 .start(c_fs_start),
 .first_clus(c_fs_first),
 .file_size(c_fs_size),
 .ready(c_fs_ready),
 .sec_per_clus(sec_per_clus),
 .fat_start_lba(fat_start_lba),
 .data_start_lba(data_start_lba),
 .total_clus(total_clus),
 .wk_busy(w_busy),
 .wk_done(w_done),
 .wk_next_clus(w_next_clus),
 .wk_eoc(w_eoc),
 .wk_error(w_error),
 .wk_err_code(w_err_code),
 .wk_err_detail(w_err_detail),
 .sd_rd_ready(c_sd_ready[1]),
 .sd_data(c_sd_data),
 .sd_data_valid(c_sd_valid[1]),
 .sd_data_last(c_sd_last[1]),
 .sd_rd_done(c_sd_done[1]),
 .sd_timeout_err(c_sd_timeout[1]),
 .sd_crc16_err(c_sd_crc[1]),
 .sd_err_code(c_sd_ec),
 .sd_err_detail(c_sd_ed),
 .busy(f_busy),
 .done(f_done),
 .error(f_error),
 .err_code(f_err_code),
 .err_detail(f_err_detail),
 .bytes_rd(f_bytes_rd),
 .dbg_state(f_dbg_state),
 .data(f_data),
 .valid(f_valid),
 .sof(f_sof),
 .eof(f_eof),
 .idle_between_sectors(f_idle_between_sectors),
 .context_out(compact_fs_context),
 .sd_rd_addr(f_sd_rd_addr),
 .sd_rd_len(f_sd_rd_len),
 .sd_rd_en(f_sd_rd_en),
 .sd_data_ready(f_sd_data_ready),
 .wk_cur_clus(f_wk_cur_clus),
 .wk_start(f_wk_start),
 .wk_rst_walk(f_wk_rst_walk));
v3_cluster_walker_ctx #(.EXTERNAL_TIMER(FLEX_FILES),.DIRECT_REQUEST_ADDRESS(FLEX_FILES)) wk(.clk(clk),
 .external_timeout_count({32'd0,shared_timeout}),.timeout_tick(timeout_ticks[2]),.timeout_reset(timeout_resets[2]),
 .rst_n(rst_n&&c_kernel_rst_n),
 .context_load(c_wk_load),
 .context_hop(c_wk_hop),
 .rst_walk(c_wk_rst),
 .start(c_wk_start),
 .cur_clus(c_wk_cur),
 .fat_start_lba(fat_start_lba),
 .total_clus(total_clus),
 .sd_rd_ready(c_sd_ready[2]),
 .sd_data(c_sd_data),
 .sd_data_valid(c_sd_valid[2]),
 .sd_data_last(c_sd_last[2]),
 .sd_rd_done(c_sd_done[2]),
 .sd_timeout_err(c_sd_timeout[2]),
 .sd_crc16_err(c_sd_crc[2]),
 .sd_err_code(c_sd_ec),
 .sd_err_detail(c_sd_ed),
 .busy(w_busy),
 .done(w_done),
 .next_clus(w_next_clus),
 .eoc(w_eoc),
 .error(w_error),
 .err_code(w_err_code),
 .err_detail(w_err_detail),
 .hop_cnt(w_hop_cnt),
 .dbg_state(w_dbg_state),
 .sd_rd_addr(w_sd_rd_addr),
 .sd_rd_len(w_sd_rd_len),
 .sd_rd_en(w_sd_rd_en),
 .sd_data_ready(w_sd_data_ready));
endmodule
