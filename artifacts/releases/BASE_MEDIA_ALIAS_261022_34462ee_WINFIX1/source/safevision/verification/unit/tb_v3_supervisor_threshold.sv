`timescale 1ns/1ps
module tb_v3_supervisor_threshold;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,manual_safe=0,recover_request=0,cache_ready=1,media_failed=0,integrity_fault=0,bus_fault=0,fatal=0;
 reg frame_heartbeat=1,mem_heartbeat=1,progress_heartbeat=1,memory_active=1,media_active=1;
 reg[7:0] media_code=0;reg[31:0] video_underflows=0,audio_underflows=0,hdmi_drops=0;reg[15:0] rejected_files=0;reg[3:0] audio_fallback=0;
 wire[100:0] actual,expected;
 wire[100:0] actual_div,expected_div;
v3_supervisor #(.CLK_HZ(10000),.BOOT_CYCLES(32),.FRAME_CYCLES(16),.MEM_CYCLES(16),.PROGRESS_CYCLES(16),.RECOVER_CYCLES(2000)) dut_div(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(actual_div[0]),.media_reset(actual_div[1]),.recovery_busy(actual_div[2]),.recovery_attempts(actual_div[4:3]),.recovery_state(actual_div[7:5]),.fault_code(actual_div[15:8]),.fault_level(actual_div[18:16]),.fault_valid(actual_div[19]),.fatal_latched(actual_div[20]),.fault_ts(actual_div[52:21]),.err_push(actual_div[53]),.err_code(actual_div[61:54]),.err_src(actual_div[65:62]),.err_level(actual_div[68:66]),.err_ts(actual_div[100:69]));
v3_supervisor_reference #(.CLK_HZ(10000),.BOOT_CYCLES(32),.FRAME_CYCLES(16),.MEM_CYCLES(16),.PROGRESS_CYCLES(16),.RECOVER_CYCLES(2000)) reference_div(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(expected_div[0]),.media_reset(expected_div[1]),.recovery_busy(expected_div[2]),.recovery_attempts(expected_div[4:3]),.recovery_state(expected_div[7:5]),.fault_code(expected_div[15:8]),.fault_level(expected_div[18:16]),.fault_valid(expected_div[19]),.fatal_latched(expected_div[20]),.fault_ts(expected_div[52:21]),.err_push(expected_div[53]),.err_code(expected_div[61:54]),.err_src(expected_div[65:62]),.err_level(expected_div[68:66]),.err_ts(expected_div[100:69]));
v3_supervisor #(.CLK_HZ(1000),.BOOT_CYCLES(32),.FRAME_CYCLES(16),.MEM_CYCLES(16),.PROGRESS_CYCLES(16),.RECOVER_CYCLES(2000)) dut(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(actual[0]),.media_reset(actual[1]),.recovery_busy(actual[2]),.recovery_attempts(actual[4:3]),.recovery_state(actual[7:5]),.fault_code(actual[15:8]),.fault_level(actual[18:16]),.fault_valid(actual[19]),.fatal_latched(actual[20]),.fault_ts(actual[52:21]),.err_push(actual[53]),.err_code(actual[61:54]),.err_src(actual[65:62]),.err_level(actual[68:66]),.err_ts(actual[100:69]));
v3_supervisor_reference #(.CLK_HZ(1000),.BOOT_CYCLES(32),.FRAME_CYCLES(16),.MEM_CYCLES(16),.PROGRESS_CYCLES(16),.RECOVER_CYCLES(2000)) reference(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(expected[0]),.media_reset(expected[1]),.recovery_busy(expected[2]),.recovery_attempts(expected[4:3]),.recovery_state(expected[7:5]),.fault_code(expected[15:8]),.fault_level(expected[18:16]),.fault_valid(expected[19]),.fatal_latched(expected[20]),.fault_ts(expected[52:21]),.err_push(expected[53]),.err_code(expected[61:54]),.err_src(expected[65:62]),.err_level(expected[68:66]),.err_ts(expected[100:69]));
 integer errors=0,comparisons=0,i,j,windows=0;reg[31:0] rng=32'hac53e921,vbase=0,abase=0;
 task check(input bit ok,input string msg);begin comparisons=comparisons+1;if(!ok)begin errors=errors+1;if(errors<20)$display("[FAIL] %s cycle=%0d",msg,i);end end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<65536;i=i+1)begin
   @(negedge clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   if(reference.window_done)begin
    case(windows%5)
     0:begin video_underflows=32'hfffffff8;audio_underflows=32'hfffffff9;end
     1:begin video_underflows=32'hffffffff;audio_underflows=0;end
     2:begin video_underflows=0;audio_underflows=32'hfffffff8;end
     3:begin video_underflows=32'h80000000;audio_underflows=32'h7ffffff8;end
     4:begin video_underflows=rng;audio_underflows=~rng;end
    endcase
    vbase=video_underflows;abase=audio_underflows;windows=windows+1;
   end else case(i%6)
    0:begin video_underflows=vbase+7;audio_underflows=abase+8;end
    1:begin video_underflows=vbase+8;audio_underflows=abase+7;end
    2:begin video_underflows=vbase+9;audio_underflows=abase+9;end
    3:begin video_underflows=vbase-1;audio_underflows=abase-1;end
    4:begin video_underflows=32'hffffffff;audio_underflows=0;end
    5:begin video_underflows=rng;audio_underflows=~rng;end
   endcase
   frame_heartbeat=(rng[1:0]!=0);mem_heartbeat=(rng[3:2]!=0);progress_heartbeat=(rng[5:4]!=0);
   manual_safe=(i>40000 && rng[15:8]==8'hff);recover_request=(i>40000 && i%4096==0);
   media_failed=(i>40000 && rng[7:0]==3);integrity_fault=(i>40000 && rng[15:8]==4);bus_fault=(i>40000 && rng[23:16]==5);
   fatal=(i>60000 && i%1000==0);media_code=rng[7:0];audio_fallback=(i>40000)?rng[3:0]:4'd0;
   if(i>40000 && rng[7:0]==6)rejected_files=rejected_files+1;
   if(i>40000 && rng[7:0]==7)hdmi_drops=hdmi_drops+1;
   @(posedge clk);#0.001;
   check(actual===expected,"all101 public bits cycle-exact, including original timestamps");
   check(actual_div===expected_div,"all101 public bits with ten-cycle millisecond divider");
   check(dut_div.watch_tick===reference_div.watch_tick,"predecoded tick equals original counter predicate");
   check(dut_div.window_done===reference_div.window_done,"predecoded window equals original counter predicate");
   check(dut.pending===reference.pending && dut.new_events===reference.new_events,"event masks and arbitration unchanged");
   for(j=0;j<11;j=j+1)if(reference.pending[j])check(dut.stamps[j]===reference.stamps[j],"every occupied timestamp slot unchanged");
  end
  check(windows>=40,"boundary windows exercised");
  if(errors==0)$display("[PASS] exact supervisor threshold predicate, all public bits/events/timestamps");
  $display("[TB] tb_v3_supervisor_threshold done errors=%0d comparisons=%0d windows=%0d",errors,comparisons,windows);$finish;
 end
 initial begin #1000000;$display("[FAIL] supervisor equivalence watchdog errors=1");$finish;end
endmodule
