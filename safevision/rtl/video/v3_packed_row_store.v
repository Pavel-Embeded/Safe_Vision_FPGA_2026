// Production-only, monotonic raster storage. Four 640-pixel rows per stream
// occupy five 512x16 RAM9K tiles (ten total). Adjacent rows are >=640 locations
// apart, so their same-column reads always use different physical RAM tiles.
// Each tile has exactly ONE SYS write port and ONE PIX synchronous read port.
//
// MEM50 and WRITE100 MUST be related phase-0 outputs of the same PLL. MEM
// captures each complete word. On the following WRITE edge LOW is written;
// the next WRITE edge writes the held HIGH. These paths are timed, not false
// paths. A completed row is acknowledged back to MEM after the final HIGH.
//
// PIX accepts sx=0 at every valid run, then repeated/increment-by-one x only,
// with unchanged sy until blanking. prepare_sy names the upcoming visible
// source row. Blanking continuously preloads pixel 0 for both row neighbors.
module v3_packed_row_store(
 input wire mem_clk,mem_rst_n,write_clk,write_rst_n,pixel_clk,pixel_rst_n,
 input wire word_valid,input wire[2:0] word_bank,input wire[8:0] word_column,
 input wire[31:0] word_data,output wire row_done,output wire serializer_fault,
 input wire coord_valid,input wire[9:0] sx,sy,
 input wire prepare_valid,input wire[9:0] prepare_sy,
 output wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11,
 output reg pixel_fault
);
 reg[31:0] packet_data;reg[11:0] packet_position;reg packet_stream,packet_last,request_toggle;
 wire[11:0] row_base={1'b0,word_bank[1:0],9'd0}+{3'd0,word_bank[1:0],7'd0};
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin packet_data<=0;packet_position<=0;packet_stream<=0;packet_last<=0;request_toggle<=0;end
  else if(word_valid)begin packet_data<=word_data;packet_position<=row_base+{2'd0,word_column,1'b0};
   packet_stream<=word_bank[2];packet_last<=word_column==319;request_toggle<=~request_toggle;end
 end
 reg seen_toggle,high_pending,high_stream,high_last,done_toggle,write_fault;
 reg[15:0] high_data;reg[11:0] high_position;
 wire new_packet=request_toggle!=seen_toggle;
 wire write_enable=high_pending||new_packet;
 wire[15:0] write_data=high_pending?high_data:packet_data[15:0];
 wire[11:0] write_position=high_pending?high_position:packet_position;
 wire write_stream=high_pending?high_stream:packet_stream;
 wire[3:0] write_tile={1'b0,write_position[11:9]}+(write_stream?4'd5:4'd0);
 always @(posedge write_clk or negedge write_rst_n)begin
  if(!write_rst_n)begin seen_toggle<=0;high_pending<=0;high_data<=0;high_position<=0;
   high_stream<=0;high_last<=0;done_toggle<=0;write_fault<=0;end
  else if(high_pending)begin
   if(new_packet)write_fault<=1; // The required 2:1 clock relationship was lost.
   high_pending<=0;if(high_last)done_toggle<=~done_toggle;
  end else if(new_packet)begin
   seen_toggle<=request_toggle;high_pending<=1;high_data<=packet_data[31:16];
   high_position<=packet_position+1'b1;high_stream<=packet_stream;high_last<=packet_last;
  end
 end
 (* async_reg="true" *) reg done_meta,done_sync,fault_meta,fault_sync;
 reg done_seen;
 assign row_done=done_sync!=done_seen;
 assign serializer_fault=fault_sync;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin done_meta<=0;done_sync<=0;done_seen<=0;fault_meta<=0;fault_sync<=0;end
  else begin done_meta<=done_toggle;done_sync<=done_meta;done_seen<=done_sync;
   fault_meta<=write_fault;fault_sync<=fault_meta;end
 end
 reg[9:0] prepared_sy,previous_sx,previous_sy;reg previous_valid;
 reg[2:0] warm;reg[15:0] ca0,ca1,cb0,cb1;
 wire[9:0] read_row0=coord_valid?sy:prepared_sy;
 wire[9:0] read_row1=read_row0==479?10'd479:read_row0+1'b1;
 wire[9:0] read_column=coord_valid?(sx==639?10'd639:sx+1'b1):10'd0;
 wire[11:0] rbase0={1'b0,read_row0[1:0],9'd0}+{3'd0,read_row0[1:0],7'd0};
 wire[11:0] rbase1={1'b0,read_row1[1:0],9'd0}+{3'd0,read_row1[1:0],7'd0};
 wire[11:0] position0=rbase0+{2'd0,read_column},position1=rbase1+{2'd0,read_column};
 wire[2:0] tile0=position0[11:9],tile1=position1[11:9];
 reg[2:0] tile0_q,tile1_q;
 wire[15:0] q[0:9];
 wire[15:0] qa0=q[{1'b0,tile0_q}],qa1=q[{1'b0,tile1_q}];
 wire[15:0] qb0=q[{1'b0,tile0_q}+4'd5],qb1=q[{1'b0,tile1_q}+4'd5];
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin prepared_sy<=0;previous_sx<=0;previous_sy<=0;previous_valid<=0;
   warm<=0;tile0_q<=0;tile1_q<=1;ca0<=0;ca1<=0;cb0<=0;cb1<=0;pixel_fault<=0;end
  else begin
   tile0_q<=tile0;tile1_q<=tile1;previous_valid<=coord_valid;
   previous_sx<=sx;previous_sy<=sy;
   if(prepare_valid)begin prepared_sy<=prepare_sy;warm<=0;end
   else if(!coord_valid&&warm!=7)warm<=warm+1'b1;
   else if(coord_valid)warm<=0;
   if(!coord_valid)begin ca0<=qa0;ca1<=qa1;cb0<=qb0;cb1<=qb1;end
   else if(!previous_valid)begin
    if(sx!=0||sy!=prepared_sy||warm<3)pixel_fault<=1;
   end else if(sy!=previous_sy||sx<previous_sx||sx>previous_sx+1'b1)pixel_fault<=1;
   else if(sx!=previous_sx)begin ca0<=qa0;ca1<=qa1;cb0<=qb0;cb1<=qb1;end
  end
 end
 genvar g;
 generate for(g=0;g<10;g=g+1)begin:tiles
  (* ram_style="block" *) reg[15:0] pixels[0:511];reg[15:0] r;
  wire[8:0] read_address=(tile0==(g%5))?position0[8:0]:position1[8:0];
  always @(posedge write_clk)if(write_rst_n&&write_enable&&write_tile==g)pixels[write_position[8:0]]<=write_data;
  always @(posedge pixel_clk)r<=pixels[read_address];
  assign q[g]=r;
 end endgenerate
 assign a00=ca0;assign a10=qa0;assign a01=ca1;assign a11=qa1;
 assign b00=cb0;assign b10=qb0;assign b01=cb1;assign b11=qb1;
endmodule
