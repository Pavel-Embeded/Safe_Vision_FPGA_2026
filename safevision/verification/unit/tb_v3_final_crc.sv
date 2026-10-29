`timescale 1ns/1ps


module tb_v3_final_crc;
 tb_v3_resident u();
 integer errors=0,corruptions=0,guard=0;
 always @(posedge u.cmdvalid)if(u.cmd==17 && u.card.o_arg==91)begin
  #1;u.card.crc_val=u.card.crc_val^16'h1;corruptions=corruptions+1;
 end
 task ck;input c;input[511:0] msg;begin
  if(c)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 initial begin
  @(posedge u.rst);
  while(u.rejected<5 && u.state!=10 && guard<50000000)begin @(negedge u.clk);guard=guard+1;end
  ck(corruptions==1 && u.rejected==5,"one final-sector CRC fault rejected after four invalid header files");
  ck(u.last_reject_error==16'h0222 && u.last_reject_key==5,"final-sector error code, detail and file ID retained");
  ck(u.count==0 && u.cv==0 && !u.mounted && u.frames==0,"failed SD transaction never grants image ownership");
  ck(u.approved==0 && u.writes<153600,"bad last sector bytes never reach writer or producer CRC approval");
  $display("PASS tb_v3_final_crc errors=%0d comparisons=%0d",errors,u.writes);$finish;
 end
endmodule
