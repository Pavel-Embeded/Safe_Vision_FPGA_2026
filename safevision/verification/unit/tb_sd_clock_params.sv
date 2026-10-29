`timescale 1ns/1ps
module sd_clock_param_case #(parameter integer CLK_HZ=125_000_000)(output reg done=0);
    localparam [15:0] INIT_DIV=(CLK_HZ+799999)/800000-1;
    localparam [15:0] FAST_DIV=(CLK_HZ+49999999)/50000000-1;
    reg clk=0;always #(500000000.0/CLK_HZ)clk=~clk;
    reg rst_n=0,start=0,rd_en=0;
    wire init_done,init_error,sdhc,init_cs,rd_cs,ready;
    wire [15:0] init_div,rd_div;wire iv,rv,tx_ready,rx_valid;
    wire [7:0] id,rd,rx_data,sector_data;wire sector_valid,sector_done,to_error,crc_error;
    wire sclk,mosi,miso;wire [7:0] byte_data=init_done?rd:id;
    wire byte_valid=init_done?rv:iv;wire [15:0] divider=init_done?rd_div:init_div;
    wire cs=init_cs&rd_cs;
    sd_initializer #(.CLK_DIV_INIT(INIT_DIV)) init(
      .clk(clk),.rst_n(rst_n),.start(start),.sdhc(sdhc),.init_done(init_done),.init_error(init_error),
      .err_code(),.err_detail(),.retry_cnt(),.dbg_state(),.spi_cs_n(init_cs),.spi_clk_div(init_div),
      .spi_tx_valid(iv),.spi_tx_data(id),.spi_tx_ready(tx_ready),.spi_rx_data(rx_data),.spi_rx_valid(rx_valid));
    sd_sector_reader #(.CLK_DIV_FAST(FAST_DIV)) reader(
      .clk(clk),.rst_n(rst_n),.sdhc(sdhc),.rd_en(rd_en),.rd_addr(32'd0),.rd_len(16'd1),.rd_ready(ready),
      .data(sector_data),.data_valid(sector_valid),.data_ready(1'b1),.data_last(),.rd_done(sector_done),.busy(),
      .timeout_err(to_error),.crc16_err(crc_error),.err_code(),.err_detail(),.crc_rx(),.dbg_state(),
      .spi_cs_n(rd_cs),.spi_clk_div(rd_div),.spi_tx_valid(rv),.spi_tx_data(rd),.spi_tx_ready(tx_ready),
      .spi_rx_data(rx_data),.spi_rx_valid(rx_valid));
    spi_master #(.CLK_FREQ(CLK_HZ)) spi(.clk(clk),.rst_n(rst_n),.clk_div(divider),.cs_n(cs),
      .tx_valid(byte_valid),.tx_data(byte_data),.tx_ready(tx_ready),.rx_data(rx_data),.rx_valid(rx_valid),
      .busy(),.sclk(sclk),.mosi(mosi),.miso(miso));
    sd_spi_card_model card(.sclk(sclk),.cs_n(cs),.mosi(mosi),.miso(miso),.i_dead(1'b0),
      .o_cmd(),.o_arg(),.o_acmd41_arg(),.o_cmd_cnt(),.o_acmd41_cnt(),.o_cmd_valid());
    realtime previous_edge=0,period_ns;
    reg previous_phase=0;
    integer init_periods=0,data_periods=0,bytes=0;
    always @(posedge sclk)begin
      if(rst_n && previous_edge>0 && previous_phase==init_done)begin
        period_ns=$realtime-previous_edge;
        if(!init_done)begin
          if(period_ns<2499.9)$fatal(1,"initialization clock exceeds400kHz CLK_HZ=%0d",CLK_HZ);
          init_periods=init_periods+1;
        end else begin
          if(period_ns<39.9)$fatal(1,"data clock exceeds25MHz CLK_HZ=%0d",CLK_HZ);
          data_periods=data_periods+1;
        end
      end
      previous_phase=init_done;previous_edge=$realtime;
    end
    always @(posedge clk)if(rst_n && sector_valid)begin
      if(sector_data!==8'((bytes&255)+17))$fatal(1,"sector mismatch");
      bytes=bytes+1;
    end
    initial begin
      repeat(4)@(negedge clk);rst_n=1;
      @(negedge clk);start=1;@(negedge clk);start=0;
      wait(init_done || init_error);
      if(init_error || init_div!==INIT_DIV || rd_div!==FAST_DIV)$fatal(1,"divider/init mismatch");
      wait(ready);@(negedge clk);rd_en=1;@(negedge clk);rd_en=0;
      wait(sector_done);@(negedge clk);
      if(bytes!=512 || to_error || crc_error || init_periods<74 || data_periods<4096)$fatal(1,"incomplete SD clock/sector test");
      $display("[PASS] SD clk=%0d init_div=%0d fast_div=%0d bytes=%0d init_edges=%0d data_edges=%0d",CLK_HZ,INIT_DIV,FAST_DIV,bytes,init_periods,data_periods);
      done=1;
    end
endmodule
module tb_sd_clock_params;
    wire d50,d100,d125;
    sd_clock_param_case #(.CLK_HZ(50_000_000)) c50(d50);
    sd_clock_param_case #(.CLK_HZ(100_000_000)) c100(d100);
    sd_clock_param_case #(.CLK_HZ(125_000_000)) c125(d125);
    initial begin wait(d50&&d100&&d125);$display("PASS tb_sd_clock_params: 50/100/125MHz real SD initialization + sector CRC + SCLK limits");$finish;end
    initial begin #20_000_000;$fatal(1,"SD clock parameter watchdog");end
endmodule
