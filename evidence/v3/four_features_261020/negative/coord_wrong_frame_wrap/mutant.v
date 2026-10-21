// Fixed-rate raster coordinates, exactly equivalent to the existing 21 tags.
// A stage-19 sample is the current pre-edge raw raster minus 19 pixels.
// At startup it is masked for the first 19 writes, matching the cleared tags.
module v3_hd_coord_arith #(parameter integer HT=1650,VT=750)(
 input wire clk,rst_n,input wire[11:0]raw_x,raw_y,
 output reg[23:0]xy19,xy20);
 localparam[11:0]WRAP_X=HT-19,LAST_Y=VT-2;
 reg[4:0]fill;
 wire previous_line=(raw_x<12'd19);
 wire[11:0]delayed_x=previous_line?(raw_x+WRAP_X):(raw_x-12'd19);
 wire[11:0]delayed_y=previous_line?((raw_y==0)?LAST_Y:(raw_y-12'd1)):raw_y;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin fill<=0;xy19<=0;xy20<=0;end
  else begin
   if(fill!=5'd19)fill<=fill+1'b1;
   xy19<=(fill==5'd19)?{delayed_x,delayed_y}:24'd0;
   xy20<=xy19;
  end
endmodule
