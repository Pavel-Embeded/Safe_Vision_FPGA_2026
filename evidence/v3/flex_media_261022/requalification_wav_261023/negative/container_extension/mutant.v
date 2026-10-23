// Compact sector-switchable PCM WAV parser. All state uses REF clk.
// Context is exactly 111 bits. Header assembly and PCM assembly share word;
// PCM valid holds that word until ready. No metadata copy or second PCM copy.
// RIFF/container bounds use widened sums; all legal extension/padding bytes are
// consumed. Data chunks must contain nonempty whole stereo PCM16 frames.
module v3_wav_parser_compact_ctx #(parameter integer PIPELINED_BOUNDS=0)(
 input wire clk,rst_n,start,context_load,context_enable,
 input wire[110:0] context_in,output wire[110:0] context_out,
 input wire[31:0] first_clus,file_size,input wire[7:0] track_id,
 input wire[7:0] din,input wire din_valid,din_eof,output wire din_ready,
 output wire[31:0] sample,output reg pcm_valid,input wire pcm_ready,
 output reg wav_error,
 // Mode1 sideband is part of the same atomic sector-boundary context.
 // Appended optional ports preserve every legacy positional connection.
 input wire[33:0] bound_context_in,output wire[33:0] bound_context_out);
localparam[3:0] W_IDLE=0,W_HDR=1,W_CHUNK=2,W_FMT=3,W_SKIP=4,
 W_DATA=5,W_PAD=6,W_END=7,W_ERR=8;
