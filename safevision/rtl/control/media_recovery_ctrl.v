


module media_recovery_ctrl #(
 parameter integer RESET_CYCLES=32,SETTLE_CYCLES=32,
 parameter integer TIMEOUT_CYCLES=500000000,MAX_ATTEMPTS=3,PROGRESSIVE_WAIT=0
)(
 input wire clk,rst_n,request,done,failed,fatal,
 output wire busy,media_reset,output reg rescan_start,recovered,
 output reg safe_latched,output reg[1:0]attempts,output reg[2:0]state,

 input wire progress
);
 localparam IDLE=0,RESET=1,SETTLE=2,START=3,WAIT=4,LOCKED=5;
 localparam integer SHORT_LIMIT=RESET_CYCLES>SETTLE_CYCLES?RESET_CYCLES:SETTLE_CYCLES;
 localparam integer SHORT_W=SHORT_LIMIT<2?1:$clog2(SHORT_LIMIT);
 localparam integer WAIT_W=32;
 reg[SHORT_W-1:0]short_timer;
 reg[WAIT_W-1:0]wait_timer;
 reg wait_expired_raw;
 wire wait_progress=PROGRESSIVE_WAIT && progress;
 wire wait_expired=wait_expired_raw && !wait_progress;
 wire next_wait_expired=TIMEOUT_CYCLES<=1?1'b1:(wait_timer>=TIMEOUT_CYCLES-2);


 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin wait_timer<=0;wait_expired_raw<=TIMEOUT_CYCLES<=1;end
  else if(state==START&&!fatal)begin wait_timer<=0;wait_expired_raw<=TIMEOUT_CYCLES<=1;end
  else if(state==WAIT&&wait_progress)begin wait_timer<=0;wait_expired_raw<=TIMEOUT_CYCLES<=1;end
  else if(state==WAIT&&!wait_expired)begin wait_timer<=wait_timer+1'b1;wait_expired_raw<=next_wait_expired;end
 end

 assign busy=(state!=IDLE&&state!=LOCKED);
 (* preserve="true",keep="true" *) reg media_reset_q;
 wire reset_next=!fatal&&(((state==IDLE||state==LOCKED)&&request&&attempts<MAX_ATTEMPTS)||
                          (state==RESET&&short_timer!=RESET_CYCLES-1));
 always @(posedge clk or negedge rst_n)
  if(!rst_n)media_reset_q<=0;else media_reset_q<=reset_next;
 assign media_reset=media_reset_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;short_timer<=0;
   rescan_start<=0;recovered<=0;safe_latched<=0;attempts<=0;
  end else begin
   rescan_start<=0;recovered<=0;
   if(fatal)begin state<=LOCKED;safe_latched<=1;end
   else case(state)
    IDLE,LOCKED:if(request&&attempts<MAX_ATTEMPTS)begin
     attempts<=attempts+1'b1;safe_latched<=1;short_timer<=0;state<=RESET;
    end
    RESET:if(short_timer==RESET_CYCLES-1)begin short_timer<=0;state<=SETTLE;end
          else short_timer<=short_timer+1'b1;
    SETTLE:if(short_timer==SETTLE_CYCLES-1)begin short_timer<=0;state<=START;end
           else short_timer<=short_timer+1'b1;
    START:begin rescan_start<=1;state<=WAIT;end
    WAIT:if(failed||wait_expired)state<=LOCKED;
         else if(done)begin state<=IDLE;safe_latched<=0;attempts<=0;recovered<=1;end

    default:begin state<=LOCKED;safe_latched<=1;end
   endcase
  end
 end
 // synthesis translate_off
 initial if(RESET_CYCLES<2||SETTLE_CYCLES<2||MAX_ATTEMPTS>3||TIMEOUT_CYCLES<1)
  begin $display("[FAIL] invalid media recovery parameters"); $finish; end 
 // synthesis translate_on
endmodule
