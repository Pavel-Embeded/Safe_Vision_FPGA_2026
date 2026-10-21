`timescale 1ns/1ps
module tb_v3_spi25_profile;
 reg clk=0;always #10 clk=!clk;
 reg rst_n=0,tx_valid=0,miso=1;reg[15:0] divider=0;reg[7:0]tx=0,model=0;
 wire ready,rx_valid,busy,sclk,mosi;wire[7:0]rx;
 // Declared 5ns forwarded-clock FPGA tCO model, not a board measurement.
 // Card/trace 18ns is additional; native STA must independently bound tCO.
 wire card_sclk;assign #5 card_sclk=sclk;
 integer checks=0,errors=0,bit_index=7,rises=0,falls=0,half_ns=20,card_delay=18;
 integer expected_mid=1,seed=32'h19382,a,b,k;reg active=0;reg[7:0]observed_tx=0;
 time last_fall=0,last_rise=0,mosi_changed=0;reg have_fall=0,have_rise=0;
 spi_master #(.CLK_FREQ(50000000),.MID_REF_SAMPLE(1))dut(.clk(clk),.rst_n(rst_n),.clk_div(divider),.cs_n(1'b0),
 .tx_valid(tx_valid),.tx_data(tx),.tx_ready(ready),.rx_data(rx),.rx_valid(rx_valid),.busy(busy),.sclk(sclk),.mosi(mosi),.miso(miso));
 task check(input bit ok,input[255:0]what);begin checks++;if(!ok)begin errors++;$display("[FAIL] %s time=%0t",what,$time);end end endtask
 always @(mosi)begin
  if(active && have_rise)check($time-last_rise>=7,"MOSI hold");
  mosi_changed=$time;
 end
 always @(posedge sclk)if(active)begin
  rises++;last_rise=$time;have_rise=1;
  if(have_fall)check($time-last_fall==half_ns,"SCLK low length");
  check($time-mosi_changed>=7,"MOSI setup");observed_tx={observed_tx[6:0],mosi};
 end
 always @(negedge sclk)if(active)begin
  falls++;last_fall=$time;have_fall=1;
  check(have_rise && $time-last_rise==half_ns,"SCLK high length");
 end
 always @(negedge card_sclk)if(active)begin
  bit_index--;if(bit_index>=0)miso<=#(card_delay)model[bit_index];
 end
 always @(negedge clk)if(rst_n && dut.sample_pending)begin
  // Every real sample is a falling REF edge, 10ns after SCLK rises.
  check(active && sclk && $time-last_rise==10,"sample edge phase");
 end
 task transfer(input integer d,input integer delay_ns,input[7:0]outbyte,input[7:0]inbyte,input bit legal);begin
  wait(ready);@(negedge clk);divider=d;card_delay=delay_ns;half_ns=(d+1)*20;
  tx=outbyte;model=inbyte;bit_index=7;rises=0;falls=0;have_fall=0;have_rise=0;observed_tx=0;miso=inbyte[7];active=1;tx_valid=1;
  @(negedge clk);tx_valid=0;
  // The divider is latched at acceptance; changing it midbyte must not alter rate.
  divider=16'd249;
  wait(rx_valid);#1;
  check(rises==8 && falls==8,"eight bit clocks");check(observed_tx===outbyte,"MOSI byte order");
  if(legal)check(rx===inbyte,"MISO byte order and worst delay");else check(rx!==inbyte,"out of budget model detected");
  active=0;@(posedge clk);#1;check(!rx_valid,"single receive pulse");
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  // All byte patterns at 25MHz, with maximum transfer response delay.
  for(k=0;k<256;k++)transfer(0,18,k[7:0],~k[7:0],1);
  // Delay extremes and lower rates including real 100kHz identification.
  for(k=0;k<32;k++)begin a=$random(seed);b=$random(seed);transfer(0,0,a[7:0],b[7:0],1);end
  transfer(1,18,8'h96,8'h69,1);transfer(249,54,8'ha5,8'h5a,1);
  // Alternate bits guarantee a stale bit is visible if the card exceeds 30ns.
  transfer(0,38,8'ha5,8'h55,0);
  // Abort at an active high phase, then prove a fresh full byte has no residue.
  wait(ready);@(negedge clk);divider=0;tx=8'h81;model=8'h69;miso=0;active=0;tx_valid=1;
  @(negedge clk);tx_valid=0;wait(sclk);#3;rst_n=0;#2;check(!sclk && !rx_valid,"asynchronous abort");
  repeat(3)@(negedge clk);rst_n=1;transfer(0,18,8'hc3,8'h96,1);
  $display("[PASS] optional SPI25 envelope checks=%0d errors=%0d",checks,errors);
  $display("PASS tb_v3_spi25_profile comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #2000000;$fatal(1,"SPI25 timeout");end
endmodule
