`timescale 1ns/1ps
module v3_priority_serial_oracle #(parameter integer RAMP=240,COUNT=262144,
 parameter[255:0] REPORT_NAME="tb_v3_priority_serial");
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,valid=0,alarm=0;reg[23:0] wl=0,wr=0,tl=0,tr=0;
 wire[23:0] ol,orr;wire ov;wire[8:0] gain;
 v3_audio_priority_serial #(.RAMP_N(RAMP)) d(.audio_clk(clk),.rst_n(rst_n),
  .sample_valid(valid),.alarm_req(alarm),.wav_l(wl),.wav_r(wr),.tone_l(tl),.tone_r(tr),
  .audio_l(ol),.audio_r(orr),.audio_valid(ov),.gain(gain));
 integer errors=0,comparisons=0,reference_gain=0,reference_error=0;
 integer i,c,phase,total,step;reg[23:0] gl,gr;reg[256:0] gains_seen=0;
 reg[31:0] rng=32'h94e17a26;
 function[31:0] random32;input[31:0] value;reg[31:0] x;begin
  x=value^(value<<13);x=x^(x>>17);random32=x^(x<<5);end endfunction
 function[23:0] blend;input[23:0] wav,tone;input integer g;
  reg signed[63:0] a,b,z;begin
   a=$signed(wav);b=$signed(tone);z=(a*(256-g)+b*g)>>>8;blend=z[23:0];
  end endfunction
 task ck;input condition;input[511:0] message_text;begin
  comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;if(errors<=5)$display("[FAIL PRIORITY_SERIAL] %0s i=%0d gain=%0d state=%0d",message_text,i,gain,d.state);end
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<COUNT;i=i+1)begin
   @(negedge clk);alarm=(i%1024)<512;
   wl={i[15:0],8'd0};rng=random32(rng);wr=rng[23:0];
   case((i/65536)%4)
    0:tl=24'h800000;1:tl=24'h7fffff;2:tl=24'd98135;default:tl=-24'sd1997591;
   endcase
   rng=random32(rng);tr=rng[23:0];
   total=reference_error+256;step=total/RAMP;reference_error=total%RAMP;
   if(alarm)reference_gain=(reference_gain+step>256)?256:reference_gain+step;
   else reference_gain=(reference_gain>step)?reference_gain-step:0;
   gl=blend(wl,tl,reference_gain);gr=blend(wr,tr,reference_gain);
   valid=1;@(negedge clk);valid=0;
   ck(gain==reference_gain,"ramp gain at accepted sample");gains_seen[gain]=1;
   for(c=0;c<5;c=c+1)begin
    // Input/SAFE policy changes while busy may not relabel a captured sample.
    rng=random32(rng);wl=rng[23:0];rng=random32(rng);wr=rng[23:0];
    rng=random32(rng);tl=rng[23:0];rng=random32(rng);tr=rng[23:0];alarm=~alarm;
    @(negedge clk);
    if(c<4)ck(!ov,"no early partial stereo publication");
   end
   ck(ov&&ol===gl&&orr===gr,"two full PCM24 channels equal independent 64bit weighted sum");
   @(negedge clk);ck(!ov,"single valid pulse");
  end
  if(RAMP==256)ck(&gains_seen,"all 257 gain coefficients exercised");
  for(phase=1;phase<=5;phase=phase+1)begin
   @(negedge clk);valid=1;alarm=1;wl=24'h800000;wr=24'h7fffff;tl=24'h7fffff;tr=24'h800000;
   @(negedge clk);valid=0;
   repeat(phase-1)@(negedge clk);
   rst_n=0;#0.001;ck(!ov&&gain==0&&ol==0&&orr==0,"async reset at every calculation phase");
   repeat(3)@(negedge clk);rst_n=1;
   repeat(8)begin @(negedge clk);ck(!ov,"no pre-reset sample leaks after release");end
  end
  if(errors==0)$display("[PASS] signed full PCM24 oracle, all PCM16 words, ROM low bits, random opposite channel, captured controls and reset each phase");
  $display("PASS %0s errors=%0d comparisons=%0d",REPORT_NAME,errors,comparisons);$finish;
 end
 initial begin #100000000;$display("[FAIL] priority watchdog errors=1");$finish;end
endmodule
module tb_v3_priority_serial;
 v3_priority_serial_oracle #(.RAMP(240),.COUNT(262144),.REPORT_NAME("tb_v3_priority_serial")) scenario();
endmodule
module tb_v3_priority_serial_gain;
 v3_priority_serial_oracle #(.RAMP(256),.COUNT(4096),.REPORT_NAME("tb_v3_priority_serial_gain")) scenario();
endmodule
module tb_v3_priority_serial_one;
 v3_priority_serial_oracle #(.RAMP(1),.COUNT(4096),.REPORT_NAME("tb_v3_priority_serial_one")) scenario();
endmodule
