`timescale 1ns/1ps
module tb_osd_text_layer;
 reg clk=0,rst=0,de=0,en=1;always #4 clk=~clk;
 reg [11:0] x=0,y=0;wire [7:0] index;wire [23:0] rgb;wire valid;
 reg [7:0] font[0:4095];reg [24:0] expected[0:3];integer i,j,ix,checks=0,seq;
 reg [23:0] fg=24'h123abc;reg want;integer row,col;reg [7:0] code;
 osd_text_layer #(.FONT_FILE("font8x16.mem")) dut(.clk(clk),.rst_n(rst),.de(de),.x(x),.y(y),.origin_x(12'd7),.origin_y(12'd3),.enable(en),.char_count(8'd2),.char_code(index==0?8'h41:8'h42),.foreground(fg),.char_index(index),.rgb(rgb),.valid(valid));
 always @(posedge clk)begin
  if(!rst)for(i=0;i<4;i=i+1)expected[i]=0;
  else begin
   row=y-3;col=x-7;code=col<8?8'h41:8'h42;
   want=en&&de&&x>=7&&x<23&&y>=3&&y<19;
   if(want)want=font[code*16+row][7-(col%8)];
   for(i=3;i>0;i=i-1)expected[i]=expected[i-1];expected[0]={want,fg};
   #0.1;
   if(valid!==expected[3][24]||(valid&&rgb!==expected[3][23:0]))$fatal(1,"OSD mask/color mismatch xy=%0d,%0d seq=%0d",x,y,seq);
   checks=checks+1;
  end
 end
 initial begin
  $readmemh("font8x16.mem",font);repeat(4)@(negedge clk);rst=1;seq=0;
  for(j=0;j<32;j=j+1)for(ix=0;ix<48;ix=ix+1)begin @(negedge clk);x=ix;y=j;de=(ix<40);fg=24'h123abc^seq;seq=seq+1;end
  @(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;en=0;
  repeat(100)@(negedge clk);
  $display("PASS tb_osd_text_layer: %0d font mask/color samples, transparent margins, disabled and reset",checks);$finish;
 end
 initial begin #30000;$fatal(1,"OSD timeout");end
endmodule
