


module v3_boot_uptime #(parameter integer CLK_HZ=50000000)(
 input wire clk,output reg[31:0] seconds=0,output reg[31:0] bcd=0);
 localparam W=CLK_HZ>1?$clog2(CLK_HZ):1;
 reg[W-1:0] ticks=0;integer d;reg carry;
 always @(posedge clk)begin
  if(ticks==CLK_HZ-1)begin
   ticks<=0;
   if(bcd!=32'h99999999)begin
    seconds<=seconds+1'b1;carry=1;
    for(d=0;d<8;d=d+1)begin
     if(carry)begin
      if(bcd[d*4+:4]==9)bcd[d*4+:4]<=0;
      else begin bcd[d*4+:4]<=bcd[d*4+:4]+1'b1;carry=0;end
     end
    end
   end
  end else ticks<=ticks+1'b1;
 end
endmodule
