`timescale 1ns/1ps
module tb_v3_audio_system_pointer;
 tb_v3_audio_system test_case();
 defparam test_case.d.DIRECT_RING_COMPARE=1;
 integer compared=0;
 always @(posedge test_case.pc)if(test_case.rst_n&&test_case.pv)begin
  if(test_case.checking||(test_case.search_first&&
    test_case.l=={test_case.gold[test_case.slot*2000][15:0],8'd0}&&
    test_case.r=={test_case.gold[test_case.slot*2000][31:16],8'd0}))compared++;
 end
 final begin
  if(test_case.gen!=3||test_case.seen<300||compared<2700||test_case.acrs<20||test_case.over!=0||test_case.d.ring.DIRECT_POINTER_COMPARE!=1)begin
   $display("[FAIL] direct-pointer full audio scenario did not complete");
   $display("PASS tb_v3_audio_system_pointer errors=1 comparisons=%0d",compared);
  end else begin
   $display("[PASS] unchanged full audio gold with production direct-pointer scheduling");
   $display("PASS tb_v3_audio_system_pointer errors=0 comparisons=%0d",compared);
  end
 end
endmodule
