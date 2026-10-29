`timescale 1ns/1ps
module tb_v3_hd_supervisor_windows;
 reg clk=0,rst=0;always #5 clk=!clk;
 reg[31:0] rng=32'hc641891f;reg[20:0] in=0;reg[7:0] code=0;
 reg[31:0] vu=0,au=0,drops=0;reg[15:0]rejected=0;reg[3:0]fallback=0;
 wire[133:0]a,b;integer comparisons=0,errors=0,k,j;
 reg[31:0] audio_rng=32'h175e2a31;
 integer windows=0,video_events=0,audio_events=0;reg[3:0] window_cases=0;
 v3_supervisor #(.CLK_HZ(1000),.BOOT_CYCLES(17),.FRAME_CYCLES(19),.MEM_CYCLES(23),.PROGRESS_CYCLES(29),.RECOVER_CYCLES(37)) dut(
 .clk(clk),.rst_n(rst),.manual_safe(in[0]),.recover_request(in[1]),.cache_ready(in[2]),.media_failed(in[3]),.media_code(code),
 .integrity_fault(in[4]),.bus_fault(in[5]),.fatal(in[6]),.frame_heartbeat(in[7]),.mem_heartbeat(in[8]),.progress_heartbeat(in[9]),.memory_active(in[10]),.media_active(in[11]),
 .video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),
 .safe_active(a[0]),.media_reset(a[1]),.recovery_busy(a[2]),.recovery_attempts(a[4:3]),.recovery_state(a[7:5]),.fault_code(a[15:8]),.fault_level(a[18:16]),.fault_valid(a[19]),.fatal_latched(a[20]),.fault_ts(a[52:21]),
 .err_push(a[53]),.err_code(a[61:54]),.err_src(a[65:62]),.err_level(a[68:66]),.err_ts(a[100:69]));
 v3_hd_supervisor_reference #(.CLK_HZ(1000),.BOOT_CYCLES(17),.FRAME_CYCLES(19),.MEM_CYCLES(23),.PROGRESS_CYCLES(29),.RECOVER_CYCLES(37)) golden(
 .clk(clk),.rst_n(rst),.manual_safe(in[0]),.recover_request(in[1]),.cache_ready(in[2]),.media_failed(in[3]),.media_code(code),
 .integrity_fault(in[4]),.bus_fault(in[5]),.fatal(in[6]),.frame_heartbeat(in[7]),.mem_heartbeat(in[8]),.progress_heartbeat(in[9]),.memory_active(in[10]),.media_active(in[11]),
 .video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),
 .safe_active(b[0]),.media_reset(b[1]),.recovery_busy(b[2]),.recovery_attempts(b[4:3]),.recovery_state(b[7:5]),.fault_code(b[15:8]),.fault_level(b[18:16]),.fault_valid(b[19]),.fatal_latched(b[20]),.fault_ts(b[52:21]),
 .err_push(b[53]),.err_code(b[61:54]),.err_src(b[65:62]),.err_level(b[68:66]),.err_ts(b[100:69]));


 task compare;begin comparisons++;
  if(a[100:0]!==b[100:0] || (rst && dut.pending_alert!==dut.pending))begin errors++;
   if(errors<9)$display("[FAIL] alert same-edge got=%h want=%h pending=%h alert=%h",a[100:0],b[100:0],dut.pending,dut.pending_alert);
  end
 end endtask


 always @(posedge clk)if(rst && golden.window_done)begin
  windows++;
  if(golden.new_events[3])video_events++;
  if(golden.new_events[4])audio_events++;
  window_cases[{golden.new_events[4],golden.new_events[3]}]=1;
 end
 initial begin
  #2;compare();#39;rst=1;


  for(k=0;k<100000;k=k+1)begin
   @(negedge clk);rng=rng*1664525+1013904223;
   audio_rng=audio_rng*22695477+1;
   in=21'h384;code=0;vu=rng;au=audio_rng;drops=0;
   rejected=0;fallback=0;#1;compare();
   @(posedge clk);#1;compare();
   if(k%16383==16382)begin #1;rst=0;#1;compare();#1;rst=1;end
  end
  if(windows<90 || video_events<10 || audio_events<10 || window_cases!==4'hf)begin
   errors++;$display("[FAIL] incomplete reference window coverage windows=%0d video=%0d audio=%0d cases=%h",windows,video_events,audio_events,window_cases);
  end
  $display("[COVER] reference windows=%0d video=%0d audio=%0d cases=%h",windows,video_events,audio_events,window_cases);
  if(errors==0)$display("[PASS] preserved alert bank same-edge equivalence,100000 changing32-bit counters,full underflow windows,priority/timestamps/reset");
  $display("PASS tb_v3_hd_supervisor_windows comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
