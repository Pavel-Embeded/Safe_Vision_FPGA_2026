`timescale 1ns/1ps
module tb_v3_command_catalog;
 reg clk=0,rst=0,rv=0;reg[7:0] data=0;always #5 clk=~clk;
 wire[6:0] catalog_id;wire cv,ocv,q,oq,pv,opv;wire[7:0] target,otarget,code,ocode;wire[95:0] name,oname;wire signed[31:0] value,ovalue;wire[31:0] rejected,orejected;
 v3_command_parser_catalog #(.TIMEOUT(10000),.CATALOG_FILE("v3_command_catalog.mem")) dut(clk,rst,rv,data,cv,target,name,value,q,pv,code,rejected,catalog_id);
 v3_command_parser_reference #(.TIMEOUT(10000)) reference(clk,rst,rv,data,ocv,otarget,oname,ovalue,oq,opv,ocode,orejected);
 wire[4:0] timeout_done;wire[31:0] timeout_errors[0:4];genvar timeout_case;
 generate for(timeout_case=0;timeout_case<5;timeout_case = timeout_case + 1)begin:timeout_contract
  localparam integer LIMIT=timeout_case==0 ? 1:(timeout_case==1 ? 2:(timeout_case==2 ? 3:(timeout_case==3 ? 17:100)));
  parser_timeout_contract #(.TIMEOUT(LIMIT)) t(.clk(clk),.start(rst),.done(timeout_done[timeout_case]),.errors(timeout_errors[timeout_case]));
 end endgenerate
 integer errors=0,comparisons=0,commands=0,replies=0,i,k;reg[31:0] seed=32'h8fd47c21;
 function  known(input[95:0] n);begin  case(n)
  96'h00000000000000414c504841,
  96'h00000000000000004155544f,
  96'h000000004241444552524f52,
  96'h000000000000004241444944,
  96'h000000000000425249474854,
  96'h000000000000004341434845,
  96'h00000000434f4e5452415354,
  96'h0000004556454e5444524f50,
  96'h000000000000000046414445,
  96'h000000000000004641554c54,
  96'h00000000000000000047454e,
  96'h000000000000494448494748,
  96'h0000000000000049444c4f57,
  96'h000000494e54454752495459,
  96'h000000000000004c4556454c,
  96'h00000000000000004e455854,
  96'h000000004f564552464c4f57,
  96'h000000000000504552494f44,
  96'h50524553454e544154494f4e,
  96'h00000000005245434f564552,
  96'h000000005245434f56455259,
  96'h0000000052454a4543544544,
  96'h000000000052455452494553,
  96'h000000000000005343414c45,
  96'h0000000000005343414c4552,
  96'h0000000000000000534c4f54,
  96'h000000000000535441545553,
  96'h000000005541525444524f50,
  96'h000000554152544652414d45,
  96'h00554152544f56455252554e,
  96'h00005541525452454a454354,
  96'h000000554e444552464c4f57,
  96'h000000000000000000564f4c,
  96'h000056554e444552464c4f57,
  96'h0057415646414c4c4241434b,
  96'h000000000000000044494147,
  96'h000000000000004252545043,
  96'h000000000000004649454c44,
  96'h00000000004c4154454e4359,
  96'h00000000000000004d454e55,
  96'h000000005343414c4553454c:

  known= ((1) === 1'b1);default:known= ((0) === 1'b1);endcase   end endfunction
 task ck(input  ok,input [4095:0] message);begin  ok = (ok === 1'b1); comparisons = comparisons + 1;if(!ok)begin errors = errors + 1;if(errors<9)$display("[FAIL] %s",message);end   end endtask
 always @(posedge clk)begin #1;
  ck({cv,pv,rejected}==={ocv,opv,orejected},"cycle-exact valid/reply/rejection-count behavior");
  if(cv)begin commands = commands + 1;ck({target,value,q}==={otarget,ovalue,oq},"target, full signed value and query match original");
   ck(known(oname) ? name===oname:name===0,"all known names exact; every unknown canonicalized without false recognition");end
  if(pv)begin replies = replies + 1;ck(code===ocode,"identical malformed-packet reply code");end
 end
 task emit(input[7:0] byte_value);begin
  @(negedge clk);data=byte_value;rv=1;@(negedge clk);rv=0;
  repeat(96)begin seed=seed*1664525+1013904223;data=seed[7:0];@(negedge clk);end
   end endtask
 function[7:0] hex(input[3:0] n);begin  hex=n<10 ? 48+n:55+n;  end endfunction
 task frame(input [4095:0] body,input  corrupt);reg[7:0] crc;integer n;begin
  corrupt = (corrupt === 1'b1); crc=0;emit(36);for(n=0;n<v_string_length(body);n = n + 1)begin crc=crc^v_string_char(body,n);emit(v_string_char(body,n));end
  if(corrupt)crc=crc^1;emit(42);emit(hex(crc[7:4]));emit(hex(crc[3:0]));emit(13);emit(10);repeat(90)@(negedge clk);
   end endtask
 reg [4095:0] random_name;
 initial begin
  repeat(4)@(negedge clk);rst=1;
  frame("A:BRTPC?",0);frame("C:BRTPC=9999999",0);
  frame("A:FIELD?",0);frame("C:FIELD=9999999",0);
  frame("A:LATENCY?",0);frame("C:LATENCY=9999999",0);
  frame("A:MENU?",0);frame("C:MENU=9999999",0);
  frame("A:SCALESEL?",0);frame("C:SCALESEL=9999999",0);
  frame("B:DIAG?",0);frame("B:DIAG=15",0);frame("B:DIAG=-1",0);
  frame("A:ALPHA?",0);
  frame("B:ALPHA=0",0);
  frame("C:ALPHA=-31",0);
  frame("C:ALPHA=9999999",0);
  frame("A:AUTO?",0);
  frame("B:AUTO=0",0);
  frame("C:AUTO=-31",0);
  frame("C:AUTO=9999999",0);
  frame("A:BADERROR?",0);
  frame("B:BADERROR=0",0);
  frame("C:BADERROR=-31",0);
  frame("C:BADERROR=9999999",0);
  frame("A:BADID?",0);
  frame("B:BADID=0",0);
  frame("C:BADID=-31",0);
  frame("C:BADID=9999999",0);
  frame("A:BRIGHT?",0);
  frame("B:BRIGHT=0",0);
  frame("C:BRIGHT=-31",0);
  frame("C:BRIGHT=9999999",0);
  frame("A:CACHE?",0);
  frame("B:CACHE=0",0);
  frame("C:CACHE=-31",0);
  frame("C:CACHE=9999999",0);
  frame("A:CONTRAST?",0);
  frame("B:CONTRAST=0",0);
  frame("C:CONTRAST=-31",0);
  frame("C:CONTRAST=9999999",0);
  frame("A:EVENTDROP?",0);
  frame("B:EVENTDROP=0",0);
  frame("C:EVENTDROP=-31",0);
  frame("C:EVENTDROP=9999999",0);
  frame("A:FADE?",0);
  frame("B:FADE=0",0);
  frame("C:FADE=-31",0);
  frame("C:FADE=9999999",0);
  frame("A:FAULT?",0);
  frame("B:FAULT=0",0);
  frame("C:FAULT=-31",0);
  frame("C:FAULT=9999999",0);
  frame("A:GEN?",0);
  frame("B:GEN=0",0);
  frame("C:GEN=-31",0);
  frame("C:GEN=9999999",0);
  frame("A:IDHIGH?",0);
  frame("B:IDHIGH=0",0);
  frame("C:IDHIGH=-31",0);
  frame("C:IDHIGH=9999999",0);
  frame("A:IDLOW?",0);
  frame("B:IDLOW=0",0);
  frame("C:IDLOW=-31",0);
  frame("C:IDLOW=9999999",0);
  frame("A:INTEGRITY?",0);
  frame("B:INTEGRITY=0",0);
  frame("C:INTEGRITY=-31",0);
  frame("C:INTEGRITY=9999999",0);
  frame("A:LEVEL?",0);
  frame("B:LEVEL=0",0);
  frame("C:LEVEL=-31",0);
  frame("C:LEVEL=9999999",0);
  frame("A:NEXT?",0);
  frame("B:NEXT=0",0);
  frame("C:NEXT=-31",0);
  frame("C:NEXT=9999999",0);
  frame("A:OVERFLOW?",0);
  frame("B:OVERFLOW=0",0);
  frame("C:OVERFLOW=-31",0);
  frame("C:OVERFLOW=9999999",0);
  frame("A:PERIOD?",0);
  frame("B:PERIOD=0",0);
  frame("C:PERIOD=-31",0);
  frame("C:PERIOD=9999999",0);
  frame("A:PRESENTATION?",0);
  frame("B:PRESENTATION=0",0);
  frame("C:PRESENTATION=-31",0);
  frame("C:PRESENTATION=9999999",0);
  frame("A:RECOVER?",0);
  frame("B:RECOVER=0",0);
  frame("C:RECOVER=-31",0);
  frame("C:RECOVER=9999999",0);
  frame("A:RECOVERY?",0);
  frame("B:RECOVERY=0",0);
  frame("C:RECOVERY=-31",0);
  frame("C:RECOVERY=9999999",0);
  frame("A:REJECTED?",0);
  frame("B:REJECTED=0",0);
  frame("C:REJECTED=-31",0);
  frame("C:REJECTED=9999999",0);
  frame("A:RETRIES?",0);
  frame("B:RETRIES=0",0);
  frame("C:RETRIES=-31",0);
  frame("C:RETRIES=9999999",0);
  frame("A:SCALE?",0);
  frame("B:SCALE=0",0);
  frame("C:SCALE=-31",0);
  frame("C:SCALE=9999999",0);
  frame("A:SCALER?",0);
  frame("B:SCALER=0",0);
  frame("C:SCALER=-31",0);
  frame("C:SCALER=9999999",0);
  frame("A:SLOT?",0);
  frame("B:SLOT=0",0);
  frame("C:SLOT=-31",0);
  frame("C:SLOT=9999999",0);
  frame("A:STATUS?",0);
  frame("B:STATUS=0",0);
  frame("C:STATUS=-31",0);
  frame("C:STATUS=9999999",0);
  frame("A:UARTDROP?",0);
  frame("B:UARTDROP=0",0);
  frame("C:UARTDROP=-31",0);
  frame("C:UARTDROP=9999999",0);
  frame("A:UARTFRAME?",0);
  frame("B:UARTFRAME=0",0);
  frame("C:UARTFRAME=-31",0);
  frame("C:UARTFRAME=9999999",0);
  frame("A:UARTOVERRUN?",0);
  frame("B:UARTOVERRUN=0",0);
  frame("C:UARTOVERRUN=-31",0);
  frame("C:UARTOVERRUN=9999999",0);
  frame("A:UARTREJECT?",0);
  frame("B:UARTREJECT=0",0);
  frame("C:UARTREJECT=-31",0);
  frame("C:UARTREJECT=9999999",0);
  frame("A:UNDERFLOW?",0);
  frame("B:UNDERFLOW=0",0);
  frame("C:UNDERFLOW=-31",0);
  frame("C:UNDERFLOW=9999999",0);
  frame("A:VOL?",0);
  frame("B:VOL=0",0);
  frame("C:VOL=-31",0);
  frame("C:VOL=9999999",0);
  frame("A:VUNDERFLOW?",0);
  frame("B:VUNDERFLOW=0",0);
  frame("C:VUNDERFLOW=-31",0);
  frame("C:VUNDERFLOW=9999999",0);
  frame("A:WAVFALLBACK?",0);
  frame("B:WAVFALLBACK=0",0);
  frame("C:WAVFALLBACK=-31",0);
  frame("C:WAVFALLBACK=9999999",0);
  for(k=0;k<100;k = k + 1)begin
   random_name="ZZ";for(i=0;i<k%10;i = i + 1)begin seed=seed*1664525+1013904223;random_name={random_name,v_cast_u8(65+(seed%26))};end
   frame({"C:",random_name,"?"},0);
  end
  frame("A:BRIGHT=-128",0);frame("A:BRIGHT=127",0);frame("C:VOL=0000000000000000",0);
  frame("C:VOL=0000000000000000-1",0);frame("C:VOL=9999999",0);frame("C:VOL=10000000",0);
  frame("A:ALPHA=1",1);frame("X:VOL=1",0);frame("C:BAD_NAME=2",0);frame("A:PRESENTATIONX?",0);
  emit(36);emit("A");emit(58);emit("B");repeat(12000)@(negedge clk);
  frame("A:CONTRAST=128",0);

  emit(36);emit("C");emit(58);@(negedge clk);data="V";rv=1;@(negedge clk);rv=0;#1;rst=0;#2;rst=1;
  frame("C:VOL=73",0);repeat(100)@(negedge clk);
  if(errors==0)$display("[PASS] exact finite-name recognition, unknowns, all consumers, payload/syntax parity, busy-input changes and reset/timeout recovery");
  $display("[TB] tb_v3_command_catalog done errors=%0d comparisons=%0d commands=%0d replies=%0d",errors,comparisons,commands,replies);wait(&timeout_done);
  ck((timeout_errors[0]|timeout_errors[1]|timeout_errors[2]|timeout_errors[3]|timeout_errors[4])==0,"exact timeout boundaries, deadline bytes, restarts and resets at five timer sizes");
  $display("[TB] tb_v3_command_catalog done errors=%0d comparisons=%0d",errors,comparisons);
  $finish;
 end
 initial begin #20000000;$display("[FAIL] catalog oracle watchdog errors=1");$finish;end

function [7:0] v_cast_u8; input [7:0] value; begin  v_cast_u8=value;   end endfunction
function integer v_string_length; input[4095:0] value; integer k; begin  v_string_length=0; for(k=0;k<512;k=k+1)if(value[k*8+:8]!=0)v_string_length=k+1;   end endfunction
function[7:0] v_string_char; input[4095:0] value; input integer index; integer n; begin  n=v_string_length(value); if((index>=0&&index<n)===1'b1)v_string_char=value[(n-1-index)*8+:8];else v_string_char=0;   end endfunction
endmodule


module parser_timeout_contract #(parameter integer TIMEOUT=2)(input wire clk,start,output reg done,output reg[31:0]errors);
 initial begin done = 0; errors = 0; end

 reg rst=0,rv=0;reg[7:0]data=0;wire cv,ocv,q,oq,pv,opv;
 wire[7:0]target,otarget,code,ocode;wire[95:0]name,oname;wire signed[31:0]value,ovalue;wire[31:0]rejected,orejected;wire[6:0]id;
 v3_command_parser_catalog #(.TIMEOUT(TIMEOUT),.CATALOG_FILE("v3_command_catalog.mem")) d(clk,rst,rv,data,cv,target,name,value,q,pv,code,rejected,id);
 v3_command_parser_reference #(.TIMEOUT(TIMEOUT)) r(clk,rst,rv,data,ocv,otarget,oname,ovalue,oq,opv,ocode,orejected);
 integer n;
 always @(posedge clk)begin #1;if(rst&&!done)begin
  if({cv,pv,rejected}!=={ocv,opv,orejected}||(pv&&code!==ocode))begin
   if(errors<3)$display("[FAIL] exact timer deadline T=%0d",TIMEOUT);errors=errors+1;
  end
 end end
 task emit(input[7:0]b);begin  @(negedge clk);rv=1;data=b;@(negedge clk);rv=0;  end endtask
 initial begin
  wait(start);@(negedge clk);rst=1;
  for(n=0;n<128;n = n + 1)begin
   emit(36);repeat(TIMEOUT-1)@(negedge clk);
   if(n%3==0)emit(36);else if(n%3==1)emit(65);
   repeat(TIMEOUT+3)@(negedge clk);
   if(n%8==0)begin emit(36);@(negedge clk);rst=0;repeat(2)@(negedge clk);rst=1;end
  end
  repeat(TIMEOUT+3)@(negedge clk);done=1;
 end
endmodule
