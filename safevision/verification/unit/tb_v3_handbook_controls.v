`timescale 1ns/1ps
module tb_v3_handbook_controls;
 reg clk=0,rst=0,power_rst=0,n=1,a=1,e=1,cv=0,query=0,cached=0,busy=0,commit=0;
 always #5 clk=~clk;
 reg[95:0] name=0;reg[7:0] target=65;reg signed[31:0] value=0;
 wire next_req,auto_en,safe,recover,reply,tick;wire[7:0] code;wire signed[31:0] result;
 wire signed[8:0] bright;wire[7:0] contrast,alpha;wire bilinear,fit,fade,menu,raw;
 wire[6:0] vol,pct;wire[1:0] period,scale;wire[2:0] field;
 integer errors=0,comparisons=0,i,ticks=0,nreq=0;
 v3_user_controls #(.CLK_HZ(32),.DEBOUNCE(2),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) dut(
 .clk(clk),.rst_n(rst),.config_rst_n(power_rst),.next_async(n),.auto_async(a),.emergency_async(e),
 .command_valid(cv),.command_target(target),.command_name(name),.command_value(value),.command_query(query),
 .cached(cached),.transition_busy(busy),.frame_commit(commit),.system_safe(1'b0),.catalog_id(7'd0),
 .next_request(next_req),.auto_enabled(auto_en),.safety(safe),.recover_request(recover),.reply_valid(reply),.reply_code(code),.reply_value(result),
 .brightness(bright),.brightness_pct(pct),.brightness_raw(raw),.contrast(contrast),.osd_alpha(alpha),.bilinear(bilinear),.fit(fit),.fade_enabled(fade),
 .volume(vol),.period_select(period),.menu(menu),.field(field),.auto_tick(tick),.scale_select(scale));
 always @(negedge clk)if(rst)begin if(tick)ticks = ticks + 1;if(next_req)nreq = nreq + 1;end
 task ck(input  ok,input [4095:0] msg);begin begin ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<10)$display("[FAIL] %s",msg);end end  end endtask
 task cmd(input[7:0] dest,input[95:0] key,input signed[31:0] v,input  ask,input integer status,wanted);
  begin begin ask = (ask === 1'b1); @(negedge clk);target=dest;name=key;value=v;query=ask;cv=1;
   @(posedge clk);#1;ck(!reply,"decoded command is captured before any reply");
   @(negedge clk);cv=0;
   @(posedge clk);#1;ck(reply&&code==status,"command reply at exactly one additional SYS edge");if(ask&&status==0)ck(result==wanted,"read back exact parameter");
   @(negedge clk);end
  end endtask
 task tap(input  inc);begin begin inc = (inc === 1'b1); @(negedge clk);if(inc)n=0;else a=0;repeat(12)@(negedge clk);
  n=1;a=1;repeat(12)@(negedge clk);end  end endtask
 reg[63:0] retained;
 initial begin
  repeat(4)@(negedge clk);power_rst=1;rst=1;repeat(4)@(negedge clk);
  ck(auto_en&&period==1&&pct==80&&bright==60&&!raw&&contrast==128&&vol==70&&scale==0&&!fit,"handbook power defaults and automatic five-second play");
  repeat(180)@(negedge clk);ck(ticks==0,"no auto request before four pictures ready");cached=1;
  repeat(159)@(negedge clk);ck(ticks==0,"five second lower boundary");repeat(4)@(negedge clk);ck(ticks==1,"automatic request at five seconds");
  cmd(67,"MENU",1,0,0,0);cmd(67,"FIELD",0,0,0,0);
  tap(1);ck(pct==85&&bright==70&&!raw,"brightness increases by five percent");
  for(i=0;i<30;i = i + 1)tap(1);ck(pct==100&&bright==100,"brightness upper clamp");
  for(i=0;i<30;i = i + 1)tap(0);ck(pct==0&&bright==-100,"brightness lower clamp without wrap");
  cmd(65,"BRTPC",80,0,0,0);cmd(65,"BRTPC",0,1,0,80);cmd(65,"BRTPC",101,0,3,0);cmd(65,"BRTPC",-1,0,3,0);ck(pct==80,"bad percentage cannot modify value");
  cmd(67,"FIELD",1,0,0,0);tap(1);ck(contrast==136,"contrast Q1.7 eight step");for(i=0;i<30;i = i + 1)tap(0);ck(contrast==64,"contrast minimum64");
  for(i=0;i<30;i = i + 1)tap(1);ck(contrast==255,"contrast maximum255");
  cmd(67,"FIELD",5,0,0,0);tap(1);ck(vol==80,"volume ten percent step");for(i=0;i<20;i = i + 1)tap(0);ck(vol==0,"volume lower clamp");for(i=0;i<20;i = i + 1)tap(1);ck(vol==100,"volume upper clamp");
  for(i=0;i<4;i = i + 1)begin cmd(65,"SCALESEL",i,0,0,0);cmd(65,"SCALESEL",0,1,0,i);ck(scale==i&&fit==(i==1),"all four geometries and compatibility flag");end
  cmd(65,"SCALESEL",4,0,3,0);ck(scale==3,"scale invalid value rejected");


  for(i=0;i<=100;i = i + 1)begin
   cmd(65,"BRTPC",i,0,0,0);
   ck(bright==2*i-100&&pct==i&&!raw,"all101 percentage values map to the exact signed RGB888 offset");
   cmd(65,"BRIGHT",0,1,0,2*i-100);
  end
  cmd(65,"BRIGHT",-128,0,0,0);ck(bright==-128&&pct==0&&raw,"legacy raw brightness remains exact");
  cmd(65,"BRIGHT",127,0,0,0);ck(bright==127&&pct==100&&raw,"legacy signed positive endpoint");
  cmd(65,"BRTPC",35,0,0,0);cmd(65,"CONTRAST",152,0,0,0);cmd(67,"VOL",20,0,0,0);cmd(67,"PERIOD",30,0,0,0);cmd(67,"AUTO",0,0,0,0);
  retained={bright,pct,raw,contrast,alpha,bilinear,fit,fade,vol,period,scale,auto_en};
  rst=0;repeat(15)@(negedge clk);rst=1;repeat(8)@(negedge clk);
  ck(retained==={bright,pct,raw,contrast,alpha,bilinear,fit,fade,vol,period,scale,auto_en},"KEY1 warm reset retains every setting");
  ck(!menu&&!next_req&&!recover,"warm reset clears transactions and menu");
  e=0;repeat(12)@(negedge clk);ck(safe,"emergency independent of retained configuration");e=1;repeat(12)@(negedge clk);
  n=0;a=0;repeat(85)@(negedge clk);n=1;a=1;repeat(12)@(negedge clk);ck(menu&&nreq==0,"long chord opens menu without a NEXT leak");
  power_rst=0;repeat(4)@(negedge clk);power_rst=1;repeat(4)@(negedge clk);
  ck(pct==80&&bright==60&&vol==70&&scale==0&&auto_en,"new FPGA configuration resets defaults");
  if(errors==0)$display("[PASS] handbook controls ranges, physical menu, auto defaults and warm/cold reset contract");
  $display("[TB] tb_v3_handbook_controls done comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
 initial begin #2000000;$display("[FAIL] controls watchdog errors=1");$finish;end
endmodule
