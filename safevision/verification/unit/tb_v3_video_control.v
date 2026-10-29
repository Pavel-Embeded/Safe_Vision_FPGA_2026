`timescale 1ns/1ps
module tb_v3_video_control;
 reg clk=0,rst=0,fs=0,mreset=0,safety=0,request=0,fade=1,ready=0;
 always #5 clk=~clk;reg[3:0] slots=15;reg[7:0] ready_gen=0;
 wire[1:0] current,target;wire[7:0] generation,target_gen,alpha;
 wire busy,initialized,direct,commit,next_done,fault;
 v3_presentation_ctrl #(.FADE_FRAMES(32),.TRANSITION_TIMEOUT_FRAMES(80)) dut(
  .clk(clk),.rst_n(rst),.frame_start(fs),.media_reset(mreset),.safety(safety),.request(request),
  .fade_enable(fade),.valid_slots(slots),.audio_ready(ready),.audio_generation(ready_gen),
  .current(current),.target(target),.generation(generation),.target_generation(target_gen),.alpha(alpha),
  .busy(busy),.initialized(initialized),.direct_target(direct),.commit_toggle(commit),
  .next_done_toggle(next_done),.presentation_fault(fault));
 integer errors=0,comparisons=0,n,k;reg[1:0] previous,expected_slot;reg[7:0] previous_gen;reg done_before;
 task frame;begin begin @(negedge clk);fs=1;@(negedge clk);fs=0;repeat(2)@(negedge clk);end  end endtask
 task next;begin begin @(negedge clk);request=1;@(negedge clk);request=0;end  end endtask
 task check(input  ok,input[255:0] message);begin begin ok = (ok === 1'b1); comparisons=comparisons+1;
  if(!ok)begin $display("[FAIL] %s current=%d target=%d gen=%d alpha=%d",message,current,target,generation,alpha);errors=errors+1;end end  end endtask
 initial begin
  #30;rst=1;frame();ready=1;ready_gen=target_gen;frame();
  check(initialized&&current==0&&generation==1&&!next_done,"initial presentation separate NEXT");
  for(n=0;n<100;n=n+1)begin
   previous=current;previous_gen=generation;done_before=next_done;expected_slot=current+2'd1;
   next();frame();ready_gen=target_gen;
   check(busy&&target==expected_slot&&alpha==0,"target accepted at frame boundary");
   repeat(5)begin @(negedge clk);check(current==previous&&generation==previous_gen,"no non-frame state commit");end
   for(k=1;k<32;k=k+1)begin frame();check(busy&&current==previous&&alpha==(k*255)/32,"32-frame exact alpha trajectory");end
   frame();check(!busy&&current==expected_slot&&generation==previous_gen+1&&next_done!=done_before,"atomic final commit and NEXT ack");
  end
  $display("[PASS] 100 exact 32-frame transitions and generation commits");
  previous=current;previous_gen=generation;next();frame();ready_gen=target_gen+1;
  repeat(40)frame();check(busy&&current==previous&&generation==previous_gen&&alpha==247,"wrong generation cannot commit");
  ready_gen=target_gen;frame();check(!busy&&generation==previous_gen+1,"matching audio releases final step");
  previous_gen=generation;next();frame();ready=0;repeat(81)frame();
  check(fault&&!busy&&generation==previous_gen,"finite presentation timeout SAFE");
  frame();check(fault&&!busy,"fault held until media reset");
  @(negedge clk);mreset=1;@(negedge clk);mreset=0;frame();
  check(!fault&&busy&&target_gen!=previous_gen+1,"reset clears fault without generation reuse");
  ready=1;ready_gen=target_gen;frame();check(initialized&&!busy,"recovered initial presentation");
  previous_gen=generation;done_before=next_done;next();frame();safety=1;frame();
  check(!busy&&generation==previous_gen&&next_done==done_before,"SAFE cancels without NEXT completion");
  safety=0;slots=4'b0101;fade=0;next();frame();ready_gen=target_gen;frame();
  check(!busy&&slots[current]&&direct,"disabled fade and legal slot successor");
  $display("[PASS] audio generation gate, cancellation, skip-invalid and bounded recovery");
  $display("[TB] tb_v3_video_control done comparisons=%0d errors=%0d",comparisons,errors);
  if(!errors)$display("PASS tb_v3_video_control");$finish;
 end
endmodule
