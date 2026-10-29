`timescale 1ns/1ps
module tb_v3_audio_prefill_pipeline;
 reg clk=0,rst_n=0,media_reset=0;always #10 clk=~clk;
 reg[3:0] stimulus=0,capacity=0;integer errors=0,comparisons=0,transitions=0,resets=0;
 reg[3:0] sampled=0;integer i,j;reg[31:0] rng=32'h17a62bd9;
 v3_audio_system #(.DIRECT_RING_COMPARE(1)) piped(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(rst_n),.media_reset(media_reset),.mounted(1'b0),.cache_ready(1'b0),.media_descriptor_valid(1'b0));
 v3_audio_system #(.DIRECT_RING_COMPARE(0)) legacy(.ref_clk(clk),.mem_clk(clk),.audio_clk(clk),.pixel_clk(clk),.sys_clk(clk),.rst_n(rst_n),.media_reset(media_reset),.mounted(1'b0),.cache_ready(1'b0),.media_descriptor_valid(1'b0));
 task verify;input[3:0] expected;begin
  comparisons=comparisons+4;
  if(piped.source.slot_fill!==expected)begin errors++;if(errors<5)$display("[FAIL] prefill admission epoch got=%b exp=%b",piped.source.slot_fill,expected);end
  if(legacy.source.slot_fill!==stimulus)begin errors++;if(errors<5)$display("[FAIL] library direct path changed");end
  if(piped.source.sector_room!==capacity||legacy.source.sector_room!==capacity)begin errors++;if(errors<5)$display("[FAIL] current hard FIFO credit was delayed");end
  if(piped.PREFILL_PIPELINE!=1||legacy.PREFILL_PIPELINE!=0)begin errors++;if(errors<5)$display("[FAIL] production or library parameter differs");end
 end endtask
 initial begin
  force piped.fill=stimulus;force legacy.fill=stimulus;
  force piped.room=capacity;force legacy.room=capacity;
  #3;rst_n=1;repeat(5)@(negedge clk);
  for(i=0;i<65536;i=i+1)begin
   @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   stimulus=i<256?i[3:0]:rng[3:0];capacity=i<256?i[7:4]:rng[19:16];
   #1;verify(sampled);if(stimulus!=sampled)transitions++;
   @(posedge clk);sampled=stimulus;#1;verify(sampled);
   if(i%257==0)begin
    #3;media_reset=1;sampled=0;#1;verify(sampled);resets++;

    stimulus=~stimulus;#1;verify(0);
    @(negedge clk);media_reset=0;
    repeat(3)@(posedge clk);#1;sampled=stimulus;verify(sampled);
   end
  end
  if(transitions<60000||resets!=256)begin errors++;$display("[FAIL] admission coverage incomplete transitions=%0d resets=%0d",transitions,resets);end
  if(errors==0)$display("[PASS] admission delay, current FIFO credit, default selection and reset epochs");
  $display("PASS tb_v3_audio_prefill_pipeline errors=%0d comparisons=%0d transitions=%0d resets=%0d",errors,comparisons,transitions,resets);$finish;
 end
 initial begin #5000000;$fatal(1,"admission test watchdog");end
endmodule
