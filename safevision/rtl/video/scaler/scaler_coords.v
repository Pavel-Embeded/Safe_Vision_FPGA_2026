// Exact source coordinates, fixed latency 2. HD fit is precisely 2/3 in BOTH
// axes. For n=0..1023, floor(n*683/1024)==floor(2*n/3); the remainder is 0,1,2,
// giving Q0.8 fractions 0,85,170. No 22-bit divide/modulo or truncated step.
module scaler_coords #(parameter integer HD=0)(input wire clk,rst_n,de,
 input wire[11:0] x,y,input wire fit,
 output reg valid,output reg[9:0] sx,sy,output reg[7:0] fx,fy);
 generate if(HD)begin:hd_coords
  wire inside_fit=de&&x>=160&&x<1120&&y<720;
  wire inside_one=de&&x>=320&&x<960&&y>=120&&y<600;
  wire[11:0] rel_x=fit?x-12'd160:x-12'd320;
  wire[11:0] rel_y=fit?y:y-12'd120;
  wire[19:0] mx=rel_x[9:0]*10'd683,my=rel_y[9:0]*10'd683;
  reg[9:0] nx,ny,qx,qy;reg fit1,v1;
  wire[10:0] rx={nx,1'b0}-({qx,1'b0}+{1'b0,qx});
  wire[10:0] ry={ny,1'b0}-({qy,1'b0}+{1'b0,qy});
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin nx<=0;ny<=0;qx<=0;qy<=0;fit1<=0;v1<=0;
    valid<=0;sx<=0;sy<=0;fx<=0;fy<=0;end
   else begin
    nx<=rel_x[9:0];ny<=rel_y[9:0];qx<=mx[19:10];qy<=my[19:10];
    fit1<=fit;v1<=fit?inside_fit:inside_one;
    sx<=fit1?qx:nx;sy<=fit1?qy:ny;
    fx<=!fit1||rx==0?0:rx==1?8'd85:8'd170;
    fy<=!fit1||ry==0?0:ry==1?8'd85:8'd170;valid<=v1;
   end
  end
 end else begin:base_coords
  reg[9:0] nx,ny;reg v1;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin nx<=0;ny<=0;v1<=0;valid<=0;sx<=0;sy<=0;fx<=0;fy<=0;end
   else begin nx<=x[9:0];ny<=y[9:0];v1<=de&&x<640&&y<480;
    sx<=nx;sy<=ny;fx<=0;fy<=0;valid<=v1;end
  end
 end endgenerate
endmodule
