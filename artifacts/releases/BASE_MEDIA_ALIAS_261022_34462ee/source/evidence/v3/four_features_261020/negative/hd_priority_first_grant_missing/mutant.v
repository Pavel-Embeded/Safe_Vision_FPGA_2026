`include "fault_code_defs.vh"
// SYS-domain supervisor. All inputs below are already atomic snapshots or
// synchronized event pulses. Idle media/memory engines do not arm watchdogs.
// The fixed raster heartbeat remains required while a static image is shown.
module v3_supervisor #(
 parameter integer CLK_HZ=100000000,BOOT_CYCLES=2000000000,BOOT_MS_OVERRIDE=0,
 parameter integer FRAME_CYCLES=10000000,MEM_CYCLES=20000000,
 parameter integer PROGRESS_CYCLES=50000000,RECOVER_CYCLES=2000000000,WINDOW_PIPELINE=0
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
 // Optional board load budget expressed in1ms ticks, avoiding32-bit
 // overflow from a60-second cycle constant. Legacy exact-cycle mode stays.
 localparam integer BOOT_LIMIT=BOOT_MS_OVERRIDE>0?BOOT_MS_OVERRIDE:(BOOT_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer FRAME_LIMIT=(FRAME_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer MEM_LIMIT=(MEM_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer PROGRESS_LIMIT=(PROGRESS_CYCLES+TICK_DIV-1)/TICK_DIV;
 localparam integer WINDOW_LIMIT=CLK_HZ/TICK_DIV;
 function integer width_for;input integer limit;begin width_for=(limit>1)?$clog2(limit+1):1;end endfunction
 reg[width_for(BOOT_LIMIT)-1:0] boot_timer;
 reg[width_for(FRAME_LIMIT)-1:0] frame_timer;
 reg[width_for(MEM_LIMIT)-1:0] mem_timer;
 // Published count is exact on this edge, including a late heartbeat clear.
 // The late clear only drives one FF; increment logic uses the prior published count.
 reg[width_for(PROGRESS_LIMIT)-1:0] progress_raw;reg progress_clear;
 wire[width_for(PROGRESS_LIMIT)-1:0] progress_timer=progress_clear?0:progress_raw;
 reg[width_for(WINDOW_LIMIT)-1:0] window_timer;
 reg[width_for(TICK_DIV-1)-1:0] ms_timer;
 // For unsigned32-bit a,b: (a>=b && a-b>=8) iff
 // {0,a}>={0,b}+33'd8. Keep the carry; b near0xffffffff must
 // never wrap the threshold into a false alarm. Snapshot timing is unchanged.
 reg[32:0] video_limit,audio_limit;
 // Force the documented carry chain on these measured constant-add paths;
 // the low three constant bits can otherwise shorten below min_ripple_len.
 (* use_ripple=1 *) wire[32:0] next_video_limit={1'b0,video_underflows}+33'd8;
 (* use_ripple=1 *) wire[32:0] next_audio_limit={1'b0,audio_underflows}+33'd8;
 reg[31:0] last_hd,ms_now;
 // Predict exactly the next counter state; no event receives an extra cycle.
 wire watch_tick;
 generate if(TICK_DIV==1)begin:every_cycle_tick
  assign watch_tick=1'b1;
 end else begin:divided_tick
  reg tick_q;
  assign watch_tick=tick_q;
  always @(posedge clk or negedge rst_n)
   if(!rst_n)tick_q<=0;
   else tick_q<=ms_timer==TICK_DIV-2;
 end endgenerate
 reg window_last;wire window_done;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)window_last<=(WINDOW_LIMIT==1);
  else if(window_done || media_reset)window_last<=(WINDOW_LIMIT==1);
  else if(watch_tick)window_last<=window_timer==WINDOW_LIMIT-2;
 end
 // Four byte comparisons run in parallel. Preserve these small group nodes
 // so area mapping cannot turn a33-bit comparison into a serial LUT chain.
 (* keep="true" *) wire[3:0] video_gt,video_eq,audio_gt,audio_eq;
 genvar group;
 generate for(group=0;group<4;group=group+1)begin:compare_byte
  assign video_gt[group]=video_underflows[8*group+:8]>video_limit[8*group+:8];
  assign video_eq[group]=video_underflows[8*group+:8]==video_limit[8*group+:8];
  assign audio_gt[group]=audio_underflows[8*group+:8]>audio_limit[8*group+:8];
  assign audio_eq[group]=audio_underflows[8*group+:8]==audio_limit[8*group+:8];
 end endgenerate
 function ge_groups;
  input[3:0] g,e;
  begin ge_groups=g[3] | (e[3]&g[2]) | (e[3]&e[2]&g[1]) | (e[3]&e[2]&e[1]&(g[0]|e[0]));end
 endfunction
 wire video_threshold=!video_limit[32] && ge_groups(video_gt,video_eq);
 wire audio_threshold=!audio_limit[32] && ge_groups(audio_gt,audio_eq);
 // Production HD may place a boundary after the two window comparisons.
 // Only these sampled window events gain one SYS edge. Preserve their raw
 // observation timestamp; manual SAFE and all other event inputs bypass it.
 // Register byte comparisons on the raw observation edge; reduction and
 // priority share the following edge. Event latency and original timestamp
 // are identical to the validated one-edge window pipeline contract.
 reg[3:0] window_video_gt_q,window_video_eq_q,window_audio_gt_q,window_audio_eq_q;
 reg window_video_overflow_q,window_audio_overflow_q,window_valid_q;
 reg[31:0] window_ms_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin window_video_gt_q<=0;window_video_eq_q<=0;window_audio_gt_q<=0;window_audio_eq_q<=0;
   window_video_overflow_q<=0;window_audio_overflow_q<=0;window_valid_q<=0;window_ms_q<=0;end
  else begin window_video_gt_q<=video_gt;window_video_eq_q<=video_eq;window_audio_gt_q<=audio_gt;window_audio_eq_q<=audio_eq;
   window_video_overflow_q<=video_limit[32];window_audio_overflow_q<=audio_limit[32];window_valid_q<=window_done;window_ms_q<=ms_now;end
 end
 wire video_window_event=WINDOW_PIPELINE?(window_valid_q&&!window_video_overflow_q&&ge_groups(window_video_gt_q,window_video_eq_q)):(window_done&&video_threshold);
 wire audio_window_event=WINDOW_PIPELINE?(window_valid_q&&!window_audio_overflow_q&&ge_groups(window_audio_gt_q,window_audio_eq_q)):(window_done&&audio_threshold);
 reg initialized,fault_i_old,fault_b_old,failed_old,hd_fault_old;
 reg[10:0] pending,selection,new_events;
 // Duplicate the SAME next state, not a delayed sample of pending. The
 // original bank drives timestamp/priority loads; the preserved alert bank
 // drives only the short fault-enable OR, removing measured5ns routing fanout.
 (* preserve="true" *) reg[10:0] pending_alert;
 reg[15:0] rejected_old;reg[3:0] fallback_old;
 // For unsigned16 A,B,carry(A+~B) iff A>B; equality sums to65535.
 // Force the native carry path instead of a long distributed LUT comparator.
 (* use_ripple=1 *) wire[16:0] rejected_order_sum={1'b0,rejected_files}+{1'b0,~rejected_old};
 wire rejected_rise=rejected_order_sum[16];
 reg[7:0] media_first;reg[31:0] stamps[0:10];
 wire recovered,recover_safe,rescan_unused,reset_unused;
 wire recover_failed=media_failed || integrity_fault || bus_fault;
 media_recovery_ctrl #(.RESET_CYCLES(64),.SETTLE_CYCLES(64),
 .TIMEOUT_CYCLES(RECOVER_CYCLES),.MAX_ATTEMPTS(3)) recovery(
 .clk(clk),.rst_n(rst_n),.request(recover_request && !manual_safe),
 .done(cache_ready && !recover_failed),.failed(recover_failed),.fatal(fatal_latched),
 .busy(recovery_busy),.media_reset(media_reset),.rescan_start(rescan_unused),
 .recovered(recovered),.safe_latched(recover_safe),.attempts(recovery_attempts),.state(recovery_state));
 assign window_done=watch_tick && window_last;
 // q holds priority(next pending) on the SAME edge as pending updates.
 // Thus every visible event, timestamp and fault edge remains identical.
 wire[10:0] pending_next=(pending & ~selection) | new_events;
 wire[10:0] priority_next;
 (* preserve="true" *) reg[10:0] priority_q;
 wire[10:0] priority_selection=priority_q;
 // Per-byte local loads retain identical one-hot selection, not delayed data.
 (* preserve="true" *) reg[43:0] priority_ts;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)priority_ts<=0;else priority_ts<={4{priority_next}};
 // Preserve balanced four-event prefix groups: exact same-edge arbitration.
 (* keep="true" *) wire[1:0] priority_busy4;
 assign priority_busy4[0]=|pending_next[3:0];
 assign priority_busy4[1]=|pending_next[7:4];
 assign priority_next[0]=1'b0;
 assign priority_next[1]=pending_next[1] && !((|pending_next[0:0]));
 assign priority_next[2]=pending_next[2] && !((|pending_next[1:0]));
 assign priority_next[3]=pending_next[3] && !((|pending_next[2:0]));
 assign priority_next[4]=pending_next[4] && !((|priority_busy4[0:0]));
 assign priority_next[5]=pending_next[5] && !((|priority_busy4[0:0]) | (|pending_next[4:4]));
 assign priority_next[6]=pending_next[6] && !((|priority_busy4[0:0]) | (|pending_next[5:4]));
 assign priority_next[7]=pending_next[7] && !((|priority_busy4[0:0]) | (|pending_next[6:4]));
 assign priority_next[8]=pending_next[8] && !((|priority_busy4[1:0]));
 assign priority_next[9]=pending_next[9] && !((|priority_busy4[1:0]) | (|pending_next[8:8]));
 assign priority_next[10]=pending_next[10] && !((|priority_busy4[1:0]) | (|pending_next[9:8]));
 always @(posedge clk or negedge rst_n)
  if(!rst_n)priority_q<=0;else priority_q<=priority_next;
 always @*begin
  new_events=0;
  if(media_failed && !failed_old && !recovery_busy)new_events[0]=1;
  if(integrity_fault && !fault_i_old && !media_reset)new_events[1]=1;
  if(bus_fault && !fault_b_old && !media_reset)new_events[2]=1;
  if(video_window_event)new_events[3]=1;
  if(audio_window_event)new_events[4]=1;
  if(watch_tick && frame_timer==FRAME_LIMIT-1 && !frame_heartbeat && !recovered)new_events[5]=1;
  if(watch_tick && memory_active && mem_timer==MEM_LIMIT-1 && !mem_heartbeat && !media_reset)new_events[6]=1;
  if(watch_tick && media_active && progress_timer==PROGRESS_LIMIT-1 && !progress_heartbeat && !media_reset)new_events[7]=1;
  if((hdmi_drops!=last_hd && !hd_fault_old) || (watch_tick && !initialized && !cache_ready && !recovery_busy && boot_timer==BOOT_LIMIT-1) || (fatal && !fatal_latched))new_events[8]=1;
  if(rejected_rise && !media_reset)new_events[9]=1;
  if((|(audio_fallback & ~fallback_old)) && !media_reset)new_events[10]=1;
  selection=priority_selection;
  err_code=
   ({8{priority_selection[0]}} & media_first) |
   ({8{priority_selection[1]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[2]}} & `ERR_SD_IO) |
   ({8{priority_selection[3]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[4]}} & `ERR_WAV) |
   ({8{priority_selection[5]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[6]}} & `ERR_SD_IO) |
   ({8{priority_selection[7]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[8]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[9]}} & `ERR_MEDIA_INVALID) |
   ({8{priority_selection[10]}} & `ERR_WAV);
  err_src=
   ({4{priority_selection[0]}} & 4'd2) |
   ({4{priority_selection[1]}} & 4'd3) |
   ({4{priority_selection[2]}} & 4'd3) |
   ({4{priority_selection[3]}} & 4'd1) |
   ({4{priority_selection[4]}} & 4'd4) |
   ({4{priority_selection[5]}} & 4'd5) |
   ({4{priority_selection[6]}} & 4'd5) |
   ({4{priority_selection[7]}} & 4'd5) |
   ({4{priority_selection[8]}} & 4'd6) |
   ({4{priority_selection[9]}} & 4'd2) |
   ({4{priority_selection[10]}} & 4'd4);
  err_ts[0+:8]=
   ({8{priority_ts[0]}} & stamps[0][0+:8]) |
   ({8{priority_ts[1]}} & stamps[1][0+:8]) |
   ({8{priority_ts[2]}} & stamps[2][0+:8]) |
   ({8{priority_ts[3]}} & stamps[3][0+:8]) |
   ({8{priority_ts[4]}} & stamps[4][0+:8]) |
   ({8{priority_ts[5]}} & stamps[5][0+:8]) |
   ({8{priority_ts[6]}} & stamps[6][0+:8]) |
   ({8{priority_ts[7]}} & stamps[7][0+:8]) |
   ({8{priority_ts[8]}} & stamps[8][0+:8]) |
   ({8{priority_ts[9]}} & stamps[9][0+:8]) |
   ({8{priority_ts[10]}} & stamps[10][0+:8]);
  err_ts[8+:8]=
   ({8{priority_ts[11]}} & stamps[0][8+:8]) |
   ({8{priority_ts[12]}} & stamps[1][8+:8]) |
   ({8{priority_ts[13]}} & stamps[2][8+:8]) |
   ({8{priority_ts[14]}} & stamps[3][8+:8]) |
   ({8{priority_ts[15]}} & stamps[4][8+:8]) |
   ({8{priority_ts[16]}} & stamps[5][8+:8]) |
   ({8{priority_ts[17]}} & stamps[6][8+:8]) |
   ({8{priority_ts[18]}} & stamps[7][8+:8]) |
   ({8{priority_ts[19]}} & stamps[8][8+:8]) |
   ({8{priority_ts[20]}} & stamps[9][8+:8]) |
   ({8{priority_ts[21]}} & stamps[10][8+:8]);
  err_ts[16+:8]=
   ({8{priority_ts[22]}} & stamps[0][16+:8]) |
   ({8{priority_ts[23]}} & stamps[1][16+:8]) |
   ({8{priority_ts[24]}} & stamps[2][16+:8]) |
   ({8{priority_ts[25]}} & stamps[3][16+:8]) |
   ({8{priority_ts[26]}} & stamps[4][16+:8]) |
   ({8{priority_ts[27]}} & stamps[5][16+:8]) |
   ({8{priority_ts[28]}} & stamps[6][16+:8]) |
   ({8{priority_ts[29]}} & stamps[7][16+:8]) |
   ({8{priority_ts[30]}} & stamps[8][16+:8]) |
   ({8{priority_ts[31]}} & stamps[9][16+:8]) |
   ({8{priority_ts[32]}} & stamps[10][16+:8]);
  err_ts[24+:8]=
   ({8{priority_ts[33]}} & stamps[0][24+:8]) |
   ({8{priority_ts[34]}} & stamps[1][24+:8]) |
   ({8{priority_ts[35]}} & stamps[2][24+:8]) |
   ({8{priority_ts[36]}} & stamps[3][24+:8]) |
   ({8{priority_ts[37]}} & stamps[4][24+:8]) |
   ({8{priority_ts[38]}} & stamps[5][24+:8]) |
   ({8{priority_ts[39]}} & stamps[6][24+:8]) |
   ({8{priority_ts[40]}} & stamps[7][24+:8]) |
   ({8{priority_ts[41]}} & stamps[8][24+:8]) |
   ({8{priority_ts[42]}} & stamps[9][24+:8]) |
   ({8{priority_ts[43]}} & stamps[10][24+:8]);
  err_level[2]=priority_selection[8] && fatal_latched;
  err_level[1]=!((priority_selection[8] && fatal_latched) || priority_selection[9] || priority_selection[10]);
  err_level[0]=!((priority_selection[0] && cache_ready) || (priority_selection[8] && fatal_latched) || priority_selection[10]);
 end
 // Preserve a direct two-level OR tree instead of sharing the priority
 // encoder's deeper, high-fanout intermediate terms with fault-code enables.
 (* keep="true" *) wire[2:0] pending_groups;
 assign pending_groups[0]=|pending_alert[3:0];
 assign pending_groups[1]=|pending_alert[7:4];
 assign pending_groups[2]=|pending_alert[10:8];
 assign err_push=|pending_groups;
 // Keep the late recovery/FATAL inputs on the final OR stage.
 // Same busy predicate for ALL8 state encodings, including invalid6/7.
 // Keep its three state bits plus two latches in one5-input recovery cone.
 localparam[2:0] RECOVERY_IDLE=3'd0,RECOVERY_LOCKED=3'd5;
 (* keep="true" *) wire safe_recovery=(recovery_state!=RECOVERY_IDLE && recovery_state!=RECOVERY_LOCKED) || recover_safe || fatal_latched;
 (* keep="true" *) wire safe_ordinary=manual_safe || !cache_ready || (fault_valid && fault_level>=3);
 assign safe_active=safe_recovery || safe_ordinary;
 fault_manager #(.CLK_HZ(CLK_HZ)) faults(.clk(clk),.rst_n(rst_n),
 .err_push(err_push),.err_code(err_code),.err_level(err_level),.wdt_timeout(1'b0),
 .wdt_reason(8'd0),.media_fatal(fatal),.recover_ack(recovered),
 .fault_code(fault_code),.fault_level(fault_level),.fault_valid(fault_valid),
 .fatal(fatal_latched),.fault_ts(fault_ts),.media_rst_req(reset_unused));
 // Timestamp storage is private until pending becomes1. An empty slot
 // is overwritten on every active edge, including the event capture edge.
 // Resetting pending and the public error registers is sufficient; retain
 // full32-bit timestamps and exact arbitration without a352-bit reset fanout.
 integer stamp_i;
 always @(posedge clk)if(rst_n)
  for(stamp_i=0;stamp_i<11;stamp_i=stamp_i+1)
   if(!pending[stamp_i])stamps[stamp_i]<=(WINDOW_PIPELINE&&(stamp_i==3||stamp_i==4))?window_ms_q:ms_now;
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin boot_timer<=0;frame_timer<=0;mem_timer<=0;progress_raw<=0;progress_clear<=1;
   window_timer<=0;video_limit<=33'd8;audio_limit<=33'd8;last_hd<=0;ms_timer<=0;ms_now<=0;
   initialized<=0;pending<=0;pending_alert<=0;media_first<=0;fault_i_old<=0;fault_b_old<=0;
   failed_old<=0;hd_fault_old<=0;rejected_old<=0;fallback_old<=0;
  end else begin
   pending<=pending_next;
   pending_alert<=pending_next;
   // An unoccupied slot has no observable timestamp. Track the current time
   // until its first event captures pending=1, then hold through arbitration.
   // Thus the timestamp on every valid event is exactly the original ms_now,
   // including simultaneous clear/retrigger; wide CE no longer decodes events.

   if(!pending[0])media_first<=media_code;
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
   progress_clear<=!media_active || progress_heartbeat || media_reset;
   if(watch_tick && progress_timer<PROGRESS_LIMIT)progress_raw<=progress_timer+1'b1;
   else progress_raw<=progress_timer;
   if(window_done || media_reset)begin
    window_timer<=0;video_limit<=next_video_limit;audio_limit<=next_audio_limit;last_hd<=hdmi_drops;
   end else if(watch_tick)window_timer<=window_timer+1'b1;
  end
 end
 // synthesis translate_off
 initial if(CLK_HZ<1000 || FRAME_CYCLES<2 || MEM_CYCLES<2 || PROGRESS_CYCLES<2)
  $fatal(1,"invalid supervisor clock or watchdog limits");
 // synthesis translate_on
 // synthesis translate_off
 initial if(BOOT_MS_OVERRIDE>0&&(CLK_HZ<1000||CLK_HZ%1000!=0))$fatal(1,"BOOT_MS_OVERRIDE requires exact1ms tick");
 // synthesis translate_on
endmodule
