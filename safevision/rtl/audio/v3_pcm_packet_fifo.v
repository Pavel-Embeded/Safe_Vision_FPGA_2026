// Lossless 48-bit PCM packet crossing through one official TD 16-bit FIFO.
// The audio writer reserves room for all three words before accepting a pair.
// Both packers and the vendor FIFO share one global reset assertion epoch.
// Media reset must NOT reset this path: the ROM alarm cadence remains active.
module v3_pcm_packet_fifo(input wire rst,wr_clk,rd_clk,input wire[47:0] wr_data,
 input wire wr_valid,output wire wr_ready,output reg[47:0] rd_data,output reg rd_valid);
 wire wr_rst_n,rd_rst_n;
 v3_audio_reset_release wr_reset(.clk(wr_clk),.assert_reset(rst),.rst_n(wr_rst_n));
 v3_audio_reset_release rd_reset(.clk(rd_clk),.assert_reset(rst),.rst_n(rd_rst_n));
 reg[47:0] pending;reg[1:0] write_part;reg holding;
 wire fifo_ready,fifo_valid;wire[7:0] write_level;wire[15:0] fifo_data;
 assign wr_ready=wr_rst_n&&!holding&&fifo_ready&&write_level<=8'd252;
 sv_async_fifo #(.WIDTH(16),.AW(8)) q(.rst(rst),.wr_clk(wr_clk),.rd_clk(rd_clk),
 .wr_data(pending[15:0]),.wr_valid(holding),.wr_ready(fifo_ready),.wr_level(write_level),
 .rd_data(fifo_data),.rd_valid(fifo_valid),.rd_ready(rd_rst_n));
 always @(posedge wr_clk or negedge wr_rst_n)begin
  if(!wr_rst_n)begin pending<=0;write_part<=0;holding<=0;end
  else if(wr_valid&&wr_ready)begin pending<=wr_data;write_part<=0;holding<=1;end
  else if(holding&&fifo_ready)begin
   pending<=pending>>16;
   if(write_part==2)holding<=0;else write_part<=write_part+1'b1;
  end
 end
 reg[1:0] read_part;reg[31:0] low_words;
 always @(posedge rd_clk or negedge rd_rst_n)begin
  if(!rd_rst_n)begin read_part<=0;low_words<=0;rd_data<=0;rd_valid<=0;end
  else begin rd_valid<=0;
   if(fifo_valid)case(read_part)
    0:begin low_words[15:0]<=fifo_data;read_part<=1;end
    1:begin low_words[31:16]<=fifo_data;read_part<=2;end
    2:begin rd_data<={fifo_data,low_words};rd_valid<=1;read_part<=0;end
    default:read_part<=0;
   endcase
  end
 end
endmodule
