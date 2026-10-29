


module v3_command_parser_reference #(parameter integer TIMEOUT=10000000)(
 input wire clk,rst_n,rx_valid,input wire [7:0] rx_data,
 output reg command_valid,output reg [7:0] target,
 output reg [95:0] name,output reg signed [31:0] value,output reg query,
 output reg reply_valid,output reg [7:0] reply_code,
 output reg [31:0] rejected);
 reg [2:0] state;reg [7:0] checksum,received;reg [31:0] timer,number;
 reg [5:0] length;reg [3:0] names,digits;reg negative,argument;
 reg [7:0] dest;reg [95:0] token;reg ask;
 function [4:0] hex;
 input[7:0] c;begin
 if(c>=48&&c<=57)hex=c-48;else if(c>=65&&c<=70)hex=c-55;else hex=31;end endfunction
 task reject;
 input[7:0] code;begin
 state<=0;reply_valid<=1;reply_code<=code;
 if(rejected!=32'hffffffff)rejected<=rejected+1'b1;
 end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;checksum<=0;received<=0;timer<=0;number<=0;
   length<=0;names<=0;digits<=0;negative<=0;argument<=0;dest<=0;token<=0;ask<=0;
   command_valid<=0;target<=0;name<=0;value<=0;query<=0;
   reply_valid<=0;reply_code<=0;rejected<=0;end
  else begin
   command_valid<=0;reply_valid<=0;
   if(state!=0)begin if(timer>=TIMEOUT-1 && !rx_valid)reject(8'h06);else timer<=timer+1'b1;end
   if(rx_valid)begin
    timer<=0;
    if(rx_data==36)begin state<=1;checksum<=0;received<=0;length<=0;names<=0;
     negative<=0;argument<=0;dest<=0;token<=0;ask<=0;number<=0;digits<=0;end
    else case(state)
     0:;
     1:begin
      if(rx_data==42)begin
       if(length<3 || names==0 || (argument && digits==0))reject(8'h04);else state<=2;
      end else if(length>=32)reject(8'h06);
      else begin
       checksum<=checksum^rx_data;length<=length+1'b1;
       if(length==0)begin
        if(rx_data==65||rx_data==66||rx_data==67)dest<=rx_data;else reject(8'h02);
       end else if(length==1)begin if(rx_data!=58)reject(8'h04);end
       else if(rx_data==61 && names!=0 && !argument && !ask)argument<=1;
       else if(rx_data==63 && names!=0 && !argument && !ask)ask<=1;
       else if(!argument && !ask && names<12 && rx_data>=65 && rx_data<=90)begin
        token<={token[87:0],rx_data};names<=names+1'b1;
       end else if(argument && rx_data==45 && digits==0 && !negative)negative<=1;
       else if(argument && rx_data>=48 && rx_data<=57 && number<1000000)begin
        number<=number*10+(rx_data-48);digits<=digits+1'b1;end
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
      else begin target<=dest;name<=token;value<=negative?-$signed(number):$signed(number);
       query<=ask;command_valid<=1;end
     end
     default:state<=0;
    endcase
   end
  end
 end
endmodule

