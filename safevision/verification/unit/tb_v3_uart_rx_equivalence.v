`timescale 1ns/1ps
module tb_v3_uart_rx_equivalence;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,rxd=1,ready=0;
 reg[31:0] rng=32'h5ae731c9;integer i,total_errors,total_comparisons;
 wire[31:0] errors[0:2],comparisons[0:2];
 genvar g;generate for(g=0;g<3;g=g+1)begin:rate
  localparam integer HZ=g==0 ? 100000000:(g==1 ? 160000:13500);
  localparam integer BAUD=g==0 ? 115200:(g==1 ? 5000:321);
  wire[72:0] actual,expected;integer errs=0,checks=0;
  assign errors[g]=errs;assign comparisons[g]=checks;
  uart_rx #(.CLK_HZ(HZ),.BAUD(BAUD)) dut(.clk(clk),.rst_n(rst_n),.rxd(rxd),.ready(ready),.data(actual[7:0]),.valid(actual[8]),.frame_errors(actual[40:9]),.overruns(actual[72:41]));
  uart_rx_reference #(.CLK_HZ(HZ),.BAUD(BAUD)) reference(.clk(clk),.rst_n(rst_n),.rxd(rxd),.ready(ready),.data(expected[7:0]),.valid(expected[8]),.frame_errors(expected[40:9]),.overruns(expected[72:41]));
  always @(posedge clk)begin #0.001;if(rst_n)begin
   checks=checks+3;
   if(actual!==expected || dut.tick!==reference.tick || dut.acc!==reference.acc)begin errs=errs+1;if(errs<10)$display("[FAIL] UART public bits/tick/acc differ rate=%0d cycle=%0d",g,i);end
  end end
 end endgenerate
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(i=0;i<150000;i=i+1)begin
   @(negedge clk);rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   rxd=rng[0];ready=(i%32768>=24576);
  end
  #1;total_errors=errors[0]+errors[1]+errors[2];total_comparisons=comparisons[0]+comparisons[1]+comparisons[2];
  if(total_errors==0)$display("[PASS] UART three rates public73 bits, tick and accumulator cycle exact");
  $display("[TB] tb_v3_uart_rx_equivalence done errors=%0d comparisons=%0d",total_errors,total_comparisons);$finish;
 end
 initial begin #2000000;$display("[FAIL] UART oracle watchdog errors=1");$finish;end
endmodule
