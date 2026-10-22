`timescale 1ns/1ps
module handbook_packed_case #(parameter PHASE=0)(output reg done=0,output integer errors=0,comparisons=0);
 reg mem=0,wr=0,pix=0,rst=0;always #10 mem=~mem;always #6.734 pix=~pix;
 initial begin #(PHASE);forever #5 wr=~wr;end
 reg valid=0,cv=0,prepare=0;reg[2:0] bank=0;reg[8:0] column=0;reg[31:0] data=0;
 reg[9:0]sx=0,sy=0,prepared=0;reg[1:0]mode=2;
 wire row_done,sf,pf;wire[15:0]a00,a10,a01,a11,b00,b10,b01,b11;
 v3_packed_row_store #(.HANDBOOK_PROFILE(1)) dut(mem,rst,wr,rst,pix,rst,valid,bank,column,data,row_done,sf,
 cv,sx,sy,mode,prepare,prepared,a00,a10,a01,a11,b00,b10,b01,b11,pf);
 function[15:0] p(input integer stream,row,col);begin p=16'((stream*31727)^(row*9257)^(col*193));end endfunction
 integer m,r,s,c,x,step,b,acks=0,oldack,t;reg[63:0]expected;
 always @(posedge mem)if(rst&&row_done)acks++;
 task fill(input integer row);begin
  for(s=0;s<2;s++)begin b=(row/(mode==2?2:4))%4;oldack=acks;
   for(c=0;c<320;c++)begin @(negedge mem);valid=1;bank=s*4+b;column=c;data={p(s,row,2*c+1),p(s,row,2*c)};end
   @(negedge mem);valid=0;t=0;while(acks==oldack&&t<30)begin @(negedge mem);t++;end
   comparisons++;if(acks!=oldack+1||sf)begin errors++;$display("[FAIL] exact packed ingress and ACK");end
  end
 end endtask
 task line(input integer row);begin
  @(negedge pix);cv=0;prepare=1;prepared=row;@(negedge pix);prepare=0;repeat(8)@(negedge pix);
  for(x=0;x<640;x+=step)begin sx=x;sy=row;cv=1;@(posedge pix);#1;
   expected={p(0,row,x),p(0,row,x),p(1,row,x),p(1,row,x)};comparisons+=4;
   // fx=fy=0: only the current column is consumed by either scaler. Both
   // vertical aliases must return the same physical source row.
   if({a00,a01,b00,b01}!==expected||pf||sf)begin errors++;if(errors<8)$display("[FAIL] packed decimation phase=%0d mode=%0d row=%0d sx=%0d want=%h got=%h",PHASE,mode,row,x,expected,{a00,a01,b00,b01});end
   @(negedge pix);
  end cv=0;repeat(4)@(negedge pix);
 end endtask
 initial begin
  #100;rst=1;
  for(m=2;m<=3;m++)begin mode=m;step=m==2?2:4;
   // More than four display rows proves bank wrap and prevents aliases from
   // passing with a single preloaded pattern. Includes the bottom source row.
   for(r=0;r<480;r+=step)begin fill(r);line(r);end
  end
  @(negedge pix);prepare=1;prepared=0;@(negedge pix);prepare=0;repeat(8)@(negedge pix);
  cv=1;sx=0;sy=0;@(negedge pix);sx=3;@(negedge pix);comparisons++;
  if(!pf)begin errors++;$display("[FAIL] illegal quarter-step accepted");end
  if(errors==0)$display("[PASS] every half/quarter output pixel, two streams, physical bank wrap, phase=%0d",PHASE);done=1;
 end
 initial begin #20000000;$display("[FAIL] decimation watchdog errors=1");$finish;end
endmodule
module tb_v3_handbook_packed;
 wire d0,d1;wire integer e0,e1,c0,c1;
 handbook_packed_case #(.PHASE(0)) a(d0,e0,c0);handbook_packed_case #(.PHASE(5)) b(d1,e1,c1);
 initial begin wait(d0&&d1);$display("[TB] tb_v3_handbook_packed done errors=%0d comparisons=%0d",e0+e1,c0+c1);$finish;end
endmodule
