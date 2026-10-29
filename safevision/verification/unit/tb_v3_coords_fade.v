`timescale 1ns/1ps
module tb_v3_coords_fade;
 reg clk=0;always #5 clk=~clk;reg rst=0,de=0;reg[11:0] x=0,y=0;
 wire v;wire[9:0] sx,sy;wire[7:0] fx,fy;
 scaler_coords #(.HD(1)) co(clk,rst,de,x,y,1'b1,2'd0,v,sx,sy,fx,fy);
 reg fs=0,request=0,safety=0;reg[1:0] target=0;reg[3:0] valid_slots=15;
 wire[1:0] cur,nxt;wire[7:0] alpha,gen;wire busy,commit,ready;
 fade_ctrl #(.FRAMES(32)) fc(clk,rst,fs,request,safety,target,valid_slots,cur,nxt,alpha,gen,busy,commit,ready);
 integer errors=0,i,j,expectedx,expectedy,checkx,checky;reg oldv=0;
 task ck;input c;input[255:0] msg;begin begin
 if(!c)begin errors=errors+1;if(errors<=5)$display("[FAIL] %s",msg);end end  end endtask
 task frame;begin begin fs=1;@(negedge clk);fs=0;@(negedge clk);end  end endtask
 initial begin
 repeat(3)@(negedge clk);rst=1;
 for(j=0;j<720;j=j+1)for(i=0;i<960;i=i+1)begin
  x=i+160;y=j;de=1;@(negedge clk);
  if(oldv)ck(v && sx==checkx && sy==checky,"exact rational coordinates");
  checkx=i*640/960;checky=j*480/720;oldv=1;
 end
 de=0;@(negedge clk);ck(v && sx==639 && sy==479,"last source coordinate not lost");
 @(negedge clk);target=1;request=1;@(negedge clk);request=0;frame;
 ck(busy && cur==0 && nxt==1 && alpha==0,"fade begins at vblank");
 for(i=0;i<32;i=i+1)begin frame;end
 ck(!busy && cur==1 && gen==1,"32-frame fade commits once");
 for(i=0;i<100;i=i+1)begin target=cur+1'b1;request=1;@(negedge clk);request=0;frame;
  repeat(32)frame;ck(!busy,"100 transitions complete");end
 if(errors==0)$display("[PASS] full HD coordinate raster and 100 fades");
 $display("PASS tb_v3_coords_fade errors=%0d",errors);$finish;
 end
 initial begin #10000000;$display("[FAIL] timeout");$finish;end
endmodule
