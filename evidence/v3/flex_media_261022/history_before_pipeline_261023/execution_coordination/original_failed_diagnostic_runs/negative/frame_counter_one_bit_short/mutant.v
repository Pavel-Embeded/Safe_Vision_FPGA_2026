`include "pixel_format_defs.vh"
// Producer signatures are computed BEFORE storage. Four resident slots, one
// CRC32 per raster row (1920 entries = 61440 bits at 640x480). Readback uses
// bounded 64-word transactions; CRC state spans all five bursts in a row.
// One synchronous signature read port is shared by mutually exclusive preload
// verification and display lookup; lookup_valid is suppressed while verifying.
module v3_row_integrity #(
 parameter integer ROW_WORDS=320,ROWS=480,BURST=64,
 parameter integer TIMEOUT=40000000
)(input wire clk,rst_n,frame_begin,input wire[1:0] frame_slot,
 input wire top_down,accepted,input wire[31:0] write_addr,write_data,
 input wire verify_start,verify_allow,
 output reg verify_done,verify_pass,fault,output reg[3:0] approved,
 output reg rd_req,output reg[31:0] rd_addr,output wire[15:0] rd_len,
 input wire rd_ack,rd_busy,rd_valid,input wire[31:0] rd_data,
 input wire[31:0] lookup_addr,output wire[31:0] lookup_crc,output reg lookup_valid,
 output reg[31:0] bad_addr,bad_expected,bad_actual,output wire[31:0] source_words,
 output reg[15:0] checked_rows);
 `include "crc32_word.vh"
 localparam IDLE=0,RETIRE=1,REQUEST=2,COLLECT=3,CHECK=4,DONE=5;
 // Separate resident slots into power-of-two banks. At480 rows this
 // uses2048 words instead of1920, fitting the same eight9K RAM blocks.
 // The unused32 rows per bank have no valid/public address. Concatenation
 // removes slot*480 additions from the synchronous RAM lookup path.
 localparam integer SIGNATURE_ROW_W=(ROWS<2)?1:$clog2(ROWS);
 localparam integer SIGNATURE_ROWS=1<<SIGNATURE_ROW_W;
 // Same65,536 signature bits and synchronous read/write contract, packed
 // into two native32K macros instead of eight9K blocks. Both configurations
 // consume eight9K-equivalent tiles; no signature or cache capacity is lost.
 (* ram_style="bram_32k" *) reg[31:0] signatures[0:4*SIGNATURE_ROWS-1];
 reg[2:0] state;reg[1:0] slot_q;reg building,complete,dir;
 // Counts stop at frame/burst/deadline bounds; retain32-bit public ports.
 localparam integer FRAME_WORDS=ROWS*ROW_WORDS;
 localparam integer SOURCE_W=$clog2(FRAME_WORDS+1)-1,ADDR_W=$clog2(`SV_IMG3_BASE+FRAME_WORDS*4+4);
 localparam integer TIMER_W=$clog2(TIMEOUT)+1;
 localparam integer COL_W=$clog2(ROW_WORDS),ROW_W=(ROWS<2)?1:$clog2(ROWS+1);
 localparam integer OFFSET_W=$clog2(ROW_WORDS+1),BURST_W=$clog2(BURST+1);
 reg[31:0] source_crc,verify_crc,base;
 reg[ADDR_W-1:0] expected_addr;
 reg[TIMER_W-1:0] timer;
 reg[SOURCE_W-1:0] source_count;
 // Exact unary view of source_count==0. It changes on the same accepted
 // beat/reset/frame edge as the counter, removing a late wide zero detector
 // from wanted-address selection and all sticky diagnostic enables.
 reg source_first;
 assign source_words=source_count;
 wire[31:0] expected_crc;
 reg[COL_W-1:0] column;reg[ROW_W-1:0] verify_row,producer_row;
 reg[OFFSET_W-1:0] row_offset;reg[BURST_W-1:0] burst_count;
 function[1:0] addr_slot;input[31:0] addr;begin
 // The reviewed slot bases are0,5,10,15 times2^17. Classification
 // therefore depends only on the upper15 bits; low17 bits cannot affect
 // ANY32-bit input result. Factor the high-prefix OR instead of mapping
 // three independent32-bit carry comparisons. Keep the generic-map fallback.
 if(`SV_IMG0_BASE==32'h00000000&&`SV_IMG1_BASE==32'h000a0000&&
    `SV_IMG2_BASE==32'h00140000&&`SV_IMG3_BASE==32'h001e0000)
  addr_slot=(|addr[31:21]) ? 2'd3 : addr[20:17]>=4'd15 ? 2'd3 :
   addr[20:17]>=4'd10 ? 2'd2 : addr[20:17]>=4'd5 ? 2'd1 : 2'd0;
 else addr_slot=addr>=`SV_IMG3_BASE?3:addr>=`SV_IMG2_BASE?2:addr>=`SV_IMG1_BASE?1:0;
 end endfunction
 wire[1:0] source_slot=addr_slot(write_addr),query_slot=addr_slot(lookup_addr);
 wire[31:0] query_offset=lookup_addr-`SV_SLOT_BASE(query_slot);
 wire[31:0] wanted=(source_first)?base+(top_down?0:(ROWS-1)*ROW_WORDS*4):expected_addr;
 wire source_beat=building && accepted && !fault && write_addr==wanted && source_slot==slot_q;
 wire signature_write=source_beat && column==ROW_WORDS-1;
 wire capture=rd_valid && (state==COLLECT || (state==REQUEST && rd_ack));
 // Mutually exclusive build/readback phases share the linear CRC network.
 // CRC_word first XORs state with data; factor selection before that network.
 wire[31:0] crc_delta=capture?(verify_crc^rd_data):(source_crc^write_data);
 wire[31:0] next_source_crc=crc32_word(32'd0,crc_delta);
 wire[31:0] next_verify_crc=next_source_crc;
 // Divide only the bounded row offset. Factoring out the constant power
 // of two avoids several synthesized 32-bit /1280 and %1280 dividers.
 // Out-of-range queries are still rejected using the FULL 32-bit offset.
 function integer stride_shift;input integer n;integer v;begin
  stride_shift=0;v=n;while((v%2)==0)begin stride_shift=stride_shift+1;v=v/2;end
 end endfunction
 localparam integer OFFSET_BITS=$clog2(ROWS*ROW_WORDS*4),LOW=stride_shift(ROW_WORDS*4);
 localparam integer ODD=(ROW_WORDS*4)>>LOW;
 wire[OFFSET_BITS-LOW-1:0] query_high=query_offset[OFFSET_BITS-1:LOW];
 // A valid source beat already matches wanted. Count physical raster rows
 // rather than dividing its address again; arbitrary source addresses retain
 // the full32-bit wanted/slot checks and can never write a signature.
 wire[9:0] source_row=(source_first)?(top_down?0:ROWS-1):producer_row;
 wire[9:0] query_row;
 wire query_divisible;
 generate if(ODD==5 && OFFSET_BITS-LOW<=12)begin:exact_five
  // 5*3277 = 1 modulo4096. For an in-range row r<ROWS<=480,
  // (5*r*3277) modulo4096 is exactly r. Conversely a result below
  // ROWS cannot wrap5*r past4096, so it proves exact divisibility.
  // The full32-bit offset and low alignment checks remain mandatory.
  // This fuses quotient/remainder/range logic into one short DSP path;
  // RAM read and lookup_valid retain their original single-edge latency.
  (* dsp_style="yes" *) wire[11:0] inverse_row=query_high*12'd3277;
  assign query_row=inverse_row[9:0];
  assign query_divisible=inverse_row<ROWS;
 end else begin:generic_divisor
  assign query_row=query_high/ODD;
  assign query_divisible=query_high%ODD==0;
 end endgenerate
 wire query_ok=query_offset<ROWS*ROW_WORDS*4 && query_offset[LOW-1:0]==0 && query_divisible;
 // The write-enable includes source_slot==slot_q, so selecting slot_q
 // here is exactly equal on EVERY memory-write edge, including invalid
 // source-address cases (which never assert signature_write).
 wire[10:0] source_index={slot_q,source_row[SIGNATURE_ROW_W-1:0]};
 wire[10:0] query_index=query_ok?{query_slot,query_row[SIGNATURE_ROW_W-1:0]}:0;
 assign rd_len=BURST;
 // The same read port serves mutually exclusive preload verification and
 // display lookup. A second independent read inferred a 2048x32 distributed
 // RAM replica in TD, costing about 10k LUTs; it was never needed concurrently.
 wire verifying=state!=IDLE && state!=DONE;
 // One shared address arithmetic path for the single physical read port.
 // Invalid queries retain the old exact address0, including lookup_crc when
 // lookup_valid is low. Truncation to11 bits remains at the same boundary.
 wire[1:0] signature_read_slot=verifying?slot_q:query_ok?query_slot:2'd0;
 wire[9:0] signature_read_row=verifying?verify_row:query_ok?query_row:10'd0;
 wire[10:0] signature_read_index={signature_read_slot,signature_read_row[SIGNATURE_ROW_W-1:0]};
 reg[31:0] signature_read;
 assign expected_crc=signature_read;assign lookup_crc=signature_read;
 // No bulk reset: validity suppresses stale RAM after every reset epoch.
 always @(posedge clk)begin
  if(signature_write)signatures[source_index]<=~next_source_crc;
  signature_read<=signatures[signature_read_index];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;slot_q<=0;building<=0;complete<=0;dir<=0;
   source_crc<=32'hffffffff;verify_crc<=32'hffffffff;base<=0;expected_addr<=0;
   timer<=0;column<=0;verify_row<=0;row_offset<=0;producer_row<=0;burst_count<=0;source_count<=0;source_first<=1;
   verify_done<=0;verify_pass<=0;fault<=0;approved<=0;rd_req<=0;rd_addr<=0;
   lookup_valid<=0;bad_addr<=0;bad_expected<=0;bad_actual<=0;checked_rows<=0;end
  else begin
   lookup_valid<=!verifying && query_ok && approved[query_slot];
   if(frame_begin && !fault)begin
    slot_q<=frame_slot;base<=`SV_SLOT_BASE(frame_slot);building<=1;complete<=0;
    approved[frame_slot]<=0;source_count<=0;source_first<=1;column<=0;source_crc<=32'hffffffff;producer_row<=top_down?0:ROWS-1;
    expected_addr<=`SV_SLOT_BASE(frame_slot)+(top_down?0:(ROWS-1)*ROW_WORDS*4);
    dir<=top_down;verify_done<=0;verify_pass<=0;checked_rows<=0;state<=IDLE;rd_req<=0;
   end else if(building && accepted && !fault)begin
    if(!source_beat)begin fault<=1;building<=0;bad_addr<=write_addr;bad_expected<=wanted;bad_actual<=write_addr;end
    else begin
     if(source_first)begin dir<=top_down;producer_row<=top_down?0:ROWS-1;end
     source_count<=source_words+1'b1;source_first<=0;
     if(column==ROW_WORDS-1)begin
      column<=0;source_crc<=32'hffffffff;
      // No live source transaction follows the final word. Avoid computing an
      // unused below-base pointer after the bottom-up last row.
      if(source_words!=FRAME_WORDS-1)begin
       producer_row<=dir?source_row+1'b1:source_row-1'b1;
       expected_addr<=dir?wanted+4:wanted-(ROW_WORDS*8)+4;
      end
     end else begin column<=column+1'b1;source_crc<=next_source_crc;expected_addr<=wanted+4;end
     if(source_words==ROWS*ROW_WORDS-1)begin complete<=1;building<=0;end
    end
   end
   if(!fault)begin
    if(state==IDLE || state==DONE || capture || rd_ack)timer<=0;else timer<=timer+1'b1;
    case(state)
     IDLE:if(verify_start)begin
      if(!complete)begin fault<=1;verify_done<=1;verify_pass<=0;bad_expected<=ROWS*ROW_WORDS;bad_actual<=source_words;end
      else begin verify_row<=0;row_offset<=0;verify_crc<=32'hffffffff;state<=RETIRE;end
     end
     RETIRE:if(!rd_busy && verify_allow)begin
      rd_addr<=base+(verify_row*ROW_WORDS+row_offset)*4;rd_req<=1;burst_count<=0;state<=REQUEST;
     end
     REQUEST:if(rd_ack)begin rd_req<=0;state<=COLLECT;end
     COLLECT:;
     CHECK:if(~verify_crc!=expected_crc)begin
      fault<=1;verify_done<=1;verify_pass<=0;bad_addr<=base+verify_row*ROW_WORDS*4;
      bad_expected<=expected_crc;bad_actual<=~verify_crc;state<=DONE;
     end else begin
      checked_rows<=checked_rows+1'b1;
      if(verify_row==ROWS-1)begin approved[slot_q]<=1;verify_done<=1;verify_pass<=1;state<=DONE;end
      else begin verify_row<=verify_row+1'b1;row_offset<=0;verify_crc<=32'hffffffff;state<=RETIRE;end
     end
     DONE:;
     default:state<=IDLE;
    endcase
    if(capture)begin
     burst_count<=burst_count+1'b1;verify_crc<=next_verify_crc;
     if(burst_count==BURST-1)begin
      if(row_offset==ROW_WORDS-BURST)state<=CHECK;
      else begin row_offset<=row_offset+BURST;state<=RETIRE;end
     end
    end
    if(state!=IDLE && state!=DONE && timer>=TIMEOUT-1)begin
     fault<=1;verify_done<=1;verify_pass<=0;rd_req<=0;state<=DONE;bad_addr<=rd_addr;
    end
   end else rd_req<=0;
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(rst_n)begin
  if(source_beat && capture)$fatal(1,"guard phase contract violated");
  if(source_first !== (source_words==0))$fatal(1,"unary source position invariant violated");
  if(source_words>FRAME_WORDS)$fatal(1,"source counter exceeded frame bound");
 end
 initial if(ROW_WORDS%BURST || ROW_WORDS<64 || BURST!=64 || ROWS<1 || ROWS>480 || TIMEOUT<2)
 $fatal(1,"unsupported row signature geometry");
 // synthesis translate_on
endmodule
