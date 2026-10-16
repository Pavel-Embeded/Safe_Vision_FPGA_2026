`timescale 1ns/1ps
module tb_v3_uart;
 reg clk=0;always #5 clk=~clk;reg rst=0,line=1;wire [7:0] data;wire valid;wire[31:0] fe,ov;
 uart_rx #(.CLK_HZ(160000),.BAUD(5000)) rx(clk,rst,line,1'b1,data,valid,fe,ov);
 reg pv=0;reg[7:0] pd=0;wire cmd;wire[7:0] target;wire[95:0] name;wire signed[31:0] val;
 wire query,reply;wire[7:0] code;wire[31:0] rejected;
 v3_command_parser #(.TIMEOUT(200)) parser(clk,rst,pv,pd,cmd,target,name,val,query,reply,code,rejected);
 integer errors=0,received=0,i,j,commands=0;reg[7:0] expected;
 task ck;input c;input[255:0] msg;begin
 if(!c)begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 always @(posedge clk)begin #1;
  if(valid)begin ck(data===expected,"UART byte identity");received=received+1;end
  if(cmd)begin commands=commands+1;ck(target==65 && name=="BRIGHT" && val==-128,"atomic validated command");end
 end
 task serial_byte;input[7:0] b;begin
 expected=b;line=0;repeat(32)@(negedge clk);
 for(j=0;j<8;j=j+1)begin line=b[j];repeat(32)@(negedge clk);end
 line=1;repeat(40)@(negedge clk);end endtask
 task ch;input[7:0] b;begin pv=1;pd=b;@(negedge clk);pv=0;@(negedge clk);end endtask
 reg [103:0] body="A:BRIGHT=-128";reg[7:0] cs;function[7:0] hx;input[3:0] x;begin hx=x<10?48+x:55+x;end endfunction
 initial begin
 repeat(3)@(negedge clk);rst=1;
 for(i=0;i<1000;i=i+1)serial_byte(i[7:0]);
 ck(received==1000 && fe==0 && ov==0,"1000 serial bytes, no framing or overrun");
 cs=0;ch(36);for(i=12;i>=0;i=i-1)begin ch(body[i*8+:8]);cs=cs^body[i*8+:8];end
 ch(42);ch(hx(cs[7:4]));ch(hx(cs[3:0]));ch(13);ch(10);repeat(3)@(negedge clk);
 ck(commands==1,"exactly one complete command");
 ch(36);for(i=12;i>=0;i=i-1)ch(body[i*8+:8]);ch(42);ch(48);ch(48);ch(13);ch(10);repeat(3)@(negedge clk);
 ck(commands==1 && rejected==1,"bad checksum has no side effects");
 ch(36);ch(65);repeat(220)@(negedge clk);ck(commands==1 && rejected==2,"partial frame timeout");
 if(errors==0)$display("[PASS] UART1000, checksum, atomicity and timeout");
 $display("PASS tb_v3_uart errors=%0d",errors);$finish;
 end
 initial begin #5000000;$display("[FAIL] timeout");$finish;end
endmodule
