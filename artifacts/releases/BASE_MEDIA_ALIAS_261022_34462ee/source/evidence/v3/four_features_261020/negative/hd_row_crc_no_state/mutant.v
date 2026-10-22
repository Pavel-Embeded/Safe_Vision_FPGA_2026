`include "pixel_format_defs.vh"
// Eight source rows: four for current and four for fade target. Each row is
// split into even/odd pixel banks; each bank has one memory write port and one
// synchronous pixel read port. A row is published only after its producer CRC
// matches the complete landed row. Five bounded bursts permit SDRAM refresh.
module v3_line_cache #(parameter integer TIMEOUT=4000000,PACKED_ROWS=0,HANDBOOK_PROFILE=0)(
 input wire mem_clk,mem_rst_n,pixel_clk,pixel_rst_n,
 input wire write_clk,write_rst_n,prepare_valid,input wire[9:0] prepare_sy,
 input wire request_valid,output wire request_ready,input wire[(HANDBOOK_PROFILE?26:24)-1:0] request_data,
 output wire response_valid,input wire response_ready,output wire[(HANDBOOK_PROFILE?26:24)-1:0] response_data,
 input wire[9:0] sx,sy,input wire coord_valid,input wire[1:0] scale_select,
 input wire[1:0] current_slot,target_slot,input wire dual_needed,output wire primed,
 output wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11,
 output reg rows_ready,output reg sample_valid,
 output reg rd_req,output reg[31:0] rd_addr,output wire[15:0] rd_len,
 input wire rd_ack,rd_busy,rd_valid,input wire[31:0] rd_data,
 output reg[31:0] lookup_addr,input wire[31:0] lookup_crc,input wire lookup_valid,
 output reg fault,output wire dma_busy,output wire dma_progress
);
 `include "crc32_word.vh"
 localparam integer DESC_W=HANDBOOK_PROFILE?26:24;
 wire[DESC_W-1:0] cmd;wire cmd_valid;wire cmd_ready;
 function[1:0] row_bank;
  input[9:0] source_row;input[1:0] mode;
  begin row_bank=!HANDBOOK_PROFILE||!mode[1]?source_row[1:0]:mode==2?source_row[2:1]:source_row[3:2];end
 endfunction
 reg[DESC_W-1:0] reply;reg reply_pending;wire reply_ready;
 video_cdc_mailbox #(.WIDTH(DESC_W)) requests(
  .src_clk(pixel_clk),.src_rst_n(pixel_rst_n),.src_data(request_data),
  .src_valid(request_valid),.src_ready(request_ready),
  .dst_clk(mem_clk),.dst_rst_n(mem_rst_n),.dst_data(cmd),
  .dst_valid(cmd_valid),.dst_ready(cmd_ready));
 video_cdc_mailbox #(.WIDTH(DESC_W)) responses(
  .src_clk(mem_clk),.src_rst_n(mem_rst_n),.src_data(reply),
  .src_valid(reply_pending),.src_ready(reply_ready),
  .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(response_data),
  .dst_valid(response_valid),.dst_ready(response_ready));
 // Descriptor: [23:22] current slot, [21:20] target slot, [19] dual,
 // [18:9] row0, [8:0] row1 (all rows are 0..479).
 reg[DESC_W-1:0] descriptor;
 wire[25:0] descriptor_extended=descriptor;wire[25:0] response_extended=response_data;
 wire[1:0] memory_scale=HANDBOOK_PROFILE?descriptor_extended[25:24]:0;reg[2:0] state;reg first_half_announced;
 localparam IDLE=0,SELECT=1,QUERY1=2,QUERY2=3,ISSUE=4,READ=5,RETIRE=6,REPLY=7;
 reg[2:0] item,bank;reg[1:0] slot;reg[9:0] row;
 reg[1:0] tag_slot[0:7];reg[9:0] tag_row[0:7];reg[7:0] tag_valid;
 reg[8:0] word_column;reg[6:0] burst_count;reg[31:0] crc,expected,timer;
 // Dual-stream order is A0,B0,A1,B1: publish the nearer row for BOTH
 // streams before spending bus time on the farther interpolation neighbor.
 wire stream=descriptor[19]&&item[0];
 wire row_select=descriptor[19]?item[1]:item[0];
 wire[1:0] wanted_slot=stream?descriptor[21:20]:descriptor[23:22];
 wire[9:0] wanted_row=row_select?{1'b0,descriptor[8:0]}:descriptor[18:9];
 wire[2:0] wanted_bank={stream,row_bank(wanted_row,memory_scale)};
 wire[2:0] item_count=descriptor[19]?4:2;
 assign cmd_ready=state==IDLE && !reply_pending && !fault;
 assign rd_len=16'd64;
 assign dma_busy=state!=IDLE;
 assign dma_progress=state==READ && rd_valid;
 wire writing=state==READ && rd_valid;
 // CRC is the same linear IEEE transform, expressed as bounded byte XORs.
 // Keep only the two half-word partials to avoid a serial area-mapped XOR chain
 // from the SDRAM BRAM output through CRC comparison into tag publication.
 // expected holds the inverse32-step CRC state of the looked-up row CRC.
 // Complete it serially in32 MEM clocks. A row has320 accepted words, so
 // it is ready before the last beat even at one word per clock. No external
 // handshake, fault edge, signature or CRC accumulator timing is changed.
 reg[5:0] expected_steps;
 wire[31:0] inverse_unpoly=expected^(expected[31]?32'hedb88320:32'd0);
 wire[31:0] inverse_step={inverse_unpoly[30:0],expected[31]};
 wire final_crc_mismatch=(crc^rd_data)!=expected;
 wire[31:0] row_crc_input=rd_data;
 wire[31:0] row_crc_next;
 // Share bounded XOR subexpressions across all32 CRC result bits.
 // The IEEE polynomial, per-word state edge and full throughput are identical;
 // exact64 input-basis vectors prove the linear transform for every input.
 (* keep="true" *) wire p0=row_crc_input[0]^row_crc_input[22];
 (* keep="true" *) wire p1=row_crc_input[2]^row_crc_input[7];
 (* keep="true" *) wire p2=row_crc_input[1]^row_crc_input[23];
 (* keep="true" *) wire p3=row_crc_input[3]^row_crc_input[5];
 (* keep="true" *) wire p4=row_crc_input[4]^p0;
 (* keep="true" *) wire p5=row_crc_input[6]^row_crc_input[9];
 (* keep="true" *) wire p6=row_crc_input[10]^row_crc_input[24];
 (* keep="true" *) wire p7=row_crc_input[11]^row_crc_input[25];
 (* keep="true" *) wire p8=row_crc_input[12]^row_crc_input[28];
 (* keep="true" *) wire p9=row_crc_input[13]^row_crc_input[29];
 (* keep="true" *) wire p10=row_crc_input[14]^row_crc_input[30];
 (* keep="true" *) wire p11=row_crc_input[15]^row_crc_input[31];
 (* keep="true" *) wire p12=row_crc_input[18]^row_crc_input[26];
 (* keep="true" *) wire p13=row_crc_input[19]^row_crc_input[27];
 (* keep="true" *) wire p14=row_crc_input[8]^row_crc_input[20];
 (* keep="true" *) wire p15=row_crc_input[3]^row_crc_input[21];
 (* keep="true" *) wire p16=row_crc_input[16]^row_crc_input[23];
 (* keep="true" *) wire p17=row_crc_input[17]^row_crc_input[24];
 (* keep="true" *) wire p18=row_crc_input[8]^p3;
 (* keep="true" *) wire p19=row_crc_input[4]^row_crc_input[11];
 (* keep="true" *) wire p20=row_crc_input[5]^row_crc_input[12];
 (* keep="true" *) wire p21=row_crc_input[7]^row_crc_input[16];
 (* keep="true" *) wire p22=row_crc_input[0]^p8;
 (* keep="true" *) wire p23=row_crc_input[6]^p1;
 (* keep="true" *) wire p24=row_crc_input[26]^p2;
 (* keep="true" *) wire p25=row_crc_input[27]^p7;
 (* keep="true" *) wire p26=row_crc_input[30]^p12;
 (* keep="true" *) wire p27=row_crc_input[31]^p13;
 (* keep="true" *) wire p28=p9^p10;
 (* keep="true" *) wire p29=row_crc_input[2]^row_crc_input[29];
 (* keep="true" *) wire p30=row_crc_input[9]^row_crc_input[14];
 (* keep="true" *) wire p31=row_crc_input[18]^row_crc_input[25];
 (* keep="true" *) wire p32=row_crc_input[15]^p19;
 (* keep="true" *) wire p33=row_crc_input[17]^p6;
 (* keep="true" *) wire p34=row_crc_input[17]^p11;
 (* keep="true" *) wire p35=row_crc_input[22]^p13;
 (* keep="true" *) wire p36=row_crc_input[28]^p5;
 assign row_crc_next[0]=^{row_crc_input[3],row_crc_input[16],p4,p14,p23,p24};
 assign row_crc_next[1]=^{row_crc_input[4],row_crc_input[9],row_crc_input[21],row_crc_input[27],p1,p2,p17,p18};
 assign row_crc_next[2]=^{row_crc_input[2],p4,p6,p18,p31,p36};
 assign row_crc_next[3]=^{row_crc_input[4],row_crc_input[7],row_crc_input[10],row_crc_input[19],row_crc_input[29],p3,p5,p7,p24};
 assign row_crc_next[4]=^{row_crc_input[26],row_crc_input[27],row_crc_input[30],p6,p14,p19,p20,p23};
 assign row_crc_next[5]=^{row_crc_input[7],row_crc_input[13],row_crc_input[21],row_crc_input[31],p5,p18,p22,p25};
 assign row_crc_next[6]=^{row_crc_input[2],row_crc_input[3],row_crc_input[10],row_crc_input[20],p9,p16,p22,p30};
 assign row_crc_next[7]=^{row_crc_input[1],p15,p28,p32,p33};
 assign row_crc_next[8]=^{row_crc_input[2],row_crc_input[16],row_crc_input[18],p4,p7,p10,p11,p20};
 assign row_crc_next[9]=^{row_crc_input[13],row_crc_input[19],p1,p4,p14,p20,p34};
 assign row_crc_next[10]=^{row_crc_input[5],row_crc_input[13],row_crc_input[21],p1,p4,p12,p30};
 assign row_crc_next[11]=^{row_crc_input[6],row_crc_input[10],row_crc_input[14],row_crc_input[15],p2,p18,p35};
 assign row_crc_next[12]=^{row_crc_input[20],row_crc_input[24],p1,p16,p32,p36};
 assign row_crc_next[13]=^{row_crc_input[0],row_crc_input[12],row_crc_input[21],row_crc_input[25],row_crc_input[29],p18,p21,p33};
 assign row_crc_next[14]=^{row_crc_input[1],row_crc_input[8],row_crc_input[13],row_crc_input[17],p4,p5,p7,p26};
 assign row_crc_next[15]=^{row_crc_input[10],p1,p2,p12,p20,p27,p30};
 assign row_crc_next[16]=^{row_crc_input[13],row_crc_input[28],p6,p21,p24,p32,p35};
 assign row_crc_next[17]=^{row_crc_input[5],row_crc_input[14],p8,p14,p16,p17,p25,p29};
 assign row_crc_next[18]=^{row_crc_input[15],row_crc_input[25],p5,p9,p15,p17,p22,p26};
 assign row_crc_next[19]=^{row_crc_input[1],row_crc_input[10],row_crc_input[25],p4,p12,p21,p27,p28};
 assign row_crc_next[20]=^{row_crc_input[6],row_crc_input[11],row_crc_input[28],p3,p4,p10,p13,p21,p34};
 assign row_crc_next[21]=^{p0,p3,p8,p12,p29,p34};
 assign row_crc_next[22]=^{p1,p9,p14,p26,p35};
 assign row_crc_next[23]=^{row_crc_input[0],row_crc_input[9],row_crc_input[23],row_crc_input[28],p10,p14,p15,p27};
 assign row_crc_next[24]=^{row_crc_input[8],row_crc_input[26],row_crc_input[29],p1,p6,p11,p15,p16,p36};
 assign row_crc_next[25]=^{row_crc_input[20],row_crc_input[30],p5,p24,p25,p29,p33};
 assign row_crc_next[26]=^{row_crc_input[31],p1,p6,p8,p15,p25,p26};
 assign row_crc_next[27]=^{row_crc_input[16],row_crc_input[20],p2,p7,p9,p22,p23,p27};
 assign row_crc_next[28]=^{row_crc_input[6],row_crc_input[21],p4,p8,p16,p17,p28};
 assign row_crc_next[29]=^{row_crc_input[5],row_crc_input[7],p0,p2,p11,p17,p28,p31};
 assign row_crc_next[30]=^{row_crc_input[3],row_crc_input[4],row_crc_input[7],row_crc_input[19],row_crc_input[20],row_crc_input[22],row_crc_input[24],p10,p11,p31};
 assign row_crc_next[31]=^{row_crc_input[1],row_crc_input[19],row_crc_input[21],row_crc_input[25],p0,p3,p11,p23};

 wire packed_row_done,packed_serializer_fault,packed_pixel_fault;
 reg row_store_done;
 (* async_reg="true" *) reg pixel_fault_meta,pixel_fault_sync;
 // Private tag data is eligible only after the independently reset valid
 // bits publish the complete tag on the SAME edge. Removing reset from these
 // payloads does not change any public output or warm-reset invalidation.
 wire tag_publish_now=state==READ && rd_valid && burst_count==63 &&
  word_column==319 && !final_crc_mismatch && !PACKED_ROWS;
 wire tag_publish_packed=state==RETIRE && !rd_busy && !fault &&
  word_column==320 && row_store_done && PACKED_ROWS;
 always @(posedge mem_clk)if(mem_rst_n&&(tag_publish_now||tag_publish_packed))begin
  tag_slot[bank]<=slot;tag_row[bank]<=row;
 end
 integer i;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin state<=IDLE;descriptor<=0;item<=0;bank<=0;slot<=0;row<=0;
   tag_valid<=0;word_column<=0;burst_count<=0;crc<=32'hffffffff;expected<=0;expected_steps<=0;
   timer<=0;rd_req<=0;rd_addr<=0;lookup_addr<=0;fault<=0;reply<=0;reply_pending<=0;first_half_announced<=0;
   row_store_done<=0;pixel_fault_meta<=0;pixel_fault_sync<=0;
  end else begin
   if(expected_steps!=0)begin expected<=inverse_step;expected_steps<=expected_steps-1'b1;end
   pixel_fault_meta<=packed_pixel_fault;pixel_fault_sync<=pixel_fault_meta;
   if(packed_row_done)row_store_done<=1;
   if(PACKED_ROWS&&(packed_serializer_fault||pixel_fault_sync))fault<=1;
   if(reply_pending&&reply_ready)reply_pending<=0;
   if(state!=IDLE && state!=REPLY)begin
    timer<=timer+1'b1;
    if(timer>=TIMEOUT-1)begin fault<=1;state<=IDLE;rd_req<=0;end
   end else timer<=0;
   case(state)
    IDLE:if(cmd_valid&&cmd_ready)begin descriptor<=cmd;item<=0;state<=SELECT;first_half_announced<=0;end
    SELECT:if(item==item_count)state<=REPLY;
     // Response bit18 (request row0[9], always zero for 480 rows) marks an
     // early pair publication. Both row fields contain the validated row0.
     // A later bit18=0 response preserves the complete-descriptor contract.
     else if(item==(descriptor[19]?2:1)&&!first_half_announced)begin
      if(!reply_pending)begin
       reply<={memory_scale,descriptor[23:19],1'b1,descriptor[17:9],descriptor[17:9]};
       reply_pending<=1;first_half_announced<=1;
      end
     end
     else if(tag_valid[wanted_bank] && tag_row[wanted_bank]==wanted_row &&
             tag_slot[wanted_bank]==wanted_slot)item<=item+1'b1;
     else begin
      bank<=wanted_bank;slot<=wanted_slot;row<=wanted_row;
      tag_valid[wanted_bank]<=0;word_column<=0;burst_count<=0;crc<=32'hffffffff;row_store_done<=0;
      lookup_addr<=`SV_SLOT_BASE(wanted_slot)+wanted_row*32'd1280;state<=QUERY1;
     end
    QUERY1:state<=QUERY2;
    QUERY2:if(lookup_valid)begin expected<=~lookup_crc;expected_steps<=6'd32;state<=ISSUE;end
     else begin fault<=1;state<=IDLE;end
    ISSUE:if(!rd_busy)begin rd_addr<=`SV_SLOT_BASE(slot)+row*32'd1280+word_column*4;
      rd_req<=1;state<=READ;burst_count<=0;end
    READ:begin
     if(rd_ack)rd_req<=0;
     if(rd_valid)begin
      crc<=row_crc_next;word_column<=word_column+1'b1;
      if(burst_count==63)begin burst_count<=0;state<=RETIRE;
       if(word_column==319)begin
        if(final_crc_mismatch)begin fault<=1;tag_valid[bank]<=0;end
        else if(!PACKED_ROWS)begin tag_valid[bank]<=1;end
       end
      end else burst_count<=burst_count+1'b1;
     end
    end
    RETIRE:if(!rd_busy)begin
     if(fault)state<=IDLE;
     else if(word_column==320)begin
      if(!PACKED_ROWS||row_store_done)begin
       if(PACKED_ROWS)begin tag_valid[bank]<=1;end
       item<=item+1'b1;state<=SELECT;
      end
     end
     else state<=ISSUE;
    end
    REPLY:if(!reply_pending)begin reply<=descriptor;reply_pending<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
 reg[1:0] pixel_slot[0:7];reg[9:0] pixel_row[0:7];reg[7:0] pixel_valid;
 wire[9:0] next_row=HANDBOOK_PROFILE&&scale_select[1]?sy:sy==479?10'd479:sy+1'b1;
 wire[1:0] sb0=row_bank(sy,scale_select),sb1=row_bank(next_row,scale_select);
 wire[1:0] rb0=row_bank({1'b0,response_data[17:9]},response_extended[25:24]);
 wire[1:0] rb1=row_bank({1'b0,response_data[8:0]},response_extended[25:24]);
 reg[2:0] row0_bank,row1_bank;reg odd_column,edge_column;
 wire[8:0] even_address=(sx[0]&&sx<639)?{1'b0,sx[9:1]}+1'b1:{1'b0,sx[9:1]};
 wire[8:0] odd_address={1'b0,sx[9:1]};
 wire[15:0] even_q[0:7],odd_q[0:7];
 reg[1:0] active_current,active_target;reg dual;
 always @(posedge pixel_clk)if(pixel_rst_n&&response_valid&&response_ready)begin
    pixel_slot[{1'b0,rb0}]<=response_data[23:22];
    pixel_row[{1'b0,rb0}]<={1'b0,response_data[17:9]};
    pixel_slot[{1'b0,rb1}]<=response_data[23:22];
    pixel_row[{1'b0,rb1}]<={1'b0,response_data[8:0]};
  if(response_data[19])begin
     pixel_slot[{1'b1,rb0}]<=response_data[21:20];
     pixel_row[{1'b1,rb0}]<={1'b0,response_data[17:9]};
     pixel_slot[{1'b1,rb1}]<=response_data[21:20];
     pixel_row[{1'b1,rb1}]<={1'b0,response_data[8:0]};
  end
 end
 integer j;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin pixel_valid<=0;active_current<=0;active_target<=0;dual<=0;
   row0_bank<=0;row1_bank<=1;odd_column<=0;edge_column<=0;rows_ready<=0;sample_valid<=0;
  end else begin
   if(response_valid&&response_ready)begin
    active_current<=response_data[23:22];active_target<=response_data[21:20];dual<=response_data[19];
    pixel_valid[{1'b0,rb0}]<=1;
    pixel_valid[{1'b0,rb1}]<=1;
    if(response_data[19])begin
     pixel_valid[{1'b1,rb0}]<=1;
     pixel_valid[{1'b1,rb1}]<=1;
    end
   end
   row0_bank<={1'b0,sb0};row1_bank<={1'b0,sb1};
   odd_column<=sx[0];edge_column<=sx==639;sample_valid<=coord_valid;
   rows_ready<=pixel_valid[{1'b0,sb0}]&&pixel_row[{1'b0,sb0}]==sy&&
    pixel_slot[{1'b0,sb0}]==current_slot&&
    pixel_valid[{1'b0,sb1}]&&pixel_row[{1'b0,sb1}]==next_row&&
    pixel_slot[{1'b0,sb1}]==current_slot&&
    (!dual_needed||(pixel_valid[{1'b1,sb0}]&&pixel_row[{1'b1,sb0}]==sy&&
     pixel_slot[{1'b1,sb0}]==target_slot&&
     pixel_valid[{1'b1,sb1}]&&pixel_row[{1'b1,sb1}]==next_row&&
     pixel_slot[{1'b1,sb1}]==target_slot));
  end
 end
 wire need_neighbor=!(HANDBOOK_PROFILE&&scale_select[1]);
 assign primed=pixel_valid[0]&&pixel_row[0]==0&&pixel_slot[0]==current_slot&&
  (!need_neighbor||(pixel_valid[1]&&pixel_row[1]==1&&pixel_slot[1]==current_slot))&&
  (!dual_needed||(pixel_valid[4]&&pixel_row[4]==0&&pixel_slot[4]==target_slot&&
   (!need_neighbor||(pixel_valid[5]&&pixel_row[5]==1&&pixel_slot[5]==target_slot))));
 genvar g;
 generate if(PACKED_ROWS)begin:packed_data
  v3_packed_row_store #(.HANDBOOK_PROFILE(HANDBOOK_PROFILE)) store(.mem_clk(mem_clk),.mem_rst_n(mem_rst_n),
   .write_clk(write_clk),.write_rst_n(write_rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),
   .word_valid(writing),.word_bank(bank),.word_column(word_column),.word_data(rd_data),
   .row_done(packed_row_done),.serializer_fault(packed_serializer_fault),
   .coord_valid(coord_valid),.sx(sx),.sy(sy),.scale_select(scale_select),.prepare_valid(prepare_valid),.prepare_sy(prepare_sy),
   .a00(a00),.a10(a10),.a01(a01),.a11(a11),.b00(b00),.b10(b10),.b01(b01),.b11(b11),.pixel_fault(packed_pixel_fault));
 end else begin:random_data
 assign packed_row_done=1'b0;assign packed_serializer_fault=1'b0;assign packed_pixel_fault=1'b0;
 for(g=0;g<8;g=g+1)begin:rows
  (* ram_style="block" *) reg[15:0] even_pixels[0:319],odd_pixels[0:319];
  reg[15:0] eq,oq;
  always @(posedge mem_clk)if(writing&&bank==g)begin
   even_pixels[word_column]<=rd_data[15:0];odd_pixels[word_column]<=rd_data[31:16];
  end
  always @(posedge pixel_clk)begin eq<=even_pixels[even_address];oq<=odd_pixels[odd_address];end
  assign even_q[g]=eq;assign odd_q[g]=oq;
 end
 assign a00=odd_column?odd_q[row0_bank]:even_q[row0_bank];
 assign a10=odd_column?(edge_column?odd_q[row0_bank]:even_q[row0_bank]):odd_q[row0_bank];
 assign a01=odd_column?odd_q[row1_bank]:even_q[row1_bank];
 assign a11=odd_column?(edge_column?odd_q[row1_bank]:even_q[row1_bank]):odd_q[row1_bank];
 assign b00=odd_column?odd_q[row0_bank+4]:even_q[row0_bank+4];
 assign b10=odd_column?(edge_column?odd_q[row0_bank+4]:even_q[row0_bank+4]):odd_q[row0_bank+4];
 assign b01=odd_column?odd_q[row1_bank+4]:even_q[row1_bank+4];
 assign b11=odd_column?(edge_column?odd_q[row1_bank+4]:even_q[row1_bank+4]):odd_q[row1_bank+4];
 end endgenerate
 // synthesis translate_off
 always @(posedge mem_clk)if(mem_rst_n&&state==READ&&rd_valid&&word_column==319)
  if(expected_steps!=0)$fatal(1,"CRC inverse not ready before final row word");
 // synthesis translate_on
endmodule
