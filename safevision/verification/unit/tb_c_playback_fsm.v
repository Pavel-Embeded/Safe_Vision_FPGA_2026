`timescale 1ns/1ps
module tb_c_playback_fsm;
 reg clk=0;always #5 clk=~clk;reg rst_n=0;reg[15:0] stim=0;
 reg mount=0,four=0,req=0,fail=0;
 wire[2:0] state,sc;wire mr,start,commit,mute,safe,auto;wire[1:0] slot;
 playback_fsm #(.WAIT_TIMEOUT(80),.RESET_CYCLES(3),.SETTLE_CYCLES(3)) dut(
 .clk(clk),.rst_n(rst_n),.boot_ready(stim[0]),.sd_mount_ok(mount),.scan_done(stim[2]),.four_img_ok(four),
 .preload_ok(stim[4]),.auto_en(stim[5]),.key_next(stim[6]),.uart_stop(stim[7]),.trans_en(stim[8]),
 .auto_tick(stim[9]),.trans_done(stim[10]),.trans_fault(stim[11]),.alarm_in(stim[12]),
 .media_fault_severe(stim[13]),.confirm_stable(stim[14]),.recover_done(stim[15]),
 .recover_req(req),.recover_failed(fail),.state(state),.state_code(sc),.media_rst_active(mr),
 .recover_start(start),.commit_next(commit),.slot_index(slot),.video_mute(mute),.safe_req(safe),.auto_mode(auto));
 integer errors=0,i;task ck;input c;input[511:0] msg;begin begin
 if(c)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end end  end endtask
 task tick;begin begin @(negedge clk);end  end endtask
 task reset;begin begin rst_n=0;stim=0;mount=0;four=0;req=0;fail=0;repeat(3)tick;rst_n=1;tick;end  end endtask
 task boot;begin begin reset;stim=1;tick;stim=0;mount=1;four=1;stim[2]=1;tick;stim=0;end  end endtask
 initial begin
 reset;ck(state==0 && mute,"BOOT mute");stim=1;tick;stim=0;ck(state==1,"BOOT to SCAN");
 stim[2]=1;tick;stim=0;ck(state==6 && safe,"incomplete scan cannot PRELOAD");
 stim[12]=1;stim[14]=1;tick;ck(state==6 && !mr,"active alarm rejects recovery");
 stim=0;req=1;tick;req=0;ck(state==7 && mr && safe,"recovery begins with isolated reset");
 repeat(3)tick;ck(state==7 && !mr && safe,"finite reset releases before recovery work");
 repeat(15)tick;ck(state==7 && safe,"unfinished work waits instead of failing after one cycle");
 stim[15]=1;tick;stim=0;ck(state==3 && !safe,"verified work returns MANUAL");
 boot;ck(state==2,"valid four-image scan PRELOAD");
 stim[2]=1;repeat(10)tick;ck(state==2 && !safe,"sticky scan_done cannot terminate preload");
 stim=16'h0010;tick;stim=0;ck(state==3,"preload success MANUAL");
 for(i=1;i<=4;i=i+1)begin stim=16'h0040;tick;ck(commit && slot==i%4,"manual slot wrap");stim=0;tick;ck(!commit,"commit one cycle");end
 stim=16'h0020;tick;ck(state==4 && auto,"auto enable");
 stim=16'h0320;tick;ck(state==5 && !commit,"auto uses enabled transition");
 stim=16'h0020;repeat(4)tick;ck(state==5,"transition waits until done");
 stim=16'h0420;tick;ck(state==4 && commit,"transition commits once");
 stim=16'h00a0;tick;ck(state==3 && !auto,"UART stop");
 stim=16'h0140;tick;ck(state==5,"manual transition");stim=16'h0800;tick;ck(state==6 && safe,"transition fault SAFE");
 stim=0;req=1;tick;req=0;repeat(8)tick;fail=1;tick;fail=0;ck(state==6 && safe,"explicit recovery failure SAFE");
 req=1;tick;req=0;repeat(90)tick;ck(state==6 && safe,"recovery timeout bounded");
 reset;stim=16'h1000;tick;ck(state==6 && safe && !mute,"alarm honored during BOOT without muting SAFE");
 reset;stim=1;tick;stim=16'h2000;tick;ck(state==6 && safe,"severe fault honored during SCAN");
 boot;stim=16'h1000;tick;ck(state==6 && safe,"alarm honored during PRELOAD");
 boot;stim=16'h0010;tick;stim=16'h0140;tick;stim=0;repeat(85)tick;
 ck(state==6 && safe,"missing transition completion times out to SAFE");
 $display("[TB] tb_c_playback_fsm done, errors=%0d",errors);$finish;
 end
 initial begin #500000;$display("[FAIL] timeout");$finish;end
endmodule
