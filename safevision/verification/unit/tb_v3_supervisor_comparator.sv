`timescale 1ns/1ps
module tb_v3_supervisor_comparator;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg[31:0] sample=0;reg[32:0] limit=8;
 integer errors=0,comparisons=0,i,j,k;reg[31:0] rng=32'h4a7c35e1,base,v;reg expected_video,expected_audio;
 v3_supervisor #(.CLK_HZ(1000),.BOOT_CYCLES(32),.FRAME_CYCLES(16),.MEM_CYCLES(16),.PROGRESS_CYCLES(16),.RECOVER_CYCLES(2000)) dut(
 .clk(clk),.rst_n(rst_n),.manual_safe(1'b0),.recover_request(1'b0),.cache_ready(1'b1),.media_failed(1'b0),.media_code(8'd0),.integrity_fault(1'b0),.bus_fault(1'b0),.fatal(1'b0),
 .frame_heartbeat(1'b1),.mem_heartbeat(1'b1),.progress_heartbeat(1'b1),.memory_active(1'b0),.media_active(1'b0),.video_underflows(sample),.audio_underflows(~sample),.hdmi_drops(32'd0),.rejected_files(16'd0),.audio_fallback(4'd0));
 task probe(input[31:0] value,previous);
  reg[31:0] delta_video,delta_audio;
  begin sample=value;limit={1'b0,previous}+33'd8;
   delta_video=value-previous;delta_audio=(~value)-previous;
   expected_video=(value>=previous && delta_video>=8);
   expected_audio=((~value)>=previous && delta_audio>=8);
   #0.001;
   comparisons=comparisons+2;
   if(dut.video_threshold!==expected_video || dut.audio_threshold!==expected_audio)begin
    errors=errors+1;if(errors<10)$display("[FAIL] threshold sample=%08x previous=%08x limit=%09x",sample,previous,limit);
   end
  end
 endtask
 initial begin
  #1;rst_n=1;force dut.video_limit=limit;force dut.audio_limit=limit;
  // Every pair of byte values at each of the four positions, equal neighbors.
  for(k=0;k<4;k=k+1)for(i=0;i<256;i=i+1)for(j=0;j<256;j=j+1)begin
   base=(32'h9abcdef0 & ~(32'hff<<(8*k))) | (j<<(8*k));
   v=(base & ~(32'hff<<(8*k))) | (i<<(8*k));probe(v,base);
  end
  for(i=0;i<100000;i=i+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);base=rng;
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);probe(rng,base);
  end
  // All threshold carry-out boundary values, including exact delta7/8/9.
  for(i=0;i<32;i=i+1)begin base=32'hffffffff-i;probe(32'hffffffff,base);probe(0,base);probe(base+7,base);probe(base+8,base);probe(base+9,base);end
  release dut.video_limit;release dut.audio_limit;
  if(errors==0)$display("[PASS] native byte-pair exhaustive plus independent32-bit predicate oracle");
  $display("[TB] tb_v3_supervisor_comparator done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #1000000;$display("[FAIL] comparator oracle watchdog errors=1");$finish;end
endmodule
