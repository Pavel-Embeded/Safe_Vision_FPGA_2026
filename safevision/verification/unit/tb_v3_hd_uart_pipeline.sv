`timescale 1ns/1ps
module tb_v3_hd_uart_pipeline;
 reg clk=0,rst=0,rxd=1,reply=0,event_valid=0;always #5 clk=~clk;
 reg[7:0] code=0,event_code=0;reg[3:0] source=0;reg[31:0] value=0,stamp=0;
 wire atx,btx,ar,br,ac,bc;wire[31:0] adrop,bdrop,areject,breject,aframe,bframe,aover,bover;
 integer errors=0,comparisons=0,edges=0,commands=0,k,epoch;reg previous_tx=1;reg[31:0] rng=32'h4739b5a1;
 v3_uart_link #(.CLK_HZ(32000000),.BAUD(1000000),.BOARD_CATALOG(0),.TX_PIPELINE(1)) d(.clk(clk),.rst_n(rst),.rxd(rxd),.txd(atx),.command_valid(ac),.reply_valid(reply),.reply_code(code),.reply_value(value),.evt_valid(event_valid),.evt_code(event_code),.evt_src(source),.evt_ts(stamp),.evt_ready(ar),.parser_rejected(areject),.rx_framing(aframe),.rx_overrun(aover),.reply_dropped(adrop));
 v3_uart_pipeline_reference #(.CLK_HZ(32000000),.BAUD(1000000),.BOARD_CATALOG(0),.TX_PIPELINE(1)) reference(.clk(clk),.rst_n(rst),.rxd(rxd),.txd(btx),.command_valid(bc),.reply_valid(reply),.reply_code(code),.reply_value(value),.evt_valid(event_valid),.evt_code(event_code),.evt_src(source),.evt_ts(stamp),.evt_ready(br),.parser_rejected(breject),.rx_framing(bframe),.rx_overrun(bover),.reply_dropped(bdrop));
 always @(posedge clk or negedge rst)begin
  #1;comparisons++;
  if({atx,ar,ac,adrop,areject,aframe,aover}!=={btx,br,bc,bdrop,breject,bframe,bover})begin errors++;if(errors<8)$display("[FAIL] bit-exact UART t=%t tx=%b/%b ready=%b/%b drops=%h/%h",$time,atx,btx,ar,br,adrop,bdrop);end
  if(rst&&atx!==previous_tx)edges++;previous_tx=atx;
  if(rst&&ac)commands++;
 end
 task byte_in(input[7:0] b);begin
  @(negedge clk);rxd=0;repeat(32)@(negedge clk);
  for(integer i=0;i<8;i++)begin rxd=b[i];repeat(32)@(negedge clk);end
  rxd=1;repeat(32)@(negedge clk);
 end endtask
 task send_command;begin

  byte_in("$");byte_in("C");byte_in(":");byte_in("N");byte_in("E");byte_in("X");byte_in("T");byte_in("=");byte_in("1");
  byte_in("*");byte_in("7");byte_in("2");byte_in(13);byte_in(10);
  byte_in("$");byte_in("Z");byte_in(13);byte_in(10);
 end endtask
 initial begin
  #22;rst=1;
  for(epoch=0;epoch<3;epoch++)begin
   fork
    begin
     for(k=0;k<320;k++)begin
      @(negedge clk);rng=rng*1664525+1013904223;code=rng[7:0];value=rng^32'h32965a7f;source=rng[11:8];event_code=~rng[7:0];stamp=rng*17;
      reply=(k%3!=0);event_valid=(k%3==0)||(k%19==0);
      if(k%11==0)repeat(70)@(negedge clk);
     end
     @(negedge clk);reply=0;event_valid=0;
    end
    begin repeat(8)send_command();end
   join

   repeat(1200000)@(negedge clk);
   if(!d.empty||d.sending||!reference.empty||reference.sending)begin errors++;$display("[FAIL] queue did not drain");end
   @(negedge clk);#1;rst=0;#2;rst=1;repeat(12)@(negedge clk);
  end
  #1;if(edges<10000||commands<24)begin errors++;$display("[FAIL] insufficient actual TX/RX coverage transitions=%0d accepted_commands=%0d",edges,commands);end
  if(errors==0)$display("[PASS] exact TXD on every SYS edge,ACK/EVT/CRC,128entry overflow policy,duplex RX and3 reset epochs;two-stage formatter preserves original line timing");
  $display("[TB] tb_v3_hd_uart_pipeline done comparisons=%0d errors=%0d edges=%0d",comparisons,errors,edges);$finish;
 end
 initial begin #60000000;errors++;$display("[FAIL] UART pipeline watchdog");$display("[TB] tb_v3_hd_uart_pipeline done comparisons=%0d errors=%0d",comparisons,errors);$finish;end
endmodule
