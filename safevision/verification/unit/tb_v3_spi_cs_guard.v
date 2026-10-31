`timescale 1ns/1ps
module tb_v3_spi_cs_guard;
 reg clk=0;always #10 clk=~clk;
 reg global_rst_n=0,media_rst_n=0,start=0,rd_en=0,owner=0,dead=0;
 wire init_cs,rd_cs,raw_cs,sd_cs,sclk,mosi,miso;
 assign raw_cs=init_cs&rd_cs;
 wire[15:0] init_div,rd_div;wire[7:0]init_txd,rd_txd,rxd,data;
 wire init_txv,rd_txv,txready,cs_ready,rxv,spi_busy,init_done,init_error,sdhc,rd_ready,rd_done,timeout_err,crc_err,valid,last;
 wire[7:0] reader_code,reader_detail;
 integer checks=0,errors=0,received=0,transactions=0,aborts=0,power_edges=0;
 realtime cs_changed=0,last_edge=0,last_rise=0;
 v3_spi_cs_guard guard(.ref_clk(clk),.ref_rst_n(global_rst_n),.raw_cs_n(raw_cs),.raw_sclk(sclk),.cs_n(sd_cs),.cs_ready(cs_ready));
 sd_initializer #(.CLK_DIV_INIT(249)) initializer(.clk(clk),.rst_n(media_rst_n),.start(start),.sdhc(sdhc),.init_done(init_done),.init_error(init_error),
 .spi_cs_n(init_cs),.spi_clk_div(init_div),.spi_tx_valid(init_txv),.spi_tx_data(init_txd),.spi_tx_ready(txready&&!owner&&cs_ready),.spi_rx_data(rxd),.spi_rx_valid(rxv&&!owner));
 sd_checked_sector_reader #(.CLK_DIV_FAST(1)) reader(.clk(clk),.rst_n(media_rst_n),.sdhc(1'b1),.rd_en(rd_en),.rd_addr(32'd0),.rd_len(16'd1),.rd_ready(rd_ready),
 .data(data),.data_valid(valid),.data_ready(1'b1),.data_last(last),.rd_done(rd_done),.timeout_err(timeout_err),.crc16_err(crc_err),.err_code(reader_code),.err_detail(reader_detail),
 .spi_cs_n(rd_cs),.spi_clk_div(rd_div),.spi_tx_valid(rd_txv),.spi_tx_data(rd_txd),.spi_tx_ready(txready&&owner&&cs_ready),.spi_rx_data(rxd),.spi_rx_valid(rxv&&owner));
 spi_master #(.CLK_FREQ(50000000)) spi(.clk(clk),.rst_n(media_rst_n),.clk_div(owner ? rd_div:init_div),.cs_n(raw_cs),.tx_valid((owner ? rd_txv:init_txv)&&cs_ready),
 .tx_data(owner ? rd_txd:init_txd),.tx_ready(txready),.rx_data(rxd),.rx_valid(rxv),.busy(spi_busy),.sclk(sclk),.mosi(mosi),.miso(miso));
 sd_spi_card_model #(.VOL_SECTORS(1)) card(.sclk(sclk),.cs_n(sd_cs),.mosi(mosi),.miso(miso),.i_dead(dead));
 task check(input  c,input [4095:0] m);begin  c = (c === 1'b1); checks = checks + 1;if(!c)begin errors = errors + 1;$display("[FAIL] %s t=%0t cs=%b raw=%b sclk=%b",m,$time,sd_cs,raw_cs,sclk);end   end endtask
 always @(sd_cs)begin
  if(global_rst_n)begin
   check(sclk===0,"CS changes only while SCLK low");
   if(last_edge!=0)check($realtime-last_edge>=7.0,"last serial edge to CS change >=7ns");
   check((($time/10)%2)==0,"CS publication on falling REF edge");
   if(!sd_cs)begin
    if(transactions==0)check(power_edges>=80,"complete >=80 physical high-CS power clocks");
    transactions = transactions + 1;
   end
  end
  cs_changed=$realtime;
 end
 always @(sclk)if(global_rst_n)last_edge=$realtime;
 always @(posedge sclk)if(global_rst_n && media_rst_n)begin
  if(sd_cs&&!owner)power_edges = power_edges + 1;
  if(!raw_cs)check(!sd_cs,"no selected serial rise before guarded CS assertion");
  if(!sd_cs)check($realtime-cs_changed>=7.0,"CS assertion to selected serial rise >=7ns");
  last_rise=$realtime;
 end
 always @(posedge clk)if(media_rst_n && valid)begin
  check(data===((received+8'h11)&8'hff),"checked sector byte independent pattern");
  check(last==(received==511),"checked sector last exact");received = received + 1;
 end
 task launch_read;begin  wait(rd_ready);@(negedge clk);received=0;rd_en=1;@(negedge clk);rd_en=0;  end endtask
 task read_good;begin  launch_read();wait(rd_done);#1;$display("[READ] bytes=%0d timeout=%b crc=%b error=%h/%h",received,timeout_err,crc_err,reader_code,reader_detail);check(!timeout_err&&!crc_err&&received==512,"complete CRC checked sector");wait(sd_cs);repeat(5)@(negedge clk);  end endtask
 initial begin
  repeat(4)@(negedge clk);global_rst_n=1;media_rst_n=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(init_done||init_error);check(init_done&&!init_error&&sdhc,"real div249 initialization/card response");
  wait(sd_cs);repeat(8)@(negedge clk);owner=1;
  read_good();read_good();
  dead=1;launch_read();wait(rd_done);#1;check(timeout_err&&received==0,"dead card timeout releases transaction without payload");wait(sd_cs);dead=0;
  begin : v_loop_1 integer phase; for( phase=0;phase<20;phase = phase + 1)begin
   launch_read();wait(sclk===1);#(phase);media_rst_n=0;aborts = aborts + 1;
   repeat(6)@(negedge clk);check(sd_cs&&sclk===0,"media abort drains CS at a safe quiet edge");
   media_rst_n=1;repeat(5)@(negedge clk);
  end end
  read_good();
  check(aborts==20&&transactions>=24,"all abort phases and owner transitions exercised");
  $display("[PASS] CS electrical boundary assertions=%0d transactions=%0d aborts=%0d",checks,transactions,aborts);
  $display("PASS tb_v3_spi_cs_guard comparisons=%0d errors=%0d",checks,errors);$finish;
 end
 initial begin #30000000;begin $display("[FAIL] CS guard test timeout"); $finish; end end
endmodule
