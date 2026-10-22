// FAT32 names: one complete validated UTF16 name in one 256x16 RAM.
// The scanner stalls while busy. Bytes0..10 share one88-bit prefix register
// for the short alias or the first five LFN words. After attr=0x0f confirms
// an LFN, five shift/flush edges write those words; remaining words stream
// directly into RAM on their high byte. No32-byte entry/multiplexer exists.
// The same native RAM9K holds LFN words0..255 and expanded8.3 words256..267.
// Alias bytes stream into that second bank; a one-edge stall inserts its dot.
// ASCII a-z folds to A-Z; all other UTF16 code units retain their value.
module v3_fat_name_store(
 input wire clk,rst_n,scan_start,byte_valid,input wire[4:0] byte_offset,
 input wire[7:0] data,input wire[7:0] read_address,
 output wire[15:0] read_data,output wire[8:0] name_length,
 output reg busy,output reg lfn_valid,output wire[87:0] raw_short_name);
 (* ram_style="bram" *)reg[15:0] name_ram[0:511];
 reg[15:0] ram_read;
 reg[87:0] prefix;
 assign raw_short_name=prefix;
 reg[3:0] base_length;reg[1:0] extension_length;
 reg chain_valid,is_lfn,flush_lfn;
 reg[4:0] expected_order;
 reg[7:0] chain_checksum,alias_checksum,char_low;
 reg[8:0] lfn_length,char_address;
 reg[2:0] flush_left;
 wire[4:0] order=prefix[84:80];
 wire fragment_last=prefix[86];
 wire entry_order_ok=order!=0&&order<=20&&(prefix[87:80]&8'ha0)==0;
 function[15:0] fold;input[15:0] c;begin fold=c>=16'h61&&c<=16'h7a ? c-16'h20 : c;end endfunction
 wire streamed_high=byte_valid&&is_lfn&&(
  byte_offset==15||byte_offset==17||byte_offset==19||byte_offset==21||
  byte_offset==23||byte_offset==25||byte_offset==29||byte_offset==31);
 wire write_character=(busy&&flush_lfn)||streamed_high;
 wire[15:0] char_data=busy?{prefix[71:64],prefix[79:72]}:{data,char_low};
 wire alias_flush=busy&&!flush_lfn;
 wire alias_write=(byte_valid&&byte_offset<=10)||alias_flush;
 wire[3:0] tail_index=base_length+(alias_flush?4'd1:byte_offset==8?4'd0:byte_offset[3:0]-4'd7);
 wire[3:0] alias_index=!alias_flush&&byte_offset<8?byte_offset[3:0]:tail_index;
 wire[15:0] alias_data=alias_flush?{8'd0,char_low}:byte_offset==8?16'h002e:{8'd0,data};
 assign name_length=lfn_valid?lfn_length:{5'd0,base_length}+(extension_length!=0?{7'd0,extension_length}+9'd1:9'd0);
 assign read_data=ram_read;
 always @(posedge clk)begin
  ram_read<=name_ram[{!lfn_valid,read_address}];
  if(write_character&&char_address<256)name_ram[{1'b0,char_address[7:0]}]<=fold(char_data);
  else if(alias_write)name_ram[{1'b1,4'd0,alias_index}]<=fold(alias_data);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;lfn_valid<=0;chain_valid<=0;is_lfn<=0;flush_lfn<=0;expected_order<=0;chain_checksum<=0;
   alias_checksum<=0;char_low<=0;lfn_length<=0;char_address<=0;flush_left<=0;
   prefix<=0;base_length<=0;extension_length<=0;
  end else if(scan_start)begin busy<=0;lfn_valid<=0;chain_valid<=0;expected_order<=0;lfn_length<=0;is_lfn<=0;end
  else begin
   if(write_character)begin
    if(char_data==0&&char_address<lfn_length)lfn_length<=char_address;
    if(char_address>=255&&char_data!=0&&char_data!=16'hffff)chain_valid<=0;
    char_address<=char_address+1'b1;
   end
   if(busy)begin
    if(flush_lfn)begin
     prefix<={prefix[87:80],prefix[63:0],16'd0};
     flush_left<=flush_left-1'b1;
     if(flush_left==1)busy<=0;
    end else busy<=0;
   end
   if(byte_valid)begin
    if(byte_offset<=10)begin
     prefix<={prefix[79:0],data};
     if(byte_offset==0)begin alias_checksum<=data;base_length<=data!=8'h20 ? 4'd1 : 4'd0;extension_length<=0;end
     else begin
      alias_checksum<={alias_checksum[0],alias_checksum[7:1]}+data;
      if(byte_offset<8&&data!=8'h20)base_length<=byte_offset[3:0]+4'd1;
      if(byte_offset>=8&&data!=8'h20)extension_length<=byte_offset[1:0]+2'd1;
     end
    end
    case(byte_offset)
     8:begin char_low<=data;busy<=1;flush_lfn<=0;end
     11:begin
      is_lfn<=data==8'h0f;
      if(data==8'h0f)begin
       if(fragment_last)begin
        chain_valid<=entry_order_ok;
        lfn_length<=order>=20?9'd255:{4'd0,order}*9'd13;
       end else if(!entry_order_ok||!chain_valid||order!=expected_order)chain_valid<=0;
       expected_order<=order-1'b1;
       char_address<=({4'd0,order}-9'd1)*9'd13;
       flush_left<=5;flush_lfn<=1;busy<=1;
      end
     end
     12:if(is_lfn&&data!=0)chain_valid<=0;
     13:if(is_lfn)begin
      if(fragment_last)chain_checksum<=data;
      else if(data!=chain_checksum)chain_valid<=0;
     end
     14,16,18,20,22,24,28,30:char_low<=data;
     26,27:if(is_lfn&&data!=0)chain_valid<=0;
     31:if(!is_lfn)begin
      lfn_valid<=chain_valid&&expected_order==0&&1'b1&&lfn_length!=0;
      chain_valid<=0;expected_order<=0;
     end
     default:;
    endcase
   end
  end
 end
endmodule
