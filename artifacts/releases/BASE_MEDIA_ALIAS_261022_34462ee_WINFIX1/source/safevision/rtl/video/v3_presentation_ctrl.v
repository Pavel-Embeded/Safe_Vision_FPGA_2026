// Pixel-domain presentation transaction. A target generation is allocated for
// every attempt, including cancelled attempts. A completed NEXT has its own
// toggle so a startup presentation cannot accidentally ACK a queued NEXT.
module v3_presentation_ctrl #(
 parameter integer FADE_FRAMES=32,TRANSITION_TIMEOUT_FRAMES=300
)(input wire clk,rst_n,frame_start,media_reset,safety,request,fade_enable,
 input wire[3:0] valid_slots,input wire audio_ready,input wire[7:0] audio_generation,
 output reg[1:0] current,target,output reg[7:0] generation,target_generation,alpha,
 output reg busy,initialized,direct_target,commit_toggle,next_done_toggle,presentation_fault,
 output wire target_is_next);
 reg pending,target_from_next;reg[7:0] allocated_generation;
 assign target_is_next=target_from_next;
 reg[$clog2(FADE_FRAMES+1)-1:0] step;
 reg[$clog2(TRANSITION_TIMEOUT_FRAMES+1)-1:0] wait_frames;
 function[1:0] successor;
  input[1:0] slot;input[3:0] legal;integer k;reg found;reg[1:0] n;
  begin successor=slot;found=0;for(k=1;k<=4;k=k+1)begin
   n=slot+k;if(!found&&legal[n])begin successor=n;found=1;end end end
 endfunction
 wire ready_for_target=audio_ready&&audio_generation==target_generation;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin current<=0;target<=0;generation<=0;target_generation<=0;alpha<=0;
   busy<=0;initialized<=0;direct_target<=0;commit_toggle<=0;next_done_toggle<=0;
   presentation_fault<=0;pending<=0;target_from_next<=0;allocated_generation<=0;step<=0;wait_frames<=0;
  end else begin
   if(request)pending<=1;
   if(media_reset)begin busy<=0;pending<=0;initialized<=0;alpha<=0;target<=current;
    presentation_fault<=0;wait_frames<=0;target_from_next<=0;end
   else if(presentation_fault)begin busy<=0;pending<=0;alpha<=0;end
   else if(frame_start)begin
    if(safety)begin busy<=0;pending<=0;alpha<=0;target<=current;target_from_next<=0;end
    else if(busy)begin
     if(!valid_slots[target])begin busy<=0;pending<=0;presentation_fault<=1;end
     else if((direct_target||step==FADE_FRAMES-1)&&ready_for_target)begin
      current<=target;generation<=target_generation;busy<=0;initialized<=1;
      alpha<=0;commit_toggle<=~commit_toggle;step<=0;wait_frames<=0;
      if(target_from_next)next_done_toggle<=~next_done_toggle;
     end else if(wait_frames>=TRANSITION_TIMEOUT_FRAMES-1)begin
      busy<=0;pending<=0;presentation_fault<=1;alpha<=0;
     end else begin
      wait_frames<=wait_frames+1'b1;
      if(!direct_target&&step<FADE_FRAMES-1)begin
       step<=step+1'b1;alpha<=((step+1)*255)/FADE_FRAMES;
      end
     end
    end else if((pending||!initialized)&&(|valid_slots))begin
     target<=initialized?successor(current,valid_slots):successor(2'd3,valid_slots);
     allocated_generation<=allocated_generation+1'b1;
     target_generation<=allocated_generation+1'b1;
     direct_target<=!initialized||!fade_enable||FADE_FRAMES==1;
     target_from_next<=initialized&&pending;
     if(initialized)pending<=0;
     busy<=1;step<=0;alpha<=0;wait_frames<=0;
    end
   end
  end
 end
endmodule
