`timescale 1ns/1ps
module tb_v3_hd_row_crc_balance;
 reg[31:0] data=0,state=0,rng=32'h389ba019;
 integer errors=0,comparisons=0,k,i;reg[31:0] expected,v;
 v3_line_cache dut(.mem_clk(1'b0),.mem_rst_n(1'b0),.pixel_clk(1'b0),.pixel_rst_n(1'b0),
 .write_clk(1'b0),.write_rst_n(1'b0),.prepare_valid(1'b0),.prepare_sy(10'd0),
 .request_valid(1'b0),.request_data(24'd0),.response_ready(1'b0),.sx(10'd0),.sy(10'd0),
 .coord_valid(1'b0),.scale_select(2'd0),.current_slot(2'd0),.target_slot(2'd0),.dual_needed(1'b0),
 .rd_ack(1'b0),.rd_busy(1'b0),.rd_valid(1'b0),.rd_data(data),.lookup_crc(32'd0),.lookup_valid(1'b0));
 task check;begin
  v=state^data;
  for(i=0;i<32;i=i+1)if(v[0])v=(v>>1)^32'hedb88320;else v=v>>1;
  expected=v;#1;comparisons = comparisons + 1;
  if(dut.row_crc_next!==expected)begin errors = errors + 1;if(errors<6)$display("[FAIL] CRC state=%h data=%h actual=%h expected=%h",state,data,dut.row_crc_next,expected);end
   end endtask
 initial begin
  force dut.crc=state;
  for(k=0;k<32;k=k+1)begin state=1<<k;data=0;check();state=0;data=1<<k;check();end
  state=0;data=0;check();state=(~0);data=0;check();state=0;data=(~0);check();state=(~0);data=(~0);check();
  for(k=0;k<1000000;k=k+1)begin rng=rng*1664525+1013904223;state=rng;rng=rng*1664525+1013904223;data=rng;check();end
  if(errors==0)$display("[PASS] balanced IEEE CRC32 exact basis and million state/data pairs; state machine and handshake unchanged");
  $display("PASS tb_v3_hd_row_crc_balance comparisons=%0d errors=%0d",comparisons,errors);$finish;
 end
endmodule
