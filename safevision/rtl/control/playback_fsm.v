// Eight externally visible states. Recovery reset and work phases are distinct.
module playback_fsm #(parameter integer SLOTS=4,WAIT_TIMEOUT=500000000,
 RESET_CYCLES=32,SETTLE_CYCLES=32)(
 input wire clk,rst_n,boot_ready,sd_mount_ok,scan_done,four_img_ok,preload_ok,
 input wire auto_en,key_next,uart_stop,trans_en,auto_tick,trans_done,trans_fault,
 input wire alarm_in,media_fault_severe,confirm_stable,recover_done,
 input wire recover_req,recover_failed,
 output reg [2:0] state,output wire [2:0] state_code,
 output wire media_rst_active,output reg recover_start,commit_next,
 output reg [$clog2(SLOTS)-1:0] slot_index,
 output reg video_mute,safe_req,auto_mode
);
 localparam BOOT=0,SCAN=1,PRELOAD=2,MANUAL=3,AUTO=4,TRANSITION=5,SAFE=6,RECOVER=7;
 reg [31:0] timer;reg [1:0] recover_phase;
 wire to_safe=alarm_in || media_fault_severe;
 wire recover_request=confirm_stable || (recover_req===1'b1);
 wire failure=(recover_failed===1'b1);
 assign state_code=state;
 assign media_rst_active=(state==RECOVER && recover_phase==0);
 wire [$clog2(SLOTS)-1:0] next_slot=(slot_index==SLOTS-1)?0:slot_index+1'b1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=BOOT;timer<=0;recover_phase<=0;recover_start<=0;
   commit_next<=0;slot_index<=0;video_mute<=1;safe_req<=0;auto_mode<=0;end
  else begin
   commit_next<=0;recover_start<=0;
   if(to_safe && state!=SAFE && state!=RECOVER)begin
    state<=SAFE;safe_req<=1;video_mute<=0;timer<=0;
   end else case(state)
    BOOT:begin video_mute<=1;safe_req<=0;
     if(boot_ready)begin state<=SCAN;timer<=0;end
     else if(timer>=WAIT_TIMEOUT-1)begin state<=SAFE;safe_req<=1;end
     else timer<=timer+1'b1;
    end
    SCAN:begin video_mute<=0;
     if(scan_done)begin timer<=0;
       if(sd_mount_ok && four_img_ok)state<=PRELOAD;
       else begin state<=SAFE;safe_req<=1;end
     end else if(timer>=WAIT_TIMEOUT-1)begin state<=SAFE;safe_req<=1;end
     else timer<=timer+1'b1;
    end
    PRELOAD:if(preload_ok)begin state<=auto_en?AUTO:MANUAL;auto_mode<=auto_en;timer<=0;end
     else if(timer>=WAIT_TIMEOUT-1)begin state<=SAFE;safe_req<=1;end
     else timer<=timer+1'b1;
    MANUAL:begin safe_req<=0;auto_mode<=0;
     if(auto_en)begin state<=AUTO;auto_mode<=1;end
     else if(key_next)begin
      if(trans_en)begin state<=TRANSITION;timer<=0;end
      else begin commit_next<=1;slot_index<=next_slot;end
     end
    end
    AUTO:begin safe_req<=0;
     if(!auto_en || uart_stop)begin auto_mode<=0;state<=MANUAL;end
     else if(auto_tick)begin
      if(trans_en)begin state<=TRANSITION;timer<=0;end
      else begin commit_next<=1;slot_index<=next_slot;end
     end
    end
    TRANSITION:if(trans_fault || timer>=WAIT_TIMEOUT-1)begin state<=SAFE;safe_req<=1;end
     else if(trans_done)begin commit_next<=1;slot_index<=next_slot;state<=auto_mode?AUTO:MANUAL;timer<=0;end
     else timer<=timer+1'b1;
    SAFE:begin safe_req<=1;video_mute<=0;
     if(recover_request && !to_safe)begin state<=RECOVER;recover_phase<=0;timer<=0;end
    end
    RECOVER:begin
     safe_req<=1;
     if(failure || to_safe)begin state<=SAFE;timer<=0;end
     else case(recover_phase)
      0:if(timer==RESET_CYCLES-1)begin recover_phase<=1;timer<=0;end
        else timer<=timer+1'b1;
      1:if(timer==SETTLE_CYCLES-1)begin recover_phase<=2;timer<=0;recover_start<=1;end
        else timer<=timer+1'b1;
      2:if(recover_done)begin state<=auto_mode?AUTO:MANUAL;safe_req<=0;timer<=0;end
        else if(timer>=WAIT_TIMEOUT-1)begin state<=SAFE;timer<=0;end
        else timer<=timer+1'b1;
      default:begin state<=SAFE;timer<=0;end
     endcase
    end
    default:begin state<=SAFE;safe_req<=1;end
   endcase
  end
 end
 // synthesis translate_off
 initial if(SLOTS<2 || SLOTS>4 || WAIT_TIMEOUT<1 || RESET_CYCLES<2 || SETTLE_CYCLES<2)
  $fatal(1,"invalid playback parameters");
 // synthesis translate_on
endmodule
