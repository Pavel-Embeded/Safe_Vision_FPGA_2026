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
  begin value=32'ha5c39e71^(slot*32'h01010101)^(sample_index*32'h1021)^(generation*32'h17283945);
  end endfunction
 always @(posedge wc)begin
  if(rst)begin written=0;begin : v_loop_1 integer c; for( c=0;c<4;c=c+1)per_write[c]=0; end end
  else begin
   if(room&&(1023-words<384+7||d.write_part!=0))begin $display("[FAIL] illegal sector reservation credit words=%0d",words); $finish; end
   begin : v_loop_2 integer c; for( c=0;c<4;c=c+1)if(in_valid[c]&&in_ready[c])begin
    oracle[written]={v_cast_s2(c),value(c,per_write[c],epoch)};
    if(in_data[c*32+:32]!==value(c,per_write[c],epoch))begin $display("[FAIL] test producer sequence"); $finish; end
    per_write[c]=per_write[c]+1;written=written+1;
   end end
  end
 end
 always @(posedge rc)begin
  read_cycle<=read_cycle+1;
  if(rst)begin read_count=0;stalled<=0;begin : v_loop_3 integer c; for( c=0;c<4;c=c+1)per_read[c]=0; end end
  else begin
   if(stalled&&(out_valid!==held_valid||out_data!==held_data))begin $display("[FAIL] tagged queue changed while ring grant stalled"); $finish; end
   stalled<=|(out_valid&~out_ready);held_data<=out_data;held_valid<=out_valid;
   if(out_valid!=0&&(out_valid&(out_valid-1'b1))!=0)begin $display("[FAIL] tagged queue multi-track output"); $finish; end
   begin : v_loop_4 integer c; for( c=0;c<4;c=c+1)if(out_valid[c]&&out_ready[c])begin
    if(read_count>=written||{v_cast_s2(c),out_data[c*32+:32]}!==oracle[read_count]||out_data[c*32+:32]!==value(c,per_read[c],epoch))
     begin $display("[FAIL] tagged queue order/slot/data epoch=%0d slot=%0d index=%0d got=%h expected=%h",epoch,c,read_count,out_data[c*32+:32],oracle[read_count]); $finish; end
    per_read[c]=per_read[c]+1;read_count=read_count+1;comparisons=comparisons+1;
   end end
  end
 end
 always @(negedge rc)if(random_read)begin : v_loop_5 integer c; for( c=0;c<4;c=c+1)out_ready[c]=(read_cycle%(7+c)!=0)&&(read_cycle%19<13); end
 task send(input integer c);
  begin  @(negedge wc);in_data=0;in_data[c*32+:32]=value(c,per_write[c],epoch);in_valid=4'b1<<c;
   begin begin @(posedge wc); end while(!in_ready[c])begin @(posedge wc); end end @(negedge wc);in_valid=0;

  end endtask
 task reset_epoch;
  begin  rst=1;in_valid=0;random_read=0;out_ready=0;read_clock_run=1;
   repeat(8)@(negedge wc);epoch=epoch+1;rst=0;repeat(12)@(negedge wc);

  end endtask
 integer sector_start,at,was_read;
 initial begin
  begin : v_loop_6 integer c; for( c=0;c<4;c=c+1)begin per_write[c]=0;per_read[c]=0;end end
  reset_epoch();send(0);wait(d.read_part==2);@(negedge rc);read_clock_run=0;
  while(words<629)send(written%4);
  repeat(4)@(negedge wc);
  if(!room||words>632)begin $display("[FAIL] full-sector worst-case setup words=%0d",words); $finish; end
  sector_start=written;was_read=read_count;
  begin : v_loop_7 integer n; for( n=0;n<128;n=n+1)send(3); end
  if(written-sector_start!=128||read_count!=was_read||words>1023)begin $display("[FAIL] full sector needed consumer progress"); $finish; end
  $display("[PASS] stopped MEM clock, near-maximum room credit retained a full 128-pair sector words=%0d",words);
  read_clock_run=1;random_read=1;
  begin : v_loop_8 integer n; for( n=0;n<4000;n=n+1)send((n*7+(n>>3))%4); end
  wait(read_count==written);repeat(15)@(negedge wc);


  begin : v_loop_9 integer partial; for( partial=1;partial<=2;partial=partial+1)begin
   fork : v_race_1
    begin : v_branch_1 begin send(partial);end disable v_race_1; end
    begin : v_branch_2 begin wait(d.write_part==partial);@(negedge wc);rst=1;in_valid=0;end disable v_race_1; end
   join
   reset_epoch();random_read=1;
   begin : v_loop_10 integer n; for( n=0;n<400;n=n+1)send((n+partial)%4); end
   wait(read_count==written);repeat(10)@(negedge wc);
  end end
  if(comparisons<5000)begin $display("[FAIL] insufficient tagged queue wrap/epoch coverage"); $finish; end
  $display("[PASS] four-track exact PCM order, tag grouping, repeated wrap, ring backpressure and midpacket epoch reset");
  $display("PASS tb_v3_ingress_shared errors=0 comparisons=%0d",comparisons);$finish;
 end
 initial begin #10000000;begin $display("[FAIL] tagged queue watchdog"); $finish; end end

function signed [1:0] v_cast_s2; input signed [1:0] value; begin  v_cast_s2=value;   end endfunction
endmodule