localparam[1:0] K_OTHER=0,K_FMT=1,K_DATA=2;
reg[3:0] state,index;
reg[31:0] word,riff_left,left;
reg[1:0] kind;
reg pad,fmt_seen,data_seen;
wire[1:0] phase=index[1:0]; // Named observation point used by split-sample TB.
wire[31:0] assembled={din,word[31:8]};
wire[32:0] riff_end={1'b0,assembled}+33'd8;
wire[33:0] padded_end={2'd0,assembled}+34'd1+assembled[0];
// a+1+a[0] > r iff r==0 || a>(r-1) || (a[0] && a==(r-1)).
// Reuse the existing remaining-byte decrement, instead of adding padding to
// the newly assembled header word before a wide comparison. No state/latency
// or111-bit context change; the widened legacy expressions remain debug views.
(* use_ripple=1 *) wire[31:0] riff_after_byte=riff_left-32'd1;
(* use_ripple=1 *) wire[31:0] file_payload_limit=file_size-32'd8;
wire[3:0] chunk_gt,chunk_eq,file_gt,file_eq;
genvar bound_byte;
generate for(bound_byte=0;bound_byte<4;bound_byte=bound_byte+1)begin:bound_compare
 assign chunk_gt[bound_byte]=assembled[8*bound_byte+:8]>riff_after_byte[8*bound_byte+:8];
 assign chunk_eq[bound_byte]=assembled[8*bound_byte+:8]==riff_after_byte[8*bound_byte+:8];
 assign file_gt[bound_byte]=assembled[8*bound_byte+:8]>file_payload_limit[8*bound_byte+:8];
 assign file_eq[bound_byte]=assembled[8*bound_byte+:8]==file_payload_limit[8*bound_byte+:8];
end endgenerate
function greater_bytes;input[3:0] g,e;
 begin greater_bytes=g[3]|(e[3]&g[2])|(e[3]&e[2]&g[1])|(e[3]&e[2]&e[1]&g[0]);end
endfunction
wire padded_overrun=(riff_left==0)||greater_bytes(chunk_gt,chunk_eq)||(assembled[0]&&(&chunk_eq));
wire riff_oversize=(file_size<8)||greater_bytes(file_gt,file_eq);
wire riff_overflow=&assembled[31:3];

assign sample=word;
assign din_ready=!pcm_valid&&(state==W_HDR||state==W_CHUNK||state==W_FMT||state==W_SKIP||
 state==W_PAD||state==W_END||state==W_DATA);
assign context_out={pcm_valid,wav_error,state,index,word,riff_left,left,kind,pad,fmt_seen,data_seen};
// Mode1 compares one little-endian size byte on each accepted byte.
// At index4 capture the settled limit. At index7 only an8-bit comparison
// remains. Size/RIFF publication and PCM suppression retain their old edge.
// A header's file_size must remain stable; the source holds its descriptor.
wire fast_padded_overrun,fast_riff_oversize;
generate if(PIPELINED_BOUNDS)begin:bytewise_bounds
 reg[31:0] limit_q;reg carry_q,greater_q;
 (* use_ripple=1 *) wire[31:0] first_limit=(state==W_HDR)?file_size-32'd8:riff_left-32'd4;
 wire[7:0] limit_byte=(index==4)?first_limit[7:0]:limit_q[index[1:0]*8+:8];
 wire round_bit=(index==4)?((state==W_CHUNK)&&din[0]):carry_q;
 wire[8:0] byte_sum={1'b0,din}+{8'd0,round_bit};
 wire prior_greater=(index==4)?1'b0:greater_q;
 wire next_greater=(byte_sum[7:0]>limit_byte)||((byte_sum[7:0]==limit_byte)&&prior_greater);
 assign fast_padded_overrun=(riff_left==0)||byte_sum[8]||next_greater;
 assign fast_riff_oversize=(file_size<8)||next_greater;
 assign bound_context_out={limit_q,carry_q,greater_q};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin limit_q<=0;carry_q<=0;greater_q<=0;end
  else if(context_load){limit_q,carry_q,greater_q}<=bound_context_in;
  else if(context_enable)begin
   if(start)begin limit_q<=0;carry_q<=0;greater_q<=0;end
   else if(din_valid&&din_ready&&(state==W_HDR||state==W_CHUNK)&&index>=4&&index<=7)begin
    if(index==4)limit_q<=first_limit;
    carry_q<=byte_sum[8];greater_q<=next_greater;
   end
  end
 end
end else begin:legacy_bounds
 assign bound_context_out=34'd0;
 assign fast_padded_overrun=1'b0;assign fast_riff_oversize=1'b0;
end endgenerate
reg reject_now,chunk_end_now;
always@(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  pcm_valid<=0;wav_error<=0;state<=W_IDLE;index<=0;word<=0;
  riff_left<=0;left<=0;kind<=K_OTHER;pad<=0;fmt_seen<=0;data_seen<=0;
 end else if(context_load)
  {pcm_valid,wav_error,state,index,word,riff_left,left,kind,pad,fmt_seen,data_seen}<=context_in;
 else if(context_enable)begin
  if(pcm_valid&&pcm_ready)pcm_valid<=0;
  if(start)begin
   pcm_valid<=0;wav_error<=0;state<=W_HDR;index<=0;word<=0;
   riff_left<=0;left<=0;kind<=K_OTHER;pad<=0;fmt_seen<=0;data_seen<=0;
  end else if(din_valid&&din_ready)begin
   reject_now=0;chunk_end_now=0;
   if(state==W_HDR)begin
    word<=assembled;
    if(index==3&&assembled!=32'h46464952)reject_now=1;
    if(index==7)begin
     if(assembled<4||riff_overflow||(file_size!=0&&(PIPELINED_BOUNDS?fast_riff_oversize:riff_oversize)))reject_now=1;
     riff_left<=assembled-4;
    end
    if(index==11)begin
     if(assembled!=32'h45564157||riff_left<8)reject_now=1;
     state<=W_CHUNK;index<=0;
    end else index<=index+1'b1;
    if(din_eof)reject_now=1;
   end else if(state!=W_END)begin
    if(riff_left==0)reject_now=1;
    riff_left<=riff_after_byte;
    case(state)
     W_CHUNK:begin
      word<=assembled;
      if(index==3)begin
       if(assembled==32'h20746d66)kind<=K_FMT;
       else if(assembled==32'h61746164)kind<=K_DATA;
       else kind<=K_OTHER;
      end
      if(index==7)begin
       if(PIPELINED_BOUNDS)begin if(fast_padded_overrun)reject_now=1;end
       else begin if(padded_overrun)reject_now=1;end
       left<=(kind==K_FMT&&assembled>16)?32'd16:assembled;pad<=assembled[0];index<=0;
       if(kind==K_FMT)begin
        if(assembled<16)reject_now=1;
        fmt_seen<=0;state<=W_FMT;
       end else if(kind==K_DATA)begin
        if(!fmt_seen||assembled==0||assembled[1:0]!=0)reject_now=1;
        data_seen<=1;state<=W_DATA;
       end else if(assembled==0)begin chunk_end_now=1;state<=W_CHUNK;end
       else state<=W_SKIP;
      end else index<=index+1'b1;
     end
     W_FMT:begin
      left<=left-1'b1;
      // A single assembly word is checked immediately after each field.
      if(index<8||index>=14)word<=assembled;
      if(index==1&&assembled[31:16]!=16'd1)reject_now=1;
      if(index==3&&assembled[31:16]!=16'd2)reject_now=1;
      if(index==7&&assembled!=32'd48000)reject_now=1;
      if(index==15)begin
       if(assembled[31:16]!=16'd16)reject_now=1;
       fmt_seen<=1;
       if(left==1)begin chunk_end_now=1;state<=W_CHUNK;index<=0;end
       else state<=W_SKIP;
      end else index<=index+1'b1;
     end
     W_SKIP:begin
      left<=left-1'b1;
      if(left==1)begin
       if(pad)state<=W_PAD;
       else begin chunk_end_now=1;state<=W_CHUNK;index<=0;end
      end
     end
     W_DATA:begin
      word<=assembled;left<=left-1'b1;index<=index+1'b1;
      if(index==3)begin pcm_valid<=1;index<=0;end
      if(left==1)begin
       if(index!=3)reject_now=1;
       chunk_end_now=1;state<=W_CHUNK;index<=0;
      end
     end
     W_PAD:begin chunk_end_now=1;state<=W_CHUNK;index<=0;end
     default:reject_now=1;
    endcase
    if(riff_left==1)begin
     if(!chunk_end_now||!data_seen)reject_now=1;
     else state<=W_END;
    end else if(chunk_end_now&&riff_left<9)reject_now=1;
    if(din_eof&&!(chunk_end_now&&riff_left==1))reject_now=1;
   end
   // Never publish a PCM pair on a byte already known to violate a bound.
   if(reject_now)begin wav_error<=1;pcm_valid<=0;state<=W_ERR;end
  end
 end
end
endmodule
