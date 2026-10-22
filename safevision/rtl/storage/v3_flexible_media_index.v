// One minimum filename per pass. Compare complete validated UTF16 names from
// the scanner; retain cursor/best in two RAM banks. A second scan finds a
// same-stem WAV regardless of its directory position. Fallback WAVs use stable
// directory order and wrap to the first when fewer than four exist.
// Cursors advance on successful and rejected BMPs through caller idx_clear.
module v3_flexible_media_index(
 input wire clk,rst_n,idx_clear,idx_commit,input wire[15:0] cursor_key,
 input wire[1:0] resident_slot,input wire[87:0] ent_name,
 input wire[7:0] ent_attr,input wire[31:0] ent_first_clus,ent_size,
 input wire[15:0] ent_index,input wire ent_valid,output wire ent_ready,
 output wire[7:0] name_address,input wire[15:0] name_data,input wire[8:0] name_length,
 output reg rescan_request,idx_done,output reg[3:0] file_cnt,file_valid,
 output reg[15:0] sel_key,output reg[31:0] sel_first_clus,sel_size,
 output wire sel_valid,output reg[31:0] sel_wav_first_clus,sel_wav_size,
 output reg sel_wav_valid,output reg[15:0] bmp_seen,wav_seen);
 localparam IDLE=0,WAIT_NAME=1,COMPARE=2,COPY_WAIT=3,COPY_WORD=4,RELEASE=5;
 reg[2:0] state;reg[1:0] phase;reg compare_best;
 reg best_valid,cursor_valid,best_bank,cursor_bank;
 reg[8:0] best_length,cursor_length,character;
 // ent_valid/ent_ready freezes raw scanner metadata throughout compare/copy.
 wire[8:0] current_length=phase==2 ? name_length-9'd4 : name_length;
 wire[31:0] current_cluster=ent_first_clus,current_size=ent_size;
 wire[15:0] current_index=ent_index;
 (* ram_style="bram" *)reg[15:0] names[0:511];
 reg[15:0] retained_character;
 wire selected_bank=compare_best?best_bank:cursor_bank;
 always @(posedge clk)begin
  retained_character<=names[{selected_bank,character[7:0]}];
  if(state==COPY_WORD)names[{best_bank,character[7:0]}]<=name_data;
 end
 assign name_address=character[7:0];
 assign ent_ready=state==RELEASE;
 assign sel_valid=best_valid;
 function[7:0] upper;input[7:0] c;begin upper=c&8'hdf;end endfunction
 wire bmp=upper(ent_name[23:16])==8'h42&&upper(ent_name[15:8])==8'h4d&&upper(ent_name[7:0])==8'h50;
 wire wav=upper(ent_name[23:16])==8'h57&&upper(ent_name[15:8])==8'h41&&upper(ent_name[7:0])==8'h56;
 wire legal=ent_attr!=8'h0f&&!ent_attr[3]&&!ent_attr[4]&&ent_name[87:80]!=8'he5&&ent_name[87:80]!=0&&ent_first_clus>=2&&ent_size!=0&&ent_index!=16'hffff;
 // The ordinal candidate supersedes the first candidate when it exists.
 // One 64-bit descriptor therefore represents both fallback cases exactly.
 reg[31:0] fallback_wav_cluster,fallback_wav_size;
 reg fallback_wav_valid,paired,commit_pending;
 reg[2:0] wav_ordinal;
 wire[8:0] target_length=phase==2?(best_length>=4?best_length-4:0):(compare_best?best_length:cursor_length);
 wire current_end=character>=current_length,target_end=character>=target_length;
 wire both_character=!current_end&&!target_end;
 wire char_equal=(current_end&&target_end)||(both_character&&name_data==retained_character);
 wire char_less=(current_end&&!target_end)||(both_character&&name_data<retained_character);
 wire char_greater=!char_equal&&!char_less;
 task release_entry;begin state<=RELEASE;end endtask
 task copy_current;begin character<=0;state<=COPY_WAIT;end endtask
 task select_current_metadata;begin
  best_valid<=1;best_length<=current_length;
  sel_first_clus<=current_cluster;sel_size<=current_size;sel_key<=current_index+16'd1;
 end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;phase<=0;compare_best<=0;best_valid<=0;cursor_valid<=0;best_bank<=0;cursor_bank<=1;
   best_length<=0;cursor_length<=0;character<=0;
   rescan_request<=0;idx_done<=0;file_cnt<=0;file_valid<=0;
   sel_key<=0;sel_first_clus<=0;sel_size<=0;sel_wav_first_clus<=0;sel_wav_size<=0;sel_wav_valid<=0;
   bmp_seen<=0;wav_seen<=0;wav_ordinal<=0;fallback_wav_cluster<=0;fallback_wav_size<=0;
   fallback_wav_valid<=0;paired<=0;commit_pending<=0;
  end else begin
   idx_done<=0;rescan_request<=0;
   if(idx_clear)begin
    phase<=1;state<=IDLE;character<=0;
    cursor_valid<=cursor_key!=0&&best_valid;cursor_length<=best_length;
    cursor_bank<=best_bank;best_bank<=~best_bank;best_valid<=0;
    file_cnt<=0;file_valid<=0;sel_wav_valid<=0;bmp_seen<=0;wav_seen<=0;wav_ordinal<=0;
    fallback_wav_valid<=0;paired<=0;commit_pending<=0;
   end else begin
    case(state)
     IDLE:if(ent_valid)begin
      if(phase==1&&legal&&bmp)begin
       if(bmp_seen!=65535)bmp_seen<=bmp_seen+1'b1;
       
       character<=0;compare_best<=0;
       if(cursor_valid)state<=WAIT_NAME;
       else if(best_valid)begin compare_best<=1;state<=WAIT_NAME;end
       else state<=COPY_WAIT;
      end else if(phase==2&&legal&&wav)begin
       if(wav_seen!=65535)wav_seen<=wav_seen+1'b1;
       if(wav_ordinal<4)wav_ordinal<=wav_ordinal+1'b1;
       if(!fallback_wav_valid||wav_ordinal=={1'b0,resident_slot})begin
        fallback_wav_valid<=1;fallback_wav_cluster<=ent_first_clus;fallback_wav_size<=ent_size;
       end
       
       if(!paired&&name_length>=4&&best_length>=4&&name_length==best_length)begin
        character<=0;compare_best<=1;state<=WAIT_NAME;
       end else release_entry();
      end else release_entry();
     end
     WAIT_NAME:state<=COMPARE;
     COMPARE:begin
      if(phase==2)begin
       if(!char_equal)release_entry();
       else if(character==current_length)begin paired<=1;sel_wav_first_clus<=current_cluster;sel_wav_size<=current_size;release_entry();end
       else begin character<=character+1'b1;state<=WAIT_NAME;end
      end else if(compare_best)begin
       if(char_less)copy_current();
       else if(char_greater||character==current_length)release_entry();
       else begin character<=character+1'b1;state<=WAIT_NAME;end
      end else begin
       if(char_greater)begin
        if(best_valid)begin compare_best<=1;character<=0;state<=WAIT_NAME;end else copy_current();
       end else if(char_less||character==current_length)release_entry();
       else begin character<=character+1'b1;state<=WAIT_NAME;end
      end
     end
     COPY_WAIT:state<=COPY_WORD;
     COPY_WORD:if(character+1>=current_length)begin select_current_metadata();release_entry();end
      else begin character<=character+1'b1;state<=COPY_WAIT;end
     RELEASE:state<=IDLE;
     default:state<=IDLE;
    endcase
    if(idx_commit)commit_pending<=1;
    if(commit_pending&&state==IDLE&&!ent_valid)begin
     commit_pending<=0;
     if(phase==1&&best_valid)begin phase<=2;rescan_request<=1;wav_seen<=0;wav_ordinal<=0;end
     else begin
      phase<=0;idx_done<=1;file_cnt<=best_valid?1:0;file_valid<=best_valid?1:0;
      sel_wav_valid<=paired||fallback_wav_valid;
      if(!paired)begin
       sel_wav_first_clus<=fallback_wav_cluster;
       sel_wav_size<=fallback_wav_size;
      end
     end
    end
   end
  end
 end
endmodule
