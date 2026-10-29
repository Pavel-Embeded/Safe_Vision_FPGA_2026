


module v3_pcm_sample_fifo(input wire rst,wr_clk,rd_clk,input wire[39:0] wr_data,
 input wire wr_valid,output wire wr_ready,output wire[8:0] wr_pairs,
 output wire[39:0] rd_data,output wire rd_valid,input wire rd_ready);
 wire wr_rst_n,rd_rst_n;
 v3_audio_reset_release wr_reset(.clk(wr_clk),.assert_reset(rst),.rst_n(wr_rst_n));
 v3_audio_reset_release rd_reset(.clk(rd_clk),.assert_reset(rst),.rst_n(rd_rst_n));
 reg[1:0] write_part;wire holding=write_part!=0;
 wire fifo_ready,fifo_valid;wire[9:0] words;wire[15:0] fifo_data;

 wire[20:0] pair_credit_product=words*10'd683+21'd1366;
 wire[8:0] pair_credit=pair_credit_product[19:11];
 wire fifo_write=wr_rst_n&&wr_valid&&(write_part!=0||words<=10'd1020);
 wire[15:0] word_data=write_part==0?wr_data[15:0]:(write_part==1?wr_data[31:16]:{8'd0,wr_data[39:32]});
 assign wr_pairs=pair_credit+(write_part!=0);
 assign wr_ready=wr_rst_n&&write_part==2&&fifo_ready;
 reg[1:0] read_part;reg[31:0] low_words;
 sv_async_fifo #(.WIDTH(16),.AW(10)) q(.rst(rst),.wr_clk(wr_clk),.rd_clk(rd_clk),
 .wr_data(word_data),.wr_valid(fifo_write),.wr_ready(fifo_ready),.wr_level(words),
 .rd_data(fifo_data),.rd_valid(fifo_valid),.rd_ready(rd_rst_n&&(read_part==2?rd_ready:1'b1)));
 always @(posedge wr_clk or negedge wr_rst_n)begin
  if(!wr_rst_n)write_part<=0;
  else if(fifo_write&&fifo_ready)begin if(write_part==2)write_part<=0;else write_part<=write_part+1'b1;end
 end

 assign rd_data={fifo_data[7:0],low_words};assign rd_valid=rd_rst_n&&read_part==2&&fifo_valid;
 always @(posedge rd_clk or negedge rd_rst_n)begin
  if(!rd_rst_n)begin read_part<=0;low_words<=0;end
  else if(fifo_valid)case(read_part)
   0:begin low_words[15:0]<=fifo_data;read_part<=1;end
   1:begin low_words[31:16]<=fifo_data;read_part<=2;end
   2:if(rd_ready)read_part<=0;
   default:read_part<=0;
  endcase
 end
endmodule
