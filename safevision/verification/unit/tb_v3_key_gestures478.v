`timescale 1ns/1ps
module tb_v3_key_gestures478;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,cfg_rst=0,bn=1,ba=1,be=1,command=0;reg[6:0] id=0;reg[7:0] target=67;reg[31:0] value=0;
 wire next,aut,safe,recover,reply;wire[7:0] code;wire[31:0] answer;wire signed[8:0] bri;wire[7:0] con,alpha;
 wire bi,fit,fade,menu,atick,raw;wire[6:0] vol,pct;wire[1:0] period,scale;wire[2:0] field;
 integer i,cycles=0,errors=0,comparisons=0,start_cycle,first_tick,second_tick,guard;
 always@(posedge clk)cycles=cycles+1;
 v3_user_controls #(.UI_TIMEBASE(1),.CLK_HZ(100000),.DEBOUNCE(2000),.BOARD_CATALOG(1),.SYSTEM_SAFE_ENABLE(1),.HANDBOOK_PROFILE(1),.DEFAULT_AUTO(1),.RETAIN_CONFIG(1)) d(
 .clk(clk),.rst_n(rst),.config_rst_n(cfg_rst),.next_async(bn),.auto_async(ba),.emergency_async(be),
 .command_valid(command),.command_target(target),.command_name(96'd0),.command_value(value),.command_query(1'b0),.catalog_id(id),
 .cached(1'b1),.transition_busy(1'b0),.frame_commit(1'b0),.system_safe(1'b0),
 .next_request(next),.auto_enabled(aut),.safety(safe),.recover_request(recover),.reply_valid(reply),.reply_code(code),.reply_value(answer),
 .brightness(bri),.contrast(con),.osd_alpha(alpha),.bilinear(bi),.fit(fit),.fade_enabled(fade),.volume(vol),.period_select(period),.menu(menu),.field(field),.auto_tick(atick),.brightness_pct(pct),.brightness_raw(raw),.scale_select(scale));
 task ck;input condition;input[511:0] label;begin begin comparisons = comparisons + 1;if(!condition)begin errors = errors + 1;$display("[FAIL] %s cycle%0d",label,cycles);end else $display("[PASS] %s",label);end  end endtask
 task ticks;input integer count;begin begin repeat(count)@(negedge clk);end  end endtask
 task set_period;input integer seconds;begin begin
  @(negedge clk);id=18;target=67;value=seconds;command=1;@(negedge clk);command=0;
  guard=0;while(!reply&&guard<20)begin @(negedge clk);guard = guard + 1;end
  ck(reply&&code==0,"UART period set acknowledged");ticks(8);
 end  end endtask
 task period_test;input integer seconds;begin begin
  start_cycle=cycles;set_period(seconds);guard=0;
  while(!atick&&guard<seconds*100000+500)begin @(negedge clk);guard = guard + 1;end
  first_tick=cycles;ck(atick&&first_tick-start_cycle>=seconds*100000&&first_tick-start_cycle<=seconds*100000+200,"initial autoplay period never early; <=2ms startup quantization");
  @(negedge clk);guard=0;while(!atick&&guard<seconds*100000+300)begin @(negedge clk);guard = guard + 1;end
  second_tick=cycles;ck(atick&&second_tick-first_tick==seconds*100000,"subsequent autoplay periods exact in SYS cycles");ticks(3);
 end  end endtask
 task release_both;begin begin bn=1;ba=1;guard=0;while(d.levels[1:0]!=0&&guard<2300)begin @(negedge clk);guard = guard + 1;end ticks(5);end  end endtask
 task short_next;begin begin bn=0;ticks(2500);bn=1;ticks(2300);end  end endtask
 task short_auto;begin begin ba=0;ticks(2500);ba=1;ticks(2300);end  end endtask
 initial begin
  ticks(5);cfg_rst=1;rst=1;ticks(8);
  ck(d.UI_DIV==100&&d.UI_DEBOUNCE==21&&d.HOLD_LIMIT==1001&&d.CHORD_LIMIT==2001,"shared tick and conservative minimum debounce/hold limits");
  ck(pct==80&&bri==60&&con==128&&vol==70&&aut&&!menu,"cold boot full defaults");


  bn=0;ticks(1000);bn=1;ticks(2300);ck(d.levels[0]==0&&!menu,"short bounce rejected");
  bn=0;ba=0;start_cycle=cycles;guard=0;
  while(!menu&&guard<203000)begin @(negedge clk);guard = guard + 1;end
  ck(menu&&cycles-start_cycle>=202000&&cycles-start_cycle<=202300,"chord requires >=20ms debounce and >=2s hold, no early menu");
  ticks(10000);ck(menu,"held chord toggles menu only once");release_both();
  short_next();ck(pct==85&&bri==70,"physical KEY2 raises visible brightness by5percent");
  short_auto();ck(pct==80&&bri==60,"physical KEY3 lowers visible brightness by5percent");
  bn=0;start_cycle=cycles;guard=0;while(field==0&&guard<103000)begin @(negedge clk);guard = guard + 1;end
  ck(field==1&&cycles-start_cycle>=102000&&cycles-start_cycle<=102300,"KEY2 long press selects next field only after >=1s");
  ticks(10000);ck(field==1,"held long press does not repeat field");release_both();
  short_next();ck(con==136,"physical contrast increase8");short_auto();ck(con==128,"physical contrast decrease8");
  ba=0;start_cycle=cycles;guard=0;while(menu&&guard<103000)begin @(negedge clk);guard = guard + 1;end
  ck(!menu&&cycles-start_cycle>=102000,"KEY3 long press exits after >=1s");release_both();ck(aut,"long exit does not leak an autoplay toggle");


  for(i=0;i<8;i=i+1)begin
   if(i[0])begin bn=0;ticks(1700);ba=0;end
   else begin ba=0;ticks(3700);bn=0;end
   guard=0;while(!menu&&guard<203000)begin @(negedge clk);guard = guard + 1;end
   ck(menu,"staggered physical chord enters menu");ticks(30000);
   ck(menu,"holding chord does not toggle twice");
   if(i[1])begin bn=1;ticks(700);bn=0;ticks(500);bn=1;ticks(3500);ba=1;end
   else begin ba=1;ticks(500);ba=0;ticks(700);ba=1;ticks(4500);bn=1;end
   ticks(4000);ck(menu&&aut,"staggered/bouncing release keeps menu without autoplay leak");

   @(negedge clk);id=38;target=67;value=0;command=1;@(negedge clk);command=0;ticks(10);
   short_next();ck(pct==85&&bri==70,"physical increase after staggered chord");
   short_auto();ck(pct==80&&bri==60,"physical decrease after staggered chord");
   bn=0;ticks(105000);bn=1;ticks(4000);ck(field==1,"physical long next selects contrast once");
   short_next();ck(con==136,"contrast increase after staggered chord");
   short_auto();ck(con==128,"contrast decrease after staggered chord");
   ba=0;ticks(105000);ba=1;ticks(4000);ck(!menu&&aut,"physical long exit remains outside menu and retains autoplay");
  end
  be=0;ticks(2300);ck(safe,"emergency remains independent of menu/timers");be=1;ticks(2300);ck(!safe,"emergency release debounced");
  @(negedge clk);id=37;target=65;value=65;command=1;@(negedge clk);command=0;ticks(10);
  ck(pct==65&&bri==30,"UART retains full brightness parameter semantics");
  rst=0;ticks(5);rst=1;ticks(10);ck(pct==65&&bri==30&&con==128&&vol==70,"warm reset retains nondefault display/audio configuration");
  if(errors==0)$display("[PASS] real tick-enabled2/5/10/30s autoplay, bounce/chord/brightness/contrast/long exit/emergency/reset");
  $display("[TB] tb_v3_key_gestures478 done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #200000000;$display("[FAIL] UI watchdog");$display("[TB] tb_v3_key_gestures478 done errors=1 comparisons=0");$finish;end
endmodule
