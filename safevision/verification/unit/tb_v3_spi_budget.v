`timescale 1ns/1ps
module tb_v3_spi_budget;
 reg clk=0;always #10 clk=!clk;reg rst_n=0,tx_valid=0,miso=1;reg[15:0] div=1;reg[7:0] tx=8'ha5,model=8'h96;
 wire ready,rx_valid,busy,sclk,mosi;wire[7:0] rx;integer bit_index,card_delay=18,half_ns=40,checks=0,errors=0;
 time last_fall,last_rise,mosi_changed;
 spi_master #(.CLK_FREQ(50000000)) dut(.clk(clk),.rst_n(rst_n),.clk_div(div),.cs_n(1'b0),
 .tx_valid(tx_valid),.tx_data(tx),.tx_ready(ready),.rx_data(rx),.rx_valid(rx_valid),.busy(busy),.sclk(sclk),.mosi(mosi),.miso(miso));
 always @(mosi)begin
  if(rst_n && busy && last_rise!=0)begin
   checks = checks + 1;if($time-last_rise<7)begin errors = errors + 1;$display("[FAIL] MOSI hold below card+trace allowance");end
  end
  mosi_changed=$time;
 end
 always @(negedge sclk)if(rst_n && busy)begin
  if(last_rise!=0)begin checks = checks + 1;if($time-last_rise!=half_ns)begin errors = errors + 1;$display("[FAIL] SCLK high duration");end end
  last_fall=$time;bit_index=bit_index-1;
  if(bit_index>=0)miso<=#(card_delay)model[bit_index];
 end
 always @(posedge sclk)if(rst_n && busy)begin
  last_rise=$time;
  if(last_fall!=0)begin checks = checks + 1;if($time-last_fall!=half_ns)begin errors = errors + 1;$display("[FAIL] enabled receive edge does not match multicycle");end end
  checks = checks + 1;if($time-mosi_changed<7)begin errors = errors + 1;$display("[FAIL] MOSI setup below card+trace allowance");end
 end
 task transfer(input integer d,input integer delay_ns,input  legal);begin begin
 legal = (legal === 1'b1); wait(ready);@(negedge clk);div=d;card_delay=delay_ns;half_ns=(d+1)*20;bit_index=7;miso=model[7];last_fall=0;last_rise=0;
 tx_valid=1;@(negedge clk);tx_valid=0;wait(rx_valid);#1;checks = checks + 1;
 if(legal && rx!==model)begin errors = errors + 1;$display("[FAIL] legal response delay rx=%h expected=%h",rx,model);end
 if(!legal && rx===model)begin errors = errors + 1;$display("[FAIL] out-of-budget negative control was not detected");end
 @(negedge clk);
 end  end endtask
 initial begin repeat(4)@(negedge clk);rst_n=1;
 transfer(1,0,1);transfer(1,18,1);transfer(249,54,1);transfer(1,60,0);
 $display("[PASS] SPI electrical envelope and negative control checks=%0d errors=%0d",checks,errors);
 $display("PASS tb_v3_spi_budget comparisons=%0d errors=%0d",checks,errors);$finish;end
 initial begin #1000000;begin $display("[FAIL] SPI budget timeout"); $finish; end end
endmodule
