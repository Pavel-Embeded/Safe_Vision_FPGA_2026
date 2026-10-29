`timescale 1ns/1ps
module tb_v3_checked_sector;
 reg clk=0;always #10 clk=~clk;reg rst=0,en=0,corrupt=0;reg[31:0] address=17;reg[15:0] length=1;
 wire ready,valid,last,done,busy,to,crc,cs,sclk,mosi,miso,txv,txready,rxv,spibusy;
 wire[7:0] data,ec,ed,txdata,rxdata;wire[15:0] div,rxcrc;wire[3:0] state;
 integer cycles=0,count=0,errors=0,checks=0,guard,injected=0;
 wire take=cycles%32<21;reg stalled=0;reg[7:0] stalled_data;reg stalled_last;
 always @(posedge clk)cycles<=cycles+1;
 sd_checked_sector_reader #(.CLK_DIV_FAST(0)) reader(
 .clk(clk),.rst_n(rst),.sdhc(1'b1),.rd_en(en),.rd_addr(address),.rd_len(length),.rd_ready(ready),
 .data(data),.data_valid(valid),.data_ready(take),.data_last(last),.rd_done(done),.busy(busy),
 .timeout_err(to),.crc16_err(crc),.err_code(ec),.err_detail(ed),.crc_rx(rxcrc),.dbg_state(state),
 .spi_cs_n(cs),.spi_clk_div(div),.spi_tx_valid(txv),.spi_tx_data(txdata),.spi_tx_ready(txready),.spi_rx_data(rxdata),.spi_rx_valid(rxv));
 spi_master #(.CLK_FREQ(50000000)) spi(.clk(clk),.rst_n(rst),.clk_div(div),.cs_n(cs),
 .tx_valid(txv),.tx_data(txdata),.tx_ready(txready),.rx_data(rxdata),.rx_valid(rxv),.busy(spibusy),
 .sclk(sclk),.mosi(mosi),.miso(miso));
 wire[5:0] cmd;wire cv;
 sd_spi_card_model card(.sclk(sclk),.cs_n(cs),.mosi(mosi),.miso(miso),.i_dead(1'b0),
 .o_cmd(cmd),.o_arg(),.o_acmd41_arg(),.o_cmd_cnt(),.o_acmd41_cnt(),.o_cmd_valid(cv));

 always @(posedge cv)if(cmd==17 && corrupt)begin #1;card.crc_val=card.crc_val^16'h1;injected=injected+1;end
 task ck;input c;input[511:0] msg;begin checks=checks+1;
 if(c)$display("[PASS] %s",msg);else begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 always @(posedge clk)if(rst)begin
  if(valid && !cs)begin errors=errors+1;$display("[FAIL] published before CRC/CS transaction completion");end
  if(stalled && (!valid || data!==stalled_data || last!==stalled_last))begin errors=errors+1;$display("[FAIL] stalled output changed");end
  stalled=valid&&!take;stalled_data=data;stalled_last=last;
  if(valid && take)begin
   if(data!==((count+17)&255) || last!==(count==511))begin errors=errors+1;$display("[FAIL] output byte or last identity at %0d",count);end
   count=count+1;
  end
 end
 task transaction;input bad;begin
  while(!ready)@(negedge clk);count=0;corrupt=bad;en=1;@(negedge clk);en=0;
  guard=0;while(!done && guard<100000)begin @(negedge clk);guard=guard+1;end
  ck(done,"bounded checked-sector completion");
  if(bad)begin
   ck(crc && !to && {ec,ed}==16'h0222,"CRC failure exposes correct code and detail");
   ck(count==0,"bad sector publishes zero bytes to all consumers");
  end else begin ck(!crc && !to && ec==0,"successful checked sector clears previous error");
   ck(count==512,"all 512 bytes delivered exactly once through backpressure");end
  repeat(8)@(negedge clk);
 end endtask
 initial begin
 repeat(5)@(negedge clk);rst=1;transaction(0);transaction(1);transaction(0);
 ck(injected==1,"exactly one faulty card transaction injected");
 $display("PASS tb_v3_checked_sector errors=%0d comparisons=%0d",errors,1024);$finish;end
 initial begin #7000000;$display("[FAIL] global timeout");$finish;end
endmodule
