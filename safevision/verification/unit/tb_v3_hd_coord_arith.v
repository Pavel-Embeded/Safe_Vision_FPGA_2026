`timescale 1ns/1ps
module tb_v3_hd_coord_arith;
 reg clk=0;always #5 clk=!clk;reg rst_n=0;wire[11:0]rx,ry;
 wire[23:0]q19,q20;reg[23:0]refq[0:20];integer checks=0,errors=0,i,k;
 video_timing #(.H_ACTIVE(1280),.H_FRONT(110),.H_SYNC(40),.H_BACK(220),
 .V_ACTIVE(720),.V_FRONT(5),.V_SYNC(5),.V_BACK(20)) raster(.clk(clk),.rst_n(rst_n),.x(rx),.y(ry));
 v3_hd_coord_arith dut(.clk(clk),.rst_n(rst_n),.raw_x(rx),.raw_y(ry),.xy19(q19),.xy20(q20));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)for(i=0;i<21;i = i + 1)refq[i]=0;
  else begin for(i=20;i>0;i = i - 1)refq[i]=refq[i-1];refq[0]={rx,ry};end
  #1;checks = checks + (2);
  if(q19!==refq[19]||q20!==refq[20])begin errors = errors + 1;if(errors<16)$display("[FAIL] raster coordinate delay got=%h/%h expected=%h/%h t=%0t",q19,q20,refq[19],refq[20],$time);end
 end
 task reset(input integer phase);begin begin
  @(posedge clk);#(phase);rst_n=0;#1;checks = checks + 1;
  if(q19!==0||q20!==0)begin errors = errors + 1;$display("[FAIL] async reset coordinates");end
  repeat(3)@(negedge clk);#2;rst_n=1;
 end  end endtask
 initial begin
  for(k=0;k<21;k = k + 1)refq[k]=0;
  repeat(3)@(negedge clk);#2;rst_n=1;
  for(k=0;k<100;k = k + 1)begin repeat(1650+k%41)@(negedge clk);reset(1+k%3);end

  repeat(1650*750*2+50)@(negedge clk);#2;
  $display("[PASS] arithmetic coordinate delay/reset/full rasters checks=%0d errors=%0d",checks,errors);
  $display("PASS tb_v3_hd_coord_arith comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #30000000;begin $display("[FAIL] coordinate arithmetic timeout"); $finish; end end
endmodule
