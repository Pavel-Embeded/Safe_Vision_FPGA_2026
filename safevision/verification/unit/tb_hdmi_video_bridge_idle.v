

`timescale 1ns/1ps
module tb_hdmi_video_bridge_idle;
 reg clk=0,rst_n=0,de=0,ready=0;always #5 clk=~clk;
 reg [11:0] x=0,y=0;reg [23:0] rgb=0;
 wire valid,user,last,resync,fault;wire [23:0] data;
 wire [31:0] drops;wire [4:0] level;
 hdmi_video_bridge dut(.clk(clk),.rst_n(rst_n),.de(de),.x(x),.y(y),.rgb(rgb),
  .axis_ready(ready),.axis_valid(valid),.axis_user(user),.axis_last(last),
  .axis_data(data),.resync(resync),.overflow_sticky(fault),
  .dropped_frames(drops),.queue_level(level));
 integer checks=0;
 task idle_check;
 begin begin #0.2;checks=checks+1;
  if(valid!==0||{user,last,data}!==26'd0)
   begin $display("[FAIL] invalid HDMI beat exposes RAM tags/data: valid=%b user=%b last=%b data=%h",valid,user,last,data); $finish; end 
 end  end endtask
 task sample(input [11:0] px,py,input [23:0] value,input enable);
 begin begin @(negedge clk);x=px;y=py;rgb=value;de=enable;@(posedge clk);#0.2;end  end endtask
 integer i;
 initial begin
  repeat(3)begin @(posedge clk);idle_check;end
  @(negedge clk);rst_n=1;repeat(3)begin @(posedge clk);idle_check;end

  sample(20,7,24'habcdef,1);idle_check;
  sample(0,0,24'h123456,1);
  if({valid,user,last,data}!=={1'b1,1'b1,1'b0,24'h123456})begin $display("[FAIL] SOF beat"); $finish; end 
  @(negedge clk);de=0;
  repeat(4)begin @(posedge clk);#0.2;
   if({valid,user,last,data}!=={1'b1,1'b1,1'b0,24'h123456})begin $display("[FAIL] stalled SOF changed"); $finish; end 
  end
  @(negedge clk);ready=1;@(posedge clk);idle_check;
  sample(639,0,24'h987654,1);
  if({valid,user,last,data}!=={1'b1,1'b0,1'b1,24'h987654})begin $display("[FAIL] EOL beat"); $finish; end 
  @(negedge clk);de=0;@(posedge clk);idle_check;

  @(negedge clk);rst_n=0;#0.2;idle_check;
  @(negedge clk);rst_n=1;ready=0;@(posedge clk);idle_check;
  sample(0,0,24'h654321,1);
  for(i=1;i<17;i=i+1)sample(i,0,24'h654321+i,1);
  if(resync!==1'b1||fault!==1'b1||drops!==32'd1)begin $display("[FAIL] overflow coverage"); $finish; end 
  idle_check;
  sample(40,0,24'hffffff,1);idle_check;
  @(negedge clk);de=0;ready=1;
  sample(0,0,24'hfedcba,1);
  if({valid,user,last,data}!=={1'b1,1'b1,1'b0,24'hfedcba})begin $display("[FAIL] recovered SOF"); $finish; end 
  @(negedge clk);de=0;@(posedge clk);idle_check;
  $display("PASS tb_hdmi_video_bridge_idle checks=%0d reset/empty/stall/EOL/overflow/recovery",checks);$finish;
 end
 initial begin #100000;begin $display("[FAIL] idle test watchdog"); $finish; end end
endmodule
