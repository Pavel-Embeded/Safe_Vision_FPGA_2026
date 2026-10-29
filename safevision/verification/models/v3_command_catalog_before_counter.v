


module v3_command_catalog_before_counter #(parameter integer TIMEOUT=10000000,parameter CATALOG_FILE="../../assets/control/v3_command_catalog.mem")(
 input wire clk,rst_n,rx_valid,input wire [7:0] rx_data,
 output reg command_valid,output wire [7:0] target,
 output wire [95:0] name,output wire signed [31:0] value,output wire query,
 output reg reply_valid,output reg [7:0] reply_code,
 output reg [31:0] rejected,output wire [6:0] catalog_id);
 reg [2:0] state;reg [7:0] checksum,received;
 localparam integer TIMER_W=TIMEOUT>1 ? $clog2(TIMEOUT):1;
 reg [TIMER_W-1:0] timer;reg [23:0] number;
 reg [5:0] length;

 reg [3:0] names;reg digit_seen;reg negative,argument;
 reg [7:0] dest;reg ask;


 reg[95:0] catalog_name;
 assign target=dest;assign name=catalog_name;assign query=ask;


 (* preserve="true" *) reg signed[31:0] value_reg;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)value_reg<=0;
  else value_reg<=negative ? -$signed({8'd0,number}):$signed({8'd0,number});
 assign value=value_reg;


 localparam integer CATALOG_N=36,CATALOG_AW=6;
 reg[CATALOG_N-1:0] possible;
 reg[1:0] scan_state;reg[CATALOG_AW-1:0] scan_index;
 reg[3:0] held_position;reg[7:0] held_character;

 (* max_fanout=8 *) reg[6:0] command_id;
 assign catalog_id=command_id;
 wire name_byte=rx_valid&&state==1&&length>=2&&length<32&&!argument&&!ask&&names<12&&rx_data>=65&&rx_data<=90;
 wire match_busy=scan_state!=0;
 (* ram_style="block" *) reg[7:0] command_rom[0:1023];
 reg[7:0] command_word;
 initial $readmemh(CATALOG_FILE,command_rom);
 always @(posedge clk)command_word<=command_rom[{scan_index,held_position}];
 wire character_match=held_character=={1'b0,command_word[6:0]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin possible<={CATALOG_N{1'b1}};scan_state<=0;scan_index<=0;held_position<=0;held_character<=0;command_id<=0;end
  else if(rx_valid&&rx_data==36)begin possible<={CATALOG_N{1'b1}};scan_state<=0;scan_index<=0;command_id<=0;end
  else if(name_byte&&!match_busy)begin held_character<=rx_data;held_position<=names;scan_index<=0;scan_state<=1;command_id<=0;end
  else case(scan_state)
   1:scan_state<=2;
   2:begin
    possible<={possible[0]&&character_match,possible[CATALOG_N-1:1]};
    if(possible[0]&&character_match&&command_word[7])command_id<=scan_index+1'b1;
    if(scan_index==CATALOG_N-1)scan_state<=0;else begin scan_index<=scan_index+1'b1;scan_state<=1;end
   end
   default:;
  endcase
 end
 always @*begin catalog_name=0;case(command_id)
  7'd1:catalog_name=96'h00000000000000414c504841;
  7'd2:catalog_name=96'h00000000000000004155544f;
  7'd3:catalog_name=96'h000000004241444552524f52;
  7'd4:catalog_name=96'h000000000000004241444944;
  7'd5:catalog_name=96'h000000000000425249474854;
  7'd6:catalog_name=96'h000000000000004341434845;
  7'd7:catalog_name=96'h00000000434f4e5452415354;
  7'd8:catalog_name=96'h0000004556454e5444524f50;
  7'd9:catalog_name=96'h000000000000000046414445;
  7'd10:catalog_name=96'h000000000000004641554c54;
  7'd11:catalog_name=96'h00000000000000000047454e;
  7'd12:catalog_name=96'h000000000000494448494748;
  7'd13:catalog_name=96'h0000000000000049444c4f57;
  7'd14:catalog_name=96'h000000494e54454752495459;
  7'd15:catalog_name=96'h000000000000004c4556454c;
  7'd16:catalog_name=96'h00000000000000004e455854;
  7'd17:catalog_name=96'h000000004f564552464c4f57;
  7'd18:catalog_name=96'h000000000000504552494f44;
  7'd19:catalog_name=96'h50524553454e544154494f4e;
  7'd20:catalog_name=96'h00000000005245434f564552;
  7'd21:catalog_name=96'h000000005245434f56455259;
  7'd22:catalog_name=96'h0000000052454a4543544544;
  7'd23:catalog_name=96'h000000000052455452494553;
  7'd24:catalog_name=96'h000000000000005343414c45;
  7'd25:catalog_name=96'h0000000000005343414c4552;
  7'd26:catalog_name=96'h0000000000000000534c4f54;
  7'd27:catalog_name=96'h000000000000535441545553;
  7'd28:catalog_name=96'h000000005541525444524f50;
  7'd29:catalog_name=96'h000000554152544652414d45;
  7'd30:catalog_name=96'h00554152544f56455252554e;
  7'd31:catalog_name=96'h00005541525452454a454354;
  7'd32:catalog_name=96'h000000554e444552464c4f57;
  7'd33:catalog_name=96'h000000000000000000564f4c;
  7'd34:catalog_name=96'h000056554e444552464c4f57;
  7'd35:catalog_name=96'h0057415646414c4c4241434b;
  7'd36:catalog_name=96'h000000000000000044494147;
  default:;endcase end


 wire[23:0] decimal_next=number*24'd10+{20'd0,rx_data[3:0]};
 function [4:0] hex;
 input[7:0] c;begin begin
 if(c>=48&&c<=57)hex=c-48;else if(c>=65&&c<=70)hex=c-55;else hex=31;end  end endfunction
 task reject;
 input[7:0] code;begin begin
 state<=0;reply_valid<=1;reply_code<=code;
 if(rejected!=32'hffffffff)rejected<=rejected+1'b1;
 end  end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;checksum<=0;received<=0;timer<=0;number<=0;
   length<=0;names<=0;digit_seen<=0;negative<=0;argument<=0;dest<=0;ask<=0;
   command_valid<=0;
   reply_valid<=0;reply_code<=0;rejected<=0;end
  else begin
   command_valid<=0;reply_valid<=0;
   if(state!=0)begin if(timer>=TIMEOUT-1 && !rx_valid)reject(8'h06);else timer<=timer+1'b1;end
   if(rx_valid)begin
    timer<=0;
    if(rx_data==36)begin state<=1;checksum<=0;received<=0;length<=0;names<=0;
     negative<=0;argument<=0;dest<=0;ask<=0;number<=0;digit_seen<=0;end
    else if(name_byte&&match_busy)reject(8'h06);
    else case(state)
     0:;
     1:begin
      if(rx_data==42)begin
       if(length<3 || names==0 || (argument && !digit_seen))reject(8'h04);else state<=2;
      end else if(length>=32)reject(8'h06);
      else begin
       checksum<=checksum^rx_data;length<=length+1'b1;
       if(length==0)begin
        if(rx_data==65||rx_data==66||rx_data==67)dest<=rx_data;else reject(8'h02);
       end else if(length==1)begin if(rx_data!=58)reject(8'h04);end
       else if(rx_data==61 && names!=0 && !argument && !ask)argument<=1;
       else if(rx_data==63 && names!=0 && !argument && !ask)ask<=1;
       else if(!argument && !ask && names<12 && rx_data>=65 && rx_data<=90)begin
        names<=names+1'b1;
       end else if(argument && rx_data==45 && !digit_seen && !negative)negative<=1;
       else if(argument && rx_data>=48 && rx_data<=57 && number<1000000)begin
        number<=decimal_next;digit_seen<=1'b1;end
       else reject(8'h03);
      end
     end
     2:if(hex(rx_data)==31)reject(8'h01);else begin received[7:4]<=hex(rx_data);state<=3;end
     3:if(hex(rx_data)==31)reject(8'h01);else begin received[3:0]<=hex(rx_data);state<=4;end
     4:if(rx_data==13)state<=5;else reject(8'h04);
     5:begin
      state<=0;
      if(rx_data!=10)reject(8'h04);
      else if(received!=checksum)reject(8'h01);
      else begin command_valid<=1;end
     end
     default:state<=0;
    endcase
   end
  end
 end
endmodule
