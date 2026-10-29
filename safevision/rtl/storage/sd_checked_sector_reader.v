`include "safevision_defs.vh"


module sd_checked_sector_reader #(parameter[15:0] CLK_DIV_FAST=`SD_DIV_FAST)(
 input wire clk,rst_n,sdhc,rd_en,input wire[31:0] rd_addr,input wire[15:0] rd_len,
 output wire rd_ready,output wire[7:0] data,output wire data_valid,
 input wire data_ready,output wire data_last,output reg rd_done,output wire busy,
 output reg timeout_err,crc16_err,output reg[7:0] err_code,err_detail,
 output reg[15:0] crc_rx,output wire[3:0] dbg_state,
 output wire spi_cs_n,output wire[15:0] spi_clk_div,
 output wire spi_tx_valid,output wire[7:0] spi_tx_data,
 input wire spi_tx_ready,input wire[7:0] spi_rx_data,input wire spi_rx_valid);
 localparam IDLE=0,FILL=1,PRIME=2,SEND=3,RETIRE=4;
 reg[2:0] state;reg raw_start;reg[31:0] address_q;reg[15:0] length_q;
 reg[9:0] filled;reg[8:0] position;
 (* ram_style="block" *) reg[7:0] sector[0:511];
 reg[7:0] read_q;
 wire raw_ready,raw_valid,raw_last,raw_done,raw_timeout,raw_crc;
 wire[7:0] raw_data,raw_code,raw_detail;wire[15:0] raw_crc_rx;
 wire fill_ready=state==FILL && filled<512;
 wire[8:0] read_address=(state==SEND && data_ready)?position+1'b1:position;
 assign rd_ready=state==IDLE && raw_ready;
 assign busy=state!=IDLE || !raw_ready;
 assign data=read_q;assign data_valid=state==SEND;
 assign data_last=state==SEND && position==511;
 assign dbg_state={1'b0,state};

 always @(posedge clk)begin
  if(raw_valid && fill_ready)sector[filled[8:0]]<=raw_data;
  read_q<=sector[read_address];
 end
 sd_sector_reader #(.CLK_DIV_FAST(CLK_DIV_FAST)) raw(
 .clk(clk),.rst_n(rst_n),.sdhc(sdhc),.rd_en(raw_start),.rd_addr(address_q),.rd_len(length_q),.rd_ready(raw_ready),
 .data(raw_data),.data_valid(raw_valid),.data_ready(fill_ready),.data_last(raw_last),
 .rd_done(raw_done),.busy(),.timeout_err(raw_timeout),.crc16_err(raw_crc),.err_code(raw_code),.err_detail(raw_detail),
 .crc_rx(raw_crc_rx),.dbg_state(),.spi_cs_n(spi_cs_n),.spi_clk_div(spi_clk_div),.spi_tx_valid(spi_tx_valid),
 .spi_tx_data(spi_tx_data),.spi_tx_ready(spi_tx_ready),.spi_rx_data(spi_rx_data),.spi_rx_valid(spi_rx_valid));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;raw_start<=0;address_q<=0;length_q<=0;filled<=0;position<=0;
   rd_done<=0;timeout_err<=0;crc16_err<=0;err_code<=0;err_detail<=0;crc_rx<=0;end
  else begin
   raw_start<=0;rd_done<=0;
   case(state)
    IDLE:if(rd_en && rd_ready)begin
     address_q<=rd_addr;length_q<=rd_len;raw_start<=1;state<=FILL;filled<=0;position<=0;
     timeout_err<=0;crc16_err<=0;err_code<=0;err_detail<=0;
    end
    FILL:begin
     if(raw_valid && fill_ready)filled<=filled+1'b1;
     if(raw_done)begin
      crc_rx<=raw_crc_rx;timeout_err<=raw_timeout;crc16_err<=raw_crc;
      err_code<=raw_code;err_detail<=raw_detail;
      if(raw_timeout || raw_crc || raw_code!=0 || filled!=512)begin
       if(raw_code==0)begin err_code<=`ERR_SD_IO;err_detail<=`DET_FS_SHORT;end
       if(filled!=512 && !raw_crc)timeout_err<=1;
       rd_done<=1;state<=IDLE;
      end else begin position<=0;state<=PRIME;end
     end
    end
    PRIME:state<=SEND;
    SEND:if(data_ready)begin
     if(position==511)state<=RETIRE;else position<=position+1'b1;
    end
    RETIRE:begin rd_done<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
