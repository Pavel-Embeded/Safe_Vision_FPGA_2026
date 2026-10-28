// Fixed Chinese bitmap strip. Position changes only on frame_start; media
// resets never enter this module. Three one-bit tags retain the production
// 21-clock raw-raster contract without delaying the existing video stream.
module v3_scrolling_ticker #(
 parameter integer WIDTH=640,HEIGHT=480,MESSAGE_CHARS=32,
 parameter integer FRAMES_PER_PIXEL=2,PIXEL_LATENCY=21,
 parameter integer SOURCE_AHEAD=0,CLIP_INPUT=1,EXTERNAL_FONT=0,
 parameter BITMAP_FILE="../../assets/fonts/v3_ticker16.mem",
 parameter integer PACKED_EXTERNAL=0
)(
 input wire clk,rst_n,frame_start,
 input wire[11:0] x,y,input wire de,
 output wire panel_pixel,text_pixel,edge_pixel,
 output wire[11:0] position,
 output wire[15:0] frames,loops,
 output wire font_request,output wire[8:0] font_index,input wire[7:0] font_word,
 output wire font_index_hi,input wire[8:0] font_word9
);
 localparam integer VIEW_LEFT=120,VIEW_RIGHT=WIDTH-8;
 localparam integer VIEW_WIDTH=WIDTH-128,TEXT_WIDTH=MESSAGE_CHARS*16;
 localparam integer PERIOD=VIEW_WIDTH+TEXT_WIDTH;
 localparam integer POSITION_W=$clog2(PERIOD);
 reg[POSITION_W-1:0] phase;
 assign position={{(12-POSITION_W){1'b0}},phase};
 localparam integer STEP_W=FRAMES_PER_PIXEL>1?$clog2(FRAMES_PER_PIXEL):1;
 reg[STEP_W-1:0] frame_divider;
 // Modulo256 diagnostic counts are sufficient for cadence/loop witnesses.
 // Zero extension prunes32 bundled-data registers across the status CDC.
 reg[7:0] frame_count,loop_count;
 assign frames={8'd0,frame_count};assign loops={8'd0,loop_count};
 // No pixel, line, FIFO or SD event may advance the scroll phase.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;frame_divider<=0;frame_count<=0;loop_count<=0;end
  else if(frame_start)begin
   frame_count<=frame_count+1'b1;
   if(frame_divider==FRAMES_PER_PIXEL-1)begin
    frame_divider<=0;
    if(position==PERIOD-1)begin phase<=0;loop_count<=loop_count+1'b1;end
    else phase<=phase+1'b1;
   end else frame_divider<=frame_divider+1'b1;
  end
 end

 // Coordinates outside the viewport are rejected by box. Within it,
 // WIDTH+PERIOD bounds the sum; negative offsets wrap above TEXT_WIDTH.
 localparam integer ARITH_W=$clog2(WIDTH+PERIOD);
 wire[ARITH_W-1:0] translated=x[ARITH_W-1:0]+position;
 wire[ARITH_W-1:0] source_x=translated-(VIEW_RIGHT-SOURCE_AHEAD);
 wire box=de&&x>=VIEW_LEFT&&x<VIEW_RIGHT&&y>=HEIGHT-24&&y<HEIGHT-4;
 wire glyph_valid=(CLIP_INPUT?box:1'b1)&&y>=HEIGHT-22&&y<HEIGHT-6&&
  source_x<TEXT_WIDTH;
 wire border=box&&(y==HEIGHT-24);
 wire[3:0] glyph_row=y-(HEIGHT-22);

 `include "v3_ticker_packed32.vh"
 reg[17:0] packed_desc0;reg[3:0] packed_column0,packed_row0;reg packed_valid0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin packed_desc0<=0;packed_column0<=0;packed_row0<=0;packed_valid0<=0;end
  else begin packed_desc0<=packed_ticker_descriptor(source_x[8:4]);packed_column0<=source_x[3:0];packed_row0<=glyph_row;packed_valid0<=glyph_valid;end
 end
 wire[17:0] packed_desc=packed_desc0;
 wire[9:0] packed_base=packed_desc[17:8];
 wire[3:0] packed_xmin=packed_desc[7:4],packed_width=packed_desc[3:0];
 wire[3:0] packed_column=packed_column0-packed_xmin,packed_row=packed_row0-4'd1;
 wire[7:0] packed_linear=({packed_column,4'b0}-{3'b0,packed_column,1'b0})+{4'b0,packed_row};
 // Exactly floor(n/9) throughout the complete8-bit input domain; no DSP.
 wire[13:0] packed_magic={packed_linear,6'b0}-{3'b0,packed_linear,3'b0}+{6'b0,packed_linear};
 wire[4:0] packed_quotient=packed_magic[13:9];
 wire[7:0] packed_multiple9={packed_quotient,3'b0}+{3'b0,packed_quotient};
 wire[3:0] packed_bit=packed_linear-packed_multiple9;
 wire[9:0] packed_word_address=packed_base+{5'b0,packed_quotient};
 wire packed_bounds=packed_column0>=packed_xmin&&{1'b0,packed_column0}<({1'b0,packed_xmin}+{1'b0,packed_width})&&packed_row0>=1&&packed_row0<=14;
 reg packed_hi1;reg[3:0] packed_bit1,packed_bit2;
 assign font_index_hi=PACKED_EXTERNAL?packed_hi1:1'b0;
 reg[12:0] address1;
 reg valid1,valid2,dot3;
 wire[0:0] row2;
 reg[8:0] shared_address1;reg[2:0] column1,column2;
 assign font_request=EXTERNAL_FONT&&valid1;
 assign font_index=shared_address1;
 generate if(EXTERNAL_FONT)begin:shared_font
  assign row2[0]=PACKED_EXTERNAL?font_word9[packed_bit2]:font_word[7-column2];
 end else begin:local_font
  (* ram_style="block" *) reg[0:0] bitmap_rom[0:8191];
  initial $readmemh(BITMAP_FILE,bitmap_rom);
  reg local_row2;
  always @(posedge clk)local_row2<=bitmap_rom[address1];
  assign row2[0]=local_row2;
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin address1<=0;shared_address1<=0;column1<=0;column2<=0;valid1<=0;valid2<=0;dot3<=0;packed_hi1<=0;packed_bit1<=0;packed_bit2<=0;end
  else begin
   address1<={source_x[8:0],glyph_row};
   shared_address1<=PACKED_EXTERNAL?packed_word_address[8:0]:{source_x[7:4],glyph_row,source_x[3]};
   packed_hi1<=PACKED_EXTERNAL&&packed_word_address[9];
   packed_bit1<=packed_bit;packed_bit2<=packed_bit1;
   column1<=source_x[2:0];column2<=column1;
   valid1<=PACKED_EXTERNAL?(packed_valid0&&packed_bounds):glyph_valid;valid2<=valid1;
   dot3<=valid2&&row2[0];
  end
 end
 reg[PIXEL_LATENCY-1:0] panel_pipe,edge_pipe;
 localparam integer TEXT_DELAY=PIXEL_LATENCY-(PACKED_EXTERNAL?4:3);
 reg[TEXT_DELAY-1:0] text_pipe;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin panel_pipe<=0;edge_pipe<=0;text_pipe<=0;end
  else begin
   panel_pipe<={panel_pipe[PIXEL_LATENCY-2:0],box};
   edge_pipe<={edge_pipe[PIXEL_LATENCY-2:0],border};
   text_pipe<=(text_pipe<<1)|dot3;
  end
 end
 assign panel_pixel=panel_pipe[PIXEL_LATENCY-1];
 assign edge_pixel=edge_pipe[PIXEL_LATENCY-1];
 assign text_pixel=text_pipe[TEXT_DELAY-1];
endmodule
