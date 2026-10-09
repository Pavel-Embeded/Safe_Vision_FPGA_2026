`timescale 1ns/1ps
module tb_sdram_response_timeout;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,req=0,wr=0,rv=0;wire ready,valid,aw,ar,idle,fault,init;
 wire [31:0] data;wire [20:0] wa,ra;wire [3:0] dm;wire [31:0] wd;
 sdram_app_adapter #(.READ_TIMEOUT(80)) dut(.clk(clk),.rst_n(rst_n),.req(req),.wr(wr),
  .addr(32'd32),.wdata(32'h12345678),.wstrb(4'hf),.rdata(data),.rdata_valid(valid),
  .ready(ready),.init_done(init),.write_idle(idle),.protocol_fault(fault),
  .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
  .App_wr_en(aw),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),
  .App_rd_en(ar),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(32'h55aa55aa));
 integer commands=0;
 always @(posedge clk)if(ar)commands=commands+1;
 initial begin
  #32;rst_n=1;req=1;
  repeat(100)@(posedge clk);#1;
  if(!fault||ready||valid||idle||init||commands!=16)$fatal(1,"Lost read response was not fenced");
  rv=1;wr=1;repeat(8)@(posedge clk);#1;
  if(!fault||ready||valid||aw||ar)$fatal(1,"Late data/new writes escaped the fault fence");
  @(negedge clk);rst_n=0;req=0;rv=0;wr=0;
  repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
  repeat(3)@(posedge clk);#1;
  if(fault||!init||!idle)$fatal(1,"Common reset did not restore a clean memory epoch");
  $display("[PASS] SDRAM LOST RESPONSE: 16 commands, bounded fault, no partial data, late response fenced, reset recovery");$finish;
 end
 initial begin #10000;$fatal(1,"Timeout test watchdog");end
endmodule
