// FAT32 long names: complete validated UTF16 ordinal names, not alias hashes.
// A256-word RAM holds only the current entry. Caller holds the scanner entry
// until every requested character has been read; no next-entry overwrite.
// ASCII letters are folded to upper case for deterministic case-insensitive
// sorting; other UTF16 code units are retained exactly, including Chinese.
module v3_fat_name_store(
 input wire clk,rst_n,scan_start,byte_valid,input wire[4:0] byte_offset,
 input wire[7:0] data,input wire[7:0] read_address,
 output wire[15:0] read_data,output wire[8:0] name_length,
 output reg busy,output reg lfn_valid);
 reg[7:0] entry[0:31];
 (* ram_style="bram" *)reg[15:0] name_ram[0:255];
 reg[15:0] ram_read,short_read;
 reg[87:0] short_name;
 reg[3:0] base_length;reg[1:0] extension_length;
 reg chain_valid;reg[4:0] expected_order;
 reg[7:0] chain_checksum;
 reg[8:0] lfn_length,base_address;
 reg[3:0] character;
 function[4:0] char_offset;input[3:0] i;begin
  case(i)
   0:char_offset=1;1:char_offset=3;2:char_offset=5;3:char_offset=7;4:char_offset=9;
   5:char_offset=14;6:char_offset=16;7:char_offset=18;8:char_offset=20;9:char_offset=22;10:char_offset=24;
   11:char_offset=28;default:char_offset=30;
  endcase
 end endfunction
 function[15:0] fold;input[15:0] c;begin fold=c>=16'h61&&c<=16'h7a ? c-16'h20 : c;end endfunction
 wire[8:0] char_address=base_address+character;
 wire[4:0] offset=char_offset(character);
 wire[15:0] char_data={entry[offset+1'b1],entry[offset]};
 wire[4:0] order=entry[0][4:0];
 wire entry_order_ok=order!=0&&order<=20&&(entry[0]&8'ha0)==0;
 wire entry_reserved_ok=entry[12]==0&&entry[26]==0&&entry[27]==0;
 reg[7:0] short_checksum;
 integer i;reg[3:0] next_base;reg[1:0] next_ext;
 always @*begin
  short_checksum=0;next_base=0;next_ext=0;
  for(i=0;i<11;i=i+1)short_checksum={short_checksum[0],short_checksum[7:1]}+entry[i];
  for(i=0;i<8;i=i+1)if(entry[i]!=8'h20)next_base=i+1;
  for(i=0;i<3;i=i+1)if(entry[i+8]!=8'h20)next_ext=i+1;
 end
 reg[7:0] short_byte;
 always @*begin
  short_byte=0;
  if(read_address<base_length)short_byte=short_name[87-read_address*8-:8];
  else if(extension_length!=0&&read_address==base_length)short_byte=8'h2e;
  else if(extension_length!=0&&read_address<base_length+extension_length+1)
   short_byte=short_name[23-(read_address-base_length-1)*8-:8];
 end
 assign name_length=lfn_valid?lfn_length:{5'd0,base_length}+(extension_length!=0?{7'd0,extension_length}+9'd1:9'd0);
 assign read_data=lfn_valid?ram_read:short_read;
 always @(posedge clk)begin
  ram_read<=name_ram[read_address];short_read<=fold({8'd0,short_byte});
  if(busy&&char_address<256)name_ram[char_address[7:0]]<=fold(char_data);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;lfn_valid<=0;chain_valid<=0;expected_order<=0;chain_checksum<=0;
   lfn_length<=0;base_address<=0;character<=0;short_name<=0;base_length<=0;extension_length<=0;
  end else if(scan_start)begin busy<=0;lfn_valid<=0;chain_valid<=0;expected_order<=0;lfn_length<=0;end
  else begin
   if(busy)begin
    if(char_data==0&&char_address<lfn_length)lfn_length<=char_address;
    if(char_address>=255&&char_data!=0&&char_data!=16'hffff)chain_valid<=0;
    if(character==12)busy<=0;else character<=character+1'b1;
   end
   if(byte_valid)begin
    entry[byte_offset]<=data;
    if(byte_offset==31)begin
     if(entry[11]==8'h0f)begin
      if(entry[0][6])begin
       chain_valid<=entry_order_ok&&entry_reserved_ok;
       chain_checksum<=entry[13];lfn_length<=order>=20?9'd255:{4'd0,order}*9'd13;
      end else if(!entry_order_ok||!entry_reserved_ok||!chain_valid||order!=expected_order||entry[13]!=chain_checksum)chain_valid<=0;
      expected_order<=order-1'b1;
      base_address<=({4'd0,order}-9'd1)*9'd13;character<=0;busy<=1;
     end else begin
      short_name<={entry[0],entry[1],entry[2],entry[3],entry[4],entry[5],entry[6],entry[7],entry[8],entry[9],entry[10]};
      base_length<=next_base;extension_length<=next_ext;
      lfn_valid<=chain_valid&&expected_order==0&&short_checksum==chain_checksum&&lfn_length!=0;
      chain_valid<=0;expected_order<=0;
     end
    end
   end
  end
 end
endmodule
