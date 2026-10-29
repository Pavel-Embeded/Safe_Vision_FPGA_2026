


module v3_wav_parser_compact_ctx(
 input wire clk,rst_n,start,context_load,context_enable,
 input wire[110:0] context_in,output wire[110:0] context_out,
 input wire[31:0] first_clus,file_size,input wire[7:0] track_id,
 input wire[7:0] din,input wire din_valid,din_eof,output wire din_ready,
 output wire[31:0] sample,output reg pcm_valid,input wire pcm_ready,
 output reg wav_error);
localparam[3:0] W_IDLE=0,W_HDR=1,W_CHUNK=2,W_FMT=3,W_SKIP=4,
 W_DATA=5,W_PAD=6,W_END=7,W_ERR=8;
localparam[1:0] K_OTHER=0,K_FMT=1,K_DATA=2;
reg[3:0] state,index;
reg[31:0] word,riff_left,left;
reg[1:0] kind;
reg pad,fmt_seen,data_seen;
wire[1:0] phase=index[1:0];
wire[31:0] assembled={din,word[31:8]};
wire[32:0] riff_end={1'b0,assembled}+33'd8;
wire[33:0] padded_end={2'd0,assembled}+34'd1+assembled[0];
assign sample=word;
assign din_ready=!pcm_valid&&(state==W_HDR||state==W_CHUNK||state==W_FMT||state==W_SKIP||
 state==W_PAD||state==W_END||state==W_DATA);
assign context_out={pcm_valid,wav_error,state,index,word,riff_left,left,kind,pad,fmt_seen,data_seen};
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
     if(assembled<4||riff_end[32]||(file_size!=0&&riff_end>file_size))reject_now=1;
     riff_left<=assembled-4;
    end
    if(index==11)begin
     if(assembled!=32'h45564157||riff_left<8)reject_now=1;
     state<=W_CHUNK;index<=0;
    end else index<=index+1'b1;
    if(din_eof)reject_now=1;
   end else if(state!=W_END)begin
    if(riff_left==0)reject_now=1;
    riff_left<=riff_left-1'b1;
    case(state)
     W_CHUNK:begin
      word<=assembled;
      if(index==3)begin
       if(assembled==32'h20746d66)kind<=K_FMT;
       else if(assembled==32'h61746164)kind<=K_DATA;
       else kind<=K_OTHER;
      end
      if(index==7)begin
       if(padded_end>{2'd0,riff_left})reject_now=1;
       left<=assembled;pad<=assembled[0];index<=0;
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

   if(reject_now)begin wav_error<=1;pcm_valid<=0;state<=W_ERR;end
  end
 end
end
endmodule
