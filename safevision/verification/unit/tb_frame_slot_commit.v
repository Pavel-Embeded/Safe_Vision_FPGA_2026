`timescale 1ns/1ps
`include "pixel_format_defs.vh"
module tb_frame_slot_commit;
 reg ac=0,bc=0,rst=0;always #7 ac=~ac;always #5 bc=~bc;
 reg req=0,fi=0,crc=1;reg [1:0] slot=0;reg [7:0] gen=0;
 integer phase=0;wire fs=(phase==36);wire re,mbvalid,mcrc,mfi;wire [1:0] mslot;wire [7:0] mgen;
 wire ackevt;wire ack,valid,afi,commit,invalid;wire [1:0] active_slot;wire [7:0] active_gen;wire [31:0] base,nextbase;wire nextvalid;
 frame_swap_cdc cdc(.clk_b(bc),.rst_b_n(rst),.swap_req_b(req),.mb_frame_index_b(fi),.mb_slot_id_b(slot),.mb_generation_b(gen),.mb_crc_ok_b(crc),.frame_start_evt_b(),.swap_ack_evt_b(ackevt),
 .clk_a(ac),.rst_a_n(rst),.swap_req_evt_a(re),.swap_req_lvl_a(),.mb_frame_index_a(mfi),.mb_slot_id_a(mslot),.mb_generation_a(mgen),.mb_crc_ok_a(mcrc),.mb_valid_a(mbvalid),.frame_start_a(fs),.swap_ack_a(ack));
 frame_slot_commit dut(.clk(ac),.rst_n(rst),.frame_start(fs),.req_evt(re),.mb_valid(mbvalid),.mb_crc_ok(mcrc),.mb_slot(mslot),.mb_generation(mgen),.mb_frame_index(mfi),.swap_ack_toggle(ack),
 .active_valid(valid),.active_slot(active_slot),.generation(active_gen),.frame_index(afi),.active_base(base),.next_frame_base(nextbase),.next_frame_valid(nextvalid),.commit(commit),.invalid_payload(invalid));
 reg previous_fs;integer commits=0,invalids=0,acks=0,n;reg [31:0] expected_base;
 always @(posedge bc)if(rst&&ackevt)acks=acks+1;
 always @(posedge ac)begin
  if(!rst)begin phase<=0;previous_fs=0;end
  else begin
   previous_fs=fs;phase<=fs ? 0:phase+1;
   if(fs&&dut.pending)begin
    expected_base=`SV_SLOT_BASE(slot);
    if(nextbase!==expected_base||!nextvalid)begin $display("[FAIL] same-edge prefetch uses old base"); $finish; end
   end
   #0.1;
   if(commit)begin
    commits=commits+1;
    if(!previous_fs||!valid||{active_slot,active_gen,afi}!=={slot,gen,fi}||base!==expected_base)begin $display("[FAIL] slot commit/mailbox tear"); $finish; end
   end
   if(invalid)invalids=invalids+1;
  end
 end
 task reset_epoch;begin
  @(negedge bc);rst=0;req=0;slot=0;gen=0;fi=0;crc=1;
  repeat(6)@(negedge bc);rst=1;repeat(6)@(negedge ac);
  if(valid||ack||commit)begin $display("[FAIL] common reset epoch failed"); $finish; end
   end endtask
 integer before_ack,before_commit,before_invalid;
 initial begin
  reset_epoch;
  for(n=0;n<120;n=n+1)begin
   if(n==60)begin
    @(negedge bc);slot=3;gen=8'hee;fi=1;req=~req;

    #1;reset_epoch;
   end
   before_ack=acks;before_commit=commits;before_invalid=invalids;
   @(negedge bc);slot=n%4;gen=(n*37)^8'h5a;fi=n%2;crc=(n%11!=0);
   @(negedge bc);req=~req;
   if(!crc)begin
    wait(invalids==before_invalid+1);repeat(80)@(negedge ac);
    if(acks!=before_ack||commits!=before_commit)begin $display("[FAIL] invalid CRC committed/acked"); $finish; end
   end else begin
    wait(acks==before_ack+1);repeat(4)@(negedge bc);
    if(commits!=before_commit+1)begin $display("[FAIL] request lost/duplicate commit"); $finish; end
   end
  end
  if(commits!=109||invalids!=11||acks!=109)begin $display("[FAIL] slot coverage totals %0d/%0d/%0d",commits,invalids,acks); $finish; end


  for(n=0;n<300;n=n+1)begin
   before_ack=acks;before_commit=commits;
   @(negedge bc);slot=n%2;gen=n[7:0];fi=n%2;crc=1;
   @(negedge bc);req=~req;
   wait(acks==before_ack+1);repeat(4)@(negedge bc);
   if(commits!=before_commit+1||active_gen!==n[7:0])begin $display("[FAIL] generation rollover lost/duplicate/incorrect commit"); $finish; end
  end
  if(commits!=409||invalids!=11||acks!=409)begin $display("[FAIL] rollover coverage totals %0d/%0d/%0d",commits,invalids,acks); $finish; end
  $display("PASS tb_frame_slot_commit: 409 atomic vblank commits/acks, 11 CRC rejects, 300 sequential generation values including 255->0, same-edge base and in-flight common reset");$finish;
 end
 initial begin #400000;begin $display("[FAIL] slot timeout"); $finish; end end
endmodule
