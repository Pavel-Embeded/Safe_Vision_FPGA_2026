`include "pixel_format_defs.vh"


module v3_line_cache #(parameter integer TIMEOUT=4000000)(
 input wire mem_clk,mem_rst_n,pixel_clk,pixel_rst_n,
 input wire request_valid,output wire request_ready,input wire[23:0] request_data,
 output wire response_valid,input wire response_ready,output wire[23:0] response_data,
 input wire[9:0] sx,sy,input wire coord_valid,
 input wire[1:0] current_slot,target_slot,input wire dual_needed,output wire primed,
 output wire[15:0] a00,a10,a01,a11,b00,b10,b01,b11,
 output reg rows_ready,output reg sample_valid,
 output reg rd_req,output reg[31:0] rd_addr,output wire[15:0] rd_len,
 input wire rd_ack,rd_busy,rd_valid,input wire[31:0] rd_data,
 output reg[31:0] lookup_addr,input wire[31:0] lookup_crc,input wire lookup_valid,
 output reg fault,output wire dma_busy,output wire dma_progress
);
 `include "crc32_word.vh"
 function[1:0] bank_index;input[9:0] r;begin begin bank_index=r%3;end  end endfunction
 wire[23:0] cmd;wire cmd_valid;wire cmd_ready;
 reg[23:0] reply;reg reply_pending;wire reply_ready;
 video_cdc_mailbox #(.WIDTH(24)) requests(
  .src_clk(pixel_clk),.src_rst_n(pixel_rst_n),.src_data(request_data),
  .src_valid(request_valid),.src_ready(request_ready),
  .dst_clk(mem_clk),.dst_rst_n(mem_rst_n),.dst_data(cmd),
  .dst_valid(cmd_valid),.dst_ready(cmd_ready));
 video_cdc_mailbox #(.WIDTH(24)) responses(
  .src_clk(mem_clk),.src_rst_n(mem_rst_n),.src_data(reply),
  .src_valid(reply_pending),.src_ready(reply_ready),
  .dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),.dst_data(response_data),
  .dst_valid(response_valid),.dst_ready(response_ready));


 reg[23:0] descriptor;reg[2:0] state;reg first_half_announced;
 localparam IDLE=0,SELECT=1,QUERY1=2,QUERY2=3,ISSUE=4,READ=5,RETIRE=6,REPLY=7;
 reg[2:0] item,bank;reg[1:0] slot;reg[9:0] row;
 reg[1:0] tag_slot[0:7];reg[9:0] tag_row[0:7];reg[7:0] tag_valid;
 reg[8:0] word_column;reg[6:0] burst_count;reg[31:0] crc,expected,timer;


 wire stream=descriptor[19]&&item[0];
 wire row_select=descriptor[19] ? item[1]:item[0];
 wire[1:0] wanted_slot=stream ? descriptor[21:20]:descriptor[23:22];
 wire[9:0] wanted_row=row_select ? {1'b0,descriptor[8:0]}:descriptor[18:9];
 wire[2:0] wanted_bank={stream,bank_index(wanted_row)};
 wire[2:0] item_count=descriptor[19] ? 4:2;
 assign cmd_ready=state==IDLE && !reply_pending && !fault;
 assign rd_len=16'd64;
 assign dma_busy=state!=IDLE;
 assign dma_progress=state==READ && rd_valid;
 wire writing=state==READ && rd_valid;
 integer i;
 always @(posedge mem_clk or negedge mem_rst_n)begin
  if(!mem_rst_n)begin state<=IDLE;descriptor<=0;item<=0;bank<=0;slot<=0;row<=0;
   tag_valid<=0;word_column<=0;burst_count<=0;crc<=32'hffffffff;expected<=0;
   timer<=0;rd_req<=0;rd_addr<=0;lookup_addr<=0;fault<=0;reply<=0;reply_pending<=0;first_half_announced<=0;
   for(i=0;i<8;i=i+1)begin tag_slot[i]<=0;tag_row[i]<=0;end
  end else begin
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
       reply<={descriptor[23:19],1'b1,descriptor[17:9],descriptor[17:9]};
       reply_pending<=1;first_half_announced<=1;
      end
     end
     else if(tag_valid[wanted_bank] && tag_row[wanted_bank]==wanted_row &&
             tag_slot[wanted_bank]==wanted_slot)item<=item+1'b1;
     else begin
      bank<=wanted_bank;slot<=wanted_slot;row<=wanted_row;
      tag_valid[wanted_bank]<=0;word_column<=0;burst_count<=0;crc<=32'hffffffff;
      lookup_addr<=`SV_SLOT_BASE(wanted_slot)+wanted_row*32'd1280;state<=QUERY1;
     end
    QUERY1:state<=QUERY2;
    QUERY2:if(lookup_valid)begin expected<=lookup_crc;state<=ISSUE;end
     else begin fault<=1;state<=IDLE;end
    ISSUE:if(!rd_busy)begin rd_addr<=`SV_SLOT_BASE(slot)+row*32'd1280+word_column*4;
      rd_req<=1;state<=READ;burst_count<=0;end
    READ:begin
     if(rd_ack)rd_req<=0;
     if(rd_valid)begin
      crc<=crc32_word(crc,rd_data);word_column<=word_column+1'b1;
      if(burst_count==63)begin burst_count<=0;state<=RETIRE;
       if(word_column==319)begin
        if((~crc32_word(crc,rd_data))!=expected)begin fault<=1;tag_valid[bank]<=0;end
        else begin tag_slot[bank]<=slot;tag_row[bank]<=row;tag_valid[bank]<=1;end
       end
      end else burst_count<=burst_count+1'b1;
     end
    end
    RETIRE:if(!rd_busy)begin
     if(fault)state<=IDLE;
     else if(word_column==320)begin item<=item+1'b1;state<=SELECT;end
     else state<=ISSUE;
    end
    REPLY:if(!reply_pending)begin reply<=descriptor;reply_pending<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
 reg[1:0] pixel_slot[0:7];reg[9:0] pixel_row[0:7];reg[7:0] pixel_valid;
 wire[9:0] next_row=sy==479 ? 10'd479:sy+1'b1;
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
    pixel_slot[{1'b0,bank_index({1'b0,response_data[17:9]})}]<=response_data[23:22];
    pixel_row[{1'b0,bank_index({1'b0,response_data[17:9]})}]<={1'b0,response_data[17:9]};
    pixel_valid[{1'b0,bank_index({1'b0,response_data[17:9]})}]<=1;
    pixel_slot[{1'b0,bank_index({1'b0,response_data[8:0]})}]<=response_data[23:22];
    pixel_row[{1'b0,bank_index({1'b0,response_data[8:0]})}]<={1'b0,response_data[8:0]};
    pixel_valid[{1'b0,bank_index({1'b0,response_data[8:0]})}]<=1;
    if(response_data[19])begin
     pixel_slot[{1'b1,bank_index({1'b0,response_data[17:9]})}]<=response_data[21:20];
     pixel_row[{1'b1,bank_index({1'b0,response_data[17:9]})}]<={1'b0,response_data[17:9]};
     pixel_valid[{1'b1,bank_index({1'b0,response_data[17:9]})}]<=1;
     pixel_slot[{1'b1,bank_index({1'b0,response_data[8:0]})}]<=response_data[21:20];
     pixel_row[{1'b1,bank_index({1'b0,response_data[8:0]})}]<={1'b0,response_data[8:0]};
     pixel_valid[{1'b1,bank_index({1'b0,response_data[8:0]})}]<=1;
    end
   end
   row0_bank<={1'b0,bank_index(sy)};row1_bank<={1'b0,bank_index(next_row)};
   odd_column<=sx[0];edge_column<=sx==639;sample_valid<=coord_valid;
   rows_ready<=pixel_valid[{1'b0,bank_index(sy)}]&&pixel_row[{1'b0,bank_index(sy)}]==sy&&
    pixel_slot[{1'b0,bank_index(sy)}]==current_slot&&
    pixel_valid[{1'b0,bank_index(next_row)}]&&pixel_row[{1'b0,bank_index(next_row)}]==next_row&&
    pixel_slot[{1'b0,bank_index(next_row)}]==current_slot&&
    (!dual_needed||(pixel_valid[{1'b1,bank_index(sy)}]&&pixel_row[{1'b1,bank_index(sy)}]==sy&&
     pixel_slot[{1'b1,bank_index(sy)}]==target_slot&&
     pixel_valid[{1'b1,bank_index(next_row)}]&&pixel_row[{1'b1,bank_index(next_row)}]==next_row&&
     pixel_slot[{1'b1,bank_index(next_row)}]==target_slot));
  end
 end
 assign primed=pixel_valid[0]&&pixel_valid[1]&&pixel_row[0]==0&&pixel_row[1]==1&&
  pixel_slot[0]==current_slot&&pixel_slot[1]==current_slot&&
  (!dual_needed||(pixel_valid[4]&&pixel_valid[5]&&pixel_row[4]==0&&pixel_row[5]==1&&
   pixel_slot[4]==target_slot&&pixel_slot[5]==target_slot));
 genvar g;
 generate for(g=0;g<8;g=g+1)begin:rows if((g%4)<3)begin:present
  (* ram_style="block" *) reg[15:0] even_pixels[0:319],odd_pixels[0:319];
  reg[15:0] eq,oq;
  always @(posedge mem_clk)if(writing&&bank==g)begin
   even_pixels[word_column]<=rd_data[15:0];odd_pixels[word_column]<=rd_data[31:16];
  end
  always @(posedge pixel_clk)begin eq<=even_pixels[even_address];oq<=odd_pixels[odd_address];end
  assign even_q[g]=eq;assign odd_q[g]=oq;
 end else begin:absent assign even_q[g]=0;assign odd_q[g]=0;end end endgenerate
 assign a00=odd_column ? odd_q[row0_bank]:even_q[row0_bank];
 assign a10=odd_column ? (edge_column ? odd_q[row0_bank]:even_q[row0_bank]):odd_q[row0_bank];
 assign a01=odd_column ? odd_q[row1_bank]:even_q[row1_bank];
 assign a11=odd_column ? (edge_column ? odd_q[row1_bank]:even_q[row1_bank]):odd_q[row1_bank];
 assign b00=odd_column ? odd_q[row0_bank+4]:even_q[row0_bank+4];
 assign b10=odd_column ? (edge_column ? odd_q[row0_bank+4]:even_q[row0_bank+4]):odd_q[row0_bank+4];
 assign b01=odd_column ? odd_q[row1_bank+4]:even_q[row1_bank+4];
 assign b11=odd_column ? (edge_column ? odd_q[row1_bank+4]:even_q[row1_bank+4]):odd_q[row1_bank+4];
endmodule
