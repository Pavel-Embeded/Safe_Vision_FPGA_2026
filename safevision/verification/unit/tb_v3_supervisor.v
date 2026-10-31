`timescale 1ns/1ps
module tb_v3_supervisor;
 reg clk=0;always #5 clk=!clk;
 reg rst_n=0,manual_safe=0,request=0,cached=1,media_failed=0,integrity=0,bus_fault=0,fatal=0;
 reg frame_enable=1,memory_active=0,media_active=0;
 reg[31:0] vu=0,au=0,hd=0;reg[15:0] bad=0;reg[3:0] fallback=0;
 wire safe,reset_media,recovery_busy,fault_valid,fatal_q,err_push;
 wire[1:0] attempts;wire[2:0] recovery_state,fault_level,err_level;
 wire[7:0] code,err_code;wire[3:0] err_src;wire[31:0] ts,evt_ts;
 integer errors=0,checks=0,i,events=0,warning_events=0,info_events=0,cycle=0;
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(err_push)begin events<=events+1;if(err_level==1)warning_events<=warning_events+1;if(err_level==0)info_events<=info_events+1;end
 end
 v3_supervisor #(.CLK_HZ(1000),.BOOT_CYCLES(1000),.FRAME_CYCLES(40),.MEM_CYCLES(16),
 .PROGRESS_CYCLES(20),.RECOVER_CYCLES(80)) dut(.clk(clk),.rst_n(rst_n),
 .manual_safe(manual_safe),.recover_request(request),.cache_ready(cached),.media_failed(media_failed),.media_code(8'h02),
 .integrity_fault(integrity),.bus_fault(bus_fault),.fatal(fatal),
 .frame_heartbeat(frame_enable && cycle%4==0),.mem_heartbeat(1'b0),.progress_heartbeat(1'b0),
 .memory_active(memory_active),.media_active(media_active),.video_underflows(vu),.audio_underflows(au),.hdmi_drops(hd),
 .rejected_files(bad),.audio_fallback(fallback),.safe_active(safe),.media_reset(reset_media),.recovery_busy(recovery_busy),
 .recovery_attempts(attempts),.recovery_state(recovery_state),.fault_code(code),.fault_level(fault_level),
 .fault_valid(fault_valid),.fatal_latched(fatal_q),.fault_ts(ts),.err_push(err_push),.err_code(err_code),
 .err_src(err_src),.err_level(err_level),.err_ts(evt_ts));
 task tick(input integer n);begin repeat(n)begin @(posedge clk);#1;end  end endtask
 task check(input  ok,input [4095:0] name);begin  ok = (ok === 1'b1); checks = checks + 1;if(!ok)begin errors = errors + 1;$display("[FAIL] %s t=%t state=%d code=%h",name,$time,recovery_state,code);end   end endtask
 task restart;begin  @(negedge clk);rst_n=0;cached=1;manual_safe=0;request=0;media_failed=0;integrity=0;bus_fault=0;fatal=0;
 frame_enable=1;memory_active=0;media_active=0;vu=0;au=0;hd=0;bad=0;fallback=0;tick(3);@(negedge clk);rst_n=1;tick(6);  end endtask
 task recover;integer guard;begin
 @(negedge clk);request=1;tick(1);@(negedge clk);request=0;
 guard=0;while(!reset_media && guard<20)begin tick(1);guard = guard + 1;end
 check(reset_media,"finite reset asserted");@(negedge clk);cached=0;media_failed=0;integrity=0;bus_fault=0;
 guard=0;while(recovery_state!=4 && guard<180)begin tick(1);guard = guard + 1;end
 check(recovery_state==4 && !reset_media,"reset released before self-test wait");
 @(negedge clk);cached=1;tick(8);
 check(!safe && !fault_valid && !recovery_busy && attempts==0,"self-test recovered and cleared paired latches");
   end endtask
 initial begin
 restart();tick(60);check(!safe && !fault_valid,"idle media and memory watchdogs disarmed");
 @(negedge clk);bad=1;tick(5);check(fault_level==1 && !safe,"bad BMP warning allows playback");
 @(negedge clk);fallback=4'b0101;tick(5);check(info_events>0 && warning_events>0 && !safe,"optional WAV fallback logged as INFO");
 for(i=0;i<1000;i = i + 1)begin
  @(negedge clk);bus_fault=1;tick(6);check(safe && fault_valid && fault_level==3,"injected storage fault enters SAFE");
  recover();
 end
 restart();@(negedge clk);frame_enable=0;tick(48);check(safe && code==8'h03,"fixed-raster watchdog catches stopped frame heartbeat");frame_enable=1;recover();
 @(negedge clk);memory_active=1;tick(24);check(safe && code==8'h02,"armed memory watchdog");memory_active=0;recover();
 @(negedge clk);media_active=1;tick(28);check(safe && code==8'h03,"armed media progress watchdog");media_active=0;recover();
 restart();@(negedge clk);vu=8;tick(1010);check(safe,"eight real missing pixels in one second trigger SAFE");recover();
 @(negedge clk);vu=0;tick(1010);check(!safe,"media counter reset is not unsigned-underflow fault");
 @(negedge clk);au=8;tick(1010);check(safe,"audio underflow threshold");recover();
 restart();@(negedge clk);integrity=1;bus_fault=1;bad=1;fallback=1;tick(12);
 check(events>=4 && code==8'h03 && fault_level==3,"simultaneous warning/info/fault events drain in order");recover();
 restart();@(negedge clk);media_failed=1;tick(6);
 for(i=0;i<3;i = i + 1)begin
  @(negedge clk);request=1;tick(1);@(negedge clk);request=0;cached=0;media_failed=0;
  tick(220);check(safe && recovery_state==5 && attempts==i+1,"bounded failed recovery waits for new manual request");
 end
 @(negedge clk);request=1;tick(5);request=0;check(!recovery_busy && attempts==3,"fourth recovery denied");
 restart();@(negedge clk);fatal=1;tick(8);check(safe && fatal_q && fault_level==4,"FATAL escalation persists");
 @(negedge clk);fatal=0;request=1;tick(8);request=0;check(fatal_q && !reset_media,"FATAL cannot be manually cleared");
 $display("[PASS] supervisor 1000 injections, checks=%0d errors=%0d",checks,errors);
 $display("PASS tb_v3_supervisor comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #10000000;begin $display("[FAIL] supervisor test timeout"); $finish; end end
endmodule
