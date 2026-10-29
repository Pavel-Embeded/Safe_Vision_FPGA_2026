`timescale 1ns/1ps
module tb_v3_uart_formatter_equivalence;
 reg clk=0,rst=0;reg[48:0]pattern=0;reg[4:0]pos=0;reg[7:0]sum=0;
 integer errors=0,comparisons=0,kind,p,lane,n,c,k;reg[31:0]rng=32'hfa261801;
 function[31:0]rand32;begin rng=rng*1664525+1013904223;rand32=rng;end endfunction
 v3_uart_link #(.BOARD_CATALOG(0),.TX_PIPELINE(0)) a(.clk(clk),.rst_n(rst),.rxd(1'b1),
 .reply_valid(1'b0),.reply_code(8'd0),.reply_value(32'd0),.evt_valid(1'b0),.evt_code(8'd0),.evt_src(4'd0),.evt_ts(32'd0));
 v3_uart_formatter_reference #(.BOARD_CATALOG(0),.TX_PIPELINE(0)) b(.clk(clk),.rst_n(rst),.rxd(1'b1),
 .reply_valid(1'b0),.reply_code(8'd0),.reply_value(32'd0),.evt_valid(1'b0),.evt_code(8'd0),.evt_src(4'd0),.evt_ts(32'd0));
 task check;begin #1;comparisons++;if(a.byte_tx!==b.byte_tx)begin errors++;if(errors<12)$display("[FAIL] formatter packet=%h position=%0d checksum=%h got=%h expected=%h",pattern,pos,sum,a.byte_tx,b.byte_tx);end end endtask
 initial begin
  force a.packet=pattern;force b.packet=pattern;force a.position=pos;force b.position=pos;force a.checksum=sum;force b.checksum=sum;


  for(kind=0;kind<2;kind++)for(p=0;p<32;p++)begin
   pos=p;
   for(lane=0;lane<12;lane++)for(n=0;n<16;n++)begin pattern=0;pattern[48]=kind;pattern[lane*4+:4]=n;sum=8'ha5;check();end
   for(c=0;c<256;c++)begin pattern={kind[0],48'h123456789abc};sum=c;check();end
  end

  for(k=0;k<100000;k++)begin pattern={rand32(),rand32()};pos=rand32();sum=rand32();check();end
  if(errors==0)$display("[PASS] ACK/EVT all32positions,all12nibble lanes,all16values,all256checksums plus100000 concurrent payload vectors");
  $display("[TB] tb_v3_uart_formatter_equivalence done errors=%0d comparisons=%0d",errors,comparisons);$finish;
 end
endmodule
