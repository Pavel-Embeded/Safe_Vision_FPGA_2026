// Cycle-exact saturating CTS interval counter with one-edge-ahead carries.
// 48 sample intervals, N=6144, first interval discarded as in the reference.
module hdmi_acr(input wire pixel_clk,rst_n,sample_valid,
 output reg valid,output reg[19:0]cts,output wire[19:0]n);
 assign n=20'd6144;
 reg[5:0]count;reg[19:0]clocks;reg armed,full,count_last;reg[3:0]carry;
 wire[3:0]n0=clocks[3:0]+4'd1,n1=clocks[7:4]+carry[0],n2=clocks[11:8]+carry[1],n3=clocks[15:12]+carry[2],n4=clocks[19:16]+carry[3];
 wire[19:0]next_clocks={n4,n3,n2,n1,n0};
 always@(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin valid<=0;cts<=0;count<=0;count_last<=0;clocks<=0;armed<=0;full<=0;carry<=0;end
  else begin
   valid<=0;
   if(!full)begin
    clocks<=next_clocks;full<=clocks==20'hffffe;
    carry[0]<=clocks[3:0]==4'he;carry[1]<=clocks[7:0]==8'hfe;
    carry[2]<=clocks[11:0]==12'hffe;carry[3]<=clocks[15:0]==16'hfffe;
   end
   if(sample_valid)begin
    if(!armed)begin armed<=1;count<=0;count_last<=0;clocks<=0;full<=0;carry<=0;end
    else if(count_last)begin cts<=next_clocks;valid<=1;clocks<=0;count<=0;count_last<=0;full<=0;carry<=0;end
    else begin count<=count+1'b1;count_last<=count==46;end
   end
  end
 end
endmodule
