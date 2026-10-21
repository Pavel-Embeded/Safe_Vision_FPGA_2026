// Production-only, monotonic raster storage. Four 640-pixel rows per stream
// occupy two native RAM32K blocks per stream (four total). Adjacent rows
// use independent read ports; all eight rows and pixel latency are retained.
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
module v3_packed_row_store #(parameter integer HANDBOOK_PROFILE=0)(
 input wire mem_clk,mem_rst_n,write_clk,write_rst_n,pixel_clk,pixel_rst_n,
 input wire word_valid,input wire[2:0] word_bank,input wire[8:0] word_column,
 input wire[31:0] word_data,output wire row_done,output wire serializer_fault,
 input wire coord_valid,input wire[9:0] sx,sy,input wire[1:0] scale_select,
 input wire prepare_valid,input wire[9:0] prepare_sy,
 output wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11,
 output reg pixel_fault
);
 reg[31:0] packet_data;reg[11:0] packet_position;reg packet_stream,packet_last,request_toggle;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin packet_data<=0;packet_position<=0;packet_stream<=0;packet_last<=0;request_toggle<=0;end
  else if(word_valid)begin packet_data<=word_data;packet_position<={word_bank[1:0],word_column,1'b0};
   packet_stream<=word_bank[2];packet_last<=word_column==319;request_toggle<=~request_toggle;end
 end
 reg seen_toggle,high_pending,high_stream,high_last,done_toggle,write_fault;
 reg[15:0] high_data;reg[11:0] high_position;
 wire new_packet=request_toggle!=seen_toggle;
 wire write_enable=high_pending||new_packet;
 wire[15:0] write_data=high_pending?high_data:packet_data[15:0];
 wire[11:0] write_position=high_pending?high_position:packet_position;
 wire write_stream=high_pending?high_stream:packet_stream;
 wire[1:0] write_tile={write_stream,write_position[10]};
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
 wire shrink=HANDBOOK_PROFILE&&scale_select[1];
 wire[2:0] raster_step=shrink?(scale_select==2?3'd2:3'd4):3'd1;
 function[1:0] row_bank;input[9:0] source_row;begin
  row_bank=!shrink?source_row[1:0]:scale_select==2?source_row[2:1]:source_row[3:2];
 end endfunction
 wire[9:0] read_row0=coord_valid?sy:prepared_sy;
 wire[9:0] read_row1=shrink?read_row0:read_row0==479?10'd479:read_row0+1'b1;
 wire[9:0] read_column=coord_valid?(sx>=640-raster_step?10'd639:sx+raster_step):10'd0;
 wire[1:0] rb0=row_bank(read_row0),rb1=row_bank(read_row1);
 // Four rows per stream remain resident. Pair rows0/2 and1/3
 // in native BRAM32K, so adjacent row reads use independent ports. The
 // two rows inside one tile use separate1024-word pages. Four BRAM32K
 // macros consume16 of the64 physical9K-equivalent RAM tiles; the two
 // resource names are configurations of the SAME physical pool.
 wire[2:0] tile0={2'b0,rb0[0]},tile1={2'b0,rb1[0]};
 reg[2:0] tile0_q,tile1_q;
 wire[15:0] qa[0:1],qb[0:1];
 wire[15:0] qa0=qb[tile0_q[0]],qa1=qa[tile1_q[0]];
 wire[15:0] qb0=qb[tile0_q[0]],qb1=qb[tile1_q[0]];
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
   end else if(sy!=previous_sy||sx<previous_sx||
    (shrink?(sx!=previous_sx&&sx!=previous_sx+raster_step):(sx>previous_sx+1'b1)))pixel_fault<=1;
   else if(sx!=previous_sx)begin ca0<=qa0;ca1<=qa1;cb0<=qb0;cb1<=qb1;end
  end
 end
 genvar g;
 generate for(g=0;g<4;g=g+1)begin:tiles
  (* ram_style="bram_32k" *) reg[15:0] pixels[0:2047];reg[15:0] r;
  wire row_page=(tile0==(g%2))?rb0[1]:rb1[1];
  always @(posedge write_clk)if(write_rst_n&&write_enable&&write_tile==g)pixels[{write_position[11],write_position[9:0]}]<=write_data;
  always @(posedge pixel_clk)r<=pixels[{row_page,read_column}];
  if(g<2)assign qa[g]=r;else assign qb[g-2]=r;
 end endgenerate
 assign a00=ca0;assign a10=qa0;assign a01=ca1;assign a11=qa1;
 assign b00=cb0;assign b10=qb0;assign b01=cb1;assign b11=qb1;
endmodule
