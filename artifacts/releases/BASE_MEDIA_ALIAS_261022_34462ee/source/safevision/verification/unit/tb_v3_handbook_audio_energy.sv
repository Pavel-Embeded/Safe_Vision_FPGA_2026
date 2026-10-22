`timescale 1ns/1ps
module tb_v3_handbook_audio_energy;
 reg rc=0,mc=0,ac=0,pc=0,sc=0,rst=0,media=0;
 always #10 rc=~rc;always #10 mc=~mc;always #5 ac=~ac;always #2.5 pc=~pc;always #3 sc=~sc;
 reg[6:0]volume=0;reg[23:0]stim_l=24'h400000,stim_r=24'he00000;reg stim_valid=0;
 integer errors=0,comparisons=0,phase=0,v,k,samples=0,settle=0,scaled_checks=0;reg check_scaled=0;
 integer expected_l,expected_r,gain_i;
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
 v3_audio_system #(.MEDIA_RESET_INCLUDES_GLOBAL(1),.HANDBOOK_PROFILE(1)) d(.ref_clk(rc),.mem_clk(mc),.audio_clk(ac),.pixel_clk(pc),.sys_clk(sc),.rst_n(rst),.external_service_ready(1'b0),.core_rsp(837'd0),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd2),.root_dir_lba(32'd2),.root_clus(32'd2),.total_clus(32'd120),.target_valid(1'b0),.target_slot(2'd0),.target_generation(8'd0),.commit_valid(1'b0),.commit_slot(2'd0),.commit_generation(8'd0),.volume(volume),.alarm_req(1'b0),.rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),.ack(1'b0),.busy(1'b0),.rdata(32'd0),.rvalid(1'b0),.media_reset(!rst||media),.core_cmd(a_core_cmd),.commit_ready(a_commit_ready),.media_ready(a_media_ready),.media_ready_generation(a_media_ready_generation),.energy(a_energy),.underflows(a_underflows),.overflows(a_overflows),.fallback(a_fallback),.wav_index_done(a_wav_index_done),.rd_en(a_rd_en),.rd_addr(a_rd_addr),.rd_len(a_rd_len),.data_ready(a_data_ready),.req(a_req),.wr(a_wr),.addr(a_addr),.wdata(a_wdata),.len(a_len),.pcm_valid(a_pcm_valid),.left(a_left),.right(a_right),.acr_valid(a_acr_valid),.N(a_N),.CTS(a_CTS));
 task ck(input bit ok,input string msg);begin comparisons++;if(!ok)begin errors++;if(errors<12)$display("[FAIL] %s",msg);end end endtask
 always@(negedge ac)begin
  if(!rst)begin phase=0;stim_valid=0;end
  else begin stim_valid=phase==0;phase=(phase+1)%256;end
 end
 always@(posedge ac)if(rst)begin
  if(stim_valid)samples++;
  if(check_scaled&&d.scaled_valid)begin
   ck(d.pcm_scaled[23:0]===expected_l[23:0]&&d.pcm_scaled[47:24]===expected_r[23:0],"output volume still scales both PCM channels including mute");scaled_checks++;
  end
 end
 initial begin
  force d.mix_l=stim_l;force d.mix_r=stim_r;force d.mix_valid=stim_valid;
  #123.7;rst=1;
  for(v=0;v<5;v++)begin
   @(negedge sc);case(v)0:volume=0;1:volume=1;2:volume=50;3:volume=70;4:volume=100;endcase
   wait(d.ctrl[15:9]==volume);repeat(2000)@(negedge ac);
   gain_i=volume;expected_l=(4194304*gain_i)/100;expected_r=(-2097152*gain_i)/100;check_scaled=1;
   k=samples;wait(samples>=k+2200);repeat(30)@(negedge sc);check_scaled=0;
   ck(a_energy==75&&d.energy_audio==75,"left-input energy75 is independent of all five volume settings, including zero");
  end
  ck(scaled_checks>10000,"actual volume/output path exercised for10000 samples");
  if(errors==0)$display("[PASS] actual system pre-volume energy and independent post-volume stereo PCM; five gains including mute");
  $display("[TB] tb_v3_handbook_audio_energy done errors=%0d comparisons=%0d PCM=%0d",errors,comparisons,scaled_checks);$finish;
 end
 initial begin #100000000;$display("[FAIL] bounded energy-system watchdog");$display("[TB] tb_v3_handbook_audio_energy done errors=1");$finish;end
endmodule
