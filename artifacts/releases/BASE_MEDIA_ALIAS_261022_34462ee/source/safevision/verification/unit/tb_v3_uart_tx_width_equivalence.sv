`timescale 1ns/1ps
module v3_tx_width_case #(parameter integer DIV=868)(input wire clk,rst,valid,input wire[7:0]data,output wire equal_pins);
 wire ar,br,at,bt;
 uart_tx #(.CLK_FREQ(DIV),.BAUD(1)) a(clk,rst,valid,data,ar,at);
 v3_uart_tx_reference #(.CLK_FREQ(DIV),.BAUD(1)) b(clk,rst,valid,data,br,bt);
 assign equal_pins={ar,at}==={br,bt};
endmodule
module tb_v3_uart_tx_width_equivalence;
 reg clk=0,rst=0,valid=0;reg[7:0]data=0;always #5 clk=~clk;
 wire[9:0]same;integer errors=0,comparisons=0,k;reg[31:0]rng=32'hba261801;
 v3_tx_width_case #(.DIV(0)) c0(clk,rst,valid,data,same[0]);
 v3_tx_width_case #(.DIV(1)) c1(clk,rst,valid,data,same[1]);
 v3_tx_width_case #(.DIV(2)) c2(clk,rst,valid,data,same[2]);
 v3_tx_width_case #(.DIV(3)) c3(clk,rst,valid,data,same[3]);
 v3_tx_width_case #(.DIV(32)) c4(clk,rst,valid,data,same[4]);
 v3_tx_width_case #(.DIV(434)) c5(clk,rst,valid,data,same[5]);
 v3_tx_width_case #(.DIV(868)) c6(clk,rst,valid,data,same[6]);
 v3_tx_width_case #(.DIV(65535)) c7(clk,rst,valid,data,same[7]);
 v3_tx_width_case #(.DIV(65536)) c8(clk,rst,valid,data,same[8]);
 v3_tx_width_case #(.DIV(65537)) c9(clk,rst,valid,data,same[9]);
 always@(posedge clk)begin #1;if(rst)begin comparisons+=20;if(same!==10'h3ff)begin errors++;if(errors<12)$display("[FAIL] UART ready/serial pin edge differs mask=%h at%0d",same,k);end end end
 initial begin
 repeat(4)@(negedge clk);rst=1;
 // First700k cycles include a complete65536-divider frame; then phase-varied
 // asynchronous resets, busy submissions, continuous and back-to-back traffic.
 for(k=0;k<2000000;k++)begin
  rng=rng*1664525+1013904223;valid=k<700000?1:rng[3:0]!=0;data=rng[31:24];
  rst=k<700000||k%100003!=0;@(negedge clk);
 end
 if(errors==0)$display("[PASS] exact public UART edges atDIV0,1,2,3,32,434,868,65535,65536,65537; complete long frame and resets");
 $display("[TB] tb_v3_uart_tx_width_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
