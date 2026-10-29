`timescale 1ns/1ps
module tb_v3_controls;
 reg clk=0;always #5 clk=~clk;reg rst=0,n=1,a=1,e=1,cv=0,cq=0,busy=0,cached=1,commit=0,system_safe=0;
 reg[7:0] target=65;reg[95:0] name=0;reg signed[31:0] value=0;
 wire next,auto_on,safe,recover,reply,bi,fit,fade,menu,tick;wire[7:0] code,contrast,alpha;
 wire signed[8:0] brightness;wire signed[31:0] result;wire[6:0] volume;wire[1:0] period;wire[2:0] field;
 v3_user_controls #(.CLK_HZ(100),.DEBOUNCE(3),.SYSTEM_SAFE_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.next_async(n),.auto_async(a),.emergency_async(e),
 .command_valid(cv),.command_target(target),.command_name(name),.command_value(value),.command_query(cq),
 .cached(cached),.system_safe(system_safe),.transition_busy(busy),.frame_commit(commit),.next_request(next),.auto_enabled(auto_on),
 .safety(safe),.recover_request(recover),.reply_valid(reply),.reply_code(code),.reply_value(result),
 .brightness(brightness),.contrast(contrast),.osd_alpha(alpha),.bilinear(bi),.fit(fit),.fade_enabled(fade),
 .volume(volume),.period_select(period),.menu(menu),.field(field),.auto_tick(tick));
 integer errors=0,nexts=0,recoveries=0,ticks=0;
 always @(posedge clk)begin #1;if(next)nexts=nexts+1;if(recover)recoveries=recoveries+1;if(tick)ticks=ticks+1;end
 task ck;input cond;input[511:0] msg;begin begin
 if(cond)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end end  end endtask
 task waitn;input integer count;begin begin repeat(count)@(negedge clk);end  end endtask
 task command;input[7:0] t;input[95:0] nm;input signed[31:0] val;input q;
 begin begin target=t;name=nm;value=val;cq=q;cv=1;waitn(1);cv=0;end  end endtask
 initial begin
 waitn(4);rst=1;waitn(12);ck(brightness==0 && contrast==128 && volume==80,"default configuration");
 n=0;waitn(1);n=1;waitn(1);n=0;waitn(1);n=1;waitn(12);ck(nexts==0,"button bounce rejected");
 n=0;waitn(12);ck(nexts==0,"next waits for release");n=1;waitn(12);ck(nexts==1,"one debounced next action");
 n=0;a=0;waitn(40);n=1;waitn(12);a=1;waitn(12);
 ck(nexts==1 && !auto_on && !menu,"short chord and staggered release leak no actions");
 n=0;a=0;waitn(230);ck(menu,"two-second chord opens menu");waitn(50);ck(menu,"held chord toggles only once");
 n=1;a=1;waitn(12);ck(nexts==1 && !auto_on,"long chord release leaks no actions");
 n=0;waitn(12);n=1;waitn(12);ck(brightness==8,"menu increment changes brightness");
 a=0;waitn(12);a=1;waitn(12);ck(brightness==0,"menu decrement changes brightness");
 n=0;waitn(125);ck(field==1,"one-second next hold changes field");n=1;waitn(12);
 ck(contrast==128,"long field change has no short-press side effect");
 a=0;waitn(125);ck(!menu,"one-second auto hold exits menu");a=1;waitn(12);ck(!auto_on,"exit release leaves auto setting intact");
 command(65,"BRIGHT",-128,0);ck(reply && code==0 && brightness==-128,"signed configuration accepted");
 command(65,"BRIGHT",0,1);ck(reply && code==0 && result==-128,"query returns signed live value");
 command(65,"BRIGHT",128,0);ck(code==3 && brightness==-128,"range rejection has no side effect");
 command(65,"UNKNOWN",0,1);ck(code==3,"unsupported query rejected");
 command(66,"BRIGHT",0,1);ck(code==3,"wrong command target rejected");
 command(67,"VOL",100,0);command(67,"VOL",0,1);ck(result==100,"volume query");
 command(67,"PERIOD",2,0);ck(period==0 && code==0,"two-second playback interval");
 command(67,"PERIOD",3,0);ck(period==0 && code==3,"invalid playback interval rejected");
 busy=1;command(67,"NEXT",1,0);ck(code==4 && nexts==1,"busy transition rejects next");busy=0;
 command(67,"NEXT",2,0);ck(code==3 && nexts==1,"invalid action value rejected");
 command(67,"AUTO",1,0);waitn(202);ck(ticks==1,"auto interval emits one request");
 e=0;waitn(12);ck(safe,"emergency remains active outside menu");
 command(67,"NEXT",1,0);ck(code==4,"emergency blocks media action");
 waitn(220);ck(ticks==1,"emergency suspends auto countdown");
 e=1;waitn(12);command(67,"AUTO",0,0);cached=0;
 n=0;waitn(12);n=1;waitn(12);ck(recoveries==1,"next requests recovery when media not ready");
 cached=1;system_safe=1;busy=1;
 n=0;waitn(12);n=1;waitn(12);
 ck(recoveries==2 && nexts==1,"KEY2 requests recovery for a latched system fault even with all caches valid");
 system_safe=0;busy=0;n=0;waitn(12);n=1;waitn(12);
 ck(recoveries==2 && nexts==2,"healthy KEY2 remains next, with no accidental recovery");
 $display("PASS tb_v3_controls errors=%0d",errors);$finish;
 end
 initial begin #100000;$display("[FAIL] global timeout");$finish;end
endmodule
