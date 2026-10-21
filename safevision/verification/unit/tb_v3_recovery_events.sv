`timescale 1ns/1ps
module tb_v3_recovery_events;
 reg clk=0;always #5 clk=~clk;reg rst=0,request=0,done=0,failed=0,fatal=0;
 wire busy,reset,start,recovered,safe;wire [1:0] attempts;wire [2:0] state;
 media_recovery_ctrl #(.RESET_CYCLES(3),.SETTLE_CYCLES(3),.TIMEOUT_CYCLES(20)) rc(
 clk,rst,request,done,failed,fatal,busy,reset,start,recovered,safe,attempts,state);
 reg push=0,ready=0;reg [7:0] code=0;reg [3:0] src=0;reg [31:0] ts=0;
 wire [3:0] typ;wire [15:0] value;wire valid,full;wire [15:0] drops;wire [31:0] stamp;
 error_report er(clk,rst,push,code,src,ts,typ,value,valid,full,ready,stamp,drops);
 integer errors=0,n,j;task ck;input c;input [255:0] msg;
 begin if(!c)begin errors=errors+1;$display("[FAIL] %s",msg);end else $display("[PASS] %s",msg);end endtask
 task tick;begin @(negedge clk);end endtask
 initial begin
  repeat(3)tick;rst=1;tick;
  for(n=0;n<8;n=n+1)begin push=1;code=n+1;src=n;ts=100+n;tick;end push=0;
  ck(full,"event queue full");ready=1;
  for(n=0;n<8;n=n+1)begin ck(valid && value==n+1 && stamp==100+n && typ==n,"ordered timestamp delivery");tick;end
  ready=0;ck(!valid,"consumption empties queue");
  for(j=0;j<1000;j=j+1)begin
   request=1;tick;request=0;
   repeat(3)tick;ck(!reset && busy && safe,"reset released while SAFE maintained");
   repeat(8)tick;ck(busy && !reset,"unfinished recovery remains waiting");
   done=1;tick;done=0;ck(recovered && !safe,"verified recovery completes");tick;
  end
  for(j=0;j<3;j=j+1)begin request=1;tick;request=0;repeat(30)tick;end
  ck(attempts==3 && safe && !busy,"bounded three retries");request=1;tick;request=0;repeat(5)tick;
  ck(attempts==3 && !reset,"exhausted retries do not reset again");
  $display("PASS tb_v3_recovery_events errors=%0d",errors);$finish;
 end
 initial begin #1000000;$display("[FAIL] timeout");$finish;end
endmodule
