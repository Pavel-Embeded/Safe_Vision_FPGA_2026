`timescale 1ns/1ps
`include "fault_code_defs.vh"
module tb_v3_hd_window_pipeline;
 reg clk=0,rst=0,manual=0;always #5 clk=~clk;
 reg mf=0,inf=0,bf=0;reg[7:0] code=0;reg[31:0] vu=0,au=0;
 reg[15:0] rejected=0;reg[3:0] fallback=0;
 wire push,safe;wire[7:0] ec;wire[3:0] es;wire[2:0] el;wire[31:0] et;
 v3_supervisor #(.WINDOW_PIPELINE(1),.CLK_HZ(1000)) dut(.clk(clk),.rst_n(rst),.manual_safe(manual),.recover_request(1'b0),.cache_ready(1'b1),.media_failed(mf),.media_code(code),
  .integrity_fault(inf),.bus_fault(bf),.fatal(1'b0),.frame_heartbeat(1'b1),.mem_heartbeat(1'b1),.progress_heartbeat(1'b1),.memory_active(1'b0),.media_active(1'b0),
  .video_underflows(vu),.audio_underflows(au),.hdmi_drops(32'd0),.rejected_files(rejected),.audio_fallback(fallback),
  .safe_active(safe),.err_push(push),.err_code(ec),.err_src(es),.err_level(el),.err_ts(et));
 reg[10:0] pending_model=0,grant=0,events=0;reg[31:0] stamp[0:10];
 reg[31:0] ms=0,previous_ms=0,rng=32'h190129aa;reg[32:0] vlimit=33'd8,alimit=33'd8;
 reg previous_mf=0,previous_inf=0,previous_bf=0,delayed_v=0,delayed_a=0;
 reg[15:0] previous_rejected=0;reg[3:0] previous_fallback=0;reg[7:0] first_code=0;
 reg raw_v,raw_a,window;reg[7:0] want_code;reg[3:0] want_src;reg[2:0] want_level;reg[31:0] want_ts;
 integer wt=0,k,i,selected,errors=0,comparisons=0,windows=0,raw_v_events=0,raw_a_events=0,v_grants=0,a_grants=0;
 task check(input  ok,input [4095:0] what);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<9)$display("[FAIL] %s k=%0d pending=%h events=%h got=%h/%h/%h/%h want=%h/%h/%h/%h",what,k,pending_model,events,ec,es,el,et,want_code,want_src,want_level,want_ts);end   end endtask
 task reset_model;begin
  pending_model=0;grant=0;ms=0;previous_ms=0;vlimit=8;alimit=8;wt=0;
  previous_mf=0;previous_inf=0;previous_bf=0;delayed_v=0;delayed_a=0;
  previous_rejected=0;previous_fallback=0;first_code=0;
  for(i=0;i<11;i=i+1)stamp[i]=0;
   end endtask
 task choose_grant;begin  grant=0;for(i=10;i>=0;i=i-1)if(pending_model[i])grant=11'd1<<i;  end endtask
 task outputs;begin
  choose_grant();selected=-1;for(i=0;i<11;i=i+1)if(grant[i])selected=i;
  check(push===(|pending_model),"public valid follows independent pending queue");
  check(dut.priority_q===grant,"current mathematical first-set grant");
  if(selected>=0)begin
   want_code=`ERR_MEDIA_INVALID;want_src=0;want_level=3;want_ts=stamp[selected];
   case(selected)
    0:begin want_code=first_code;want_src=2;want_level=2;end
    1:want_src=3;
    2:begin want_code=`ERR_SD_IO;want_src=3;end
    3:want_src=1;
    4:begin want_code=`ERR_WAV;want_src=4;end
    9:begin want_src=2;want_level=1;end
    10:begin want_code=`ERR_WAV;want_src=4;want_level=0;end
    default:begin errors = errors + 1;$display("[FAIL] unexpected watchdog event");end
   endcase
   check(ec===want_code&&es===want_src&&el===want_level&&et===want_ts,"original observation timestamp, code, source and severity");
   if(selected==3)v_grants = v_grants + 1;if(selected==4)a_grants = a_grants + 1;
  end
   end endtask
 initial begin
  reset_model();#12;@(negedge clk);rst=1;
  for(k=0;k<300000;k=k+1)begin
   if(k%20000==19999)begin #0.1;rst=0;reset_model();#0.1;check(!push,"async reset clears queue and pipeline");#0.1;rst=1;end
   if(k==0)begin manual=1;#0.1;check(safe,"manual emergency bypass is immediate");manual=0;#0.1;check(!safe,"manual release has no extra pipeline");end
   rng=rng*1664525+1013904223;
   mf=(k%64<32)&&rng[28];inf=(k%64<32)&&rng[22];bf=(k%64<32)&&rng[17];code=rng[31:24];
   rejected=(k%64<32) ? rng[15:0]:0;fallback=(k%64<32) ? rng[11:8]:0;
   vu=vu+rng[4:0];au=au+rng[9:5];window=(wt==999);
   if(window)begin
    case(windows%6)
     0:begin vu=vlimit[31:0]-1;au=alimit[31:0];end
     1:begin vu=vlimit[31:0];au=alimit[31:0]-1;end
     2:begin vu=vlimit[31:0];au=alimit[31:0];end
     3:begin vu=32'hfffffffe;au=32'hffffffff;end
     4:begin vu=0;au=0;end
     5:begin vu=vlimit[31:0]+9;au=alimit[31:0]+11;end
    endcase
   end
   raw_v=window&&({1'b0,vu}>=vlimit);raw_a=window&&({1'b0,au}>=alimit);
   events=0;events[0]=mf&&!previous_mf;events[1]=inf&&!previous_inf;events[2]=bf&&!previous_bf;
   events[3]=delayed_v;events[4]=delayed_a;events[9]=rejected>previous_rejected;events[10]=|(fallback&~previous_fallback);
   #0.1;check(dut.window_done===window,"independent1000-cycle window");check(dut.new_events===events,"only sampled underflows gain one edge");
   choose_grant();
   for(i=0;i<11;i=i+1)if(!pending_model[i])stamp[i]=(i==3||i==4) ? previous_ms:ms;
   if(!pending_model[0])first_code=code;
   pending_model=(pending_model&~grant)|events;
   if(window)begin vlimit={1'b0,vu}+33'd8;alimit={1'b0,au}+33'd8;wt=0;windows = windows + 1;end else wt = wt + 1;
   if(raw_v)raw_v_events = raw_v_events + 1;if(raw_a)raw_a_events = raw_a_events + 1;
   delayed_v=raw_v;delayed_a=raw_a;previous_ms=ms;ms = ms + 1;
   previous_mf=mf;previous_inf=inf;previous_bf=bf;previous_rejected=rejected;previous_fallback=fallback;
   @(posedge clk);#0.1;outputs();@(negedge clk);
  end
  check(windows>250&&raw_v_events>50&&raw_a_events>50&&v_grants>25&&a_grants>25,"real window events reach public output under mixed contention");
  if(errors==0)$display("[PASS] production pipeline independent event queue,original timestamps,threshold equality/overflow,manual bypass,mixed contention,resets windows=%0d video=%0d audio=%0d",windows,raw_v_events,raw_a_events);
  $display("[TB] tb_v3_hd_window_pipeline done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
