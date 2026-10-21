`timescale 1ns/1ps
module tb_v3_uart_rom_hd357;
 reg clk=0;always #5 clk=~clk;reg rst=0,rxd=1;
 wire[6:0] catalog_id;wire txd,cmd,q;wire[7:0] target;wire[95:0] name;wire signed[31:0] value;
 reg reply=0;reg[7:0] code=0;reg signed[31:0] answer=0;
 reg evt=0;reg[7:0] evtcode=0;reg[3:0] evtsrc=0;reg[31:0] evtts=0;wire evtready;
 wire[31:0] rejected,framing,overrun,dropped;
 v3_uart_miter_hd357 #(.BOARD_CATALOG(1),.CLK_HZ(160000),.BAUD(5000)) dut(
 .clk(clk),.rst_n(rst),.rxd(rxd),.txd(txd),.command_valid(cmd),.command_target(target),
 .command_name(name),.command_value(value),.command_query(q),.catalog_id(catalog_id),
 .reply_valid(reply),.reply_code(code),.reply_value(answer),
 .evt_valid(evt),.evt_code(evtcode),.evt_src(evtsrc),.evt_ts(evtts),.evt_ready(evtready),
 .parser_rejected(rejected),.rx_framing(framing),.rx_overrun(overrun),.reply_dropped(dropped));
 defparam dut.current.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 defparam dut.previous.g_catalog.parser.CATALOG_FILE="v3_command_catalog.mem";
 wire[7:0] decoded;wire decoded_valid;wire[31:0] txfe,txov;
 uart_rx #(.CLK_HZ(160000),.BAUD(5000)) decoder(
 .clk(clk),.rst_n(rst),.rxd(txd),.ready(1'b1),.data(decoded),.valid(decoded_valid),.frame_errors(txfe),.overruns(txov));
 integer errors=0,enqueued=0,received=0,commands=0,i,j,guard,rxstate=0,bytes_sent=0;
 integer want_code[0:255],want_kind[0:255],want_src[0:255];reg[31:0] want_value[0:255];
 string body="";reg[7:0] rxsum=0,rxcheck=0;integer gotcode,gotsrc;reg[31:0] gotvalue;
 function[7:0] hx;input[3:0] n;begin hx=n<10?48+n:55+n;end endfunction
 function[3:0] unhex;input[7:0] c;begin unhex=c<=57?c-48:c-55;end endfunction
 task ck;input c;input[511:0] msg;begin if(!c)begin errors=errors+1;$display("[FAIL] %s",msg);end end endtask
 task expect_reply;input integer kind,src,status;input[31:0] val;begin
 want_kind[enqueued]=kind;want_src[enqueued]=src;want_code[enqueued]=status;want_value[enqueued]=val;enqueued=enqueued+1;end endtask
 always @(posedge clk)begin #1;
  if(cmd)begin commands=commands+1;ck(target==65 && name=="BRIGHT" && value==-128 && !q && catalog_id==5,"command delivered atomically");end
  if(decoded_valid)case(rxstate)
   0:begin ck(decoded==36,"response starts with dollar");body="";rxsum=0;rxstate=1;end
   1:if(decoded==42)rxstate=2;else begin body={body,decoded};rxsum=rxsum^decoded;end
   2:begin rxcheck[7:4]=unhex(decoded);rxstate=3;end
   3:begin rxcheck[3:0]=unhex(decoded);ck(rxcheck==rxsum,"response XOR checksum");rxstate=4;end
   4:begin ck(decoded==13,"response CR");rxstate=5;end
   5:begin
    ck(decoded==10 && received<enqueued,"response LF and no extra reply");
    if(want_kind[received]==0)begin
     ck(body.len()==17 && $sscanf(body,"C:ACK=%h,%h",gotcode,gotvalue)==2,"ACK format");gotsrc=0;
    end else ck(body.len()==20 && $sscanf(body,"C:EVT=%h,%h,%h",gotsrc,gotcode,gotvalue)==3,"event format");
    ck(gotcode==want_code[received] && gotvalue===want_value[received] && gotsrc==want_src[received],"ordered response code/value/timestamp");
    received=received+1;rxstate=0;
   end
  endcase
 end
 task byte_in;input[7:0] b;integer bitno;begin
 rxd=0;repeat(32)@(negedge clk);for(bitno=0;bitno<8;bitno=bitno+1)begin
 rxd=b[bitno];repeat(32)@(negedge clk);end rxd=1;repeat(36)@(negedge clk);bytes_sent=bytes_sent+1;
 end endtask
 task send_command;input string s;input corrupt;integer index;reg[7:0] sum;begin
 sum=0;byte_in(36);for(index=0;index<s.len();index=index+1)begin byte_in(s[index]);sum=sum^s[index];end
 byte_in(42);byte_in(hx(sum[7:4]));byte_in(hx(sum[3:0]^(corrupt?1:0)));byte_in(13);byte_in(10);
 end endtask
 initial begin
 repeat(4)@(negedge clk);rst=1;
 send_command("A:BRIGHT=-128",0);ck(commands==1,"one command from real serial input");
 expect_reply(0,0,0,32'hffffff80);reply=1;answer=-128;@(negedge clk);reply=0;
 expect_reply(0,0,1,0);send_command("A:BRIGHT=-128",1);
 expect_reply(0,0,4,0);send_command("A:BRIGHT=",0);
 expect_reply(0,0,4,0);send_command("A:BRIGHT=-",0);
 expect_reply(0,0,3,0);send_command("A:BRIGHT=0-1",0);
 expect_reply(0,0,3,0);send_command("A:BRIGHT??",0);
 ck(commands==1 && rejected==5,"malformed commands have no effects");
 // A bounded burst tests queue capacity and UART's ready/valid byte cadence.
 for(i=0;i<100;i=i+1)begin expect_reply(0,0,i,i*32'h10204081);
 code=i;answer=i*32'h10204081;reply=1;@(negedge clk);end reply=0;
 expect_reply(1,3,8'hf3,32'h12345678);evtsrc=3;evtcode=8'hf3;evtts=32'h12345678;
 while(!evtready)@(negedge clk);evt=1;@(negedge clk);evt=0;
 expect_reply(1,2,7,32'hfffffff0);evtsrc=2;evtcode=7;evtts=32'hfffffff0;
 while(!evtready)@(negedge clk);evt=1;@(negedge clk);evt=0;
 // Minimum supported clock/baud ratio32; RX noise runs concurrently
 // with the original108 ordered replies, preserving the12ms watchdog.
 for(integer noise=0;noise<1000;noise++)byte_in(8'h55);
 ck(commands==1 && bytes_sent>=1000,"1000 serial noise bytes never generate a spurious command");
 guard=0;while(received<enqueued && guard<1000000)begin @(negedge clk);guard=guard+1;end
 ck(received==108 && rxstate==0,"all queued replies and timestamped events consumed");
 ck(framing==0 && overrun==0 && txfe==0 && txov==0 && dropped==0,"zero receive/transmit/queue loss");
 errors=errors+dut.miter_errors;
 $display("UART full public comparisons=%0d",dut.miter_comparisons);
 if(errors==0)$display("[PASS] serial commands, malformed rejection, 100-reply burst and ordered event timestamps");
 $display("PASS tb_v3_uart_rom_hd357 errors=%0d comparisons=%0d",errors,received);$finish;
 end
 initial begin #12000000;$display("[FAIL] global timeout");$finish;end
endmodule
