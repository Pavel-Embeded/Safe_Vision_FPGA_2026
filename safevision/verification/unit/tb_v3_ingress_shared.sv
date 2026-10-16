`timescale 1ns/1ps
module tb_v3_ingress_shared;
 reg wc=0,rc=0,read_clock_run=1;always #10 wc=~wc;
 always #12.5 if(read_clock_run)rc=~rc;else rc=0;
 reg rst=1;reg[127:0] in_data=0;reg[3:0] in_valid=0,out_ready=0;
 wire[3:0] in_ready,out_valid;wire[127:0] out_data;wire[8:0] pairs;wire room;wire[10:0] words;
 integer written=0,read_count=0,comparisons=0,epoch=0,read_cycle=0;
 integer per_write[0:3],per_read[0:3];reg random_read=0;
 reg[33:0] oracle[0:16383];reg[127:0] held_data;reg[3:0] held_valid;reg stalled=0;
 v3_pcm_ingress_shared_fifo d(.rst(rst),.wr_clk(wc),.rd_clk(rc),.wr_data(in_data),.wr_valid(in_valid),.wr_ready(in_ready),.wr_pairs(pairs),.sector_room(room),.wr_words(words),.rd_data(out_data),.rd_valid(out_valid),.rd_ready(out_ready));
 function[31:0] value(input integer slot,input integer sample_index,input integer generation);
  value=32'ha5c39e71^(slot*32'h01010101)^(sample_index*32'h1021)^(generation*32'h17283945);
 endfunction
 always @(posedge wc)begin
  if(rst)begin written=0;for(integer c=0;c<4;c=c+1)per_write[c]=0;end
  else begin
   if(room&&(1023-words<384+7||d.write_part!=0))$fatal(1,"illegal sector reservation credit words=%0d",words);
   for(integer c=0;c<4;c=c+1)if(in_valid[c]&&in_ready[c])begin
    oracle[written]={2'(c),value(c,per_write[c],epoch)};
    if(in_data[c*32+:32]!==value(c,per_write[c],epoch))$fatal(1,"test producer sequence");
    per_write[c]=per_write[c]+1;written=written+1;
   end
  end
 end
 always @(posedge rc)begin
  read_cycle<=read_cycle+1;
  if(rst)begin read_count=0;stalled<=0;for(integer c=0;c<4;c=c+1)per_read[c]=0;end
  else begin
   if(stalled&&(out_valid!==held_valid||out_data!==held_data))$fatal(1,"tagged queue changed while ring grant stalled");
   stalled<=|(out_valid&~out_ready);held_data<=out_data;held_valid<=out_valid;
   if(out_valid!=0&&(out_valid&(out_valid-1'b1))!=0)$fatal(1,"tagged queue multi-track output");
   for(integer c=0;c<4;c=c+1)if(out_valid[c]&&out_ready[c])begin
    if(read_count>=written||{2'(c),out_data[c*32+:32]}!==oracle[read_count]||out_data[c*32+:32]!==value(c,per_read[c],epoch))
     $fatal(1,"tagged queue order/slot/data epoch=%0d slot=%0d index=%0d got=%h expected=%h",epoch,c,read_count,out_data[c*32+:32],oracle[read_count]);
    per_read[c]=per_read[c]+1;read_count=read_count+1;comparisons=comparisons+1;
   end
  end
 end
 always @(negedge rc)if(random_read)for(integer c=0;c<4;c=c+1)out_ready[c]=(read_cycle%(7+c)!=0)&&(read_cycle%19<13);
 task send(input integer c);
  begin @(negedge wc);in_data=0;in_data[c*32+:32]=value(c,per_write[c],epoch);in_valid=4'b1<<c;
   do @(posedge wc);while(!in_ready[c]);@(negedge wc);in_valid=0;
  end
 endtask
 task reset_epoch;
  begin rst=1;in_valid=0;random_read=0;out_ready=0;read_clock_run=1;
   repeat(8)@(negedge wc);epoch=epoch+1;rst=0;repeat(12)@(negedge wc);
  end
 endtask
 integer sector_start,at,was_read;
 initial begin
  for(integer c=0;c<4;c=c+1)begin per_write[c]=0;per_read[c]=0;end
  reset_epoch();send(0);wait(d.read_part==2);@(negedge rc);read_clock_run=0;
  while(words<629)send(written%4);
  repeat(4)@(negedge wc);
  if(!room||words>632)$fatal(1,"full-sector worst-case setup words=%0d",words);
  sector_start=written;was_read=read_count;
  for(integer n=0;n<128;n=n+1)send(3);
  if(written-sector_start!=128||read_count!=was_read||words>1023)$fatal(1,"full sector needed consumer progress");
  $display("[PASS] stopped MEM clock, near-maximum room credit retained a full 128-pair sector words=%0d",words);
  read_clock_run=1;random_read=1;
  for(integer n=0;n<4000;n=n+1)send((n*7+(n>>3))%4);
  wait(read_count==written);repeat(15)@(negedge wc);
  // Cancel an unaccepted producer on reset; no old epoch pair is required to
  // survive. A fresh payload is established before the next legal handshake.
  for(integer partial=1;partial<=2;partial=partial+1)begin
   fork
    begin send(partial);end
    begin wait(d.write_part==partial);@(negedge wc);rst=1;in_valid=0;end
   join_any disable fork;
   reset_epoch();random_read=1;
   for(integer n=0;n<400;n=n+1)send((n+partial)%4);
   wait(read_count==written);repeat(10)@(negedge wc);
  end
  if(comparisons<5000)$fatal(1,"insufficient tagged queue wrap/epoch coverage");
  $display("[PASS] four-track exact PCM order, tag grouping, repeated wrap, ring backpressure and midpacket epoch reset");
  $display("PASS tb_v3_ingress_shared errors=0 comparisons=%0d",comparisons);$finish;
 end
 initial begin #10000000;$fatal(1,"tagged queue watchdog");end
endmodule
