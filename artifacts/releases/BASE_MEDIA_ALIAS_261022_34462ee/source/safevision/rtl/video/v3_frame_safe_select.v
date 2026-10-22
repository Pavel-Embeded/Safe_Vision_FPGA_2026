// The source and output blanking windows are separated by the pixel pipeline.
// Each selector may change throughout VBLANK, but never during visible rows.
// Two FFs reuse existing delayed coordinates rather than another20-bit shift.
module v3_frame_safe_select(input wire clk,rst_n,raw_vblank,output_vblank,request,
 output reg raw_selected,output_selected);
 always@(posedge clk or negedge rst_n)begin
  if(!rst_n)begin raw_selected<=1;output_selected<=1;end
  else begin
   if(raw_vblank)raw_selected<=request;
   if(output_vblank)output_selected<=raw_selected;
  end
 end
endmodule
