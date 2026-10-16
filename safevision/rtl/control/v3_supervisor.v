`include "fault_code_defs.vh"
// SYS-domain supervisor. All inputs below are already atomic snapshots or
// synchronized event pulses. Idle media/memory engines do not arm watchdogs.
// The fixed raster heartbeat remains required while a static image is shown.
module v3_supervisor #(
 parameter integer CLK_HZ=100000000,BOOT_CYCLES=2000000000,
 parameter integer FRAME_CYCLES=10000000,MEM_CYCLES=20000000,
 parameter integer PROGRESS_CYCLES=50000000,RECOVER_CYCLES=2000000000
)(input wire clk,rst_n,manual_safe,recover_request,cache_ready,media_failed,
 input wire[7:0] media_code,input wire integrity_fault,bus_fault,fatal,
 input wire frame_heartbeat,mem_heartbeat,progress_heartbeat,
 input wire memory_active,media_active,
 input wire[31:0] video_underflows,audio_underflows,hdmi_drops,
 input wire[15:0] rejected_files,input wire[3:0] audio_fallback,
 output wire safe_active,media_reset,recovery_busy,
 output wire[1:0] recovery_attempts,output wire[2:0] recovery_state,
 output wire[7:0] fault_code,output wire[2:0] fault_level,
 output wire fault_valid,fatal_latched,output wire[31:0] fault_ts,
 output wire err_push,output reg[7:0] err_code,output reg[3:0] err_src,
 output reg[2:0] err_level,output reg[31:0] err_ts);
 // A shared 1 ms enable avoids five independent 100 MHz wide counters.
 // Heartbeats clear immediately; expiry occurs on a shared tick, within one
 // tick before the exact cycle interval. At CLK_HZ=1000 the unit is one clock.
 // Non-integral-kHz test clocks retain exact cycle counting (TICK_DIV=1).
 localparam integer TICK_DIV=(CLK_HZ>=1000 && CLK_HZ%1000==0)?CLK_HZ/1000:1;
 localparam integer BOOT_LIMIT=(BOOT_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer FRAME_LIMIT=(FRAME_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer MEM_LIMIT=(MEM_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer PROGRESS_LIMIT=(PROGRESS_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer WINDOW_LIMIT=CLK_HZ/TICK_DIV;
 function integer width_for;input integer limit;begin width_for=(limit>1)?$clog2(limit+1):1;end endfunction
 reg[width_for(BOOT_LIMIT)-1:0] boot_timer;
 reg[width_for(FRAME_LIMIT)-1:0] frame_timer;
 reg[width_for(MEM_LIMIT)-1:0] mem_timer;
 reg[width_for(PROGRESS_LIMIT)-1:0] progress_timer;
 reg[width_for(WINDOW_LIMIT)-1:0] window_timer;
 reg[width_for(TICK_DIV-1)-1:0] ms_timer;
 reg[31:0] last_vu,last_au,last_hd,ms_now;
 wire watch_tick=ms_timer==TICK_DIV-1;
 reg initialized,fault_i_old,fault_b_old,failed_old,hd_fault_old;
 reg[10:0] pending,selection,new_events;
 reg[15:0] rejected_old;reg[3:0] fallback_old;
 reg[7:0] media_first;reg[31:0] stamps[0:10];
 wire recovered,recover_safe,rescan_unused,reset_unused;
 wire recover_failed=media_failed || integrity_fault || bus_fault;
 media_recovery_ctrl #(.RESET_CYCLES(64),.SETTLE_CYCLES(64),
 .TIMEOUT_CYCLES(RECOVER_CYCLES),.MAX_ATTEMPTS(3)) recovery(
 .clk(clk),.rst_n(rst_n),.request(recover_request && !manual_safe),
 .done(cache_ready && !recover_failed),.failed(recover_failed),.fatal(fatal_latched),
 .busy(recovery_busy),.media_reset(media_reset),.rescan_start(rescan_unused),
 .recovered(recovered),.safe_latched(recover_safe),.attempts(recovery_attempts),.state(recovery_state));
 wire window_done=watch_tick && window_timer==WINDOW_LIMIT-1;
 always @*begin
  new_events=0;
  if(media_failed && !failed_old && !recovery_busy)new_events[0]=1;
  if(integrity_fault && !fault_i_old && !media_reset)new_events[1]=1;
  if(bus_fault && !fault_b_old && !media_reset)new_events[2]=1;
  if(window_done && video_underflows>=last_vu && video_underflows-last_vu>=8)new_events[3]=1;
  if(window_done && audio_underflows>=last_au && audio_underflows-last_au>=8)new_events[4]=1;
  if(watch_tick && frame_timer==FRAME_LIMIT-1 && !frame_heartbeat && !recovered)new_events[5]=1;
  if(watch_tick && memory_active && mem_timer==MEM_LIMIT-1 && !mem_heartbeat && !media_reset)new_events[6]=1;
  if(watch_tick && media_active && progress_timer==PROGRESS_LIMIT-1 && !progress_heartbeat && !media_reset)new_events[7]=1;
  if((hdmi_drops!=last_hd && !hd_fault_old) || (watch_tick && !initialized && !cache_ready && !recovery_busy && boot_timer==BOOT_LIMIT-1) || (fatal && !fatal_latched))new_events[8]=1;
  if(rejected_files>rejected_old && !media_reset)new_events[9]=1;
  if((|(audio_fallback & ~fallback_old)) && !media_reset)new_events[10]=1;
  selection=0;err_code=0;err_src=0;err_level=3;err_ts=0;
  if(pending[0])begin selection[0]=1;err_code=media_first;err_src=2;err_level=cache_ready?2:3;err_ts=stamps[0];end
  else if(pending[1])begin selection[1]=1;err_code=`ERR_MEDIA_INVALID;err_src=3;err_ts=stamps[1];end
  else if(pending[2])begin selection[2]=1;err_code=`ERR_SD_IO;err_src=3;err_ts=stamps[2];end
  else if(pending[3])begin selection[3]=1;err_code=`ERR_MEDIA_INVALID;err_src=1;err_ts=stamps[3];end
  else if(pending[4])begin selection[4]=1;err_code=`ERR_WAV;err_src=4;err_ts=stamps[4];end
  else if(pending[5])begin selection[5]=1;err_code=`ERR_MEDIA_INVALID;err_src=5;err_ts=stamps[5];end
  else if(pending[6])begin selection[6]=1;err_code=`ERR_SD_IO;err_src=5;err_ts=stamps[6];end
  else if(pending[7])begin selection[7]=1;err_code=`ERR_MEDIA_INVALID;err_src=5;err_ts=stamps[7];end
  else if(pending[8])begin selection[8]=1;err_code=`ERR_MEDIA_INVALID;err_src=6;err_level=fatal_latched?4:3;err_ts=stamps[8];end
  else if(pending[9])begin selection[9]=1;err_code=`ERR_MEDIA_INVALID;err_src=2;err_level=1;err_ts=stamps[9];end
  else if(pending[10])begin selection[10]=1;err_code=`ERR_WAV;err_src=4;err_level=0;err_ts=stamps[10];end
 end
 assign err_push=|pending;
 assign safe_active=manual_safe || !cache_ready || recovery_busy || recover_safe || fatal_latched || (fault_valid && fault_level>=3);
 fault_manager #(.CLK_HZ(CLK_HZ)) faults(.clk(clk),.rst_n(rst_n),
 .err_push(err_push),.err_code(err_code),.err_level(err_level),.wdt_timeout(1'b0),
 .wdt_reason(8'd0),.media_fatal(fatal),.recover_ack(recovered),
 .fault_code(fault_code),.fault_level(fault_level),.fault_valid(fault_valid),
 .fatal(fatal_latched),.fault_ts(fault_ts),.media_rst_req(reset_unused));
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin boot_timer<=0;frame_timer<=0;mem_timer<=0;progress_timer<=0;
   window_timer<=0;last_vu<=0;last_au<=0;last_hd<=0;ms_timer<=0;ms_now<=0;
   initialized<=0;pending<=0;media_first<=0;fault_i_old<=0;fault_b_old<=0;
   failed_old<=0;hd_fault_old<=0;rejected_old<=0;fallback_old<=0;for(i=0;i<11;i=i+1)stamps[i]<=0;
  end else begin
   pending<=(pending & ~selection) | new_events;
   for(i=0;i<11;i=i+1)if(new_events[i] && !pending[i])stamps[i]<=ms_now;
   if(new_events[0] && !pending[0])media_first<=media_code;
   fault_i_old<=integrity_fault;fault_b_old<=bus_fault;failed_old<=media_failed;
   hd_fault_old<=hdmi_drops!=last_hd;
   rejected_old<=rejected_files;fallback_old<=audio_fallback;
   if(watch_tick)begin ms_timer<=0;ms_now<=ms_now+1'b1;end else ms_timer<=ms_timer+1'b1;
   if(cache_ready)initialized<=1;
   if(initialized || recovery_busy || cache_ready)boot_timer<=0;
   else if(watch_tick && boot_timer<BOOT_LIMIT)boot_timer<=boot_timer+1'b1;
   if(frame_heartbeat || recovered)frame_timer<=0;
   else if(watch_tick && frame_timer<FRAME_LIMIT)frame_timer<=frame_timer+1'b1;
   if(!memory_active || mem_heartbeat || media_reset)mem_timer<=0;
   else if(watch_tick && mem_timer<MEM_LIMIT)mem_timer<=mem_timer+1'b1;
   if(!media_active || progress_heartbeat || media_reset)progress_timer<=0;
   else if(watch_tick && progress_timer<PROGRESS_LIMIT)progress_timer<=progress_timer+1'b1;
   if(window_done || media_reset)begin
    window_timer<=0;last_vu<=video_underflows;last_au<=audio_underflows;last_hd<=hdmi_drops;
   end else if(watch_tick)window_timer<=window_timer+1'b1;
  end
 end
 // synthesis translate_off
 initial if(CLK_HZ<1000 || FRAME_CYCLES<2 || MEM_CYCLES<2 || PROGRESS_CYCLES<2)
  $fatal(1,"invalid supervisor clock or watchdog limits");
 // synthesis translate_on
endmodule
