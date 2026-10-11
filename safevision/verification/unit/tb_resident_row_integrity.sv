`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_resident_row_integrity;
 `include "crc32_word.vh"
 reg clk=0;always #12.5 clk=~clk;reg rst=0,fb=0,abort=0,accepted=0,top=0,vs=0;
 reg [1:0] slot=0;reg [31:0] wa=0,wd=0,query=0;
 wire done,pass,fault,req;wire [31:0] ra,lc;wire [15:0] len;wire lv;
 reg ack=0,busy=0,valid=0;reg [31:0] data=0;
 wire [31:0] bad,expected,actual,words,raw;wire [15:0] blocks;
 frame_integrity_guard #(.WORDS(640),.ROW_WORDS(320),.BLOCK_WORDS(320),.SLOTS(4),.TIMEOUT(4000)) dut(
 .clk(clk),.rst_n(rst),.frame_begin(fb),.frame_abort(abort),.frame_slot(slot),.top_down(top),
 .accepted(accepted),.write_addr(wa),.write_data(wd),.verify_start(vs),.verify_allow(1'b1),
 .verify_done(done),.verify_pass(pass),.fault(fault),.rd_req(req),.rd_addr(ra),.rd_len(len),
 .rd_ack(ack),.rd_busy(busy),.rd_data(data),.rd_valid(valid),.lookup_addr(query),.lookup_crc(lc),.lookup_valid(lv),
 .bad_addr(bad),.bad_expected(expected),.bad_actual(actual),.bad_first_word(raw),.source_words(words),.checked_blocks(blocks));
 reg [31:0] mem[0:2559];integer index=0,left=0;
 function [1:0] slot_at(input [31:0] address);
 begin slot_at=(address>=`SV_IMG3_BASE)?3:(address>=`SV_IMG2_BASE)?2:(address>=`SV_IMG1_BASE)?1:0;end endfunction
 function integer memory_index(input [31:0] address);
 reg [1:0] a;begin a=slot_at(address);memory_index=a*640+((address-`SV_SLOT_BASE(a))>>2);end endfunction
 always @(posedge clk)if(accepted)mem[memory_index(wa)]<=wd;
 always @(negedge clk)begin
   ack=0;valid=0;
   if(req&&!busy)begin index=memory_index(ra);left=len;busy=1;ack=1;end
   else if(busy)begin data=mem[index];valid=1;index=index+1;left=left-1;if(left==0)busy=0;end
 end
 integer s,row,c,k,checks=0;reg [31:0] crc;
 task check(input bit condition,input string message);
 begin checks=checks+1;if(!condition)$fatal(1,"ROW INTEGRITY: %s slot=%0d words=%0d blocks=%0d",message,slot,words,blocks);end endtask
 initial begin
   repeat(4)@(negedge clk);rst=1;
   for(s=0;s<4;s=s+1)begin
     @(negedge clk);slot=s;top=s[0];fb=1;@(negedge clk);fb=0;
     for(row=0;row<2;row=row+1)for(c=0;c<320;c=c+1)begin
       wa=`SV_SLOT_BASE(slot)+((top?row:1-row)*320+c)*4;
       wd=(s<<24)^((top?row:1-row)<<16)^c;accepted=1;@(negedge clk);
     end
     accepted=0;vs=1;@(negedge clk);vs=0;wait(done);@(negedge clk);
     check(pass&&!fault&&words==640&&blocks==2,"complete source and both 320-word rows checked");
   end
   for(s=0;s<4;s=s+1)for(row=0;row<2;row=row+1)begin
     @(negedge clk);query=`SV_SLOT_BASE(s)+row*1280;repeat(3)@(negedge clk);
     crc=32'hffffffff;for(k=0;k<320;k=k+1)crc=crc32_word(crc,mem[s*640+row*320+k]);
     check(lv&&lc===~crc,"four slots retain independent CRC signatures");
   end
   @(negedge clk);slot=2;fb=1;@(negedge clk);fb=0;
   query=`SV_IMG2_BASE;repeat(3)@(negedge clk);check(!lv,"new build revokes only target approval");
   vs=1;abort=1;@(negedge clk);abort=0;vs=0;query=`SV_IMG1_BASE;repeat(3)@(negedge clk);
   check(lv&&!fault&&!pass&&!req,"abort overrides a simultaneous verification request and preserves other approvals");
   rst=0;repeat(3)@(negedge clk);rst=1;repeat(3)@(negedge clk);
   check(!lv,"common reset revokes all stale signatures");
   $display("PASS tb_resident_row_integrity checks=%0d: four slots / signed rows / 320-word CRC / abort / reset",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"row regression watchdog");end
endmodule
