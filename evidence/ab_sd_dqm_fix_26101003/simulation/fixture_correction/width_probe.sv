`timescale 1ns/1ps
module narrow(output reg [7:0] cnt=8'h37);
endmodule
module tb;
 wire [31:0] wide;
 wire [7:0] correct;
 narrow d(.cnt(wide));
 assign correct=wide[7:0];
 integer snap,total=0,total_snapshot,i;
 reg event_valid=0;
 reg [7:0] narrow_snapshot;
 always @(posedge event_valid)total=total+1;
 initial begin
  #1;snap=wide;
  $display("COUNT WIDTH wide=%h snapshot=%h equal=%b",wide,snap,wide==snap);
  if((wide==snap)!==1'bx)$fatal(1,"Mismatch must reproduce unknown comparison");
  narrow_snapshot=correct;total_snapshot=total;
  if((correct==narrow_snapshot)!==1'b1)$fatal(1,"Correct width must compare exactly");
  for(i=0;i<256;i=i+1)begin
   #1;d.cnt=d.cnt+1'b1;event_valid=1;
   #1;event_valid=0;
  end
  #1;
  if(correct!==narrow_snapshot||total!=256||total==total_snapshot)
   $fatal(1,"Independent event count must detect a full diagnostic counter wrap");
  $display("[PASS] corrected width is known; independent command events detect all 256 commands despite 8-bit wrap");
  $finish;
 end
endmodule
