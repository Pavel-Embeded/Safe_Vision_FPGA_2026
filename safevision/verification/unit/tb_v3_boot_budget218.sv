`timescale 1ns/1ps
module tb_v3_boot_budget218;
reg clk=0,rst_n=0,cache_ready=0;always #5 clk=~clk;
 wire manual_safe=0,recover_request=0,media_failed=0,integrity_fault=0,bus_fault=0,fatal=0;
 wire frame_heartbeat=1,mem_heartbeat=1,progress_heartbeat=1,memory_active=0,media_active=0;
 wire[7:0]media_code=0;wire[31:0]video_underflows=0,audio_underflows=0,hdmi_drops=0;
 wire[15:0]rejected_files=0;wire[3:0]audio_fallback=0;
 wire[100:0]actual,expected;integer errors=0,comparisons=0,n;
 v3_supervisor #(.CLK_HZ(1000),.BOOT_CYCLES(7),.BOOT_MS_OVERRIDE(60000),.FRAME_CYCLES(1000000),.MEM_CYCLES(1000000),.PROGRESS_CYCLES(1000000)) dut(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(actual[0]),.media_reset(actual[1]),.recovery_busy(actual[2]),.recovery_attempts(actual[4:3]),.recovery_state(actual[7:5]),.fault_code(actual[15:8]),.fault_level(actual[18:16]),.fault_valid(actual[19]),.fatal_latched(actual[20]),.fault_ts(actual[52:21]),.err_push(actual[53]),.err_code(actual[61:54]),.err_src(actual[65:62]),.err_level(actual[68:66]),.err_ts(actual[100:69]));
 v3_supervisor_reference #(.CLK_HZ(1000),.BOOT_CYCLES(60000),.FRAME_CYCLES(1000000),.MEM_CYCLES(1000000),.PROGRESS_CYCLES(1000000)) reference_dut(.clk(clk),.rst_n(rst_n),.manual_safe(manual_safe),.recover_request(recover_request),.cache_ready(cache_ready),.media_failed(media_failed),.media_code(media_code),.integrity_fault(integrity_fault),.bus_fault(bus_fault),.fatal(fatal),.frame_heartbeat(frame_heartbeat),.mem_heartbeat(mem_heartbeat),.progress_heartbeat(progress_heartbeat),.memory_active(memory_active),.media_active(media_active),.video_underflows(video_underflows),.audio_underflows(audio_underflows),.hdmi_drops(hdmi_drops),.rejected_files(rejected_files),.audio_fallback(audio_fallback),.safe_active(expected[0]),.media_reset(expected[1]),.recovery_busy(expected[2]),.recovery_attempts(expected[4:3]),.recovery_state(expected[7:5]),.fault_code(expected[15:8]),.fault_level(expected[18:16]),.fault_valid(expected[19]),.fatal_latched(expected[20]),.fault_ts(expected[52:21]),.err_push(expected[53]),.err_code(expected[61:54]),.err_src(expected[65:62]),.err_level(expected[68:66]),.err_ts(expected[100:69]));
 always@(negedge clk)if(rst_n)begin comparisons++;
  if(actual!==expected)begin errors++;if(errors<8)$display("[FAIL] millisecond budget/public pins mismatch at%0d",n);end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(n=0;n<60010;n++)begin @(posedge clk);#1;
   if(n<59990&&actual[19])begin errors++;$display("[FAIL] boot timeout before60000ms");end
  end
  if(!actual[19])begin errors++;$display("[FAIL] boot deadline never triggers");end
  @(negedge clk);rst_n=0;repeat(5)@(negedge clk);cache_ready=1;rst_n=1;
  for(n=0;n<60100;n++)begin @(posedge clk);#1;if(actual[19])begin errors++;$display("[FAIL] completed initialization must suppress boot deadline");end end
  if(!errors)$display("[PASS]60000ms override vs frozen exact-cycle reference;original7-cycle parameter overridden;no32-bit cycle overflow;cache-ready disarms deadline");
  $display("[TB] tb_v3_boot_budget218 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #2000000;$display("[FAIL] boot budget watchdog errors=1");$finish;end
endmodule
