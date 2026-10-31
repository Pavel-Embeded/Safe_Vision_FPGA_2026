`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_v3_row_integrity;
 reg clk=0;always #5 clk=~clk;reg rst=0,begin_frame=0,td=0,accepted=0,start=0,allow=1;
 reg[1:0] slot=0;reg[31:0] wa=0,wd=0,lookup=0;
 wire done,pass,fault,req,lv;wire[3:0] approved;wire[31:0] addr,lc,ba,be,bact,words;wire[15:0] len,rows;
 reg ack=0,busy=0,rv=0;reg[31:0] data=0;
 v3_row_integrity #(.ROWS(8),.ROW_WORDS(128),.TIMEOUT(200)) dut(
 .clk(clk),.rst_n(rst),.frame_begin(begin_frame),.frame_slot(slot),.top_down(td),
 .accepted(accepted),.write_addr(wa),.write_data(wd),.verify_start(start),.verify_allow(allow),
 .verify_done(done),.verify_pass(pass),.fault(fault),.approved(approved),
 .rd_req(req),.rd_addr(addr),.rd_len(len),.rd_ack(ack),.rd_busy(busy),.rd_valid(rv),.rd_data(data),
 .lookup_addr(lookup),.lookup_crc(lc),.lookup_valid(lv),.bad_addr(ba),.bad_expected(be),.bad_actual(bact),
 .source_words(words),.checked_rows(rows));
 reg[31:0] memory[0:1048575],golden[0:31];
 integer read_index=0,left=0,clock_count=0,errors=0,comparisons=0,s,r,c,k,guard;
 reg corrupt=0,block_reads=0;
 always @(posedge clk)begin
  clock_count<=clock_count+1;ack<=0;rv<=0;
  if(!rst)begin busy<=0;left<=0;end
  else begin
   if(accepted)memory[wa>>2]<=wd;
   if(req && !busy && !block_reads)begin ack<=1;busy<=1;read_index<=addr>>2;left<=len;end
   else if(busy && clock_count%5!=0)begin
    data<=memory[read_index]^((corrupt && read_index%128==73) ? 32'h00008000:0);
    rv<=1;read_index<=read_index+1;left<=left-1;if(left==1)busy<=0;
   end
  end
 end
 function[31:0] pattern;input integer sl,row,col;begin  pattern=(sl<<28)^(row<<16)^(col*32'h10204081);  end endfunction
 task ck;input cond;input[511:0] msg;begin  if(cond)$display("[PASS] %s",msg);else begin
  errors=errors+1;$display("[FAIL] %s",msg);end   end endtask
 task build;input integer sl;input direction;integer y,x,row;begin
  slot=sl;td=direction;begin_frame=1;@(negedge clk);begin_frame=0;
  ck(!approved[sl],"slot invalidated before source overwrite");
  for(y=0;y<8;y=y+1)begin row=direction ? y:7-y;
   for(x=0;x<128;x=x+1)begin
    wa=`SV_SLOT_BASE(slot)+(row*128+x)*4;wd=pattern(sl,row,x);accepted=1;@(negedge clk);
   end
  end
  accepted=0;@(negedge clk);ck(words==1024,"all source words accepted exactly once");
   end endtask
 task verify;begin  start=1;@(negedge clk);start=0;guard=0;
 while(!done && guard<5000)begin @(negedge clk);guard=guard+1;end   end endtask
 task reset;begin  rst=0;accepted=0;begin_frame=0;start=0;repeat(3)@(negedge clk);rst=1;repeat(3)@(negedge clk);  end endtask
 initial begin
 $readmemh("row_crc_golden.mem",golden);reset;
 for(s=0;s<4;s=s+1)begin
  build(s,s[0]);verify;ck(done && pass && !fault && rows==8,"four-slot readback with burst stalls");
  for(r=0;r<8;r=r+1)begin lookup=`SV_SLOT_BASE(slot)+r*512;repeat(3)@(negedge clk);
   comparisons=comparisons+1;ck(lv && lc===golden[s*8+r],"row signature equals Python zlib CRC32");end
 end
 ck(approved==15,"all four resident approvals retained");
 lookup=`SV_SLOT_BASE(slot)+4096;repeat(3)@(negedge clk);ck(!lv,"out-of-range signature lookup rejected");

 reset;build(2,0);corrupt=1;verify;
 ck(done && !pass && fault && !approved[2],"negative CRC control catches corruption beyond first burst");
 corrupt=0;reset;slot=1;begin_frame=1;@(negedge clk);begin_frame=0;
 accepted=1;wa=`SV_IMG2_BASE;wd=0;@(negedge clk);accepted=0;ck(fault,"wrong slot/address source rejected");
 reset;build(0,1);block_reads=1;verify;ck(done && fault && !pass,"stalled readback timeout is bounded");
 block_reads=0;
 $display("PASS tb_v3_row_integrity errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #500000;$display("[FAIL] global timeout");$finish;end
endmodule
