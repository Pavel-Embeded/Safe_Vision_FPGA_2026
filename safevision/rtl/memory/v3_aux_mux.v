// Own exactly one complete auxiliary burst, including all delayed read
// responses. Verification has priority; audio data is held by its producer
// until the physical acceptance edge, never consumed at an arbiter grant.
module v3_aux_mux(input wire clk,rst_n,
 input wire verify_req,input wire[31:0] verify_addr,input wire[15:0] verify_len,
 output wire verify_ack,verify_busy,verify_valid,output wire[31:0] verify_data,
 input wire audio_req,audio_wr,input wire[31:0] audio_addr,audio_wdata,input wire[15:0] audio_len,
 output wire audio_ack,audio_busy,audio_valid,output wire[31:0] audio_data,
 output wire sd_req,sd_wr,output wire[31:0] sd_addr,sd_wdata,output wire[15:0] sd_len,
 input wire sd_ack,sd_busy,sd_valid,input wire[31:0] sd_data);
 localparam IDLE=0,REQUEST=1,TRANSFER=2,RETIRE=3;
 reg[1:0] state;reg owner_audio,wr_q;reg[31:0] addr_q;reg[15:0] len_q;
 assign sd_req=state==REQUEST;
 assign sd_wr=wr_q;assign sd_addr=addr_q;assign sd_len=len_q;
 assign sd_wdata=audio_wdata;
 assign verify_ack=state==REQUEST && sd_ack && !owner_audio;
 assign audio_ack=state==REQUEST && sd_ack && owner_audio;
 assign verify_busy=state!=IDLE && !owner_audio;
 assign audio_busy=state!=IDLE && owner_audio;
 assign verify_valid=sd_valid && !owner_audio && state!=IDLE;
 assign audio_valid=sd_valid && owner_audio && state!=IDLE;
 assign verify_data=sd_data;assign audio_data=sd_data;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;owner_audio<=0;wr_q<=0;addr_q<=0;len_q<=0;end
  else case(state)
   IDLE:if(verify_req || audio_req)begin
    owner_audio<=!verify_req;wr_q<=verify_req?0:audio_wr;
    addr_q<=verify_req?verify_addr:audio_addr;len_q<=verify_req?verify_len:audio_len;state<=REQUEST;
   end
   REQUEST:if(sd_ack)state<=TRANSFER;
   TRANSFER:if(!sd_busy)state<=RETIRE;
   // The producer observes busy falling and withdraws/replaces its request.
   // One retire edge prevents regrant of that old level on the same edge.
   RETIRE:state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
