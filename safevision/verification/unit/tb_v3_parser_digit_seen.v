`timescale 1ns/1ps
module tb_v3_parser_digit_seen;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,rx_valid=0;reg[7:0] rx_data=0;
 wire cv,query,rv;wire[7:0] target,reply;wire[95:0] name;
 wire signed[31:0] value;wire[31:0] rejected;
 v3_command_parser #(.TIMEOUT(200)) dut(clk,rst_n,rx_valid,rx_data,
   cv,target,name,value,query,rv,reply,rejected);
 integer errors=0,comparisons=0,commands=0,replies=0;
 integer expected_count=0;reg signed[31:0] expected_value;
 reg checking=0;reg [4095:0] current_body;
 task ck;input condition;input[511:0] label_text;begin
  comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;
   $display("[FAIL] %s body=%s value=%0d",label_text,current_body,value);end
   end endtask
 always @(posedge clk)begin #1;if(rst_n)begin
  if(cv)begin commands=commands+1;
   ck(checking&&target==65&&name=="BRIGHT"&&!query&&value===expected_value,
      "independent command payload");end
  if(rv)replies=replies+1;
 end end
 function[7:0] hx;input[3:0] n;begin  hx=n<10 ? 48+n:55+n;  end endfunction
 task byte_in;input[7:0] b;begin
  rx_data=b;rx_valid=1;@(negedge clk);rx_valid=0;@(negedge clk);
   end endtask
 task frame;input [4095:0] body;input integer accepted;input integer number;
  integer i,old_commands,old_replies;reg[31:0] old_rejected;reg[7:0] crc;
  begin  current_body=body;expected_value=number;checking=1;
   old_commands=commands;old_replies=replies;old_rejected=rejected;
   crc=0;byte_in(36);
   for(i=0;i<v_string_length(body);i=i+1)begin crc=crc^v_string_char(body,i);byte_in(v_string_char(body,i));end
   byte_in(42);byte_in(hx(crc[7:4]));byte_in(hx(crc[3:0]));byte_in(13);byte_in(10);
   repeat(3)@(negedge clk);
   ck(commands-old_commands==accepted,"command count and absence of invalid side effects");
   ck(rejected-old_rejected==(accepted ? 0:1)&&replies-old_replies==(accepted ? 0:1),
      "exactly one rejection for invalid frame");checking=0;

  end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  frame("A:BRIGHT=0000000000000000",1,0);
  frame("A:BRIGHT=-0000000000000000",1,0);

  frame("A:BRIGHT=00000000000000000000001",1,1);
  frame("A:BRIGHT=-0000000000000000000001",1,-1);
  frame("A:BRIGHT=0000000000000000-1",0,0);
  frame("A:BRIGHT=0000000000000000-",0,0);
  frame("A:BRIGHT=000000000000000000000001",0,0);
  frame("A:BRIGHT=--1",0,0);
  frame("A:BRIGHT=-",0,0);
  frame("A:BRIGHT=",0,0);
  frame("A:BRIGHT=00000000000000000",1,0);
  frame("A:BRIGHT=9999999",1,9999999);
  frame("A:BRIGHT=10000000",0,0);
  if(errors==0)$display("[PASS] leading-zero signed grammar and exact 32-character body boundary");
  $display("[TB] tb_v3_parser_digit_seen done errors=%0d comparisons=%0d",errors,comparisons);
  $finish;
 end
 initial begin #1000000;$display("[FAIL] global timeout");$finish;end

function integer v_string_length; input[4095:0] value; integer k; begin  v_string_length=0; for(k=0;k<512;k=k+1)if(value[k*8+:8]!=0)v_string_length=k+1;   end endfunction
function[7:0] v_string_char; input[4095:0] value; input integer index; integer n; begin  n=v_string_length(value); if((index>=0&&index<n)===1'b1)v_string_char=value[(n-1-index)*8+:8];else v_string_char=0;   end endfunction
endmodule
