`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_v3_hd_guard_255_320;
 reg clk=0;always #5 clk=~clk;reg rst=0,begin_frame=0,td=0,accepted=0,start=0,allow=1;
 reg[1:0] slot=0;reg[31:0] wa=0,wd=0,lookup=0;
 wire done,pass,fault,req,lv;wire[3:0] approved;wire[31:0] addr,lc,ba,be,bact,words;wire[15:0] len,rows;
 reg ack=0,busy=0,rv=0;reg[31:0] data=0;
 v3_row_integrity #(.ROWS(255),.ROW_WORDS(320),.TIMEOUT(2000)) dut(
 .clk(clk),.rst_n(rst),.frame_begin(begin_frame),.frame_slot(slot),.top_down(td),
 .accepted(accepted),.write_addr(wa),.write_data(wd),.verify_start(start),.verify_allow(allow),
 .verify_done(done),.verify_pass(pass),.fault(fault),.approved(approved),
 .rd_req(req),.rd_addr(addr),.rd_len(len),.rd_ack(ack),.rd_busy(busy),.rd_valid(rv),.rd_data(data),
 .lookup_addr(lookup),.lookup_crc(lc),.lookup_valid(lv),.bad_addr(ba),.bad_expected(be),.bad_actual(bact),
 .source_words(words),.checked_rows(rows));
 wire gold_done,gold_pass,gold_fault,gold_req,gold_lv;wire[3:0] gold_approved;wire[31:0] gold_addr,gold_lc,gold_ba,gold_be,gold_bact,gold_words;wire[15:0] gold_len,gold_rows;
 v3_hd_guard_reference #(.ROWS(255),.ROW_WORDS(320),.TIMEOUT(2000)) reference(
 .clk(clk),.rst_n(rst),.frame_begin(begin_frame),.frame_slot(slot),.top_down(td),
 .accepted(accepted),.write_addr(wa),.write_data(wd),.verify_start(start),.verify_allow(allow),
 .verify_done(gold_done),.verify_pass(gold_pass),.fault(gold_fault),.approved(gold_approved),
 .rd_req(gold_req),.rd_addr(gold_addr),.rd_len(gold_len),.rd_ack(ack),.rd_busy(busy),.rd_valid(rv),.rd_data(data),
 .lookup_addr(lookup),.lookup_crc(gold_lc),.lookup_valid(gold_lv),.bad_addr(gold_ba),.bad_expected(gold_be),.bad_actual(gold_bact),
 .source_words(gold_words),.checked_rows(gold_rows));
 reg[31:0] memory[0:1048575],golden[0:1019];
 integer read_index=0,left=0,clock_count=0,errors=0,comparisons=0,s,r,c,k,guard;
 reg corrupt=0,block_reads=0;
 always @(posedge clk)begin
  clock_count<=clock_count+1;ack<=0;rv<=0;
  if(!rst)begin busy<=0;left<=0;end
  else begin
   if(accepted)memory[wa>>2]<=wd;
   if(req && !busy && !block_reads)begin ack<=1;busy<=1;read_index<=addr>>2;left<=len;end
   else if(busy && clock_count%5!=0)begin
    data<=memory[read_index]^((corrupt && read_index%320==319)?32'h00008000:0);
    rv<=1;read_index<=read_index+1;left<=left-1;if(left==1)busy<=0;
   end
  end
 end
 function[31:0] pattern;input integer sl,row,col;begin pattern=(sl<<28)^(row<<16)^(col*32'h10204081);end endfunction
 task ck;input cond;input[511:0] msg;begin if(cond)$display("[PASS] %s",msg);else begin
  errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 task build;input integer sl;input direction;integer y,x,row;begin
  slot=sl;td=direction;begin_frame=1;@(negedge clk);begin_frame=0;
  ck(!approved[sl],"slot invalidated before source overwrite");
  for(y=0;y<255;y=y+1)begin row=direction?y:254-y;
   for(x=0;x<320;x=x+1)begin
    wa=`SV_SLOT_BASE(slot)+(row*320+x)*4;wd=pattern(sl,row,x);accepted=1;@(negedge clk);
   end
  end
  accepted=0;@(negedge clk);ck(words==81600,"all source words accepted exactly once");
 end endtask
 task verify;begin start=1;@(negedge clk);start=0;guard=0;
 while(!done && guard<1000000)begin @(negedge clk);guard=guard+1;end end endtask
 task reset;begin rst=0;accepted=0;begin_frame=0;start=0;repeat(3)@(negedge clk);rst=1;repeat(3)@(negedge clk);end endtask

 always @(negedge clk)if(rst)begin
  comparisons=comparisons+1;
  if({done,pass,fault,approved,req,addr,len,lc,lv,ba,be,bact,words,rows} !== {gold_done,gold_pass,gold_fault,gold_approved,gold_req,gold_addr,gold_len,gold_lc,gold_lv,gold_ba,gold_be,gold_bact,gold_words,gold_rows})begin
   errors=errors+1;if(errors<8)$display("[FAIL] guard interface differs at cycle %0d",clock_count);
  end
 end
 initial begin
 $readmemh("guard_pad_255_320.mem",golden);reset;
 for(s=0;s<4;s=s+1)begin
  build(s,s[0]);verify;ck(done && pass && !fault && rows==255,"four-slot readback with burst stalls");
  for(r=0;r<255;r=r+1)begin lookup=`SV_SLOT_BASE(slot)+r*1280;repeat(3)@(negedge clk);
   comparisons=comparisons+1;ck(lv && lc===golden[s*255+r],"row signature equals Python zlib CRC32");end
 end
 ck(approved==15,"all four resident approvals retained");
 for(k=0;k<4096;k=k+1)begin
  case(k%4)
   0:lookup=`SV_SLOT_BASE(k[3:2])+((k/16)%255)*1280;
   1:lookup=`SV_SLOT_BASE(k[3:2])+((k/16)%255)*1280+4;
   2:lookup=`SV_SLOT_BASE(k[3:2])+326400;
   3:lookup=(k*32'h9e3779b9)^32'h80000000;
  endcase
  repeat(2)@(negedge clk);
 end
 lookup=`SV_SLOT_BASE(slot)+326400;repeat(3)@(negedge clk);ck(!lv,"out-of-range signature lookup rejected");

 reset;build(2,0);corrupt=1;verify;
 ck(done && !pass && fault && !approved[2],"negative CRC control catches corruption beyond first burst");
 corrupt=0;reset;slot=1;begin_frame=1;@(negedge clk);begin_frame=0;
 accepted=1;wa=`SV_IMG2_BASE;wd=0;@(negedge clk);accepted=0;ck(fault,"wrong slot/address source rejected");
 reset;build(0,1);block_reads=1;verify;ck(done && fault && !pass,"stalled readback timeout is bounded");
 block_reads=0;
 $display("PASS tb_v3_hd_guard_255_320 errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #50000000;$display("[FAIL] global timeout");$finish;end
endmodule
