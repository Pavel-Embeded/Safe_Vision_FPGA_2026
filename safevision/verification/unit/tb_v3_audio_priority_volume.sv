`timescale 1ns/1ps
// Two production clock profiles use one PCM/CTS oracle. This file is kept
// separate from the legacy MEM40 protocol stress bench.
module v3_audio_priority_volume_scenario #(
 parameter real PIX_HALF_NS=6.733,
 parameter integer CTS_MIN=74100, CTS_MAX=74400, VOL=37,
 parameter [255:0] REPORT_NAME="tb_v3_priority_hd50");
 reg rc=0,mc=0,ac=0,pc=0,sc=0;
 always #10 rc=~rc;always #10 mc=~mc;always #40.69 ac=~ac;always #(PIX_HALF_NS) pc=~pc;always #5 sc=~sc;
 reg rst_n=0,media_reset=0,tv=0,cv=0,alarm=0;reg [1:0] slot=0;reg [7:0] gen=1;
 wire cr,mready;wire [7:0] mg;wire [6:0] energy;wire [31:0] under,over;wire [3:0] fallback;wire indexed;
 wire sd_en,sd_dr;wire [31:0] sd_addr;wire [15:0] sd_len;
 reg sd_ready=1;reg [7:0] sd_data=0;reg sd_dv=0,sd_last=0,sd_done=0,sd_reading=0;
 reg [7:0] disk[0:65535];reg [31:0] gold[0:7999],ram[0:65535];
 wire req,wr;wire [31:0] addr,wd;wire [15:0] len;reg ack=0,busy=0,rv=0;reg [31:0] rd=0;
 wire pv,av;wire [23:0] l,r;wire [19:0] n,cts;
 integer cnt=0,lba=0,rcycle=0,mcycle=0,delay=0,pairs=0,acrs=0,interval=0,last_audio=0,aedges=0;
 reg [31:0] lataddr,latdata;reg latwr;integer seen=0;reg checking=0,search_first=0;integer pc_count=0,acr_base=0,acr_samples=0,expected_cts=0;reg acr_armed=0;
 v3_audio_system d(.ref_clk(rc),.mem_clk(mc),.audio_clk(ac),.pixel_clk(pc),.sys_clk(sc),.rst_n(rst_n),.media_reset(media_reset),
 .mounted(1'b1),.cache_ready(1'b1),.cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),
 .fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),
 .target_valid(tv),.target_slot(slot),.target_generation(gen),.commit_valid(cv),.commit_slot(slot),.commit_generation(gen),
 .commit_ready(cr),.volume(VOL[6:0]),.alarm_req(alarm),.media_ready(mready),.media_ready_generation(mg),
 .energy(energy),.underflows(under),.overflows(over),.fallback(fallback),.wav_index_done(indexed),
 .rd_en(sd_en),.rd_addr(sd_addr),.rd_len(sd_len),.rd_ready(sd_ready),.data(sd_data),.data_valid(sd_dv),.data_ready(sd_dr),
 .data_last(sd_last),.rd_done(sd_done),.timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),
 .req(req),.wr(wr),.addr(addr),.wdata(wd),.len(len),.ack(ack),.busy(busy),.rdata(rd),.rvalid(rv),
 .pcm_valid(pv),.left(l),.right(r),.acr_valid(av),.N(n),.CTS(cts));
 always @(posedge rc)if(!rst_n||media_reset)begin
  sd_ready<=1;sd_reading<=0;sd_dv<=0;sd_last<=0;sd_done<=0;cnt<=0;
 end else begin
  rcycle<=rcycle+1;sd_done<=0;
  if(sd_en&&sd_ready)begin sd_ready<=0;sd_reading<=1;lba<=sd_addr;cnt<=0;end
  if(sd_dv&&sd_dr)begin sd_dv<=0;if(sd_last)begin sd_last<=0;sd_reading<=0;sd_ready<=1;sd_done<=1;end else cnt<=cnt+1;end
  else if(sd_reading&&!sd_dv&&rcycle%5!=0)begin sd_data<=disk[lba*512+cnt];sd_dv<=1;sd_last<=cnt==511;end
 end
 always @(posedge mc)begin
  ack<=0;rv<=0;mcycle<=mcycle+1;
  if(rst_n)begin
   if(!busy&&req&&mcycle%7!=0)begin ack<=1;busy<=1;lataddr<=addr;latdata<=wd;latwr<=wr;delay<=2+mcycle%7;end
   else if(busy)if(delay!=0)delay<=delay-1;else begin busy<=0;
    if(latwr)ram[(lataddr-32'h280000)>>2]<=latdata;else begin rd<=ram[(lataddr-32'h280000)>>2];rv<=1;end
   end
  end
 end
 always @(posedge ac)if(rst_n)begin
  aedges<=aedges+1;
  if(d.tick)begin
   if(last_audio!=0&&aedges-last_audio!=256)$fatal(1,"48k divider period");
   last_audio<=aedges;
  end
 end
 always @(posedge pc)if(rst_n)begin
  pc_count<=pc_count+1;
  if(pv)begin
   if(!acr_armed)begin acr_armed<=1;acr_base<=pc_count;acr_samples<=0;end
   else if(acr_samples==47)begin expected_cts<=pc_count-acr_base;acr_base<=pc_count;acr_samples<=0;end
   else acr_samples<=acr_samples+1;
  end
  if(pv)begin pairs<=pairs+1;
   if(search_first&&l==scale_pcm({gold[slot*2000][15:0],8'd0},VOL)&&r==scale_pcm({gold[slot*2000][31:16],8'd0},VOL))begin search_first<=0;checking<=1;seen<=1;end
   if(checking)begin
    if(l!==scale_pcm({gold[slot*2000+seen%2000][15:0],8'd0},VOL)||r!==scale_pcm({gold[slot*2000+seen%2000][31:16],8'd0},VOL))
      $fatal(1,"full audio PCM slot=%0d idx=%0d got=%h,%h exp=%h",slot,seen,l,r,gold[slot*2000+seen%2000]);
    seen<=seen+1;
   end
  end
  if(av)begin acrs<=acrs+1;
   if(n!=6144||cts!=expected_cts||cts<CTS_MIN||cts>CTS_MAX)$fatal(1,"measured HDMI ACR N=%0d CTS=%0d",n,cts);
  end
 end
 // Independent queue checks captured PCM24 through every priority pipeline phase.
 // It deliberately does not assign a new generation to a previously captured pair.
 reg[23:0] queued_l[0:7],queued_r[0:7];integer due[0:7];
 integer qw=0,qr=0,qn=0,priority_cycle=0,priority_comparisons=0;
 integer reference_gain=0,reference_error=0,total_gain,step_gain;
 reg[4:0] reset_phases=0,commit_phases=0,alarm_phases=0;
 function[23:0] full_blend;input[23:0] wav,tone;input integer g;
  reg signed[63:0] wa,to,answer;begin
   wa=$signed(wav);to=$signed(tone);answer=(wa*(256-g)+to*g)>>>8;full_blend=answer[23:0];
  end endfunction
 always@(posedge ac)begin
  if(!d.audio_global_rst_n)begin qw=0;qr=0;qn=0;reference_gain=0;reference_error=0;priority_cycle=0;end
  else begin
   priority_cycle=priority_cycle+1;
   if(d.sample_valid)begin
    total_gain=reference_error+256;step_gain=total_gain/240;reference_error=total_gain%240;
    if(d.ctrl[16]||(d.ctrl[17]&&d.ctrl[8]))reference_gain=(reference_gain+step_gain>256)?256:reference_gain+step_gain;
    else reference_gain=(reference_gain>step_gain)?reference_gain-step_gain:0;
    queued_l[qw]=full_blend(d.wav_l,d.tone_l,reference_gain);
    queued_r[qw]=full_blend(d.wav_r,d.tone_r,reference_gain);
    due[qw]=priority_cycle+5;qw=(qw+1)%8;qn=qn+1;
    if(qn>1)$fatal(1,"serial priority scheduling overlap");
   end
   #0.001;
   if(d.mix_valid)begin
    if(qn==0||priority_cycle!=due[qr]||d.mix_l!==queued_l[qr]||d.mix_r!==queued_r[qr])
     $fatal(1,"priority epoch/SAFE pipeline changed captured pair cycle=%0d due=%0d count=%0d got=%h,%h expected=%h,%h",priority_cycle,due[qr],qn,d.mix_l,d.mix_r,queued_l[qr],queued_r[qr]);
    qr=(qr+1)%8;qn=qn-1;priority_comparisons=priority_comparisons+2;
   end else if(qn!=0&&priority_cycle>=due[qr])$fatal(1,"priority missing output at exact capture latency");
  end
 end
 integer injected_phase;
 function[23:0] scale_pcm;input[23:0] value;input integer percent;
  reg signed[63:0] signed_value,answer;begin
   signed_value=$signed(value);answer=signed_value*percent/100;scale_pcm=answer[23:0];
  end endfunction
 integer volume_cycle=0,volume_queued=0,volume_due=0,volume_comparisons=0;
 reg[23:0] volume_gold_l,volume_gold_r;
 always@(posedge ac)begin
  if(!d.audio_global_rst_n)begin volume_cycle=0;volume_queued=0;end
  else begin
   volume_cycle=volume_cycle+1;
   if(d.mix_valid)begin
    if(volume_queued!=0)$fatal(1,"volume overlapping captured input");
    volume_gold_l=scale_pcm(d.mix_l,VOL);volume_gold_r=scale_pcm(d.mix_r,VOL);
    volume_queued=1;volume_due=volume_cycle+74;
   end
   #0.001;
   if(d.scaled_valid)begin
    if(volume_queued!=1||volume_cycle!=volume_due||d.pcm_scaled[23:0]!==volume_gold_l||d.pcm_scaled[47:24]!==volume_gold_r)
     $fatal(1,"volume changed/dropped captured pair across epoch/recovery cycle=%0d due=%0d",volume_cycle,volume_due);
    volume_queued=0;volume_comparisons=volume_comparisons+2;
   end else if(volume_queued!=0&&volume_cycle>=volume_due)$fatal(1,"volume missing exact74-clock output");
  end
 end
 wire[6:0] volume_phase_index=d.volume_scale.busy?
  (d.volume_scale.right_phase?7'd38:7'd1)+(d.volume_scale.state==2?7'd7:7'd0)+d.volume_scale.count:7'd0;
 reg[7:0] volume_phase_seen=0;integer volume_injection,volume_target;
 task commit;
  begin @(negedge sc);tv=1;wait(mready&&mg==gen);@(negedge sc);cv=1;wait(cr);@(negedge sc);cv=0;tv=0;end
 endtask
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  #100;rst_n=1;commit();
  // Identify first nonzero PCM to ignore explicit startup silence.
  search_first=1;wait(checking);wait(seen>=1200);checking=0;
  if(under!=0)$fatal(1,"false underflow in primed/commit window %0d",under);
  $display("[INFO] generation=%0d stereo_pairs=%0d underflows=%0d",gen,seen,under);
  slot=3;gen=2;commit();
  search_first=1;wait(checking);wait(seen>=1200);checking=0;
  if(under!=0)$fatal(1,"false underflow in primed/commit window %0d",under);
  $display("[INFO] generation=%0d stereo_pairs=%0d underflows=%0d",gen,seen,under);
  alarm=1;repeat(500*256)@(posedge ac);
  media_reset=1;repeat(300*256)@(posedge ac);
  if(d.u_priority.gain!=256||over!=0||acrs<20)$fatal(1,"independent alarm/HDMI reset boundary");
  media_reset=0;alarm=0;slot=0;gen=3;commit();
  search_first=1;wait(checking);wait(seen>=300);checking=0;
  // Enter media recovery, commit a fresh epoch, and change the alarm request
  // at each serial calculation phase. The HDMI stream remains fully checked
  // after each new first matching sample, while the capture queue runs throughout.
  for(injected_phase=1;injected_phase<=5;injected_phase=injected_phase+1)begin
   @(negedge ac);while(d.u_priority.state!=injected_phase)@(negedge ac);
   reset_phases[injected_phase-1]=1;alarm_phases[injected_phase-1]=1;
   media_reset=1;alarm=1;
   repeat(4*256)@(negedge ac);
   media_reset=0;alarm=0;slot=injected_phase%4;gen=gen+1;
   @(negedge sc);tv=1;wait(mready&&mg==gen);
   @(negedge ac);while(d.u_priority.state!=injected_phase)@(negedge ac);
   commit_phases[injected_phase-1]=1;
   @(negedge sc);cv=1;wait(cr);@(negedge sc);cv=0;tv=0;
   search_first=1;wait(checking);wait(seen>=16);checking=0;
  end
  // Exercise both edges of every multiply/divide stage with real user
  // recovery/alarm/commit requests. Captured PCM stays immutable through reset.
  for(volume_injection=0;volume_injection<8;volume_injection=volume_injection+1)begin
   case(volume_injection)
    0:volume_target=1;1:volume_target=7;2:volume_target=8;3:volume_target=37;
    4:volume_target=38;5:volume_target=44;6:volume_target=45;7:volume_target=74;
   endcase
   @(negedge ac);while(volume_phase_index!=volume_target)@(negedge ac);
   volume_phase_seen[volume_injection]=1;media_reset=1;alarm=1;
   repeat(4*256)@(negedge ac);
   media_reset=0;alarm=0;slot=volume_injection%4;gen=gen+1;
   @(negedge sc);tv=1;wait(mready&&mg==gen);
   @(negedge ac);while(volume_phase_index!=volume_target)@(negedge ac);
   @(negedge sc);cv=1;wait(cr);@(negedge sc);cv=0;tv=0;
   search_first=1;wait(checking);wait(seen>=16);checking=0;
  end
  if(volume_phase_seen!=255||volume_comparisons<5000)$fatal(1,"volume boundary injection coverage incomplete");
  $display("[INFO] volume_channel_comparisons=%0d phase_mask=%h percent=%0d",volume_comparisons,volume_phase_seen,VOL);
  if(reset_phases!=31||commit_phases!=31||alarm_phases!=31||priority_comparisons<5000)
   $fatal(1,"phase injection or independent priority queue coverage incomplete");
  $display("[PASS] five-phase user commit/mediareset/alarm requests, captured full PCM24 queue, old queued pair never relabeled, later HDMI/CTS checked");
  $display("[INFO] priority_channel_comparisons=%0d reset_phases=%h commit_phases=%h alarm_phases=%h",priority_comparisons,reset_phases,commit_phases,alarm_phases);
  $display("[PASS] stereo full-scale, 4-domain FIFO, 48k, target800pairs, generation switch, alarm mediareset, energy/CTS");
  $display("PASS %0s errors=0 comparisons=2908 HDMI_pairs=%0d ACR=%0d under=%0d over=%0d",REPORT_NAME,pairs,acrs,under,over);$finish;
 end
 initial begin #300000000;$fatal(1,"audio system watchdog idx=%b fb=%h level=%h seen=%0d",indexed,fallback,d.ring_levels,seen);end
endmodule


module tb_v3_pv_base37;
 v3_audio_priority_volume_scenario #(.PIX_HALF_NS(19.84126984126984),.CTS_MIN(25100),.CTS_MAX(25300),.VOL(37),.REPORT_NAME("tb_v3_pv_base37")) scenario();
endmodule

module tb_v3_pv_hd37;
 v3_audio_priority_volume_scenario #(.PIX_HALF_NS(6.734006734006734),.CTS_MIN(74100),.CTS_MAX(74400),.VOL(37),.REPORT_NAME("tb_v3_pv_hd37")) scenario();
endmodule

module tb_v3_pv_base73;
 v3_audio_priority_volume_scenario #(.PIX_HALF_NS(19.84126984126984),.CTS_MIN(25100),.CTS_MAX(25300),.VOL(73),.REPORT_NAME("tb_v3_pv_base73")) scenario();
endmodule

module tb_v3_pv_hd73;
 v3_audio_priority_volume_scenario #(.PIX_HALF_NS(6.734006734006734),.CTS_MIN(74100),.CTS_MAX(74400),.VOL(73),.REPORT_NAME("tb_v3_pv_hd73")) scenario();
endmodule
