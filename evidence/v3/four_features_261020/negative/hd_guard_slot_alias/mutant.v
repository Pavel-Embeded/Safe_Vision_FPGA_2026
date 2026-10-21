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
 // Pad each slot to a power of two. Unused rows are never eligible.
 // 480 rows still occupy eight RAM9K blocks; slot indexing is wiring.
 localparam integer INDEX_W=(ROWS<2)?1:$clog2(ROWS);
 localparam integer SLOT_ROWS=1<<INDEX_W;
 reg[31:0] signatures[0:4*SLOT_ROWS-1];
 reg[2:0] state;reg[1:0] slot_q;reg building,complete,dir;
 // Counts stop at frame/burst/deadline bounds; retain32-bit public ports.
 localparam integer FRAME_WORDS=ROWS*ROW_WORDS;
 localparam integer SOURCE_W=$clog2(FRAME_WORDS+1),ADDR_W=$clog2(`SV_IMG3_BASE+FRAME_WORDS*4+4);
 localparam integer TIMER_W=$clog2(TIMEOUT)+1;
 localparam integer COL_W=$clog2(ROW_WORDS),ROW_W=(ROWS<2)?1:$clog2(ROWS+1);
 localparam integer OFFSET_W=$clog2(ROW_WORDS+1),BURST_W=$clog2(BURST+1);
 reg[31:0] crc_state,base;
 reg[ADDR_W-1:0] expected_addr;
 reg[TIMER_W-1:0] timer;
 reg[SOURCE_W-1:0] source_count;
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
 wire[31:0] wanted=(source_words==0)?base+(top_down?0:(ROWS-1)*ROW_WORDS*4):expected_addr;
 wire source_beat=building && accepted && !fault && write_addr==wanted && source_slot==slot_q;
 wire signature_write=source_beat && column==ROW_WORDS-1;
 wire capture=rd_valid && (state==COLLECT || (state==REQUEST && rd_ack));
 // The production sink withholds the next frame until readback completes.
 // Its WRITE and FLUSH phases therefore share one CRC state register;
 // every row and verification epoch initializes that register to FFFFFFFF.
 // Continuous accepted/capture throughput remains one word per clock.
 // Public counters, signatures, requests and completion edges are unchanged.
 // Mutually exclusive build/readback phases share the linear CRC network.
 // CRC_word first XORs state with data; factor selection before that network.
 // Source construction and verification are separate registered phases.
 // Select the shared CRC input by phase, keeping the last-cycle rvalid
 // path out of its XOR network. Source/capture qualifying edges are unchanged.
 wire verifying=state!=IDLE && state!=DONE;
 wire[31:0] crc_delta=crc_state^(verifying?rd_data:write_data);
 wire[31:0] next_source_crc;
 (* keep="true" *) wire p0=crc_delta[0]^crc_delta[22];
 (* keep="true" *) wire p1=crc_delta[2]^crc_delta[7];
 (* keep="true" *) wire p2=crc_delta[1]^crc_delta[23];
 (* keep="true" *) wire p3=crc_delta[3]^crc_delta[5];
 (* keep="true" *) wire p4=crc_delta[4]^p0;
 (* keep="true" *) wire p5=crc_delta[6]^crc_delta[9];
 (* keep="true" *) wire p6=crc_delta[10]^crc_delta[24];
 (* keep="true" *) wire p7=crc_delta[11]^crc_delta[25];
 (* keep="true" *) wire p8=crc_delta[12]^crc_delta[28];
 (* keep="true" *) wire p9=crc_delta[13]^crc_delta[29];
 (* keep="true" *) wire p10=crc_delta[14]^crc_delta[30];
 (* keep="true" *) wire p11=crc_delta[15]^crc_delta[31];
 (* keep="true" *) wire p12=crc_delta[18]^crc_delta[26];
 (* keep="true" *) wire p13=crc_delta[19]^crc_delta[27];
 (* keep="true" *) wire p14=crc_delta[8]^crc_delta[20];
 (* keep="true" *) wire p15=crc_delta[3]^crc_delta[21];
 (* keep="true" *) wire p16=crc_delta[16]^crc_delta[23];
 (* keep="true" *) wire p17=crc_delta[17]^crc_delta[24];
 (* keep="true" *) wire p18=crc_delta[8]^p3;
 (* keep="true" *) wire p19=crc_delta[4]^crc_delta[11];
 (* keep="true" *) wire p20=crc_delta[5]^crc_delta[12];
 (* keep="true" *) wire p21=crc_delta[7]^crc_delta[16];
 (* keep="true" *) wire p22=crc_delta[0]^p8;
 (* keep="true" *) wire p23=crc_delta[6]^p1;
 (* keep="true" *) wire p24=crc_delta[26]^p2;
 (* keep="true" *) wire p25=crc_delta[27]^p7;
 (* keep="true" *) wire p26=crc_delta[30]^p12;
 (* keep="true" *) wire p27=crc_delta[31]^p13;
 (* keep="true" *) wire p28=p9^p10;
 (* keep="true" *) wire p29=crc_delta[2]^crc_delta[29];
 (* keep="true" *) wire p30=crc_delta[9]^crc_delta[14];
 (* keep="true" *) wire p31=crc_delta[18]^crc_delta[25];
 (* keep="true" *) wire p32=crc_delta[15]^p19;
 (* keep="true" *) wire p33=crc_delta[17]^p6;
 (* keep="true" *) wire p34=crc_delta[17]^p11;
 (* keep="true" *) wire p35=crc_delta[22]^p13;
 (* keep="true" *) wire p36=crc_delta[28]^p5;
 assign next_source_crc[0]=^{crc_delta[3],crc_delta[16],p4,p14,p23,p24};
 assign next_source_crc[1]=^{crc_delta[4],crc_delta[9],crc_delta[21],crc_delta[27],p1,p2,p17,p18};
 assign next_source_crc[2]=^{crc_delta[2],p4,p6,p18,p31,p36};
 assign next_source_crc[3]=^{crc_delta[4],crc_delta[7],crc_delta[10],crc_delta[19],crc_delta[29],p3,p5,p7,p24};
 assign next_source_crc[4]=^{crc_delta[26],crc_delta[27],crc_delta[30],p6,p14,p19,p20,p23};
 assign next_source_crc[5]=^{crc_delta[7],crc_delta[13],crc_delta[21],crc_delta[31],p5,p18,p22,p25};
 assign next_source_crc[6]=^{crc_delta[2],crc_delta[3],crc_delta[10],crc_delta[20],p9,p16,p22,p30};
 assign next_source_crc[7]=^{crc_delta[1],p15,p28,p32,p33};
 assign next_source_crc[8]=^{crc_delta[2],crc_delta[16],crc_delta[18],p4,p7,p10,p11,p20};
 assign next_source_crc[9]=^{crc_delta[13],crc_delta[19],p1,p4,p14,p20,p34};
 assign next_source_crc[10]=^{crc_delta[5],crc_delta[13],crc_delta[21],p1,p4,p12,p30};
 assign next_source_crc[11]=^{crc_delta[6],crc_delta[10],crc_delta[14],crc_delta[15],p2,p18,p35};
 assign next_source_crc[12]=^{crc_delta[20],crc_delta[24],p1,p16,p32,p36};
 assign next_source_crc[13]=^{crc_delta[0],crc_delta[12],crc_delta[21],crc_delta[25],crc_delta[29],p18,p21,p33};
 assign next_source_crc[14]=^{crc_delta[1],crc_delta[8],crc_delta[13],crc_delta[17],p4,p5,p7,p26};
 assign next_source_crc[15]=^{crc_delta[10],p1,p2,p12,p20,p27,p30};
 assign next_source_crc[16]=^{crc_delta[13],crc_delta[28],p6,p21,p24,p32,p35};
 assign next_source_crc[17]=^{crc_delta[5],crc_delta[14],p8,p14,p16,p17,p25,p29};
 assign next_source_crc[18]=^{crc_delta[15],crc_delta[25],p5,p9,p15,p17,p22,p26};
 assign next_source_crc[19]=^{crc_delta[1],crc_delta[10],crc_delta[25],p4,p12,p21,p27,p28};
 assign next_source_crc[20]=^{crc_delta[6],crc_delta[11],crc_delta[28],p3,p4,p10,p13,p21,p34};
 assign next_source_crc[21]=^{p0,p3,p8,p12,p29,p34};
 assign next_source_crc[22]=^{p1,p9,p14,p26,p35};
 assign next_source_crc[23]=^{crc_delta[0],crc_delta[9],crc_delta[23],crc_delta[28],p10,p14,p15,p27};
 assign next_source_crc[24]=^{crc_delta[8],crc_delta[26],crc_delta[29],p1,p6,p11,p15,p16,p36};
 assign next_source_crc[25]=^{crc_delta[20],crc_delta[30],p5,p24,p25,p29,p33};
 assign next_source_crc[26]=^{crc_delta[31],p1,p6,p8,p15,p25,p26};
 assign next_source_crc[27]=^{crc_delta[16],crc_delta[20],p2,p7,p9,p22,p23,p27};
 assign next_source_crc[28]=^{crc_delta[6],crc_delta[21],p4,p8,p16,p17,p28};
 assign next_source_crc[29]=^{crc_delta[5],crc_delta[7],p0,p2,p11,p17,p28,p31};
 assign next_source_crc[30]=^{crc_delta[3],crc_delta[4],crc_delta[7],crc_delta[19],crc_delta[20],crc_delta[22],crc_delta[24],p10,p11,p31};
 assign next_source_crc[31]=^{crc_delta[1],crc_delta[19],crc_delta[21],crc_delta[25],p0,p3,p11,p23};

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
 wire[9:0] source_row=(source_words==0)?(top_down?0:ROWS-1):producer_row;
 // For valid rows, high=5*row and row<512. The inverse of5 modulo512
 // is205, so only nine low bits are needed for the exact signature index.
 // Alignment/range/remainder checks still reject every invalid address.
 wire[9:0] query_row;wire query_multiple;
 generate if(ODD==5)begin:bounded_inverse5
  wire[11:0] digits=query_high;
  wire[5:0] digit_sum={2'd0,digits[11:8]}+{2'd0,digits[7:4]}+{2'd0,digits[3:0]};
  reg divisible;
  always @*begin case(digit_sum)
   0,5,10,15,20,25,30,35,40,45:divisible=1;default:divisible=0;
  endcase end
  // In Z/(2^9), 5^-1=(1-4)*(1+16)*(1+256)=205.
  // Truncate each stage at nine bits: only a7-bit subtract, a5-bit
  // add and one XOR remain. This is exact for ALL512 low-bit inputs,
  // not an approximation of division; range/multiple tests remain full.
  (* keep="true",use_ripple=1 *) wire[8:0] q_minus={digits[8:2]-digits[6:0],digits[1:0]};
  (* keep="true",use_ripple=1 *) wire[8:0] q_plus={q_minus[8:4]+q_minus[4:0],q_minus[3:0]};
  wire[8:0] quotient={q_plus[8]^q_plus[0],q_plus[7:0]};
  assign query_row={1'b0,quotient};assign query_multiple=divisible;
 end else begin:generic_stride
  assign query_row=query_high/ODD;assign query_multiple=query_high%ODD==0;
 end endgenerate
 wire query_ok=query_offset<ROWS*ROW_WORDS*4 && query_offset[LOW-1:0]==0 && query_multiple;
 // The write-enable includes source_slot==slot_q, so selecting slot_q
 // here is exactly equal on EVERY memory-write edge, including invalid
 // source-address cases (which never assert signature_write).
 wire[10:0] source_index={2'b00,source_row[INDEX_W-1:0]};
 wire[10:0] query_index=query_ok?({query_slot,query_row[INDEX_W-1:0]}):0;
 assign rd_len=BURST;
 // The same read port serves mutually exclusive preload verification and
 // display lookup. A second independent read inferred a 2048x32 distributed
 // RAM replica in TD, costing about 10k LUTs; it was never needed concurrently.

 // One shared address arithmetic path for the single physical read port.
 // Invalid queries retain the old exact address0, including lookup_crc when
 // lookup_valid is low. Truncation to11 bits remains at the same boundary.
 wire[1:0] signature_read_slot=verifying?slot_q:query_ok?query_slot:2'd0;
 wire[9:0] signature_read_row=verifying?verify_row:query_ok?query_row:10'd0;
 wire[10:0] signature_read_index={signature_read_slot,signature_read_row[INDEX_W-1:0]};
 reg[31:0] signature_read;
 assign expected_crc=signature_read;assign lookup_crc=signature_read;
 // No bulk reset: validity suppresses stale RAM after every reset epoch.
 always @(posedge clk)begin
  if(signature_write)signatures[source_index]<=~next_source_crc;
  signature_read<=signatures[signature_read_index];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;slot_q<=0;building<=0;complete<=0;dir<=0;
   crc_state<=32'hffffffff;base<=0;expected_addr<=0;
   timer<=0;column<=0;verify_row<=0;row_offset<=0;producer_row<=0;burst_count<=0;source_count<=0;
   verify_done<=0;verify_pass<=0;fault<=0;approved<=0;rd_req<=0;rd_addr<=0;
   lookup_valid<=0;bad_addr<=0;bad_expected<=0;bad_actual<=0;checked_rows<=0;end
  else begin
   lookup_valid<=!verifying && query_ok && approved[query_slot];
   if(frame_begin && !fault)begin
    slot_q<=frame_slot;base<=`SV_SLOT_BASE(frame_slot);building<=1;complete<=0;
    approved[frame_slot]<=0;source_count<=0;column<=0;crc_state<=32'hffffffff;producer_row<=top_down?0:ROWS-1;
    expected_addr<=`SV_SLOT_BASE(frame_slot)+(top_down?0:(ROWS-1)*ROW_WORDS*4);
    dir<=top_down;verify_done<=0;verify_pass<=0;checked_rows<=0;state<=IDLE;rd_req<=0;
   end else if(building && accepted && !fault)begin
    if(!source_beat)begin fault<=1;building<=0;bad_addr<=write_addr;bad_expected<=wanted;bad_actual<=write_addr;end
    else begin
     if(source_words==0)begin dir<=top_down;producer_row<=top_down?0:ROWS-1;end
     source_count<=source_words+1'b1;
     if(column==ROW_WORDS-1)begin
      column<=0;crc_state<=32'hffffffff;
      // No live source transaction follows the final word. Avoid computing an
      // unused below-base pointer after the bottom-up last row.
      if(source_words!=FRAME_WORDS-1)begin
       producer_row<=dir?source_row+1'b1:source_row-1'b1;
       expected_addr<=dir?wanted+4:wanted-(ROW_WORDS*8)+4;
      end
     end else begin column<=column+1'b1;crc_state<=next_source_crc;expected_addr<=wanted+4;end
     if(source_words==ROWS*ROW_WORDS-1)begin complete<=1;building<=0;end
    end
   end
   if(!fault)begin
    if(state==IDLE || state==DONE || capture || rd_ack)timer<=0;else timer<=timer+1'b1;
    case(state)
     IDLE:if(verify_start)begin
      if(!complete)begin fault<=1;verify_done<=1;verify_pass<=0;bad_expected<=ROWS*ROW_WORDS;bad_actual<=source_words;end
      else begin verify_row<=0;row_offset<=0;crc_state<=32'hffffffff;state<=RETIRE;end
     end
     RETIRE:if(!rd_busy && verify_allow)begin
      rd_addr<=base+(verify_row*ROW_WORDS+row_offset)*4;rd_req<=1;burst_count<=0;state<=REQUEST;
     end
     REQUEST:if(rd_ack)begin rd_req<=0;state<=COLLECT;end
     COLLECT:;
     CHECK:if(~crc_state!=expected_crc)begin
      fault<=1;verify_done<=1;verify_pass<=0;bad_addr<=base+verify_row*ROW_WORDS*4;
      bad_expected<=expected_crc;bad_actual<=~crc_state;state<=DONE;
     end else begin
      checked_rows<=checked_rows+1'b1;
      if(verify_row==ROWS-1)begin approved[slot_q]<=1;verify_done<=1;verify_pass<=1;state<=DONE;end
      else begin verify_row<=verify_row+1'b1;row_offset<=0;crc_state<=32'hffffffff;state<=RETIRE;end
     end
     DONE:;
     default:state<=IDLE;
    endcase
    if(capture)begin
     burst_count<=burst_count+1'b1;crc_state<=next_verify_crc;
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
  if(source_beat && verifying)$fatal(1,"source overlaps readback phase");
  if(frame_begin && verifying)$fatal(1,"new source frame overlaps readback phase");
  if(source_beat && capture)$fatal(1,"guard phase contract violated");
  if(source_words>FRAME_WORDS)$fatal(1,"source counter exceeded frame bound");
 end
 initial if(ROW_WORDS%BURST || ROW_WORDS<64 || BURST!=64 || ROWS<1 || ROWS>480 || TIMEOUT<2)
 $fatal(1,"unsupported row signature geometry");
 // synthesis translate_on
endmodule

