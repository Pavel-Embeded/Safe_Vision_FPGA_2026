`timescale 1ns/1ps
// Independent row-landing oracle. This short test is also the negative-control
// entry point: disabling the DUT CRC comparison must produce errors, then a
// normal $finish, rather than being mistaken for a successful test.
module tb_v3_video_cache;
 reg mem=0,pix=0,rst=0;always #12.5 mem=~mem;always #6.734 pix=~pix;
 reg req=0;wire ready;reg[23:0] desc=0;wire rv;wire[23:0] reply;
 reg[9:0] sx=0,sy=0;reg cv=0;reg[1:0] current=0,target=1;reg dual=1;
 wire primed,rows_ready,sample_valid,fault,busy,progress;
 wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11;
 wire rd_req;wire[31:0] rd_addr,lookup_addr;wire[15:0] rd_len;
 reg ack=0,rd_busy=0,valid=0;reg[31:0] data=0,crc=0;reg lookup_valid=0,corrupt=0;
 v3_line_cache dut(.mem_clk(mem),.mem_rst_n(rst),.pixel_clk(pix),.pixel_rst_n(rst),
  .request_valid(req),.request_ready(ready),.request_data(desc),
  .response_valid(rv),.response_ready(1'b1),.response_data(reply),
  .sx(sx),.sy(sy),.coord_valid(cv),.current_slot(current),.target_slot(target),.dual_needed(dual),.primed(primed),
  .a00(a00),.a10(a10),.a01(a01),.a11(a11),.b00(b00),.b10(b10),.b01(b01),.b11(b11),
  .rows_ready(rows_ready),.sample_valid(sample_valid),.rd_req(rd_req),.rd_addr(rd_addr),.rd_len(rd_len),
  .rd_ack(ack),.rd_busy(rd_busy),.rd_valid(valid),.rd_data(data),
  .lookup_addr(lookup_addr),.lookup_crc(crc),.lookup_valid(lookup_valid),.fault(fault),.dma_busy(busy),.dma_progress(progress));
 function[31:0] word_at(input[31:0] address);begin word_at=32'h00123456^(address>>2)*32'h01020304;end endfunction
 function[15:0] pixel_at(input integer slot,row,col);
  reg[31:0] w;begin w=word_at(slot*32'ha0000+row*1280+(col/2)*4);pixel_at=col%2?w[31:16]:w[15:0];end
 endfunction
 function[31:0] row_crc(input[31:0] address);
  integer w,b;reg[31:0] c,d;begin c=32'hffffffff;
   for(w=0;w<320;w=w+1)begin d=word_at(address+w*4);c=c^d;
    for(b=0;b<32;b=b+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;end
   row_crc=~c;
  end
 endfunction
 reg[31:0] previous_lookup=32'hffffffff,address;integer remaining=0,count=0,stall=0;
 always @(posedge mem)begin
  ack<=0;valid<=0;
  if(!rst)begin rd_busy<=0;remaining<=0;previous_lookup<=32'hffffffff;lookup_valid<=0;end
  else begin
   if(previous_lookup!=lookup_addr)begin crc<=row_crc(lookup_addr)^(corrupt?1:0);previous_lookup<=lookup_addr;end
   lookup_valid<=1;
   if(rd_req&&!rd_busy)begin address<=rd_addr;remaining<=rd_len;rd_busy<=1;ack<=1;end
   else if(rd_busy)begin
    if(remaining==0)rd_busy<=0;
    else if(stall%7!=6)begin valid<=1;data<=word_at(address);address<=address+4;remaining<=remaining-1;count<=count+1;end
    stall<=stall+1;
   end
  end
 end
 integer errors=0,comparisons=0,start_count,x,k;
 task ask(input integer first_row);begin
  @(negedge pix);while(!ready)@(negedge pix);
  desc={current,target,dual,10'(first_row),9'(first_row==479?479:first_row+1)};req=1;
  @(negedge pix);req=0;
 end endtask
 task wait_reply;integer timeout;begin timeout=0;
  while((!rv||reply[18])&&timeout<30000)begin @(negedge pix);timeout=timeout+1;end
  if(!rv||reply[18])begin $display("[FAIL] full descriptor reply timeout");errors=errors+1;end
  repeat(3)@(negedge pix);
 end endtask
 task check_pixels(input integer row);integer col,next_col,step;reg[127:0] expected,observed;begin
  // 193 is coprime with 640: the second row visits every column exactly once,
  // with jumps, backwards moves and both edge columns. Generic mode must not
  // inherit the production packed branch's monotonic scan restriction.
  for(step=0;step<640;step=step+1)begin
   col=row==1?(step*193+17)%640:step;
   @(negedge pix);sx=col;sy=row;cv=1;
   @(posedge pix);#1;next_col=col==639?639:col+1;
   expected={pixel_at(current,row,col),pixel_at(current,row,next_col),pixel_at(current,row+1,col),pixel_at(current,row+1,next_col),
    pixel_at(target,row,col),pixel_at(target,row,next_col),pixel_at(target,row+1,col),pixel_at(target,row+1,next_col)};
   observed={a00,a10,a01,a11,b00,b10,b01,b11};
   if(!sample_valid||!rows_ready||observed!==expected)begin
    if(errors<4)$display("[FAIL] row=%0d col=%0d wanted=%h got=%h ready=%b",row,col,expected,observed,rows_ready);
    errors=errors+1;end
   comparisons=comparisons+8;
  end
  @(negedge pix);cv=0;
 end endtask
 initial begin
  #100;rst=1;ask(0);wait_reply();
  if(count!=1280||!primed)begin $display("[FAIL] first two streams rows count=%d primed=%b",count,primed);errors=errors+1;end
  check_pixels(0);
  start_count=count;ask(1);wait_reply();
  if(count-start_count!=640)begin $display("[FAIL] overlap row refetched count=%d",count-start_count);errors=errors+1;end
  check_pixels(1);
  start_count=count;ask(1);wait_reply();
  if(count!=start_count)begin $display("[FAIL] cached descriptor caused reads");errors=errors+1;end
  $display("[PASS] even/odd 8-neighbor packing, last column clamp and row reuse");
  corrupt=1;ask(6);k=0;while(!fault&&k<5000)begin @(negedge mem);k=k+1;end
  if(!fault)begin $display("[FAIL] intentionally corrupt row CRC was accepted");errors=errors+1;end
  else $display("[PASS] intentionally corrupt CRC rejected before row publication");
  rst=0;repeat(5)@(negedge mem);rst=1;corrupt=0;repeat(5)@(negedge mem);
  if(fault||primed||rv)begin $display("[FAIL] stale row/fault after fetch reset");errors=errors+1;end
  ask(0);wait_reply();check_pixels(0);
  $display("[PASS] fetch reset flush and revalidation");
  $display("[TB] tb_v3_video_cache done comparisons=%0d errors=%0d",comparisons,errors);
  if(!errors)$display("PASS tb_v3_video_cache");$finish;
 end
 initial begin #20000000;$display("[FAIL] cache TB timeout errors=1");$finish;end
endmodule
