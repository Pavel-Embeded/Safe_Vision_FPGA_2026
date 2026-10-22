// Behavioral DDR primitive only; no electrical, clock-tree or silicon proof.
module EG_LOGIC_ODDR(input wire clk,rst,d1,d0,output reg q);
 always @(posedge clk or posedge rst)if(rst)q<=0;else q<=d0;
 always @(negedge clk or posedge rst)if(rst)q<=0;else q<=d1;
endmodule
