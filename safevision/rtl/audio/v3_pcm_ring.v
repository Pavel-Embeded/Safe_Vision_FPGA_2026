// MEM-domain four independent circular partitions in AUDIO_RING (256 KiB total).
// Each stereo PCM pair is one 32-bit word. slot0..3 each owns 64 KiB (16384 pairs).
// req is retained through ack; address/wdata remain stable through busy completion.
// One-word transactions use the existing memory-arbiter SD client; refresh/backpressure
// never advance pointers until a completed write or an actual read-data-valid beat.
// Valid/ready ingress obeys backpressure. All media state resets together.
module v3_pcm_ring #(parameter integer PTR_W=14,PREFETCH=800,DIRECT_POINTER_COMPARE=0)(
 input wire clk,rst_n,input wire [127:0] in_data,input wire [3:0] in_valid,output reg [3:0] in_ready,
 input wire commit_valid,input wire [1:0] commit_slot,input wire [7:0] commit_generation,
 output wire commit_ready,input wire [3:0] fallback,
 output wire [3:0] prefetched,output wire [63:0] levels,
 output reg [39:0] out_data,output reg out_valid,input wire out_ready,
 input wire [9:0] output_level,
 output reg req,output reg wr,output reg [31:0] addr,wdata,output wire [15:0] len,
 input wire ack,busy,input wire [31:0] rdata,input wire rvalid,
 output reg [31:0] overflow_count);
 localparam integer CAP=1<<PTR_W;
 // The extra pointer bit distinguishes full from empty after an address wrap.
 // Occupancy is their modular difference; no independent occupancy state can
 // diverge from the actual accepted write/read events.
 reg [PTR_W:0] wp[0:3],rp[0:3];wire [PTR_W:0] count[0:3];
 wire[3:0] pointer_empty,pointer_full;
 reg [1:0] active,owner,rr;reg [7:0] generation;reg enabled;
 reg [1:0] state;reg reading,seen_data;reg [1:0] pick;reg any_write;
 integer i,j,k;
 assign len=1;assign commit_ready=(state==0)&&!out_valid&&!busy;
 genvar g;generate for(g=0;g<4;g=g+1)begin:status
  assign pointer_empty[g]=(wp[g]==rp[g]);
  assign pointer_full[g]=(wp[g]=={~rp[g][PTR_W],rp[g][PTR_W-1:0]});
  assign prefetched[g]=count[g]>=PREFETCH;
  assign levels[g*16+:16]={{(15-PTR_W){1'b0}},count[g]};
 end endgenerate
 wire take_read=((state==1)&&ack&&reading&&rvalid)||
                 ((state==2)&&reading&&rvalid&&!seen_data);
 wire finish_write=(state==2)&&!busy&&!reading;
 generate for(genvar slot_index=0;slot_index<4;slot_index=slot_index+1)begin:parallel_pointers
  (* use_ripple=1 *) wire[PTR_W:0] occupancy=wp[slot_index]-rp[slot_index];
  assign count[slot_index]=occupancy;
  always @(posedge clk or negedge rst_n)
   if(!rst_n)begin wp[slot_index]<=0;rp[slot_index]<=0;end
   else if(owner==slot_index)begin
    if(take_read)rp[slot_index]<=rp[slot_index]+1'b1;
    else if(finish_write)wp[slot_index]<=wp[slot_index]+1'b1;
   end
 end endgenerate
 always @*begin
  any_write=0;pick=0;in_ready=0;
  for(i=0;i<4;i=i+1)begin
   j=rr+i;if(j>=4)j=j-4;
   if(!any_write&&in_valid[j]&&(DIRECT_POINTER_COMPARE?!pointer_full[j]:count[j]<CAP))begin any_write=1;pick=j;end
  end
  if(state==1&&ack&&!reading)in_ready[owner]=1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   req<=0;wr<=0;addr<=0;wdata<=0;out_data<=0;out_valid<=0;state<=0;
   active<=0;owner<=0;rr<=0;generation<=0;enabled<=0;reading<=0;seen_data<=0;overflow_count<=0;

  end else begin
   if(out_valid&&out_ready)out_valid<=0;
   case(state)
    0:begin
     if(commit_valid&&commit_ready)begin active<=commit_slot;generation<=commit_generation;enabled<=1;end
     // Reserve our one output register before issuing the read. A ready/valid
     // consumer may legally wait for valid before ready (the serialized FIFO
     // accepts its final word last), so ready must not gate valid production.
     else if(!busy&&enabled&&!fallback[active]&&(DIRECT_POINTER_COMPARE?!pointer_empty[active]:count[active]!=0)&&!out_valid&&output_level<10'd240)begin
      owner<=active;reading<=1;seen_data<=0;req<=1;wr<=0;
      addr<=32'h00280000+({30'd0,active}<<16)+({{(30-PTR_W){1'b0}},rp[active][PTR_W-1:0]}<<2);state<=1;
     end else if(!busy&&any_write)begin
      owner<=pick;reading<=0;seen_data<=0;req<=1;wr<=1;
      addr<=32'h00280000+({30'd0,pick}<<16)+({{(30-PTR_W){1'b0}},wp[pick][PTR_W-1:0]}<<2);
      wdata<=in_data[pick*32+:32];state<=1;
     end
    end
    1:if(ack)begin req<=0;state<=2;
      if(reading&&rvalid)begin out_data<={generation,rdata};out_valid<=1;seen_data<=1;
       end
    end
    2:begin
     if(reading&&rvalid&&!seen_data)begin
      out_data<={generation,rdata};out_valid<=1;seen_data<=1;

     end
     if(!busy&&(!reading||seen_data))begin
      if(!reading)rr<=owner+1'b1;
      state<=0;
     end
    end
    default:state<=0;
   endcase
  end
 end
 // synthesis translate_off
 initial if(PTR_W<4||PTR_W>14||PREFETCH>=CAP)$fatal(1,"v3_pcm_ring invalid size");
 always @(posedge clk)if(rst_n&&out_valid&&!out_ready&&state==2&&rvalid&&!seen_data)
  $fatal(1,"v3_pcm_ring missing reserved output capacity");
 // synthesis translate_on
endmodule
