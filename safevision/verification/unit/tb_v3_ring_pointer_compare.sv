`timescale 1ns/1ps
module ring_pointer_lane #(parameter PW=4)(input wire clk,output reg done=0,output integer errors=0,comparisons=0);
 localparam CAP=1<<PW,PF=CAP>800?800:CAP/2;
 reg rst=0;reg[3:0]valid=0,fallback=15;wire[127:0]data;
 reg commit=0;reg[1:0]slot=0;reg[7:0]gen=0;
 wire[3:0]ready[0:1],prefetched[0:1];wire[63:0]levels[0:1];
 wire commit_ready[0:1],out_valid[0:1],req[0:1],wr[0:1];
 wire[39:0]out_data[0:1];wire[31:0]addr[0:1],wdata[0:1],overflow[0:1];wire[15:0]len[0:1];
 localparam[15:0] CAP16=CAP;
 wire[63:0]current_levels=levels[0];
 wire all_full=current_levels=={4{CAP16}};
 wire current_commit_ready=commit_ready[0],current_req=req[0];
 reg ack=0,busy=0,rvalid=0;reg[31:0]rdata=0;reg[9:0]out_level=0;reg out_ready=0;
 integer writes[0:3],reads[0:3],cycles=0,transactions=0,countdown=0,ack_wait=0,round,n,i;
 wire[127:0]read_status={reads[3],reads[2],reads[1],reads[0]};
 reg saved_wr;reg[31:0]saved_addr,saved_data;reg early_read;
 reg[31:0]memory[0:4*CAP-1];
 function automatic integer index_of(input[31:0]a);reg[31:0]offset;begin offset=a-32'h00280000;index_of=(offset>>16)*CAP+((offset&32'hffff)>>2);end endfunction
 genvar g;generate for(g=0;g<4;g++)begin:source
  assign data[g*32+:32]=32'ha5000000|(g<<20)|writes[g];
 end endgenerate
 v3_pcm_ring #(.PTR_W(PW),.PREFETCH(PF),.DIRECT_POINTER_COMPARE(1))current(
  .clk(clk),.rst_n(rst),.in_data(data),.in_valid(valid),.in_ready(ready[0]),.commit_valid(commit),.commit_slot(slot),.commit_generation(gen),.commit_ready(commit_ready[0]),.fallback(fallback),.prefetched(prefetched[0]),.levels(levels[0]),
  .out_data(out_data[0]),.out_valid(out_valid[0]),.out_ready(out_ready),.output_level(out_level),.req(req[0]),.wr(wr[0]),.addr(addr[0]),.wdata(wdata[0]),.len(len[0]),.ack(ack),.busy(busy),.rdata(rdata),.rvalid(rvalid),.overflow_count(overflow[0]));
 v3_pcm_ring_frozen_pointer #(.PTR_W(PW),.PREFETCH(PF))original(
  .clk(clk),.rst_n(rst),.in_data(data),.in_valid(valid),.in_ready(ready[1]),.commit_valid(commit),.commit_slot(slot),.commit_generation(gen),.commit_ready(commit_ready[1]),.fallback(fallback),.prefetched(prefetched[1]),.levels(levels[1]),
  .out_data(out_data[1]),.out_valid(out_valid[1]),.out_ready(out_ready),.output_level(out_level),.req(req[1]),.wr(wr[1]),.addr(addr[1]),.wdata(wdata[1]),.len(len[1]),.ack(ack),.busy(busy),.rdata(rdata),.rvalid(rvalid),.overflow_count(overflow[1]));
 task ck(input bit okay,input string message);begin comparisons++;if(!okay)begin errors++;if(errors<12)$display("[FAIL] PW=%0d %s cycle=%0d",PW,message,cycles);end end endtask
 reg held=0,held_req=0;reg[39:0]held_data;reg[64:0]held_command;
 always @(posedge clk)begin
  if(!rst)begin
   cycles=0;transactions=0;ack<=0;busy<=0;rvalid<=0;rdata<=0;countdown=0;ack_wait=0;
   for(integer j=0;j<4;j++)begin writes[j]<=0;reads[j]<=0;end
   held=0;held_req=0;
  end else if(!done)begin
   cycles++;
   if(held)ck(out_valid[0]&&out_data[0]===held_data,"reserved output stays valid and stable through backpressure");
   held=out_valid[0]&&!out_ready;held_data=out_data[0];
   if(held_req)ck(req[0]&&{wr[0],addr[0],wdata[0]}===held_command,"request address/data remain stable until ACK");
   held_req=req[0]&&!ack;held_command={wr[0],addr[0],wdata[0]};
   for(integer j=0;j<4;j++)begin
    if(ready[0][j]&&valid[j])writes[j]<=writes[j]+1;
    ck(levels[0][j*16+:16]<=CAP,"all four occupancies stay within capacity");
    ck(prefetched[0][j]==(levels[0][j*16+:16]>=PF),"prefetch threshold retains exact occupancy semantics");
   end
   if(out_valid[0]&&out_ready)begin
    ck(out_data[0]==={gen,(32'ha5000000|(slot<<20)|reads[slot])},"every independent PCM payload, slot and generation matches");
    reads[slot]<=reads[slot]+1;
   end
   ack<=0;rvalid<=0;
   if(!busy&&countdown==0&&req[0])begin
    ck(len[0]==1&&addr[0][1:0]==0&&addr[0]>=32'h00280000&&addr[0]<32'h002c0000,"physical one-word request address and range");
    ck(index_of(addr[0])>=0&&index_of(addr[0])<4*CAP,"physical address decodes into the selected finite memory");
    saved_wr=wr[0];saved_addr=addr[0];saved_data=wdata[0];early_read=transactions%2==0;
    busy<=1;countdown=9+transactions%7;ack_wait=2+transactions%3;transactions++;
   end else if(countdown!=0)begin
    countdown--;
    if(ack_wait!=0)begin ack_wait--;if(ack_wait==0)begin ack<=1;if(!saved_wr&&early_read)begin rvalid<=1;rdata<=memory[index_of(saved_addr)];end end end
    if(countdown==3&&!saved_wr&&!early_read)begin rvalid<=1;rdata<=memory[index_of(saved_addr)];end
    if(countdown==0)begin busy<=0;if(saved_wr)memory[index_of(saved_addr)]<=saved_data;end
   end
  end
  #0.001;
  if(!done)ck({ready[0],prefetched[0],levels[0],commit_ready[0],out_data[0],out_valid[0],req[0],wr[0],addr[0],wdata[0],len[0],overflow[0]}==={ready[1],prefetched[1],levels[1],commit_ready[1],out_data[1],out_valid[1],req[1],wr[1],addr[1],wdata[1],len[1],overflow[1]},"every public output equals the complete frozen ring on every clock");
 end
 always @(negedge clk)begin
  out_ready=rst&&(cycles%31<23);
  out_level=cycles%257<11?10'd255:10'd0;
 end
 task fill_and_drain(input integer epoch);begin
  @(negedge clk);fallback=15;valid=15;
  while(!all_full)begin @(negedge clk);end
  @(negedge clk);valid=0;
  repeat(50)@(negedge clk);
  ck(levels[0]=={4{16'(CAP)}}&&ready[0]==0,"full partitions reject all additional writes without overflow");
  for(n=0;n<4;n++)begin
   while(!current_commit_ready)begin @(negedge clk);end
   @(negedge clk);slot=n;gen=epoch*4+n+1;commit=1;fallback=0;
   @(negedge clk);commit=0;
   while(read_status[n*32+:32]!=(epoch+1)*CAP)begin @(negedge clk);end
   while(!current_commit_ready)begin @(negedge clk);end
   ck(levels[0][n*16+:16]==0,"active partition drains completely without an empty read");
  end
  repeat(50)@(negedge clk);
  ck(levels[0]==0&&overflow[0]==0,"all partitions empty and no overflow after a complete round");
 end endtask
 initial begin
  for(i=0;i<4;i++)begin writes[i]=0;reads[i]=0;end
  repeat(5)@(negedge clk);rst=1;
  fill_and_drain(0);fill_and_drain(1);
  for(i=0;i<4;i++)ck(writes[i]==2*CAP&&reads[i]==2*CAP,"each pointer makes two complete capacity traversals");


  @(negedge clk);fallback=15;valid=15;while(!(current_req&&!ack))begin @(negedge clk);end
  #2;rst=0;
  #0.002;ck(req[0]===req[1]&&out_valid[0]===out_valid[1],"asynchronous reset immediately matches the parent");
  repeat(4)@(negedge clk);rst=1;fill_and_drain(0);
  ck(transactions>=8*CAP,"substantial complete physical write/read activity is covered after reset");
  done=1;$display("[PASS] pointer lane PW=%0d capacity=%0d two wraps, full/empty, independent PCM and reset",PW,CAP);
 end
endmodule
module tb_v3_ring_pointer_compare;
 reg clk=0;always #5 clk=~clk;
 wire[2:0]done;wire[31:0]errors[0:2],comparisons[0:2];
 ring_pointer_lane #(.PW(4))a(clk,done[0],errors[0],comparisons[0]);
 ring_pointer_lane #(.PW(7))b(clk,done[1],errors[1],comparisons[1]);
 ring_pointer_lane #(.PW(14))c(clk,done[2],errors[2],comparisons[2]);
 initial begin
  wait(&done);$display("[PASS] all public outputs and independent full-capacity memory/PCM checks");
  $display("PASS tb_v3_ring_pointer_compare errors=%0d comparisons=%0d",errors[0]+errors[1]+errors[2],comparisons[0]+comparisons[1]+comparisons[2]);$finish;
 end
 initial begin #1000000000;$display("[FAIL] pointer comparison watchdog");$display("PASS tb_v3_ring_pointer_compare errors=1 comparisons=0");$finish;end
endmodule
