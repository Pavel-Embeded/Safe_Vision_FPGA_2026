// REF -> MEM single source, tagged four-track queue. One source track is active
// at a time; valid/data remain held until the THIRD 16-bit word is accepted.
// Full 512-byte PCM sector = 128 pairs = 384 FIFO words. Admit a sector only
// at a group boundary and <=632/1023 words, reserving >=391 = 384+7 words.
// MEM retains the tag at FIFO head until the ring accepts the entire pair.
// This queue is valid for V3 bounded prefill (<~1.5k/track << ring CAP16384).
// A generic permanently-full destination could cause head-of-line blocking.
module v3_pcm_ingress_shared_fifo(
 input wire rst,wr_clk,rd_clk,input wire[127:0] wr_data,input wire[3:0] wr_valid,
 output wire[3:0] wr_ready,output wire[8:0] wr_pairs,output wire sector_room,
 output wire[10:0] wr_words,output wire wr_partial,
 output wire[127:0] rd_data,output wire[3:0] rd_valid,input wire[3:0] rd_ready);
 wire wr_rst_n,rd_rst_n;
 v3_audio_reset_release wr_reset(.clk(wr_clk),.assert_reset(rst),.rst_n(wr_rst_n));
 v3_audio_reset_release rd_reset(.clk(rd_clk),.assert_reset(rst),.rst_n(rd_rst_n));
 reg[1:0] write_part,read_part;reg[31:0] low_words;
 reg[1:0] selected;reg[31:0] selected_data;
 always @*begin
  selected=0;selected_data=wr_data[31:0];
  case(wr_valid)
   4'b0010:begin selected=1;selected_data=wr_data[63:32];end
   4'b0100:begin selected=2;selected_data=wr_data[95:64];end
   4'b1000:begin selected=3;selected_data=wr_data[127:96];end
   default:begin selected=0;selected_data=wr_data[31:0];end
  endcase
 end
 wire[15:0] fifo_wdata=(write_part==0)?selected_data[15:0]:(write_part==1)?selected_data[31:16]:{14'd0,selected};
 wire fifo_wr_ready,fifo_rd_valid;wire[15:0] fifo_data;wire[9:0] words;
 wire[10:0] rounded_words={1'b0,words}+11'd2;
 wire fifo_wr_valid=wr_rst_n&&(|wr_valid);
 wire fifo_rd_ready=rd_rst_n&&((read_part!=2)||rd_ready[fifo_data[1:0]]);
 assign wr_ready=(wr_rst_n&&write_part==2&&fifo_wr_ready)?wr_valid:4'd0;
 assign wr_pairs=(rounded_words/3)+(write_part!=0);
 assign wr_words={1'b0,words};
 assign wr_partial=(write_part!=0);
 assign sector_room=wr_rst_n&&write_part==0&&words<=11'd632;
 assign rd_data={4{low_words}};
 assign rd_valid=(rd_rst_n&&read_part==2&&fifo_rd_valid)?(4'b1<<fifo_data[1:0]):4'd0;
 sv_async_fifo #(.WIDTH(16),.AW(10)) q(.rst(rst),.wr_clk(wr_clk),.wr_data(fifo_wdata),
 .wr_valid(fifo_wr_valid),.wr_ready(fifo_wr_ready),.wr_level(words),.rd_clk(rd_clk),
 .rd_data(fifo_data),.rd_valid(fifo_rd_valid),.rd_ready(fifo_rd_ready),.rd_level());
 always @(posedge wr_clk or negedge wr_rst_n)
  if(!wr_rst_n)write_part<=0;
  else if(fifo_wr_valid&&fifo_wr_ready)begin
   if(write_part==2)write_part<=0;else write_part<=write_part+1'b1;
  end
 always @(posedge rd_clk or negedge rd_rst_n)
  if(!rd_rst_n)begin read_part<=0;low_words<=0;end
  else if(fifo_rd_valid&&fifo_rd_ready)begin
   if(read_part==0)begin low_words[15:0]<=fifo_data;read_part<=1;end
   else if(read_part==1)begin low_words[31:16]<=fifo_data;read_part<=2;end
   else read_part<=0;
  end
 // synthesis translate_off
 reg[131:0] held_input;
 always @(posedge wr_clk)if(wr_rst_n)begin
  if(wr_valid!=0&&(wr_valid&(wr_valid-1'b1))!=0)$fatal(1,"tagged ingress requires one active source");
  if(write_part!=0&&{wr_valid,wr_data}!==held_input)$fatal(1,"tagged ingress source changed before third-word acceptance");
  held_input<={wr_valid,wr_data};
 end
 always @(posedge rd_clk)if(rd_rst_n&&read_part==2&&fifo_rd_valid&&fifo_data[15:2]!=0)
  $fatal(1,"tagged ingress invalid slot padding");
 // synthesis translate_on
endmodule
