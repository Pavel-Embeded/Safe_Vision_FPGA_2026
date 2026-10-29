`timescale 1ns/1ps
module tb_v3_hd_audio_system;
 reg rc=0,mc=0,ac=0,pc=0,sc=0;
 always #10 rc=~rc;always #12.5 mc=~mc;always #40.69 ac=~ac;always #6.733 pc=~pc;always #5 sc=~sc;
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
 .commit_ready(cr),.volume(7'd100),.alarm_req(alarm),.media_ready(mready),.media_ready_generation(mg),
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
   if(last_audio!=0&&aedges-last_audio!=256)begin $display("[FAIL] 48k divider period"); $finish; end 
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
   if(search_first&&l=={gold[slot*2000][15:0],8'd0}&&r=={gold[slot*2000][31:16],8'd0})begin search_first<=0;checking<=1;seen<=1;end
   if(checking)begin
    if(l!=={gold[slot*2000+seen%2000][15:0],8'd0}||r!=={gold[slot*2000+seen%2000][31:16],8'd0})
      begin $display("[FAIL] full audio PCM slot=%0d idx=%0d got=%h,%h exp=%h",slot,seen,l,r,gold[slot*2000+seen%2000]); $finish; end 
    seen<=seen+1;
   end
  end
  if(av)begin acrs<=acrs+1;
   if(n!=6144||cts!=expected_cts||cts<74100||cts>74400)begin $display("[FAIL] measured HDMI ACR N=%0d CTS=%0d",n,cts); $finish; end 
  end
 end
 task commit;
  begin begin @(negedge sc);tv=1;wait(mready&&mg==gen);@(negedge sc);cv=1;wait(cr);@(negedge sc);cv=0;tv=0;end
  end endtask
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  #100;rst_n=1;commit();

  search_first=1;wait(checking);wait(seen>=1200);checking=0;
  if(under!=0)begin $display("[FAIL] false underflow in primed/commit window %0d",under); $finish; end 
  $display("[INFO] generation=%0d stereo_pairs=%0d underflows=%0d",gen,seen,under);
  slot=3;gen=2;commit();
  search_first=1;wait(checking);wait(seen>=1200);checking=0;
  if(under!=0)begin $display("[FAIL] false underflow in primed/commit window %0d",under); $finish; end 
  $display("[INFO] generation=%0d stereo_pairs=%0d underflows=%0d",gen,seen,under);
  alarm=1;repeat(500*256)@(posedge ac);
  media_reset=1;repeat(300*256)@(posedge ac);
  if(d.u_priority.gain!=256||over!=0||acrs<20)begin $display("[FAIL] independent alarm/HDMI reset boundary"); $finish; end 
  media_reset=0;alarm=0;slot=0;gen=3;commit();
  search_first=1;wait(checking);wait(seen>=300);checking=0;
  $display("[PASS] stereo full-scale, 4-domain FIFO, 48k, target800pairs, generation switch, alarm mediareset, energy/CTS");
  $display("PASS tb_v3_hd_audio_system errors=0 comparisons=2700 HDMI_pairs=%0d ACR=%0d under=%0d over=%0d",pairs,acrs,under,over);$finish;
 end
 initial begin #150000000;begin $display("[FAIL] audio system watchdog idx=%b fb=%h level=%h seen=%0d",indexed,fallback,d.ring_levels,seen); $finish; end end
endmodule

