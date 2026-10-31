`timescale 1ns/1ps
module tb_v3_parser_compact;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,valid=0;reg[7:0] data=0;
 wire cv,rv,cq,cv0,rv0,cq0;wire[7:0] target,reply,target0,reply0;
 wire[95:0] name,name0;wire signed[31:0] value,value0;wire[31:0] rejected,rejected0;
 v3_command_parser #(.TIMEOUT(200)) d(clk,rst_n,valid,data,cv,target,name,value,cq,rv,reply,rejected);
 v3_command_parser_reference #(.TIMEOUT(200)) reference(clk,rst_n,valid,data,cv0,target0,name0,value0,cq0,rv0,reply0,rejected0);
 integer errors=0,comparisons=0,commands=0,i,j,n,before_commands,accept_expected;
 reg signed[31:0] expect_value;reg expect_query;reg[7:0] expect_target;reg[95:0] expect_name;
 reg known_frame=0;reg [4095:0] body;reg[31:0] random_state=32'h1cd873a9;
 task ck;input condition;input[511:0] message;begin  comparisons=comparisons+1;
  if(!condition)begin errors=errors+1;if(errors<20)$display("[FAIL] %s body=%s val=%0d expected=%0d",message,body,value,expect_value);end   end endtask
 always @(posedge clk)begin #1;
  if(rst_n)begin
   ck(cv===cv0 && rv===rv0 && rejected===rejected0 && (!rv||reply===reply0),"cycle-exact valid/reply/rejection reference");
   if(cv)begin
    commands=commands+1;ck(target===target0&&name===name0&&value===value0&&cq===cq0,"published validated payload equals original parser");
    if(known_frame)ck(target==expect_target&&name==expect_name&&value==expect_value&&cq==expect_query,"independent signed decimal/query field oracle");
   end
  end
 end
 function[7:0] hexchar;input[3:0] n;begin  hexchar=n<10 ? 48+n:55+n;  end endfunction
 task byte_in;input[7:0] c;begin  data=c;valid=1;@(negedge clk);valid=0;@(negedge clk);  end endtask
 task frame;input [4095:0] text;input corrupt_checksum;input integer accepted;begin begin
  body=text;before_commands=commands;byte_in(36);
  begin : v_local_1  reg[7:0] checksum;integer k;checksum=0;
   for(k=0;k<v_string_length(text);k=k+1)begin checksum=checksum^v_string_char(text,k);byte_in(v_string_char(text,k));end
   if(corrupt_checksum)checksum=checksum^8'h01;
   byte_in(42);byte_in(hexchar(checksum[7:4]));byte_in(hexchar(checksum[3:0]));byte_in(13);byte_in(10);
  end
  repeat(3)@(negedge clk);ck(commands-before_commands==accepted,"whole frame acceptance count");
 end  end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;expect_target=65;expect_name="BRIGHT";expect_query=0;
  for(i=0;i<520;i=i+1)begin
   random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
   n=random_state%10000000;
   case(i%17)0:n=0;1:n=9999999;2:n=1000000;3:n=999999;4:n=128;default:;endcase
   if(i[0])n=-n;
   expect_value=n;expect_query=0;known_frame=1;
   frame(v_format_brightness(n),0,1);
   known_frame=0;frame(v_format_brightness(n),1,0);
  end
  known_frame=1;expect_value=0;expect_query=1;frame("A:BRIGHT?",0,1);
  expect_query=0;frame("A:BRIGHT=-0",0,1);expect_value=128;frame("A:BRIGHT=00000000000128",0,1);
  known_frame=0;
  frame("A:BRIGHT=10000000",0,0);frame("A:BRIGHT=-10000000",0,0);
  frame("A:BRIGHT=2147483647",0,0);frame("A:BRIGHT=-2147483648",0,0);
  frame("A:BRIGHT=--1",0,0);frame("A:BRIGHT=-",0,0);frame("A:BRIGHT??",0,0);
  frame("D:BRIGHT=0",0,0);frame("A:bright=1",0,0);
  for(i=0;i<1000;i=i+1)begin random_state=random_state*1664525+1013904223;byte_in(random_state[15:8]);end
  byte_in(36);byte_in(65);repeat(220)@(negedge clk);
  if(errors==0)$display("[PASS] compact parser byte/reference equivalence and full signed decimal bounds");
  $display("[TB] tb_v3_parser_compact done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
 initial begin #5000000;$display("[FAIL] global timeout");$finish;end

function[4095:0] v_format_brightness; input integer value; begin  $sformat(v_format_brightness,"A:BRIGHT=%0d",value);   end endfunction
function integer v_string_length; input[4095:0] value; integer k; begin  v_string_length=0; for(k=0;k<512;k=k+1)if(value[k*8+:8]!=0)v_string_length=k+1;   end endfunction
function[7:0] v_string_char; input[4095:0] value; input integer index; integer n; begin  n=v_string_length(value); if((index>=0&&index<n)===1'b1)v_string_char=value[(n-1-index)*8+:8];else v_string_char=0;   end endfunction
endmodule
