

module hdmi_acr(input wire pixel_clk,rst_n,sample_valid,
 output reg valid,output reg [19:0] cts,output wire [19:0] n);
 assign n=20'd6144;
 reg [5:0] count;reg [19:0] clocks;reg armed;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin valid<=0;cts<=0;count<=0;clocks<=0;armed<=0;end
  else begin
   valid<=0;if(clocks!=20'hfffff)clocks<=clocks+1'b1;
   if(sample_valid)begin
    if(!armed)begin armed<=1;count<=0;clocks<=0;end
    else if(count==47)begin
     cts<=clocks+1'b1;valid<=1;clocks<=0;count<=0;
    end else count<=count+1'b1;
   end
  end
 end
endmodule
