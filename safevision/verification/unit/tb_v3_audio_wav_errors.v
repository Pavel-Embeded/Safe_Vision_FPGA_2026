`timescale 1ns/1ps
module tb_v3_audio_wav_errors;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;wire en;wire [31:0] addr;wire [15:0] len;
 reg ready=1;reg [7:0] data=0;reg dv=0,last=0,done=0;wire dr;
 wire [127:0] pcm;wire [3:0] valid;reg [3:0] pr=4'hf;wire indexed;wire [3:0] fallback,found;
 reg [3:0] fill=4'hf;reg [7:0] disk[0:65535];reg [31:0] gold[0:7999];
 integer cnt=0,lba=0,received[0:3],checks=0,cycle=0;reg reading=0;reg crc=0;reg [1:0] scenario=0;integer rejected=0;
 v3_wav_source d(.clk(clk),.rst_n(rst_n),.mounted(1'b1),.cache_ready(1'b1),
 .cache_keys(64'h9999900010000001),.sec_per_clus(8'd1),.fat_start_lba(32'd1),.data_start_lba(32'd16),
 .root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),.slot_fill(fill),.sector_room(4'hf),
 .pcm_data(pcm),.pcm_valid(valid),.pcm_ready(pr),.index_done(indexed),.fallback(fallback),.found(found),
 .rd_en(en),.rd_addr(addr),.rd_len(len),.rd_ready(ready),.data(data),.data_valid(dv),.data_ready(dr),
 .data_last(last),.rd_done(done),.timeout_err(1'b0),.crc16_err(crc),.err_code(8'h02),.err_detail(8'h22));
 always @(posedge clk)begin
  if(!rst_n)begin ready<=1;reading<=0;dv<=0;last<=0;done<=0;cnt<=0;crc<=0;end
  else begin
   cycle<=cycle+1;done<=0;crc<=0;
   if(en&&ready)begin
    if((scenario==0&&addr==17)||(scenario==1&&addr==31))begin
     crc<=1;done<=1;ready<=1;reading<=0;rejected<=rejected+1;
    end else begin ready<=0;reading<=1;lba<=addr;cnt<=0;end
    if(len!=1||addr>=128)begin $display("[FAIL] WAV sector request"); $finish; end end
   if(dv&&dr)begin dv<=0;if(last)begin last<=0;reading<=0;ready<=1;done<=1;end else cnt<=cnt+1;end
   else if(reading&&!dv&&cycle%5!=0)begin data<=disk[lba*512+cnt];dv<=1;last<=cnt==511;end
   begin : v_loop_1 integer i; for( i=0;i<4;i=i+1)if(valid[i]&&pr[i])begin
    if(pcm[i*32+:32]!==gold[i*2000+received[i]%2000])begin $display("[FAIL] WAV PCM slot=%0d pair=%0d got=%h exp=%h",i,received[i],pcm[i*32+:32],gold[i*2000+received[i]%2000]); $finish; end 
    received[i]<=received[i]+1;checks<=checks+1;
   end end 
  end
 end
 always @(negedge clk)if(rst_n)begin
  begin : v_loop_2 integer i; for( i=0;i<4;i=i+1)pr[i]=(cycle%(5+i)!=0); end 
 end
 initial begin
  $readmemh("audio_disk.mem",disk);$readmemh("audio_pcm.mem",gold);
  begin : v_loop_3 integer i; for( i=0;i<4;i=i+1)received[i]=0; end 
  #30;rst_n=1;wait(indexed);repeat(20)@(posedge clk);
  if(fallback!=15||received[0]!=0||received[3]!=0)begin $display("[FAIL] directory CRC must reject scan before playback"); $finish; end 
  rst_n=0;scenario=1;

  disk[16*512+27*32]=8'he5;disk[32*512+24]=8'h44;disk[32*512+25]=8'hac;
  begin : v_loop_4 integer i; for( i=0;i<4;i=i+1)received[i]=0; end 
  #30;rst_n=1;wait(indexed);wait(fallback==14);wait(received[0]>=300);
  if(received[1]!=0||received[2]!=0||received[3]!=0||rejected!=2)begin $display("[FAIL] bad/missing WAV leaked PCM or CRC transaction count"); $finish; end 
  $display("[PASS] zero-byte checked-sector CRC failures, incomplete directory, missing key, bad rate, independent good WAV");
  $display("PASS tb_v3_audio_wav_errors errors=0 comparisons=%0d",received[0]);$finish;
 end
 initial begin #5000000;begin $display("[FAIL] WAV error watchdog fb=%h indexed=%b received=%0d",fallback,indexed,received[0]); $finish; end end
endmodule
