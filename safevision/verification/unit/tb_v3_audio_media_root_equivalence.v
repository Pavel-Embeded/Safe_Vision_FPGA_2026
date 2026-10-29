`timescale 1ns/1ps
module tb_v3_audio_media_root_equivalence;
 reg rc=0,mc=0,ac=0,pc=0,sc=0,rst=0,media=0;
 always #10 rc=~rc;always #10 mc=~mc;always #40.69 ac=~ac;always #6.741573 pc=~pc;always #5 sc=~sc;
 integer errors=0,comparisons=0,k,pcm_count=0,before_pcm=0;
 wire [444:0] a_core_cmd,b_core_cmd;
 wire  a_commit_ready,b_commit_ready;
 wire  a_media_ready,b_media_ready;
 wire [7:0] a_media_ready_generation,b_media_ready_generation;
 wire [6:0] a_energy,b_energy;
 wire [31:0] a_underflows,b_underflows;
 wire [31:0] a_overflows,b_overflows;
 wire [3:0] a_fallback,b_fallback;
 wire  a_wav_index_done,b_wav_index_done;
 wire  a_rd_en,b_rd_en;
 wire [31:0] a_rd_addr,b_rd_addr;
 wire [15:0] a_rd_len,b_rd_len;
 wire  a_data_ready,b_data_ready;
 wire  a_req,b_req;
 wire  a_wr,b_wr;
 wire [31:0] a_addr,b_addr;
 wire [31:0] a_wdata,b_wdata;
 wire [15:0] a_len,b_len;
 wire  a_pcm_valid,b_pcm_valid;
 wire [23:0] a_left,b_left;
 wire [23:0] a_right,b_right;
 wire  a_acr_valid,b_acr_valid;
 wire [19:0] a_N,b_N;
 wire [19:0] a_CTS,b_CTS;
 v3_audio_system #(.MEDIA_RESET_INCLUDES_GLOBAL(1)) a(.ref_clk(rc),.mem_clk(mc),.audio_clk(ac),.pixel_clk(pc),.sys_clk(sc),.rst_n(rst),.external_service_ready(1'b0),.core_rsp(837'd0),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd2),.root_dir_lba(32'd2),.root_clus(32'd2),.total_clus(32'd120),.target_valid(1'b0),.target_slot(2'd0),.target_generation(8'd0),.commit_valid(1'b0),.commit_slot(2'd0),.commit_generation(8'd0),.volume(7'd73),.alarm_req(1'b1),.rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.ack(1'b0),.busy(1'b0),.rdata(32'd0),.rvalid(1'b0),.media_reset(!rst||media),.core_cmd(a_core_cmd),.commit_ready(a_commit_ready),.media_ready(a_media_ready),.media_ready_generation(a_media_ready_generation),.energy(a_energy),.underflows(a_underflows),.overflows(a_overflows),.fallback(a_fallback),.wav_index_done(a_wav_index_done),.rd_en(a_rd_en),.rd_addr(a_rd_addr),.rd_len(a_rd_len),.data_ready(a_data_ready),.req(a_req),.wr(a_wr),.addr(a_addr),.wdata(a_wdata),.len(a_len),.pcm_valid(a_pcm_valid),.left(a_left),.right(a_right),.acr_valid(a_acr_valid),.N(a_N),.CTS(a_CTS));
 v3_audio_root_reference  b(.ref_clk(rc),.mem_clk(mc),.audio_clk(ac),.pixel_clk(pc),.sys_clk(sc),.rst_n(rst),.external_service_ready(1'b0),.core_rsp(837'd0),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd2),.root_dir_lba(32'd2),.root_clus(32'd2),.total_clus(32'd120),.target_valid(1'b0),.target_slot(2'd0),.target_generation(8'd0),.commit_valid(1'b0),.commit_slot(2'd0),.commit_generation(8'd0),.volume(7'd73),.alarm_req(1'b1),.rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.ack(1'b0),.busy(1'b0),.rdata(32'd0),.rvalid(1'b0),.media_reset(media),.core_cmd(b_core_cmd),.commit_ready(b_commit_ready),.media_ready(b_media_ready),.media_ready_generation(b_media_ready_generation),.energy(b_energy),.underflows(b_underflows),.overflows(b_overflows),.fallback(b_fallback),.wav_index_done(b_wav_index_done),.rd_en(b_rd_en),.rd_addr(b_rd_addr),.rd_len(b_rd_len),.data_ready(b_data_ready),.req(b_req),.wr(b_wr),.addr(b_addr),.wdata(b_wdata),.len(b_len),.pcm_valid(b_pcm_valid),.left(b_left),.right(b_right),.acr_valid(b_acr_valid),.N(b_N),.CTS(b_CTS));
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<12)$display("[FAIL] %s",msg);end end  end endtask
 always@(posedge pc)begin #0.001;
  if($time>1000)begin
   ck({a_core_cmd,a_commit_ready,a_media_ready,a_media_ready_generation,a_energy,a_underflows,a_overflows,a_fallback,a_wav_index_done,a_rd_en,a_rd_addr,a_rd_len,a_data_ready,a_req,a_wr,a_addr,a_wdata,a_len,a_pcm_valid,a_left,a_right,a_acr_valid,a_N,a_CTS}==={b_core_cmd,b_commit_ready,b_media_ready,b_media_ready_generation,b_energy,b_underflows,b_overflows,b_fallback,b_wav_index_done,b_rd_en,b_rd_addr,b_rd_len,b_data_ready,b_req,b_wr,b_addr,b_wdata,b_len,b_pcm_valid,b_left,b_right,b_acr_valid,b_N,b_CTS},"every public audio/control/PCM/ACR output matches the unchanged original root contract");
   if(a_pcm_valid)pcm_count = pcm_count + 1;
  end
 end
 initial begin
 #123.7;rst=1;#6000000;
 ck(a.u_priority.gain==256&&b.u_priority.gain==256,"alarm fully active before media recovery");
 for(k=0;k<16;k = k + 1)begin
  #(1.119+k*7.137);before_pcm=pcm_count;media=1;
  #1;ck(a.media_reset_any&&b.media_reset_any,"media assertion reaches both reset structures immediately");
  #500;ck(a.u_priority.gain==256&&b.u_priority.gain==256,"media recovery leaves alarm ramp independent");
  media=0;#250000;ck(pcm_count>before_pcm,"HDMI alarm samples continue through media recovery");
 end
 for(k=0;k<8;k = k + 1)begin
  #(2.311+k*13.711);rst=0;#501;rst=1;#500000;
 end
 if(errors==0)$display("[PASS]16 asynchronous media phases,8 global reset phases, independent alarm and all public PCM/ACR/status pins against frozen original");
 $display("[TB] tb_v3_audio_media_root_equivalence done errors=%0d comparisons=%0d pcm_pairs=%0d",errors,comparisons,pcm_count);$finish;
 end
 initial begin #20000000;$display("[FAIL] media root watchdog errors=1");$finish;end
endmodule
