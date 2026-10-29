`include "pixel_format_defs.vh"


module v3_hd_cache255_reference #(parameter integer TIMEOUT=4000000,PACKED_ROWS=0,HANDBOOK_PROFILE=0)(
 input wire mem_clk,mem_rst_n,pixel_clk,pixel_rst_n,
 input wire write_clk,write_rst_n,prepare_valid,input wire[9:0] prepare_sy,
 input wire request_valid,output wire request_ready,input wire[(HANDBOOK_PROFILE ? 26:24)-1:0] request_data,
 output wire response_valid,input wire response_ready,output wire[(HANDBOOK_PROFILE ? 26:24)-1:0] response_data,
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
 localparam integer DESC_W=HANDBOOK_PROFILE ? 26:24;
 wire[DESC_W-1:0] cmd;wire cmd_valid;wire cmd_ready;
 function[1:0] row_bank;
  input[9:0] source_row;input[1:0] mode;
  begin begin row_bank=!HANDBOOK_PROFILE||!mode[1] ? source_row[1:0]:mode==2 ? source_row[2:1]:source_row[3:2];end
  end endfunction
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


 reg[DESC_W-1:0] descriptor;
 wire[25:0] descriptor_extended=descriptor;wire[25:0] response_extended=response_data;
 wire[1:0] memory_scale=HANDBOOK_PROFILE ? descriptor_extended[25:24]:0;reg[2:0] state;reg first_half_announced;
 localparam IDLE=0,SELECT=1,QUERY1=2,QUERY2=3,ISSUE=4,READ=5,RETIRE=6,REPLY=7;
 reg[2:0] item,bank;reg[1:0] slot;reg[9:0] row;
 reg[1:0] tag_slot[0:7];reg[9:0] tag_row[0:7];reg[7:0] tag_valid;
 reg[8:0] word_column;reg[6:0] burst_count;reg[31:0] crc,expected,timer;


 wire stream=descriptor[19]&&item[0];
 wire row_select=descriptor[19] ? item[1]:item[0];
 wire[1:0] wanted_slot=stream ? descriptor[21:20]:descriptor[23:22];
 wire[9:0] wanted_row=row_select ? {1'b0,descriptor[8:0]}:descriptor[18:9];
 wire[2:0] wanted_bank={stream,row_bank(wanted_row,memory_scale)};
 wire[2:0] item_count=descriptor[19] ? 4:2;
 assign cmd_ready=state==IDLE && !reply_pending && !fault;
 assign rd_len=16'd64;
 assign dma_busy=state!=IDLE;
 assign dma_progress=state==READ && rd_valid;
 wire writing=state==READ && rd_valid;


 reg[5:0] expected_steps;
 wire[31:0] inverse_unpoly=expected^(expected[31] ? 32'hedb88320:32'd0);
 wire[31:0] inverse_step={inverse_unpoly[30:0],expected[31]};
 wire final_crc_mismatch=(crc^rd_data)!=expected;
 wire[31:0] row_crc_input=crc^rd_data;
 wire[31:0] row_crc_next;
 (* keep="true" *) wire[63:0] row_crc_part;
 function[31:0] row_crc_mask;input integer bit_number;
 begin begin case(bit_number)
  0:row_crc_mask=32'h04d101df;
  1:row_crc_mask=32'h09a203be;
  2:row_crc_mask=32'h1344077d;
  3:row_crc_mask=32'h26880efa;
  4:row_crc_mask=32'h4d101df4;
  5:row_crc_mask=32'h9a203be9;
  6:row_crc_mask=32'h3091760d;
  7:row_crc_mask=32'h6122ec1a;
  8:row_crc_mask=32'hc245d835;
  9:row_crc_mask=32'h805ab1b5;
  10:row_crc_mask=32'h046462b5;
  11:row_crc_mask=32'h08c8c56a;
  12:row_crc_mask=32'h11918ad4;
  13:row_crc_mask=32'h232315a9;
  14:row_crc_mask=32'h46462b53;
  15:row_crc_mask=32'h8c8c56a6;
  16:row_crc_mask=32'h1dc9ac92;
  17:row_crc_mask=32'h3b935924;
  18:row_crc_mask=32'h7726b249;
  19:row_crc_mask=32'hee4d6493;
  20:row_crc_mask=32'hd84bc8f9;
  21:row_crc_mask=32'hb446902d;
  22:row_crc_mask=32'h6c5c2184;
  23:row_crc_mask=32'hd8b84309;
  24:row_crc_mask=32'hb5a187cc;
  25:row_crc_mask=32'h6f920e46;
  26:row_crc_mask=32'hdf241c8c;
  27:row_crc_mask=32'hba9938c7;
  28:row_crc_mask=32'h71e37051;
  29:row_crc_mask=32'he3c6e0a3;
  30:row_crc_mask=32'hc35cc098;
  31:row_crc_mask=32'h826880ef;
  default:row_crc_mask=0;
 endcase end  end endfunction
 genvar crc_bit,crc_byte;
 generate for(crc_bit=0;crc_bit<32;crc_bit=crc_bit+1)begin:balanced_crc
  localparam[31:0] MASK=row_crc_mask(crc_bit);
  for(crc_byte=0;crc_byte<2;crc_byte=crc_byte+1)begin:byte_partial
   assign row_crc_part[crc_bit*2+crc_byte]=^(row_crc_input[crc_byte*16+:16]&MASK[crc_byte*16+:16]);
  end
  assign row_crc_next[crc_bit]=^row_crc_part[crc_bit*2+:2];
 end endgenerate

 wire packed_row_done,packed_serializer_fault,packed_pixel_fault;
 reg row_store_done;
 (* async_reg="true" *) reg pixel_fault_meta,pixel_fault_sync;
 integer i;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin state<=IDLE;descriptor<=0;item<=0;bank<=0;slot<=0;row<=0;
   tag_valid<=0;word_column<=0;burst_count<=0;crc<=32'hffffffff;expected<=0;expected_steps<=0;
   timer<=0;rd_req<=0;rd_addr<=0;lookup_addr<=0;fault<=0;reply<=0;reply_pending<=0;first_half_announced<=0;
   row_store_done<=0;pixel_fault_meta<=0;pixel_fault_sync<=0;
   for(i=0;i<8;i=i+1)begin tag_slot[i]<=0;tag_row[i]<=0;end
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


     else if(item==(descriptor[19] ? 2:1)&&!first_half_announced)begin
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
        else if(!PACKED_ROWS)begin tag_slot[bank]<=slot;tag_row[bank]<=row;tag_valid[bank]<=1;end
       end
      end else burst_count<=burst_count+1'b1;
     end
    end
    RETIRE:if(!rd_busy)begin
     if(fault)state<=IDLE;
     else if(word_column==320)begin
      if(!PACKED_ROWS||row_store_done)begin
       if(PACKED_ROWS)begin tag_slot[bank]<=slot;tag_row[bank]<=row;tag_valid[bank]<=1;end
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
 wire[9:0] next_row=HANDBOOK_PROFILE&&scale_select[1] ? sy:sy==479 ? 10'd479:sy+1'b1;
 wire[1:0] sb0=row_bank(sy,scale_select),sb1=row_bank(next_row,scale_select);
 wire[1:0] rb0=row_bank({1'b0,response_data[17:9]},response_extended[25:24]);
 wire[1:0] rb1=row_bank({1'b0,response_data[8:0]},response_extended[25:24]);
 reg[2:0] row0_bank,row1_bank;reg odd_column,edge_column;
 wire[8:0] even_address=(sx[0]&&sx<639) ? {1'b0,sx[9:1]}+1'b1:{1'b0,sx[9:1]};
 wire[8:0] odd_address={1'b0,sx[9:1]};
 wire[15:0] even_q[0:7],odd_q[0:7];
 reg[1:0] active_current,active_target;reg dual;
 integer j;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin pixel_valid<=0;active_current<=0;active_target<=0;dual<=0;
   row0_bank<=0;row1_bank<=1;odd_column<=0;edge_column<=0;rows_ready<=0;sample_valid<=0;
   for(j=0;j<8;j=j+1)begin pixel_slot[j]<=0;pixel_row[j]<=0;end
  end else begin
   if(response_valid&&response_ready)begin
    active_current<=response_data[23:22];active_target<=response_data[21:20];dual<=response_data[19];
    pixel_slot[{1'b0,rb0}]<=response_data[23:22];
    pixel_row[{1'b0,rb0}]<={1'b0,response_data[17:9]};
    pixel_valid[{1'b0,rb0}]<=1;
    pixel_slot[{1'b0,rb1}]<=response_data[23:22];
    pixel_row[{1'b0,rb1}]<={1'b0,response_data[8:0]};
    pixel_valid[{1'b0,rb1}]<=1;
    if(response_data[19])begin
     pixel_slot[{1'b1,rb0}]<=response_data[21:20];
     pixel_row[{1'b1,rb0}]<={1'b0,response_data[17:9]};
     pixel_valid[{1'b1,rb0}]<=1;
     pixel_slot[{1'b1,rb1}]<=response_data[21:20];
     pixel_row[{1'b1,rb1}]<={1'b0,response_data[8:0]};
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
 assign a00=odd_column ? odd_q[row0_bank]:even_q[row0_bank];
 assign a10=odd_column ? (edge_column ? odd_q[row0_bank]:even_q[row0_bank]):odd_q[row0_bank];
 assign a01=odd_column ? odd_q[row1_bank]:even_q[row1_bank];
 assign a11=odd_column ? (edge_column ? odd_q[row1_bank]:even_q[row1_bank]):odd_q[row1_bank];
 assign b00=odd_column ? odd_q[row0_bank+4]:even_q[row0_bank+4];
 assign b10=odd_column ? (edge_column ? odd_q[row0_bank+4]:even_q[row0_bank+4]):odd_q[row0_bank+4];
 assign b01=odd_column ? odd_q[row1_bank+4]:even_q[row1_bank+4];
 assign b11=odd_column ? (edge_column ? odd_q[row1_bank+4]:even_q[row1_bank+4]):odd_q[row1_bank+4];
 end endgenerate
 // synthesis translate_off
 always @(posedge mem_clk)if(mem_rst_n&&state==READ&&rd_valid&&word_column==319)
  if(expected_steps!=0)begin $display("[FAIL] CRC inverse not ready before final row word"); $finish; end 
 // synthesis translate_on
endmodule
