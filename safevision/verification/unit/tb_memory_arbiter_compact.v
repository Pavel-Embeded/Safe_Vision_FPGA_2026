


`timescale 1ns/1ps
module arb_compact_case #(parameter integer N=4)(output reg done);
 initial begin done = 0; end

 reg clk=0;always #4 clk=~clk;reg rn=0,rd=0,wr=0,sd=0;
 integer cycle=0,reads=0,writes=0,sd_grants=0;reg ready=0;
 reg [2:0] rv=0;reg [31:0] d0=0,d1=0,d2=0;
 wire ra0;
 wire rb0;
 wire [31:0] rdata0;
 wire rvalid0;
 wire wa0;
 wire wb0;
 wire sa0;
 wire sb0;
 wire [31:0] sdata0;
 wire svalid0;
 wire req0;
 wire mw0;
 wire [31:0] addr0;
 wire [31:0] data0;
 wire [3:0] strb0;
 wire [15:0] ws0;
 wire [15:0] rs0;
 memory_arbiter #(.MAX_BURSTS(N),.STARVE_LIMIT(64),.COMPACT_CONSEC_COUNTER(0)) dut0(
 .clk(clk),.rst_n(rn),.video_fifo_level(16'd0),
 .rd_req(rd),.rd_addr(32'h1000),.rd_len(16'd3),
 .wr_req(wr),.wr_addr(32'h80000),.wr_data(32'hdb65ad39),.wr_len(16'd1),
 .sd_req(sd),.sd_wr(1'b0),.sd_addr(32'h2c0000),.sd_wdata(32'd0),.sd_len(16'd2),
 .mem_ready(ready),.mem_rdata(d2),.mem_rdata_valid(rv[2]),
 .rd_ack(ra0),
 .rd_busy(rb0),
 .rd_data(rdata0),
 .rd_data_valid(rvalid0),
 .wr_ack(wa0),
 .wr_busy(wb0),
 .sd_ack(sa0),
 .sd_busy(sb0),
 .sd_rdata(sdata0),
 .sd_rdata_valid(svalid0),
 .mem_req(req0),
 .mem_wr(mw0),
 .mem_addr(addr0),
 .mem_wdata(data0),
 .mem_wstrb(strb0),
 .wr_starve_cnt(ws0),
 .rd_starve_cnt(rs0));
 wire ra1;
 wire rb1;
 wire [31:0] rdata1;
 wire rvalid1;
 wire wa1;
 wire wb1;
 wire sa1;
 wire sb1;
 wire [31:0] sdata1;
 wire svalid1;
 wire req1;
 wire mw1;
 wire [31:0] addr1;
 wire [31:0] data1;
 wire [3:0] strb1;
 wire [15:0] ws1;
 wire [15:0] rs1;
 memory_arbiter #(.MAX_BURSTS(N),.STARVE_LIMIT(64),.COMPACT_CONSEC_COUNTER(1)) dut1(
 .clk(clk),.rst_n(rn),.video_fifo_level(16'd0),
 .rd_req(rd),.rd_addr(32'h1000),.rd_len(16'd3),
 .wr_req(wr),.wr_addr(32'h80000),.wr_data(32'hdb65ad39),.wr_len(16'd1),
 .sd_req(sd),.sd_wr(1'b0),.sd_addr(32'h2c0000),.sd_wdata(32'd0),.sd_len(16'd2),
 .mem_ready(ready),.mem_rdata(d2),.mem_rdata_valid(rv[2]),
 .rd_ack(ra1),
 .rd_busy(rb1),
 .rd_data(rdata1),
 .rd_data_valid(rvalid1),
 .wr_ack(wa1),
 .wr_busy(wb1),
 .sd_ack(sa1),
 .sd_busy(sb1),
 .sd_rdata(sdata1),
 .sd_rdata_valid(svalid1),
 .mem_req(req1),
 .mem_wr(mw1),
 .mem_addr(addr1),
 .mem_wdata(data1),
 .mem_wstrb(strb1),
 .wr_starve_cnt(ws1),
 .rd_starve_cnt(rs1));
 always @(posedge clk)begin
  cycle=cycle+1;ready<=cycle%11!=0;
  rv<={rv[1:0],req0&&ready&&!mw0};d0<=addr0^32'h936a8275;d1<=d0;d2<=d1;
 end
 always @(posedge clk)begin
  if(rn)begin
   if(ra0)reads=reads+1;if(wa0)writes=writes+1;if(sa0)sd_grants=sd_grants+1;
   #0.001;
   if({ra0,rb0,rdata0,rvalid0,wa0,wb0,sa0,sb0,sdata0,svalid0,req0,mw0,addr0,data0,strb0,ws0,rs0}!=={ra1,rb1,rdata1,rvalid1,wa1,wb1,sa1,sb1,sdata1,svalid1,req1,mw1,addr1,data1,strb1,ws1,rs1})begin $display("[FAIL] arbiter compact changed public behavior N=%0d cycle=%0d",N,cycle); $finish; end 
  end
 end
 initial begin
  repeat(4)@(negedge clk);rn=1;rd=1;
  repeat(200000)@(negedge clk);
  if(dut0.consec_cnt<=15||dut1.consec_cnt<N)begin $display("[FAIL] saturation coverage"); $finish; end 
  wr=1;sd=1;repeat(100000)@(negedge clk);
  if(reads<10000||writes<100||sd_grants<100)begin $display("[FAIL] grant coverage"); $finish; end 
  $display("PASS compact arbiter N=%0d compared=300000 cycles read=%0d write=%0d sd=%0d",N,reads,writes,sd_grants);
  done=1;
 end
endmodule
module tb_memory_arbiter_compact;
 wire [2:0] done;
 arb_compact_case #(.N(1)) a(done[0]);arb_compact_case #(.N(4)) b(done[1]);arb_compact_case #(.N(8)) c(done[2]);
 initial begin wait(&done);$display("PASS tb_memory_arbiter_compact exact public-output equivalence");$finish;end
 initial begin #3000000;begin $display("[FAIL] compact watchdog"); $finish; end end
endmodule
