// One response for the latest accepted PIX NEXT. Startup commits and the old
// current image cannot complete it. A target must be allocated AFTER request;
// comparing its eight-bit ID with the baseline is safe even at255->0 wrap.
// Cancellation clears the arm. A newer request supersedes an unfinished one.
module v3_pixel_response_tracker(
 input wire clk,rst_n,request,cancel,source_output_valid,
 input wire busy,direct_target,target_is_next,initialized,
 input wire[7:0] target_generation,current_generation,fade_alpha,
 output wire response_event,output reg response_toggle);
 reg armed;reg[7:0] allocation_baseline;
 wire target_contributes=busy?(!direct_target&&fade_alpha!=0):
  (initialized&&current_generation==target_generation);
 assign response_event=armed&&!request&&!cancel&&source_output_valid&&target_is_next&&
  target_generation!=allocation_baseline&&target_contributes;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin armed<=0;allocation_baseline<=0;response_toggle<=0;end
  else if(cancel)begin armed<=0;allocation_baseline<=target_generation;end
  else if(request)begin armed<=1;allocation_baseline<=target_generation;end
  else if(response_event)begin armed<=0;response_toggle<=!response_toggle;end
 end
endmodule
