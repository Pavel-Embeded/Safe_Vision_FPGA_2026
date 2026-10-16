// The active pair and alpha are immutable between frame_start events.
// Request is retained while busy. Target must be valid; safety aborts at vblank.
module fade_ctrl #(parameter integer FRAMES=32)(
 input wire clk,rst_n,frame_start,request,safety,
 input wire [1:0] target,input wire [3:0] valid_slots,
 output reg [1:0] current,next,output reg [7:0] alpha,generation,
 output reg busy,commit,output wire ready);
 reg pending;reg [1:0] pending_slot;reg [$clog2(FRAMES+1)-1:0] step;
 assign ready=!busy && !pending;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin current<=0;next<=0;alpha<=0;generation<=0;busy<=0;
   commit<=0;pending<=0;pending_slot<=0;step<=0;end
  else begin
   commit<=0;
   if(request && ready && valid_slots[target])begin pending<=1;pending_slot<=target;end
   if(frame_start)begin
    if(safety)begin busy<=0;pending<=0;alpha<=0;next<=current;end
    else if(busy)begin
     if(step==FRAMES-1)begin
      current<=next;busy<=0;alpha<=0;generation<=generation+1'b1;commit<=1;step<=0;
     end else begin step<=step+1'b1;alpha<=((step+1)*255)/FRAMES;end
    end else if(pending)begin
     pending<=0;
     if(valid_slots[pending_slot])begin
      if(!valid_slots[current] || pending_slot==current || FRAMES==1)begin
       current<=pending_slot;next<=pending_slot;generation<=generation+1'b1;commit<=1;
      end else begin next<=pending_slot;busy<=1;step<=0;alpha<=0;end
     end
    end
   end
  end
 end
endmodule
