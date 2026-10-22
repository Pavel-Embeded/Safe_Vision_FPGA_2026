`timescale 1ns/1ps
module tb_v3_audio_packet;
 reg wc=0,rc=0,rst=1,read_clock=1,valid=0,produce=1;
 always #5 wc=~wc;always #6.7 if(read_clock)rc=~rc;
 reg[47:0] data=0;wire ready,rv;wire[47:0] out;
 v3_pcm_packet_fifo dut(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(data),.wr_valid(valid),.wr_ready(ready),.rd_data(out),.rd_valid(rv));
 reg[47:0] expected[0:8191];integer tail=0,head=0,checks=0,cycles=0;
 function[47:0] value(input integer n);begin value={24'(n*72131+32'h800001),24'(n*91247+32'h7fffff)};end endfunction
 always @(posedge wc)if(!rst)begin
  cycles<=cycles+1;
  if(valid&&ready)begin expected[tail]=data;tail=tail+1;end
 end
 always @(negedge wc)if(!rst)begin data=value(tail);valid=produce;end
 always @(posedge rc)if(!rst&&rv)begin
  if(head>=tail||out!==expected[head])$fatal(1,"packet order/framing epoch idx=%0d got=%h expected=%h tail=%0d",head,out,expected[head],tail);
  head=head+1;checks=checks+1;
 end
 task reset_epoch;begin rst=1;valid=0;read_clock=1;#100;head=0;tail=0;cycles=0;data=value(0);rst=0;end endtask
 initial begin
  reset_epoch();wait(tail>=100);@(negedge rc);read_clock=0;
  repeat(600)@(negedge wc);
  if(ready)$fatal(1,"packet FIFO failed to apply group backpressure");
  read_clock=1;wait(head>=200);
  // Drop an in-flight three-word group by the SAME global assertion epoch.
  wait(dut.holding&&dut.write_part==1);reset_epoch();wait(head>=200);
  produce=0;wait(!valid);wait(head==tail);repeat(20)@(negedge rc);
  if(head!=tail)$fatal(1,"packet stale tail after drain");
  $display("[PASS] lossless 48bit via3x16 TD FIFO async clocks full group reservation stalls wrap midgroup reset");
  $display("PASS tb_v3_audio_packet errors=0 comparisons=%0d",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"packet watchdog");end
endmodule
