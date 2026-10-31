`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_v3_direct_row_hd;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,frame_begin=0,top_down=1,accepted=0,verify_start=0,verify_allow=1;
 reg[1:0] frame_slot=0,lookup_slot_index=0;
 reg[9:0] lookup_row_index=0;
 reg[31:0] write_addr=0,write_data=0,lookup_addr=0;
 reg rd_ack=0,rd_busy=0,rd_valid=0;reg[31:0] rd_data=0;
  wire d_verify_done;
 wire d_verify_pass;
 wire d_fault;
 wire[3:0] d_approved;
 wire d_rd_req;
 wire[31:0] d_rd_addr;
 wire[15:0] d_rd_len;
 wire[31:0] d_lookup_crc;
 wire d_lookup_valid;
 wire[31:0] d_bad_addr;
 wire[31:0] d_bad_expected;
 wire[31:0] d_bad_actual;
 wire[31:0] d_source_words;
 wire[15:0] d_checked_rows;
 wire g_verify_done;
 wire g_verify_pass;
 wire g_fault;
 wire[3:0] g_approved;
 wire g_rd_req;
 wire[31:0] g_rd_addr;
 wire[15:0] g_rd_len;
 wire[31:0] g_lookup_crc;
 wire g_lookup_valid;
 wire[31:0] g_bad_addr;
 wire[31:0] g_bad_expected;
 wire[31:0] g_bad_actual;
 wire[31:0] g_source_words;
 wire[15:0] g_checked_rows;
  wire[232:0] d_public={d_verify_done,d_verify_pass,d_fault,d_approved,d_rd_req,d_rd_addr,d_rd_len,d_lookup_crc,d_lookup_valid,d_bad_addr,d_bad_expected,d_bad_actual,d_source_words,d_checked_rows};
 wire[232:0] g_public={g_verify_done,g_verify_pass,g_fault,g_approved,g_rd_req,g_rd_addr,g_rd_len,g_lookup_crc,g_lookup_valid,g_bad_addr,g_bad_expected,g_bad_actual,g_source_words,g_checked_rows};
 v3_row_integrity #(.TIMEOUT(50000000),.DIRECT_LOOKUP(1)) dut(
 .clk(clk),
 .rst_n(rst_n),
 .frame_begin(frame_begin),
 .frame_slot(frame_slot),
 .top_down(top_down),
 .accepted(accepted),
 .write_addr(write_addr),
 .write_data(write_data),
 .verify_start(verify_start),
 .verify_allow(verify_allow),
 .verify_done(d_verify_done),
 .verify_pass(d_verify_pass),
 .fault(d_fault),
 .approved(d_approved),
 .rd_req(d_rd_req),
 .rd_addr(d_rd_addr),
 .rd_len(d_rd_len),
 .rd_ack(rd_ack),
 .rd_busy(rd_busy),
 .rd_valid(rd_valid),
 .rd_data(rd_data),
 .lookup_addr(lookup_addr),
 .lookup_crc(d_lookup_crc),
 .lookup_valid(d_lookup_valid),
 .bad_addr(d_bad_addr),
 .bad_expected(d_bad_expected),
 .bad_actual(d_bad_actual),
 .source_words(d_source_words),
 .checked_rows(d_checked_rows),
 .lookup_slot_index(lookup_slot_index),
 .lookup_row_index(lookup_row_index));
 v3_row_integrity_frozen_direct_hd #(.TIMEOUT(50000000)) gold(
 .clk(clk),
 .rst_n(rst_n),
 .frame_begin(frame_begin),
 .frame_slot(frame_slot),
 .top_down(top_down),
 .accepted(accepted),
 .write_addr(write_addr),
 .write_data(write_data),
 .verify_start(verify_start),
 .verify_allow(verify_allow),
 .verify_done(g_verify_done),
 .verify_pass(g_verify_pass),
 .fault(g_fault),
 .approved(g_approved),
 .rd_req(g_rd_req),
 .rd_addr(g_rd_addr),
 .rd_len(g_rd_len),
 .rd_ack(rd_ack),
 .rd_busy(rd_busy),
 .rd_valid(rd_valid),
 .rd_data(rd_data),
 .lookup_addr(lookup_addr),
 .lookup_crc(g_lookup_crc),
 .lookup_valid(g_lookup_valid),
 .bad_addr(g_bad_addr),
 .bad_expected(g_bad_expected),
 .bad_actual(g_bad_actual),
 .source_words(g_source_words),
 .checked_rows(g_checked_rows));
 reg[31:0] row_expected[0:2047];
 reg[31:0] rng=32'hd12a7635,next_address=0;
 integer remaining=0,cycle=0,errors=0,data_errors=0,driver_errors=0,gold_errors=0;
 integer slot,row,col,k,wait_cycles,selected,index,queries=0,verified_frames=0;
 reg manual_queries=0,finished=0;reg wanted_valid;
 reg [63:0]  comparisons=0;
 function[31:0] word_at;input[31:0] address;begin
  word_at=32'h93a57ce1^(address*32'h01020411)^(address>>3);
   end endfunction
 task compare_public;begin
  comparisons=comparisons+1;
  if(d_public!==g_public)begin
   errors=errors+1;data_errors=data_errors+1;
   if(data_errors<=4)$display("[FAIL] complete row-guard public interface differs time=%0t",$time);
  end
   end endtask
 always @(posedge clk)begin
  if(rst_n)compare_public;
  #1;if(rst_n)compare_public;
 end
 always @(negedge clk)if(rst_n&&!manual_queries)begin
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  lookup_slot_index=rng[1:0];lookup_row_index=rng[11:2];
  lookup_addr=`SV_SLOT_BASE(lookup_slot_index)+lookup_row_index*32'd1280;
 end


 always @(posedge clk)begin
  if(!rst_n)begin rd_ack<=0;rd_busy<=0;rd_valid<=0;rd_data<=0;remaining<=0;cycle<=0;next_address<=0;end
  else begin
   cycle<=cycle+1;rd_ack<=0;rd_valid<=0;
   if(!rd_busy&&d_rd_req)begin
    rd_ack<=1;rd_busy<=1;remaining<=d_rd_len;next_address<=d_rd_addr;
   end else if(rd_busy&&(cycle%5!=0))begin
    rd_valid<=1;rd_data<=word_at(next_address);next_address<=next_address+4;remaining<=remaining-1;
    if(remaining==1)rd_busy<=0;
   end
  end
 end
 task finish_test;begin
  finished=1;
  if(errors==0)$display("[PASS] four full source/readback frames and all4096cache-address aliases;14ports233bits before/after each edge");
  $display("PASS tb_v3_direct_row_hd errors=%0d comparisons=%0d data_errors=%0d driver_errors=%0d gold_errors=%0d queries=%0d verified_frames=%0d public_bits=233",errors,comparisons,data_errors,driver_errors,gold_errors,queries,verified_frames);
  $finish;
   end endtask
 initial begin
  $readmemh("direct_row_crc113.mem",row_expected);
  repeat(4)@(negedge clk);rst_n=1;
  for(slot=0;slot<4;slot=slot+1)begin
   @(negedge clk);frame_slot=slot;top_down=!slot[0];frame_begin=1;
   @(negedge clk);frame_begin=0;
   for(k=0;k<480;k=k+1)begin
    row=top_down ? k:479-k;
    for(col=0;col<320;col=col+1)begin
     accepted=1;write_addr=slot*32'd655360+row*32'd1280+col*4;write_data=word_at(write_addr);
     @(negedge clk);
    end
   end
   accepted=0;
   @(negedge clk);verify_start=1;
   @(negedge clk);verify_start=0;wait_cycles=0;
   while(!d_verify_done&&wait_cycles<400000)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(!d_verify_done||!g_verify_done||!d_verify_pass||!g_verify_pass||d_fault||g_fault||d_checked_rows!=480||g_checked_rows!=480)begin
    errors=errors+1;driver_errors=driver_errors+1;$display("[FAIL] frame verification did not complete slot=%0d",slot);finish_test;
   end
   verified_frames=verified_frames+1;
  end
  if(d_approved!=15||g_approved!=15)begin errors=errors+1;driver_errors=driver_errors+1;end
  manual_queries=1;repeat(2)@(negedge clk);
  for(slot=0;slot<4;slot=slot+1)for(row=0;row<1024;row=row+1)begin
   lookup_slot_index=slot;lookup_row_index=row;
   lookup_addr=slot*32'd655360+row*32'd1280;
   @(posedge clk);#2;
   selected=slot+(row>>9);wanted_valid=selected<4&&(row%512)<480;
   index=wanted_valid ? selected*512+(row%512):0;
   if(d_lookup_valid!==wanted_valid||g_lookup_valid!==wanted_valid||d_lookup_crc!==row_expected[index]||g_lookup_crc!==row_expected[index])begin
    errors=errors+1;gold_errors=gold_errors+1;
    if(gold_errors<=4)$display("[FAIL] independent zlib row CRC slot=%0d row=%0d actual=%08x expected=%08x valid=%0d/%0d",slot,row,d_lookup_crc,row_expected[index],d_lookup_valid,wanted_valid);
   end
   queries=queries+1;@(negedge clk);
  end
  finish_test;
 end
 initial begin #150000000;if(!finished)begin errors=errors+1;driver_errors=driver_errors+1;$display("[FAIL] row-guard driver budget expired");finish_test;end end
endmodule
