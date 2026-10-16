// One stereo PCM32 pair becomes two ordered 16bit words in official TD FIFO.
// AW9=511 usable words: >=255pairs. The scheduler grants a new SD sector ONLY
// with no partial writer packet and <=252 occupied words, reserving >=259 words
// for all128pairs of a512byte sector plus pipeline margin. No halfpair is exposed.
module v3_pcm_ingress_fifo(input wire rst,wr_clk,rd_clk,input wire[31:0] wr_data,
 input wire wr_valid,output wire wr_ready,output wire[8:0] wr_pairs,output wire sector_room,
 output wire[31:0] rd_data,output wire rd_valid,input wire rd_ready);
 wire wr_rst_n,rd_rst_n;
 v3_audio_reset_release wr_reset(.clk(wr_clk),.assert_reset(rst),.rst_n(wr_rst_n));
 v3_audio_reset_release rd_reset(.clk(rd_clk),.assert_reset(rst),.rst_n(rd_rst_n));
 reg write_part;wire holding=write_part;
 wire fifo_ready,fifo_valid;wire[8:0] words;wire[15:0] fifo_data;
 // Upstream holds valid/data until the HIGH word is accepted. No pair copy.
 wire fifo_write=wr_rst_n&&wr_valid&&(write_part||words<=9'd509);
 assign wr_ready=wr_rst_n&&write_part&&fifo_ready;
 assign wr_pairs={1'b0,words[8:1]}+words[0]+write_part;
 assign sector_room=wr_rst_n&&!write_part&&words<=9'd252;
 reg read_part;reg[15:0] low_word;
 sv_async_fifo #(.WIDTH(16),.AW(9)) q(.rst(rst),.wr_clk(wr_clk),.rd_clk(rd_clk),
 .wr_data(write_part?wr_data[31:16]:wr_data[15:0]),.wr_valid(fifo_write),.wr_ready(fifo_ready),.wr_level(words),
 .rd_data(fifo_data),.rd_valid(fifo_valid),.rd_ready(rd_rst_n&&(read_part?rd_ready:1'b1)));
 always @(posedge wr_clk or negedge wr_rst_n)begin
  if(!wr_rst_n)write_part<=0;else if(fifo_write&&fifo_ready)write_part<=~write_part;
 end
 // Keep the HIGH word at the FIFO head until MEM accepts the complete pair.
 assign rd_data={fifo_data,low_word};assign rd_valid=rd_rst_n&&read_part&&fifo_valid;
 always @(posedge rd_clk or negedge rd_rst_n)begin
  if(!rd_rst_n)begin read_part<=0;low_word<=0;end
  else if(fifo_valid)begin
   if(!read_part)begin low_word<=fifo_data;read_part<=1;end
   else if(rd_ready)read_part<=0;
  end
 end
endmodule
