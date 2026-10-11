`timescale 1ns/1ps
// Directed child-protocol test: no media data is faked as a valid image.
// Mount/first-window work is bypassed to exercise a repeated scan's sticky DONE.
module tb_player_scan_epoch;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 wire [3:0] state_o;integer checks=0;
 sd_bmp_player #(.RESIDENT_FRAMES(1),.MOUNT_TO_N(64)) dut(
  .clk(clk),.rst_n(rst_n),.run(1'b0),.btn_next(1'b0),.btn_auto(1'b0),
  .sd_miso(1'b1),.px_word_ready(1'b1),.mem_ready(1'b1),
  .frame_done(1'b0),.last_frame_ok(1'b1),.state_o(state_o));
 task step;begin @(posedge clk);#1;end endtask
 task check(input bit ok,input string label);
  begin checks=checks+1;if(!ok)$fatal(1,"SCAN EPOCH: %s state=%0d sub=%0d",label,state_o,dut.scan_sub);
   $display("[PASS] %s",label);end
 endtask
 task start_repeat;
  begin
   rst_n=0;repeat(3)step;@(negedge clk);rst_n=1;step;
   @(negedge clk);dut.state_o=4'd9;dut.resident_valid=4'b0111;
   dut.resident_count=3;dut.cur_file=3;
   force dut.candidate_count=4;force dut.candidate_max=4;
   force dut.scan_done=1;step;
   check(state_o==4,"full candidate window starts another directory scan");
   check(dut.scan_after==4,"window frontier advances past processed candidates");
  end
 endtask
 initial begin
  start_repeat;
  repeat(8)begin step;check(state_o==4&&!dut.idx_commit,"old sticky completion cannot commit new window");end
  check(dut.resident_valid==7&&dut.boot_loading,"verified slots survive repeated scan");
  force dut.scan_done=0;repeat(2)step;
  check(state_o==4&&dut.scan_sub==3,"new scan must first acknowledge clearing DONE");
  force dut.scan_done=1;step;
  check(state_o==5&&dut.idx_commit,"only new completion commits refreshed index");
  force dut.idx_done=0;repeat(3)step;
  force dut.candidate_count=1;force dut.idx_done=1;step;
  check(state_o==6&&dut.boot_loading&&dut.resident_valid==7,"next valid candidate is selected for missing fourth resident slot");
  release dut.idx_done;release dut.scan_done;release dut.candidate_count;release dut.candidate_max;
  start_repeat;repeat(80)step;
  check(state_o==10&&dut.err_code!=0,"missing scan acknowledgment has bounded error exit");
  $display("PASS tb_player_scan_epoch checks=%0d",checks);$finish;
 end
 initial begin #10000;$fatal(1,"scan epoch watchdog");end
endmodule
