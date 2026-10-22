`timescale 1ns/1ps
module progress_supervisor_case561 #(parameter HD=0,HZ=1000)(output reg done=0,output integer errors=0,comparisons=0);
 localparam DIV=HZ/1000,BOOT=11;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,manual_safe=0,request=0,cached=0,failed=0,integrity=0,bus=0,fatal=0;
 reg frame_hb=1,mem_hb=0,media_hb=0,memory_active=0,media_active=0;
 reg[31:0]vu=0,au=0,drops=0;reg[15:0]rejected=0;reg[3:0]fallback=0;
  wire opt_safe_active;
 wire opt_media_reset;
 wire opt_recovery_busy;
 wire [1:0] opt_recovery_attempts;
 wire [2:0] opt_recovery_state;
 wire [7:0] opt_fault_code;
 wire [2:0] opt_fault_level;
 wire opt_fault_valid;
 wire opt_fatal_latched;
 wire [31:0] opt_fault_ts;
 wire opt_err_push;
 wire [7:0] opt_err_code;
 wire [3:0] opt_err_src;
 wire [2:0] opt_err_level;
 wire [31:0] opt_err_ts;
 wire legacy_safe_active;
 wire legacy_media_reset;
 wire legacy_recovery_busy;
 wire [1:0] legacy_recovery_attempts;
 wire [2:0] legacy_recovery_state;
 wire [7:0] legacy_fault_code;
 wire [2:0] legacy_fault_level;
 wire legacy_fault_valid;
 wire legacy_fatal_latched;
 wire [31:0] legacy_fault_ts;
 wire legacy_err_push;
 wire [7:0] legacy_err_code;
 wire [3:0] legacy_err_src;
 wire [2:0] legacy_err_level;
 wire [31:0] legacy_err_ts;
 wire reference_safe_active;
 wire reference_media_reset;
 wire reference_recovery_busy;
 wire [1:0] reference_recovery_attempts;
 wire [2:0] reference_recovery_state;
 wire [7:0] reference_fault_code;
 wire [2:0] reference_fault_level;
 wire reference_fault_valid;
 wire reference_fatal_latched;
 wire [31:0] reference_fault_ts;
 wire reference_err_push;
 wire [7:0] reference_err_code;
 wire [3:0] reference_err_src;
 wire [2:0] reference_err_level;
 wire [31:0] reference_err_ts;
  wire[100:0] opt_pack={opt_safe_active,opt_media_reset,opt_recovery_busy,opt_recovery_attempts,opt_recovery_state,opt_fault_code,opt_fault_level,opt_fault_valid,opt_fatal_latched,opt_fault_ts,opt_err_push,opt_err_code,opt_err_src,opt_err_level,opt_err_ts};
 wire[100:0] legacy_pack={legacy_safe_active,legacy_media_reset,legacy_recovery_busy,legacy_recovery_attempts,legacy_recovery_state,legacy_fault_code,legacy_fault_level,legacy_fault_valid,legacy_fatal_latched,legacy_fault_ts,legacy_err_push,legacy_err_code,legacy_err_src,legacy_err_level,legacy_err_ts};
 wire[100:0] reference_pack={reference_safe_active,reference_media_reset,reference_recovery_busy,reference_recovery_attempts,reference_recovery_state,reference_fault_code,reference_fault_level,reference_fault_valid,reference_fatal_latched,reference_fault_ts,reference_err_push,reference_err_code,reference_err_src,reference_err_level,reference_err_ts};
  v3_supervisor #(.CLK_HZ(HZ),.BOOT_CYCLES(BOOT*DIV),.FRAME_CYCLES(200*DIV),.MEM_CYCLES(100*DIV),.PROGRESS_CYCLES(120*DIV),.RECOVER_CYCLES(9),.WINDOW_PIPELINE(HD),.BOOT_MS_OVERRIDE(BOOT),.PROGRESSIVE_LOAD(1)) opt(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(request),.cache_ready(cached),.media_failed(failed),.media_code(8'h02),
  .integrity_fault(integrity),.bus_fault(bus),.fatal(fatal),.frame_heartbeat(frame_hb),.mem_heartbeat(mem_hb),.progress_heartbeat(media_hb),
  .memory_active(memory_active),.media_active(media_active),.video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),.safe_active(opt_safe_active),
  .media_reset(opt_media_reset),
  .recovery_busy(opt_recovery_busy),
  .recovery_attempts(opt_recovery_attempts),
  .recovery_state(opt_recovery_state),
  .fault_code(opt_fault_code),
  .fault_level(opt_fault_level),
  .fault_valid(opt_fault_valid),
  .fatal_latched(opt_fatal_latched),
  .fault_ts(opt_fault_ts),
  .err_push(opt_err_push),
  .err_code(opt_err_code),
  .err_src(opt_err_src),
  .err_level(opt_err_level),
  .err_ts(opt_err_ts));
 v3_supervisor #(.CLK_HZ(HZ),.BOOT_CYCLES(BOOT*DIV),.FRAME_CYCLES(200*DIV),.MEM_CYCLES(100*DIV),.PROGRESS_CYCLES(120*DIV),.RECOVER_CYCLES(9)) legacy(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(request),.cache_ready(cached),.media_failed(failed),.media_code(8'h02),
  .integrity_fault(integrity),.bus_fault(bus),.fatal(fatal),.frame_heartbeat(frame_hb),.mem_heartbeat(mem_hb),.progress_heartbeat(media_hb),
  .memory_active(memory_active),.media_active(media_active),.video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),.safe_active(legacy_safe_active),
  .media_reset(legacy_media_reset),
  .recovery_busy(legacy_recovery_busy),
  .recovery_attempts(legacy_recovery_attempts),
  .recovery_state(legacy_recovery_state),
  .fault_code(legacy_fault_code),
  .fault_level(legacy_fault_level),
  .fault_valid(legacy_fault_valid),
  .fatal_latched(legacy_fatal_latched),
  .fault_ts(legacy_fault_ts),
  .err_push(legacy_err_push),
  .err_code(legacy_err_code),
  .err_src(legacy_err_src),
  .err_level(legacy_err_level),
  .err_ts(legacy_err_ts));
 generate if(HD)begin:hd_ref v3_hd_supervisor_reference #(.CLK_HZ(HZ),.BOOT_CYCLES(BOOT*DIV),.FRAME_CYCLES(200*DIV),.MEM_CYCLES(100*DIV),.PROGRESS_CYCLES(120*DIV),.RECOVER_CYCLES(9)) reference(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(request),.cache_ready(cached),.media_failed(failed),.media_code(8'h02),
  .integrity_fault(integrity),.bus_fault(bus),.fatal(fatal),.frame_heartbeat(frame_hb),.mem_heartbeat(mem_hb),.progress_heartbeat(media_hb),
  .memory_active(memory_active),.media_active(media_active),.video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),.safe_active(reference_safe_active),
  .media_reset(reference_media_reset),
  .recovery_busy(reference_recovery_busy),
  .recovery_attempts(reference_recovery_attempts),
  .recovery_state(reference_recovery_state),
  .fault_code(reference_fault_code),
  .fault_level(reference_fault_level),
  .fault_valid(reference_fault_valid),
  .fatal_latched(reference_fatal_latched),
  .fault_ts(reference_fault_ts),
  .err_push(reference_err_push),
  .err_code(reference_err_code),
  .err_src(reference_err_src),
  .err_level(reference_err_level),
  .err_ts(reference_err_ts));end
 else begin:base_ref v3_supervisor_reference #(.CLK_HZ(HZ),.BOOT_CYCLES(BOOT*DIV),.FRAME_CYCLES(200*DIV),.MEM_CYCLES(100*DIV),.PROGRESS_CYCLES(120*DIV),.RECOVER_CYCLES(9)) reference(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(request),.cache_ready(cached),.media_failed(failed),.media_code(8'h02),
  .integrity_fault(integrity),.bus_fault(bus),.fatal(fatal),.frame_heartbeat(frame_hb),.mem_heartbeat(mem_hb),.progress_heartbeat(media_hb),
  .memory_active(memory_active),.media_active(media_active),.video_underflows(vu),.audio_underflows(au),.hdmi_drops(drops),.rejected_files(rejected),.audio_fallback(fallback),.safe_active(reference_safe_active),
  .media_reset(reference_media_reset),
  .recovery_busy(reference_recovery_busy),
  .recovery_attempts(reference_recovery_attempts),
  .recovery_state(reference_recovery_state),
  .fault_code(reference_fault_code),
  .fault_level(reference_fault_level),
  .fault_valid(reference_fault_valid),
  .fatal_latched(reference_fatal_latched),
  .fault_ts(reference_fault_ts),
  .err_push(reference_err_push),
  .err_code(reference_err_code),
  .err_src(reference_err_src),
  .err_level(reference_err_level),
  .err_ts(reference_err_ts));end endgenerate

 integer boot_events=0,cycles=0,i,guard;reg[31:0]random_state=32'h51951;
 task check(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;if(errors<18)$display("[FAIL] supervisor HD%0d HZ%0d %s t%0t state%0d",HD,HZ,message,$time,opt_recovery_state);end end endtask
 task tick(input integer n);repeat(n)begin @(posedge clk);#2;end endtask
 always @(posedge clk)begin
  if(!rst_n)boot_events=0;
  else if(opt_err_push&&opt_err_src==6)boot_events=boot_events+1;
  #1;if(rst_n)check(legacy_pack===reference_pack,"default0 exactly matches frozen pre-change supervisor on every public output and edge");
 end
 task reset;begin
  @(negedge clk);rst_n=0;manual_safe=0;request=0;cached=0;failed=0;integrity=0;bus=0;fatal=0;
  frame_hb=1;mem_hb=0;media_hb=0;memory_active=0;media_active=0;vu=0;au=0;drops=0;rejected=0;fallback=0;
  tick(3);@(negedge clk);rst_n=1;
 end endtask
 task reach_wait;begin
  @(negedge clk);request=1;tick(1);@(negedge clk);request=0;
  guard=0;while(opt_recovery_state!=4&&guard<160)begin tick(1);guard=guard+1;end
  check(opt_recovery_state==4&&opt_recovery_busy&&!opt_media_reset,"finite reset/settle enters released self-test WAIT");
 end endtask
 initial begin
  reset();
  for(i=0;i<800;i=i+1)begin
   @(negedge clk);media_hb=i%5==0;mem_hb=i%5==2;tick(1);
   check(!opt_fault_valid&&boot_events==0,"real alternating media/memory progress extends boot many original deadlines");
  end
  check(legacy_fault_valid,"default fixed boot deadline still expires despite progress");
  @(negedge clk);media_hb=0;mem_hb=0;tick(BOOT*DIV+8);
  check(opt_fault_valid&&boot_events>0,"stopped progress is bounded even with continuous raster heartbeat");

  reset();tick(BOOT*DIV+8);
  check(opt_fault_valid&&boot_events>0,"frame heartbeat alone never extends boot budget");

  reset();guard=0;
  while(!(opt.watch_tick&&opt.boot_timer==BOOT-1)&&guard<BOOT*DIV+8)begin @(negedge clk);guard=guard+1;end
  check(guard<BOOT*DIV+8,"located exact next boot expiry edge");
  media_hb=1;tick(1);check(opt.boot_timer==0&&!opt_fault_valid,"progress on exact expiry edge wins over boot timeout");
  @(negedge clk);media_hb=0;tick(3);check(!opt_fault_valid&&boot_events==0,"deadline progress creates no deferred boot event");

  reset();reach_wait();
  for(i=0;i<200;i=i+1)begin
   @(negedge clk);media_hb=i%4==0;mem_hb=i%4==2;tick(1);
   check(opt_recovery_state==4&&opt_recovery_busy,"supervisor routes actual load progress into recovery WAIT beyond old timeout");
  end
  @(negedge clk);cached=1;media_hb=1;tick(5);
  check(opt_recovery_state==0&&!opt_recovery_busy&&!opt_safe_active&&opt_recovery_attempts==0,"completed large preload successfully recovers and clears SAFE");

  reset();reach_wait();tick(12);
  check(opt_recovery_state==5&&opt_recovery_attempts==1,"raster-only recovery WAIT locks after finite inactivity");

  reset();@(negedge clk);cached=1;frame_hb=0;media_hb=1;mem_hb=1;tick(200*DIV+8);
  check(opt_fault_valid&&opt_fault_code==3&&boot_events==0,"media progress cannot hide a stopped raster heartbeat");
  reset();@(negedge clk);cached=1;memory_active=1;mem_hb=0;media_hb=1;tick(100*DIV+8);
  check(opt_fault_valid&&opt_fault_code==2&&boot_events==0,"media progress cannot hide an active stalled memory engine");
  reset();@(negedge clk);cached=1;media_active=1;media_hb=0;mem_hb=1;tick(120*DIV+8);
  check(opt_fault_valid&&opt_fault_code==3&&boot_events==0,"memory progress cannot hide an active stalled media engine");

  // Frozen default0 equivalence also covers mixed faults, requests and resets.
  reset();
  for(i=0;i<1800;i=i+1)begin
   @(negedge clk);random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   frame_hb=random_state[0];media_hb=random_state[1];mem_hb=random_state[2];cached=random_state[3];
   request=random_state[4]&&i%17==0;manual_safe=random_state[5]&&i%31==0;
   memory_active=random_state[6];media_active=random_state[7];failed=i%71==0;integrity=i%113==0;bus=i%97==0;
   fatal=i%599==598;rejected=i/151;fallback=i%137==0?4'b0001:0;
   if(i%421==420)begin rst_n=0;end else rst_n=1;
   tick(1);
  end
  if(errors==0)$display("[PASS] progress-aware supervisor HD%0d HZ%0d, boot/recovery inactivity and exact default equivalence",HD,HZ);
  done=1;
 end
endmodule

module progress_recovery_case561 #(parameter TIMEOUT=7)(output reg done_all=0,output integer errors=0,comparisons=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,request=0,completed=0,failed=0,fatal=0,progress=0;
 wire busy,media_reset,rescan,recovered,safe;wire[1:0]attempts;wire[2:0]state;
 media_recovery_ctrl #(.RESET_CYCLES(2),.SETTLE_CYCLES(3),.TIMEOUT_CYCLES(TIMEOUT),.MAX_ATTEMPTS(3),.PROGRESSIVE_WAIT(1)) dut(
  .clk(clk),.rst_n(rst_n),.request(request),.done(completed),.failed(failed),.fatal(fatal),.progress(progress),
  .busy(busy),.media_reset(media_reset),.rescan_start(rescan),.recovered(recovered),.safe_latched(safe),.attempts(attempts),.state(state));
 integer i,j,guard,reset_count,settle_count,scans=0;
 task check(input bit ok,input string message);begin comparisons++;if(!ok)begin errors++;if(errors<18)$display("[FAIL] direct recovery T%0d %s t%0t state%0d",TIMEOUT,message,$time,state);end end endtask
 task tick(input integer n);repeat(n)begin @(posedge clk);#2;end endtask
 task reset;begin @(negedge clk);rst_n=0;request=0;completed=0;failed=0;fatal=0;progress=0;tick(3);@(negedge clk);rst_n=1;end endtask
 task reach_wait;begin
  @(negedge clk);request=1;tick(1);@(negedge clk);request=0;reset_count=0;settle_count=0;guard=0;
  while(state!=4&&guard<20)begin if(state==1)reset_count=reset_count+1;if(state==2)settle_count=settle_count+1;tick(1);guard=guard+1;end
  check(state==4&&busy&&!media_reset&&safe,"request enters finite reset/settle then released WAIT");
  check(reset_count==2&&settle_count==3&&rescan,"reset and settle exact cycle counts; single rescan entry");
 end endtask
 initial begin
  reset();reach_wait();
  for(i=0;i<140;i=i+1)begin
   @(negedge clk);progress=TIMEOUT==1?1:i%3==0;tick(1);
   check(state==4&&busy&&safe,"continuous valid progress keeps long recovery alive");
  end
  @(negedge clk);progress=0;
  // Start a fresh inactivity epoch by one known pulse.
  progress=1;tick(1);@(negedge clk);progress=0;
  for(i=1;i<=TIMEOUT;i=i+1)begin tick(1);check(state==(i<TIMEOUT?4:5),"exact inactivity deadline after final progress pulse");end
  check(!busy&&safe&&attempts==1&&!recovered,"timed-out recovery locks SAFE and retains attempt count");

  reset();reach_wait();
  for(i=1;i<TIMEOUT;i=i+1)tick(1);
  @(negedge clk);progress=1;tick(1);
  check(state==4&&dut.wait_timer==0,"progress on exact WAIT expiry edge wins");
  @(negedge clk);completed=1;progress=1;tick(1);
  check(state==0&&recovered&&!safe&&attempts==0,"done with valid progress succeeds and resets attempts");

  reset();reach_wait();for(i=1;i<TIMEOUT;i=i+1)tick(1);
  @(negedge clk);completed=1;progress=0;tick(1);
  check(state==5&&safe&&!recovered,"expired inactivity deadline wins over unaccompanied done");

  reset();reach_wait();
  @(negedge clk);completed=1;failed=1;progress=1;tick(1);
  check(state==5&&safe&&!recovered&&attempts==1,"failed wins over simultaneous done and progress");

  reset();reach_wait();
  @(negedge clk);completed=1;fatal=1;progress=1;tick(1);
  check(state==5&&safe&&!recovered&&!media_reset,"fatal wins over simultaneous done and progress");

  reset();
  for(j=1;j<=3;j=j+1)begin
   reach_wait();@(negedge clk);failed=1;progress=1;tick(1);
   check(state==5&&attempts==j&&safe&&!busy,"three independent failed attempts remain bounded");
   @(negedge clk);failed=0;progress=0;
  end
  @(negedge clk);request=1;progress=1;tick(4);
  check(state==5&&attempts==3&&!busy&&!media_reset,"fourth request denied even with progress");
  if(errors==0)$display("[PASS] direct progress recovery timeout%0d, deadline priorities, completion and three attempts",TIMEOUT);
  done_all=1;
 end
endmodule

module progress_recovery_legacy_case561(output reg done_all=0,output integer errors=0,comparisons=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,request=0,completed=0,failed=0,fatal=0,progress=0;
 wire[10:0] actual,reference;
 media_recovery_ctrl #(.RESET_CYCLES(2),.SETTLE_CYCLES(3),.TIMEOUT_CYCLES(7),.MAX_ATTEMPTS(3)) dut(
 .clk(clk),.rst_n(rst_n),.request(request),.done(completed),.failed(failed),.fatal(fatal),.progress(progress),
 .busy(actual[10]),.media_reset(actual[9]),.rescan_start(actual[8]),.recovered(actual[7]),.safe_latched(actual[6]),.attempts(actual[5:4]),.state(actual[2:0]));
 assign actual[3]=0;assign reference[3]=0;
 v3_recovery_reset_reference #(.RESET_CYCLES(2),.SETTLE_CYCLES(3),.TIMEOUT_CYCLES(7),.MAX_ATTEMPTS(3)) old(
 .clk(clk),.rst_n(rst_n),.request(request),.done(completed),.failed(failed),.fatal(fatal),
 .busy(reference[10]),.media_reset(reference[9]),.rescan_start(reference[8]),.recovered(reference[7]),.safe_latched(reference[6]),.attempts(reference[5:4]),.state(reference[2:0]));
 integer i;reg[31:0] random_state=32'h12535478;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(i=0;i<4000;i=i+1)begin
   @(negedge clk);random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   request=i%37==0;completed=random_state[0]&&i%11==0;failed=i%53==0;fatal=i%307==306;progress=random_state[2];
   rst_n=i%379!=378;@(posedge clk);#2;
   comparisons++;if(actual!==reference)begin errors++;if(errors<10)$display("[FAIL] exact default recovery equivalence cycle%0d actual%h reference%h",i,actual,reference);end
  end
  if(errors==0)$display("[PASS] default0 recovery exact frozen reference,4000 cycles with unrelated progress");
  done_all=1;
 end
endmodule

module tb_v3_progress_watchdog_base561;
 wire d0,d1;wire[31:0]e0,e1,c0,c1;
 progress_supervisor_case561 #(.HD(0),.HZ(1000)) a(d0,e0,c0);
 progress_supervisor_case561 #(.HD(0),.HZ(4000)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[PASS] BASE progress watchdog complete");$display("[TB] tb_v3_progress_watchdog_base561 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
 initial begin #20000000;$display("[FAIL] watchdog test timeout errors=1");$finish;end
endmodule
module tb_v3_progress_watchdog_hd561;
 wire d0,d1;wire[31:0]e0,e1,c0,c1;
 progress_supervisor_case561 #(.HD(1),.HZ(1000)) a(d0,e0,c0);
 progress_supervisor_case561 #(.HD(1),.HZ(4000)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[PASS] HD progress watchdog complete");$display("[TB] tb_v3_progress_watchdog_hd561 done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
 initial begin #20000000;$display("[FAIL] watchdog test timeout errors=1");$finish;end
endmodule
module tb_v3_progress_recovery561;
 wire d0,d1,d2;wire[31:0]e0,e1,e2,c0,c1,c2;
 progress_recovery_case561 #(.TIMEOUT(7)) a(d0,e0,c0);
 progress_recovery_case561 #(.TIMEOUT(1)) b(d1,e1,c1);
 progress_recovery_legacy_case561 c(d2,e2,c2);
 initial begin wait(d0&&d1&&d2);$display("[PASS] progress recovery complete");$display("[TB] tb_v3_progress_recovery561 done errors=%0d comparisons=%0d",e0+e1+e2,c0+c1+c2);$finish;end
 initial begin #20000000;$display("[FAIL] recovery test timeout errors=1");$finish;end
endmodule
module tb_v3_progress_recovery_hd561;
 wire d0,d1,d2;wire[31:0]e0,e1,e2,c0,c1,c2;
 progress_recovery_case561 #(.TIMEOUT(7)) a(d0,e0,c0);
 progress_recovery_case561 #(.TIMEOUT(1)) b(d1,e1,c1);
 progress_recovery_legacy_case561 c(d2,e2,c2);
 initial begin wait(d0&&d1&&d2);$display("[PASS] HD progress recovery complete");$display("[TB] tb_v3_progress_recovery_hd561 done errors=%0d comparisons=%0d",e0+e1+e2,c0+c1+c2);$finish;end
 initial begin #20000000;$display("[FAIL] recovery test timeout errors=1");$finish;end
endmodule
