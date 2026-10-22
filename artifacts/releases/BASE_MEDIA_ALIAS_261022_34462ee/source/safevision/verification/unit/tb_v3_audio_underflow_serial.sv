`timescale 1ns/1ps
// Timer semantics use SAMPLE_DIV=8 to accelerate the 800-sample failure window;
// Serial candidate requires >=6 clocks between accepted samples.
// tb_v3_audio_system independently checks the production /256 physical cadence.
module tb_v3_audio_underflow_serial;
 reg rc=0,mc=0,ac=0,pc=0,sc=0;always #10 rc=~rc;always #12.5 mc=~mc;
 always #40.69 ac=~ac;always #6.733 pc=~pc;always #5 sc=~sc;
 reg rst_n=0,mreset=0,cv=0,alarm=0;reg [7:0] generation=1;wire cr;
 wire [31:0] under,over;wire pv;wire [23:0] l,r;integer ticks=0,pairs=0,nonzero=0;
 v3_audio_system #(.SAMPLE_DIV(8)) d(.ref_clk(rc),.mem_clk(mc),.audio_clk(ac),.pixel_clk(pc),.sys_clk(sc),
 .rst_n(rst_n),.media_reset(mreset),.mounted(1'b0),.cache_ready(1'b0),.cache_keys(64'd0),.sec_per_clus(8'd1),
 .fat_start_lba(32'd1),.data_start_lba(32'd16),.root_dir_lba(32'd16),.root_clus(32'd2),.total_clus(32'd120),
 .target_valid(1'b0),.target_slot(2'd0),.target_generation(generation),
 .commit_valid(cv),.commit_slot(2'd0),.commit_generation(generation),.commit_ready(cr),
 .volume(7'd100),.alarm_req(alarm),.underflows(under),.overflows(over),.pcm_valid(pv),.left(l),.right(r),
 .rd_ready(1'b0),.data(8'd0),.data_valid(1'b0),.data_last(1'b0),.rd_done(1'b0),
 .timeout_err(1'b0),.crc16_err(1'b0),.err_code(8'd0),.err_detail(8'd0),
 .ack(1'b0),.busy(1'b0),.rdata(32'd0),.rvalid(1'b0));
 always @(posedge ac)if(rst_n&&d.tick)ticks<=ticks+1;
 always @(posedge pc)if(rst_n&&pv)begin pairs<=pairs+1;if(l!=0||r!=0)nonzero<=nonzero+1;end
 task commit;
  begin @(negedge sc);cv=1;wait(cr);@(negedge sc);cv=0;end
 endtask
 integer base,prior;
 initial begin
  #100;rst_n=1;repeat(20)@(posedge sc);commit();base=ticks;
  wait(ticks>=base+780);if(under!=0)$fatal(1,"unprimed generation false underflow");
  wait(ticks>=base+850);repeat(20)@(posedge sc);
  if(under<20||under>60)$fatal(1,"failed priming must become true underflow %0d",under);
  prior=under;generation=2;commit();base=ticks;wait(ticks>=base+100);
  if(under>prior+5)$fatal(1,"new generation did not restart bounded priming");
  alarm=1;wait(ticks>=base+400);prior=pairs;mreset=1;
  wait(ticks>=base+700);
  if(d.u_priority.gain!=256||pairs<prior+250||nonzero<250||over!=0)$fatal(1,"alarm/cadence interrupted by media reset");
  $display("[PASS] first/new generation bounded priming, true timeout underflow, alarm survives media reset");
  $display("PASS tb_v3_audio_underflow_serial errors=0 comparisons=%0d",pairs);$finish;
 end
 initial begin #2000000;$fatal(1,"underflow test watchdog");end
endmodule
